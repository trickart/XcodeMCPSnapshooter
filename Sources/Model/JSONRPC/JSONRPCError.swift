import Foundation

/// JSON-RPC 2.0 standard error codes
public enum JSONRPCErrorCode {
    /// Parse error
    public static let parseError = -32700
    /// Invalid request
    public static let invalidRequest = -32600
    /// Method not found
    public static let methodNotFound = -32601
    /// Invalid params
    public static let invalidParams = -32602
    /// Internal error
    public static let internalError = -32603
}
