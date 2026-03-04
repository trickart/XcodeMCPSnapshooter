import Foundation

/// MCP client
/// Manages server connection, tool invocation, etc.
public actor MCPClient {
    /// Connection state
    public enum ConnectionState: Sendable {
        case disconnected
        case connecting
        case initializing
        case ready
    }

    private let transport: any MCPTransport
    private let clientInfo: MCPClientInfo
    private let requestTimeout: Duration

    private(set) public var state: ConnectionState = .disconnected
    private(set) public var serverInfo: MCPServerInfo?
    private(set) public var serverCapabilities: MCPServerCapabilities?

    private var nextRequestID: Int = 1
    private var pendingRequests: [Int: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var bufferedResponses: [Int: JSONRPCResponse] = [:]
    private var cancelledRequests: Set<Int> = []
    private var receiveTask: Task<Void, Never>?

    public init(
        transport: any MCPTransport,
        clientInfo: MCPClientInfo = MCPClientInfo(name: "XcodeMCPSnapshooter", version: "0.1.0"),
        requestTimeout: Duration = .seconds(30)
    ) {
        self.transport = transport
        self.clientInfo = clientInfo
        self.requestTimeout = requestTimeout
    }

    // MARK: - Public API

    /// Connect to the server (start transport -> initialize -> initialized)
    public func connect() async throws {
        guard state == .disconnected else {
            throw MCPClientError.alreadyConnected
        }

        state = .connecting

        do {
            try await transport.start()
        } catch {
            state = .disconnected
            throw MCPClientError.transportError(error)
        }

        // Start receive loop
        startReceiveLoop()

        state = .initializing

        // Send initialize request
        let initParams = MCPInitializeParams(clientInfo: clientInfo)
        let encoder = JSONEncoder()
        let paramsData = try encoder.encode(initParams)
        let paramsValue = try JSONDecoder().decode(JSONValue.self, from: paramsData)

        // Convert JSONValue to [String: JSONValue]
        guard case .object(let paramsDict) = paramsValue else {
            state = .disconnected
            throw MCPClientError.connectionFailed("Failed to encode initialize params")
        }

        let response = try await sendRequest(method: "initialize", params: paramsDict)

        // Decode response
        guard let result = response.result else {
            if let error = response.error {
                state = .disconnected
                throw MCPClientError.serverError(code: error.code, message: error.message)
            }
            state = .disconnected
            throw MCPClientError.invalidResponse("No result in initialize response")
        }

        let resultData = try encoder.encode(result)
        let initResult = try JSONDecoder().decode(MCPInitializeResult.self, from: resultData)

        self.serverInfo = initResult.serverInfo
        self.serverCapabilities = initResult.capabilities

        // Send initialized notification
        try await sendNotification(method: "notifications/initialized")

        state = .ready
    }

    /// List available tools
    public func listTools() async throws -> [MCPToolDefinition] {
        guard state == .ready else {
            throw MCPClientError.notConnected
        }

        let response = try await sendRequest(method: "tools/list")

        guard let result = response.result else {
            if let error = response.error {
                throw MCPClientError.serverError(code: error.code, message: error.message)
            }
            throw MCPClientError.invalidResponse("No result in tools/list response")
        }

        let resultData = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(MCPToolsListResult.self, from: resultData).tools
    }

    /// Call a tool
    public func callTool(
        name: String,
        arguments: [String: JSONValue]? = nil,
        timeout: Duration? = nil
    ) async throws -> MCPToolCallResult {
        guard state == .ready else {
            throw MCPClientError.notConnected
        }

        let params: [String: JSONValue] = {
            var p: [String: JSONValue] = ["name": .string(name)]
            if let arguments {
                p["arguments"] = .object(arguments)
            }
            return p
        }()

        let response = try await sendRequest(method: "tools/call", params: params, timeout: timeout)

        guard let result = response.result else {
            if let error = response.error {
                throw MCPClientError.serverError(code: error.code, message: error.message)
            }
            throw MCPClientError.invalidResponse("No result in tools/call response")
        }

        let resultData = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(MCPToolCallResult.self, from: resultData)
    }

    /// Disconnect from the server
    public func disconnect() async {
        receiveTask?.cancel()
        receiveTask = nil

        // Cancel pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: MCPClientError.notConnected)
        }
        pendingRequests.removeAll()
        bufferedResponses.removeAll()

        try? await transport.stop()
        state = .disconnected
        serverInfo = nil
        serverCapabilities = nil
    }

    // MARK: - Private

    private func sendRequest(
        method: String,
        params: [String: JSONValue]? = nil,
        timeout: Duration? = nil
    ) async throws -> JSONRPCResponse {
        let id = nextRequestID
        nextRequestID += 1

        let request = JSONRPCRequest(id: .int(id), method: method, params: params)
        let data = try JSONEncoder().encode(request)

        try await transport.send(data)

        let effectiveTimeout = timeout ?? self.requestTimeout

        // Wait for response with timeout
        return try await withThrowingTaskGroup(of: JSONRPCResponse.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        Task { await self.registerPending(id: id, continuation: continuation) }
                    }
                } onCancel: {
                    Task { await self.cancelPending(id: id) }
                }
            }

            group.addTask {
                try await Task.sleep(for: effectiveTimeout)
                throw MCPClientError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func registerPending(id: Int, continuation: CheckedContinuation<JSONRPCResponse, Error>) {
        // If the request was already cancelled before the continuation was registered
        if cancelledRequests.remove(id) != nil {
            continuation.resume(throwing: CancellationError())
        // If the response arrived before the continuation was registered, return it from the buffer
        } else if let response = bufferedResponses.removeValue(forKey: id) {
            continuation.resume(returning: response)
        } else {
            pendingRequests[id] = continuation
        }
    }

    private func cancelPending(id: Int) {
        if let continuation = pendingRequests.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        } else {
            // Mark as cancelled so registerPending can handle it if called later
            cancelledRequests.insert(id)
        }
    }

    private func sendNotification(method: String, params: [String: JSONValue]? = nil) async throws {
        let notification = JSONRPCNotification(method: method, params: params)
        let data = try JSONEncoder().encode(notification)
        try await transport.send(data)
    }

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            let messages = self.transport.messages
            do {
                for try await data in messages {
                    await self.handleMessage(data)
                }
            } catch {
                await self.handleStreamError(error)
            }
        }
    }

    private func handleMessage(_ data: Data) {
        do {
            let incoming = try JSONRPCIncoming.parse(from: data)
            switch incoming {
            case .response(let response):
                handleResponse(response)
            case .notification:
                break
            }
        } catch {
            // Ignore parse errors
        }
    }

    private func handleResponse(_ response: JSONRPCResponse) {
        guard let id = response.id else { return }
        guard case .int(let intID) = id else { return }

        if let continuation = pendingRequests.removeValue(forKey: intID) {
            continuation.resume(returning: response)
        } else {
            // Buffer the response if the continuation has not been registered yet
            bufferedResponses[intID] = response
        }
    }

    private func handleStreamError(_ error: Error) {
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: MCPClientError.transportError(error))
        }
        pendingRequests.removeAll()
        state = .disconnected
    }
}
