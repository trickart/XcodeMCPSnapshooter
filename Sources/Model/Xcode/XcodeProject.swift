import Foundation

/// Project information grouped by workspacePath
public struct XcodeProject: Sendable {
    public let workspacePath: String
    public let tabIdentifiers: [String]

    /// Project name (last path component without extension)
    public var name: String {
        let url = URL(fileURLWithPath: workspacePath)
        return url.deletingPathExtension().lastPathComponent
    }

    public init(workspacePath: String, tabIdentifiers: [String]) {
        self.workspacePath = workspacePath
        self.tabIdentifiers = tabIdentifiers
    }
}
