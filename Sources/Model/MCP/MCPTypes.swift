import Foundation

// MARK: - Initialize (Handshake)

/// Client information
public struct MCPClientInfo: Codable, Sendable {
    public var name: String
    public var version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

/// Client capabilities
public struct MCPClientCapabilities: Codable, Sendable {
    public init() {}
}

/// Parameters for the initialize request
public struct MCPInitializeParams: Codable, Sendable {
    public var protocolVersion: String
    public var capabilities: MCPClientCapabilities
    public var clientInfo: MCPClientInfo

    public init(
        protocolVersion: String = "2024-11-05",
        capabilities: MCPClientCapabilities = MCPClientCapabilities(),
        clientInfo: MCPClientInfo
    ) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.clientInfo = clientInfo
    }
}

/// Server information
public struct MCPServerInfo: Codable, Sendable {
    public var name: String
    public var version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

/// Server capabilities
public struct MCPServerCapabilities: Codable, Sendable {
    public var tools: ToolsCapability?

    public struct ToolsCapability: Codable, Sendable {
        public var listChanged: Bool?
    }

    public init(tools: ToolsCapability? = nil) {
        self.tools = tools
    }
}

/// Result of the initialize response
public struct MCPInitializeResult: Codable, Sendable {
    public var protocolVersion: String
    public var capabilities: MCPServerCapabilities
    public var serverInfo: MCPServerInfo

    public init(
        protocolVersion: String,
        capabilities: MCPServerCapabilities,
        serverInfo: MCPServerInfo
    ) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.serverInfo = serverInfo
    }
}

// MARK: - Tools

/// Tool definition
public struct MCPToolDefinition: Codable, Sendable {
    public var name: String
    public var description: String?
    public var inputSchema: JSONValue?

    public init(name: String, description: String? = nil, inputSchema: JSONValue? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// tools/list response
public struct MCPToolsListResult: Codable, Sendable {
    public var tools: [MCPToolDefinition]

    public init(tools: [MCPToolDefinition]) {
        self.tools = tools
    }
}

// MARK: - Tool Call

/// Parameters for the tools/call request
public struct MCPToolCallParams: Codable, Sendable {
    public var name: String
    public var arguments: [String: JSONValue]?

    public init(name: String, arguments: [String: JSONValue]? = nil) {
        self.name = name
        self.arguments = arguments
    }
}

/// Result of the tools/call response
public struct MCPToolCallResult: Codable, Sendable {
    public var content: [MCPContent]
    public var isError: Bool?
    /// Xcode MCP bridge returns actual data in this field instead of `content`.
    public var message: String?

    public init(content: [MCPContent], isError: Bool? = nil, message: String? = nil) {
        self.content = content
        self.isError = isError
        self.message = message
    }
}

// MARK: - Content

/// MCP content type
public enum MCPContent: Sendable, Hashable {
    case text(String)
    case image(data: String, mimeType: String)
    case resource(uri: String, mimeType: String?, text: String?)
}

extension MCPContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType, uri
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image":
            let data = try container.decode(String.self, forKey: .data)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .image(data: data, mimeType: mimeType)
        case "resource":
            let uri = try container.decode(String.self, forKey: .uri)
            let mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
            let text = try container.decodeIfPresent(String.self, forKey: .text)
            self = .resource(uri: uri, mimeType: mimeType, text: text)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown content type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let data, let mimeType):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .resource(let uri, let mimeType, let text):
            try container.encode("resource", forKey: .type)
            try container.encode(uri, forKey: .uri)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
            try container.encodeIfPresent(text, forKey: .text)
        }
    }
}
