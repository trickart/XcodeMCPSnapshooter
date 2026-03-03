import Foundation
import Synchronization

/// stdio-based MCP transport
/// Launches a server process and exchanges JSON-RPC messages via stdin/stdout
public final class StdioTransport: MCPTransport, @unchecked Sendable {
    private let serverPath: String
    private let serverArguments: [String]
    private let serverEnvironment: [String: String]?

    private struct MutableState {
        var process: Process?
        var stdinPipe: Pipe?
        var stdoutBuffer: Data = Data()
    }

    private let mutableState = Mutex(MutableState())

    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    public let messages: AsyncThrowingStream<Data, Error>

    public init(
        serverPath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) {
        self.serverPath = serverPath
        self.serverArguments = arguments
        self.serverEnvironment = environment
        (self.messages, self.continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    }

    public func start() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverPath)
        process.arguments = serverArguments

        if let serverEnvironment {
            process.environment = serverEnvironment
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Forward stderr as debug output
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                fputs("[MCP Server stderr] \(text)", stderr)
            }
        }

        // Read stdout line by line
        let continuation = self.continuation
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF
                continuation.finish()
                return
            }
            self?.handleStdoutData(data)
        }

        // Process termination handler
        process.terminationHandler = { _ in
            continuation.finish()
        }

        mutableState.withLock {
            $0.process = process
            $0.stdinPipe = stdinPipe
        }

        try process.run()
    }

    public func send(_ data: Data) async throws {
        let pipe = mutableState.withLock { $0.stdinPipe }

        guard let pipe else {
            throw StdioTransportError.notStarted
        }
        // Send with newline delimiter
        var payload = data
        payload.append(contentsOf: [UInt8(ascii: "\n")])
        try pipe.fileHandleForWriting.write(contentsOf: payload)
    }

    public func stop() async throws {
        let (pipe, proc) = mutableState.withLock {
            let pipe = $0.stdinPipe
            let proc = $0.process
            $0.stdinPipe = nil
            $0.process = nil
            return (pipe, proc)
        }

        pipe?.fileHandleForWriting.closeFile()
        proc?.terminate()
        continuation.finish()
    }

    // MARK: - Private

    private func handleStdoutData(_ data: Data) {
        let lines: [Data] = mutableState.withLock { s in
            s.stdoutBuffer.append(data)
            var result: [Data] = []
            while let newlineIndex = s.stdoutBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = s.stdoutBuffer[s.stdoutBuffer.startIndex..<newlineIndex]
                s.stdoutBuffer = Data(s.stdoutBuffer[(newlineIndex + 1)...])
                if !lineData.isEmpty {
                    result.append(Data(lineData))
                }
            }
            return result
        }

        for line in lines {
            continuation.yield(line)
        }
    }
}

/// StdioTransport errors
public enum StdioTransportError: Error, LocalizedError {
    case notStarted

    public var errorDescription: String? {
        switch self {
        case .notStarted:
            return "Transport has not been started"
        }
    }
}
