import Foundation

/// Errors thrown by ProjectDiscovery methods
public enum ProjectDiscoveryError: Error, CustomStringConvertible {
    /// The specified path does not exist on disk
    case noProjectFileFound(directory: String)
    /// No Xcode project matching the given path is currently open
    case projectNotOpenInXcode(path: String)
    /// Multiple open Xcode projects matched the given path
    case multipleProjectsMatched([XcodeProject])

    public var description: String {
        switch self {
        case .noProjectFileFound(let directory):
            return "No project file found at: \(directory)"
        case .projectNotOpenInXcode(let path):
            return "No matching project is open in Xcode: \(path)"
        case .multipleProjectsMatched(let projects):
            let names = projects.map(\.name).joined(separator: ", ")
            return "Multiple projects matched: \(names)"
        }
    }
}

/// Utility for discovering and matching Xcode projects
public enum ProjectDiscovery {

    /// Resolve a user-supplied path to a concrete project file path.
    ///
    /// - If the path points to a `.xcworkspace` or `.xcodeproj` file, return it as-is.
    /// - If the path is a directory, search its immediate children for `.xcworkspace`
    ///   (preferred) or `.xcodeproj`.
    /// - If no project file is found, return the directory path itself (SPM projects).
    ///
    /// - Throws: ``ProjectDiscoveryError/noProjectFileFound(directory:)`` if the path
    ///   does not exist on disk.
    public static func findProjectFile(in path: String) throws -> String {
        let fileManager = FileManager.default
        let standardized = (path as NSString).standardizingPath

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized, isDirectory: &isDirectory) else {
            throw ProjectDiscoveryError.noProjectFileFound(directory: path)
        }

        // If the path is a file (.xcworkspace or .xcodeproj are technically directories,
        // but they appear as files to the user), return it directly.
        if !isDirectory.boolValue
            || standardized.hasSuffix(".xcworkspace")
            || standardized.hasSuffix(".xcodeproj") {
            return standardized
        }

        // Search directory for project files
        let contents = (try? fileManager.contentsOfDirectory(atPath: standardized)) ?? []

        // Prefer .xcworkspace over .xcodeproj
        if let workspace = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return (standardized as NSString).appendingPathComponent(workspace)
        }
        if let project = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return (standardized as NSString).appendingPathComponent(project)
        }

        // No project file found — assume SPM project, return directory itself
        return standardized
    }

    /// Find the open Xcode project that matches the given path.
    ///
    /// Matching strategy:
    /// 1. Exact match on normalised `workspacePath`.
    /// 2. Containment: the path is a parent of `workspacePath`, or vice-versa.
    ///
    /// - Throws:
    ///   - ``ProjectDiscoveryError/projectNotOpenInXcode(path:)`` if no match is found.
    ///   - ``ProjectDiscoveryError/multipleProjectsMatched(_:)`` if more than one project matches.
    public static func matchProject(path: String, in projects: [XcodeProject]) throws -> XcodeProject {
        let normalized = normalizePath(path)

        // 1. Exact match
        let exactMatches = projects.filter { normalizePath($0.workspacePath) == normalized }
        if exactMatches.count == 1 { return exactMatches[0] }
        if exactMatches.count > 1 { throw ProjectDiscoveryError.multipleProjectsMatched(exactMatches) }

        // 2. Containment match
        let containmentMatches = projects.filter { project in
            let wp = normalizePath(project.workspacePath)
            return wp.hasPrefix(normalized + "/") || normalized.hasPrefix(wp + "/")
        }

        switch containmentMatches.count {
        case 1:
            return containmentMatches[0]
        case 0:
            throw ProjectDiscoveryError.projectNotOpenInXcode(path: path)
        default:
            throw ProjectDiscoveryError.multipleProjectsMatched(containmentMatches)
        }
    }

    /// Normalize a path by standardizing and removing a trailing slash.
    static func normalizePath(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        if standardized.hasSuffix("/") && standardized != "/" {
            return String(standardized.dropLast())
        }
        return standardized
    }
}
