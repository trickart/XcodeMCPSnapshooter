import Foundation

/// Abstract protocol for MCP transport
public protocol MCPTransport: Sendable {
    /// Send a message
    func send(_ data: Data) async throws

    /// Stream of incoming messages
    var messages: AsyncThrowingStream<Data, Error> { get }

    /// Start the transport
    func start() async throws

    /// Stop the transport
    func stop() async throws
}
