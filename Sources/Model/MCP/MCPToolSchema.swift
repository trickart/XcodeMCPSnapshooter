import Foundation

/// Tool definition loaded from an NDJSON schema file
public struct MCPToolSchema: Codable, Sendable {
    public var name: String
    public var description: String
    public var parameters: Parameters

    public struct Parameters: Codable, Sendable {
        public var properties: [String: Property]
        public var required: [String]
    }

    public struct Property: Codable, Sendable {
        public var description: String?
        public var type: String?
        public var items: Items?
        public var properties: [String: Property]?
        public var `required`: [String]?
        public var `enum`: [String]?
    }

    public struct Items: Codable, Sendable {
        public var type: String?
        public var properties: [String: Property]?
        public var `required`: [String]?
    }
}

extension MCPToolSchema {
    /// Load tool schemas from an NDJSON file
    public static func loadFromNDJSON(at url: URL) throws -> [MCPToolSchema] {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }

        let decoder = JSONDecoder()
        return try lines.map { line in
            let lineData = Data(line.utf8)
            return try decoder.decode(MCPToolSchema.self, from: lineData)
        }
    }
}
