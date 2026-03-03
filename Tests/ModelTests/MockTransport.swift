import Foundation
import Synchronization
@testable import Model

/// Mock transport for testing
/// Allows injecting responses from tests
public final class MockTransport: MCPTransport, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    public let messages: AsyncThrowingStream<Data, Error>

    /// Records sent messages
    private let _sentMessages = Mutex<[Data]>([])

    public var sentMessages: [Data] {
        _sentMessages.withLock { $0 }
    }

    /// Handler called on send (used to inject responses from tests)
    public var onSend: (@Sendable (Data) -> Void)?

    private var started = false

    public init() {
        (self.messages, self.continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    }

    public func start() async throws {
        started = true
    }

    public func send(_ data: Data) async throws {
        _sentMessages.withLock { $0.append(data) }
        onSend?(data)
    }

    public func stop() async throws {
        continuation.finish()
    }

    /// Inject a message from a test
    public func injectMessage(_ data: Data) {
        continuation.yield(data)
    }

    /// Inject a JSON-encoded message from a test
    public func injectResponse(_ response: JSONRPCResponse) throws {
        let data = try JSONEncoder().encode(response)
        injectMessage(data)
    }
}
