import Foundation
import Testing
@testable import Model

@Suite("MCPInitializeParams Tests")
struct MCPInitializeParamsTests {
    @Test("Encode/Decode")
    func roundTrip() throws {
        let params = MCPInitializeParams(
            clientInfo: MCPClientInfo(name: "test", version: "1.0")
        )
        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(MCPInitializeParams.self, from: data)

        #expect(decoded.protocolVersion == "2024-11-05")
        #expect(decoded.clientInfo.name == "test")
        #expect(decoded.clientInfo.version == "1.0")
    }
}

@Suite("MCPInitializeResult Tests")
struct MCPInitializeResultTests {
    @Test("Encode/Decode")
    func roundTrip() throws {
        let result = MCPInitializeResult(
            protocolVersion: "2024-11-05",
            capabilities: MCPServerCapabilities(
                tools: .init(listChanged: true)
            ),
            serverInfo: MCPServerInfo(name: "xcode-mcp", version: "0.1.0")
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(MCPInitializeResult.self, from: data)

        #expect(decoded.protocolVersion == "2024-11-05")
        #expect(decoded.serverInfo.name == "xcode-mcp")
        #expect(decoded.capabilities.tools?.listChanged == true)
    }
}

@Suite("MCPToolCallParams Tests")
struct MCPToolCallParamsTests {
    @Test("Encode/Decode")
    func roundTrip() throws {
        let params = MCPToolCallParams(
            name: "XcodeListWindows",
            arguments: ["tabIdentifier": .string("tab-1")]
        )
        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(MCPToolCallParams.self, from: data)

        #expect(decoded.name == "XcodeListWindows")
        #expect(decoded.arguments?["tabIdentifier"] == .string("tab-1"))
    }
}

@Suite("MCPToolCallResult Tests")
struct MCPToolCallResultTests {
    @Test("Decode text content")
    func textContent() throws {
        let json = #"{"content":[{"type":"text","text":"Hello"}]}"#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(MCPToolCallResult.self, from: data)

        #expect(result.content.count == 1)
        #expect(result.content[0] == .text("Hello"))
    }

    @Test("Result with error flag")
    func errorResult() throws {
        let json = #"{"content":[{"type":"text","text":"Error occurred"}],"isError":true}"#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(MCPToolCallResult.self, from: data)

        #expect(result.isError == true)
    }

    @Test("Decode result with message field")
    func messageField() throws {
        let json = #"{"content":[],"message":"* tabIdentifier: tab1, workspacePath: /Users/test/App.xcworkspace"}"#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(MCPToolCallResult.self, from: data)

        #expect(result.content.isEmpty)
        #expect(result.message == "* tabIdentifier: tab1, workspacePath: /Users/test/App.xcworkspace")
    }
}

@Suite("MCPContent Tests")
struct MCPContentTests {
    @Test("Text content round-trip")
    func textRoundTrip() throws {
        let content: MCPContent = .text("Hello, World!")
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(MCPContent.self, from: data)
        #expect(decoded == .text("Hello, World!"))
    }

    @Test("Image content round-trip")
    func imageRoundTrip() throws {
        let content: MCPContent = .image(data: "base64data", mimeType: "image/png")
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(MCPContent.self, from: data)
        #expect(decoded == .image(data: "base64data", mimeType: "image/png"))
    }

    @Test("Resource content round-trip")
    func resourceRoundTrip() throws {
        let content: MCPContent = .resource(uri: "file:///test.txt", mimeType: "text/plain", text: "content")
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(MCPContent.self, from: data)
        #expect(decoded == .resource(uri: "file:///test.txt", mimeType: "text/plain", text: "content"))
    }
}

@Suite("MCPToolSchema Tests")
struct MCPToolSchemaTests {
    @Test("Decode from JSON")
    func decodeFromJSON() throws {
        let json = """
        {"name":"XcodeListWindows","description":"Lists windows","parameters":{"properties":{},"required":[]}}
        """
        let data = Data(json.utf8)
        let schema = try JSONDecoder().decode(MCPToolSchema.self, from: data)

        #expect(schema.name == "XcodeListWindows")
        #expect(schema.description == "Lists windows")
        #expect(schema.parameters.required.isEmpty)
    }
}
