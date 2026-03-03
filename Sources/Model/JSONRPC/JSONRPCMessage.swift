import Foundation

// MARK: - JSONValue

/// A type representing an arbitrary JSON value
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode JSONValue")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

// MARK: - ExpressibleBy Literals

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - RequestID

/// JSON-RPC request ID (Int or String)
public enum RequestID: Sendable, Hashable {
    case int(Int)
    case string(String)
}

extension RequestID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "RequestID must be Int or String")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

// MARK: - JSON-RPC 2.0 Messages

/// JSON-RPC 2.0 request
public struct JSONRPCRequest: Codable, Sendable {
    public var jsonrpc: String = "2.0"
    public var id: RequestID
    public var method: String
    public var params: [String: JSONValue]?

    public init(id: RequestID, method: String, params: [String: JSONValue]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 notification (no ID)
public struct JSONRPCNotification: Codable, Sendable {
    public var jsonrpc: String = "2.0"
    public var method: String
    public var params: [String: JSONValue]?

    public init(method: String, params: [String: JSONValue]? = nil) {
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 error detail
public struct JSONRPCErrorDetail: Codable, Sendable {
    public var code: Int
    public var message: String
    public var data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

/// JSON-RPC 2.0 response
public struct JSONRPCResponse: Codable, Sendable {
    public var jsonrpc: String = "2.0"
    public var id: RequestID?
    public var result: JSONValue?
    public var error: JSONRPCErrorDetail?

    public init(id: RequestID?, result: JSONValue?, error: JSONRPCErrorDetail? = nil) {
        self.id = id
        self.result = result
        self.error = error
    }
}

// MARK: - Incoming Message

/// Incoming message from the server (response or notification)
public enum JSONRPCIncoming: Sendable {
    case response(JSONRPCResponse)
    case notification(JSONRPCNotification)
}

extension JSONRPCIncoming {
    /// Parse incoming JSON data
    public static func parse(from data: Data) throws -> JSONRPCIncoming {
        let decoder = JSONDecoder()

        // Determine response or notification by the presence of the id field
        // First, attempt a generic decode
        struct Probe: Decodable {
            var id: RequestID?
            var method: String?
        }
        let probe = try decoder.decode(Probe.self, from: data)

        if probe.id != nil {
            let response = try decoder.decode(JSONRPCResponse.self, from: data)
            return .response(response)
        } else if probe.method != nil {
            let notification = try decoder.decode(JSONRPCNotification.self, from: data)
            return .notification(notification)
        } else {
            // If neither id nor method is present, treat as a response
            let response = try decoder.decode(JSONRPCResponse.self, from: data)
            return .response(response)
        }
    }
}
