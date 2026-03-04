import Foundation
import Testing
@testable import Model

@Suite("MCPClient Tests")
struct MCPClientTests {
    @Test("Connection handshake succeeds")
    func connectHandshake() async throws {
        let transport = MockTransport()

        // Inject initialize response when send is called
        transport.onSend = { data in
            // Decode request and check method
            guard let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
                return
            }

            if request.method == "initialize" {
                let initResult = MCPInitializeResult(
                    protocolVersion: "2024-11-05",
                    capabilities: MCPServerCapabilities(),
                    serverInfo: MCPServerInfo(name: "test-server", version: "1.0.0")
                )
                let resultData = try! JSONEncoder().encode(initResult)
                let resultValue = try! JSONDecoder().decode(JSONValue.self, from: resultData)

                let response = JSONRPCResponse(id: request.id, result: resultValue)
                try! transport.injectResponse(response)
            }
            // No response needed for initialized notification
        }

        let client = MCPClient(transport: transport)
        try await client.connect()

        let state = await client.state
        #expect(state == .ready)

        let serverInfo = await client.serverInfo
        #expect(serverInfo?.name == "test-server")
        #expect(serverInfo?.version == "1.0.0")

        await client.disconnect()
    }

    @Test("Calling a tool when disconnected throws an error")
    func callToolWhenDisconnected() async throws {
        let transport = MockTransport()
        let client = MCPClient(transport: transport)

        await #expect(throws: MCPClientError.self) {
            try await client.callTool(name: "test")
        }
    }

    @Test("Can list tools")
    func listTools() async throws {
        let transport = MockTransport()

        transport.onSend = { data in
            guard let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
                return
            }

            if request.method == "initialize" {
                let initResult = MCPInitializeResult(
                    protocolVersion: "2024-11-05",
                    capabilities: MCPServerCapabilities(),
                    serverInfo: MCPServerInfo(name: "test-server", version: "1.0.0")
                )
                let resultData = try! JSONEncoder().encode(initResult)
                let resultValue = try! JSONDecoder().decode(JSONValue.self, from: resultData)
                let response = JSONRPCResponse(id: request.id, result: resultValue)
                try! transport.injectResponse(response)
            } else if request.method == "tools/list" {
                let toolsResult = MCPToolsListResult(tools: [
                    MCPToolDefinition(name: "XcodeListWindows", description: "Lists windows"),
                    MCPToolDefinition(name: "XcodeRead", description: "Reads a file"),
                ])
                let resultData = try! JSONEncoder().encode(toolsResult)
                let resultValue = try! JSONDecoder().decode(JSONValue.self, from: resultData)
                let response = JSONRPCResponse(id: request.id, result: resultValue)
                try! transport.injectResponse(response)
            }
        }

        let client = MCPClient(transport: transport)
        try await client.connect()

        let tools = try await client.listTools()
        #expect(tools.count == 2)
        #expect(tools[0].name == "XcodeListWindows")
        #expect(tools[1].name == "XcodeRead")

        await client.disconnect()
    }

    @Test("Custom timeout on callTool fires before default timeout")
    func callToolCustomTimeout() async throws {
        let transport = MockTransport()

        transport.onSend = { data in
            guard let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
                return
            }

            if request.method == "initialize" {
                let initResult = MCPInitializeResult(
                    protocolVersion: "2024-11-05",
                    capabilities: MCPServerCapabilities(),
                    serverInfo: MCPServerInfo(name: "test-server", version: "1.0.0")
                )
                let resultData = try! JSONEncoder().encode(initResult)
                let resultValue = try! JSONDecoder().decode(JSONValue.self, from: resultData)
                let response = JSONRPCResponse(id: request.id, result: resultValue)
                try! transport.injectResponse(response)
            }
            // Do NOT respond to tools/call — let it time out
        }

        let client = MCPClient(transport: transport, requestTimeout: .seconds(60))
        try await client.connect()

        let start = ContinuousClock.now
        await #expect(throws: MCPClientError.self) {
            try await client.callTool(name: "SlowTool", timeout: .milliseconds(500))
        }
        let elapsed = ContinuousClock.now - start

        // Should time out in ~0.5s, not 60s
        #expect(elapsed < .seconds(5))

        await client.disconnect()
    }

    @Test("Tool call succeeds")
    func callTool() async throws {
        let transport = MockTransport()

        transport.onSend = { data in
            guard let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
                return
            }

            if request.method == "initialize" {
                let initResult = MCPInitializeResult(
                    protocolVersion: "2024-11-05",
                    capabilities: MCPServerCapabilities(),
                    serverInfo: MCPServerInfo(name: "test-server", version: "1.0.0")
                )
                let resultData = try! JSONEncoder().encode(initResult)
                let resultValue = try! JSONDecoder().decode(JSONValue.self, from: resultData)
                let response = JSONRPCResponse(id: request.id, result: resultValue)
                try! transport.injectResponse(response)
            } else if request.method == "tools/call" {
                let callResult = MCPToolCallResult(content: [.text("Window list here")])
                let resultData = try! JSONEncoder().encode(callResult)
                let resultValue = try! JSONDecoder().decode(JSONValue.self, from: resultData)
                let response = JSONRPCResponse(id: request.id, result: resultValue)
                try! transport.injectResponse(response)
            }
        }

        let client = MCPClient(transport: transport)
        try await client.connect()

        let result = try await client.callTool(name: "XcodeListWindows")
        #expect(result.content.count == 1)
        #expect(result.content[0] == .text("Window list here"))

        await client.disconnect()
    }
}
