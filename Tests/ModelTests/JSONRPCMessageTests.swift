import Foundation
import Testing
@testable import Model

@Suite("JSONValue Tests")
struct JSONValueTests {
    @Test("null encode/decode")
    func nullRoundTrip() throws {
        let value: JSONValue = .null
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .null)
    }

    @Test("bool encode/decode")
    func boolRoundTrip() throws {
        let value: JSONValue = .bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .bool(true))
    }

    @Test("int encode/decode")
    func intRoundTrip() throws {
        let value: JSONValue = .int(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .int(42))
    }

    @Test("double encode/decode")
    func doubleRoundTrip() throws {
        let value: JSONValue = .double(3.14)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .double(3.14))
    }

    @Test("string encode/decode")
    func stringRoundTrip() throws {
        let value: JSONValue = .string("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .string("hello"))
    }

    @Test("array encode/decode")
    func arrayRoundTrip() throws {
        let value: JSONValue = .array([.int(1), .string("two"), .bool(false)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .array([.int(1), .string("two"), .bool(false)]))
    }

    @Test("object encode/decode")
    func objectRoundTrip() throws {
        let value: JSONValue = .object(["key": .string("value"), "num": .int(1)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .object(["key": .string("value"), "num": .int(1)]))
    }

    @Test("Can initialize with literal syntax")
    func literals() {
        let _: JSONValue = nil
        let _: JSONValue = true
        let _: JSONValue = 42
        let _: JSONValue = 3.14
        let _: JSONValue = "hello"
        let _: JSONValue = [1, 2, 3]
        let _: JSONValue = ["key": "value"]
    }
}

@Suite("RequestID Tests")
struct RequestIDTests {
    @Test("Int ID encode/decode")
    func intID() throws {
        let id: RequestID = .int(1)
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(RequestID.self, from: data)
        #expect(decoded == .int(1))
    }

    @Test("String ID encode/decode")
    func stringID() throws {
        let id: RequestID = .string("abc-123")
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(RequestID.self, from: data)
        #expect(decoded == .string("abc-123"))
    }
}

@Suite("JSONRPCRequest Tests")
struct JSONRPCRequestTests {
    @Test("Request round-trip")
    func roundTrip() throws {
        let request = JSONRPCRequest(
            id: .int(1),
            method: "initialize",
            params: ["protocolVersion": .string("2024-11-05")]
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(JSONRPCRequest.self, from: data)

        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == .int(1))
        #expect(decoded.method == "initialize")
        #expect(decoded.params?["protocolVersion"] == .string("2024-11-05"))
    }
}

@Suite("JSONRPCResponse Tests")
struct JSONRPCResponseTests {
    @Test("Success response round-trip")
    func successRoundTrip() throws {
        let response = JSONRPCResponse(
            id: .int(1),
            result: .object(["name": .string("test")])
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)

        #expect(decoded.id == .int(1))
        #expect(decoded.result == .object(["name": .string("test")]))
        #expect(decoded.error == nil)
    }

    @Test("Error response round-trip")
    func errorRoundTrip() throws {
        let response = JSONRPCResponse(
            id: .int(1),
            result: nil,
            error: JSONRPCErrorDetail(code: -32601, message: "Method not found")
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)

        #expect(decoded.id == .int(1))
        #expect(decoded.result == nil)
        #expect(decoded.error?.code == -32601)
        #expect(decoded.error?.message == "Method not found")
    }
}

@Suite("JSONRPCIncoming Tests")
struct JSONRPCIncomingTests {
    @Test("Parsed as response")
    func parseResponse() throws {
        let json = #"{"jsonrpc":"2.0","id":1,"result":{"ok":true}}"#
        let data = Data(json.utf8)
        let incoming = try JSONRPCIncoming.parse(from: data)

        guard case .response(let response) = incoming else {
            Issue.record("Expected response")
            return
        }
        #expect(response.id == .int(1))
    }

    @Test("Parsed as notification")
    func parseNotification() throws {
        let json = #"{"jsonrpc":"2.0","method":"notifications/progress","params":{}}"#
        let data = Data(json.utf8)
        let incoming = try JSONRPCIncoming.parse(from: data)

        guard case .notification(let notification) = incoming else {
            Issue.record("Expected notification")
            return
        }
        #expect(notification.method == "notifications/progress")
    }
}
