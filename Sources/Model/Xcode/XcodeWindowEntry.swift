import Foundation

/// Window entry extracted from XcodeListWindows result
public struct XcodeWindowEntry: Sendable, Hashable {
    public let tabIdentifier: String
    public let workspacePath: String

    public init(tabIdentifier: String, workspacePath: String) {
        self.tabIdentifier = tabIdentifier
        self.workspacePath = workspacePath
    }
}
