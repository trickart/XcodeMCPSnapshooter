import Foundation

/// MCPClient error type
public enum MCPClientError: Error, LocalizedError {
    case notConnected
    case alreadyConnected
    case connectionFailed(String)
    case timeout
    case serverError(code: Int, message: String)
    case invalidResponse(String)
    case transportError(Error)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to MCP server"
        case .alreadyConnected:
            return "Already connected to MCP server"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .timeout:
            return "Request timed out"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .invalidResponse(let detail):
            return "Invalid response: \(detail)"
        case .transportError(let error):
            return "Transport error: \(error.localizedDescription)"
        }
    }
}
