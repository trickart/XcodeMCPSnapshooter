import Foundation
import Testing
@testable import Model

@Suite("ProjectDiscovery Tests")
struct ProjectDiscoveryTests {

    // MARK: - matchProject

    let sampleProjects: [XcodeProject] = [
        XcodeProject(
            workspacePath: "/Users/test/MyApp/MyApp.xcworkspace",
            tabIdentifiers: ["tab1"]
        ),
        XcodeProject(
            workspacePath: "/Users/test/OtherApp/OtherApp.xcodeproj",
            tabIdentifiers: ["tab2"]
        ),
        XcodeProject(
            workspacePath: "/Users/test/SPMProject",
            tabIdentifiers: ["tab3"]
        ),
    ]

    @Test("Exact match with .xcworkspace path")
    func exactMatchWorkspace() throws {
        let result = try ProjectDiscovery.matchProject(
            path: "/Users/test/MyApp/MyApp.xcworkspace",
            in: sampleProjects
        )
        #expect(result.name == "MyApp")
        #expect(result.tabIdentifiers == ["tab1"])
    }

    @Test("Exact match with .xcodeproj path")
    func exactMatchXcodeproj() throws {
        let result = try ProjectDiscovery.matchProject(
            path: "/Users/test/OtherApp/OtherApp.xcodeproj",
            in: sampleProjects
        )
        #expect(result.name == "OtherApp")
        #expect(result.tabIdentifiers == ["tab2"])
    }

    @Test("Exact match with SPM directory (no extension)")
    func exactMatchSPM() throws {
        let result = try ProjectDiscovery.matchProject(
            path: "/Users/test/SPMProject",
            in: sampleProjects
        )
        #expect(result.name == "SPMProject")
        #expect(result.tabIdentifiers == ["tab3"])
    }

    @Test("Directory matches workspace file via containment")
    func directoryMatchesWorkspace() throws {
        let result = try ProjectDiscovery.matchProject(
            path: "/Users/test/MyApp",
            in: sampleProjects
        )
        #expect(result.name == "MyApp")
    }

    @Test("Throws projectNotOpenInXcode when no match")
    func noMatch() {
        #expect(throws: ProjectDiscoveryError.self) {
            try ProjectDiscovery.matchProject(
                path: "/Users/test/UnknownProject",
                in: sampleProjects
            )
        }
    }

    @Test("Throws multipleProjectsMatched when ambiguous")
    func multipleMatches() {
        let overlappingProjects: [XcodeProject] = [
            XcodeProject(
                workspacePath: "/Users/test/Shared/AppA.xcworkspace",
                tabIdentifiers: ["tab1"]
            ),
            XcodeProject(
                workspacePath: "/Users/test/Shared/AppB.xcodeproj",
                tabIdentifiers: ["tab2"]
            ),
        ]
        #expect(throws: ProjectDiscoveryError.self) {
            try ProjectDiscovery.matchProject(
                path: "/Users/test/Shared",
                in: overlappingProjects
            )
        }
    }

    @Test("Trailing slash is normalized")
    func trailingSlash() throws {
        let result = try ProjectDiscovery.matchProject(
            path: "/Users/test/SPMProject/",
            in: sampleProjects
        )
        #expect(result.name == "SPMProject")
    }

    // MARK: - findProjectFile

    @Test("Direct path to .xcworkspace is returned as-is")
    func directWorkspacePath() throws {
        // Create a temporary .xcworkspace directory
        let tmpDir = NSTemporaryDirectory() + "ProjectDiscoveryTest-\(UUID().uuidString)"
        let wsPath = tmpDir + "/Test.xcworkspace"
        try FileManager.default.createDirectory(atPath: wsPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let result = try ProjectDiscovery.findProjectFile(in: wsPath)
        #expect(result == (wsPath as NSString).standardizingPath)
    }

    @Test(".xcworkspace is preferred over .xcodeproj in directory")
    func workspacePreferredOverXcodeproj() throws {
        let tmpDir = NSTemporaryDirectory() + "ProjectDiscoveryTest-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tmpDir + "/App.xcworkspace",
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            atPath: tmpDir + "/App.xcodeproj",
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let result = try ProjectDiscovery.findProjectFile(in: tmpDir)
        #expect(result.hasSuffix(".xcworkspace"))
    }

    @Test("Directory without project files returns directory path (SPM)")
    func spmDirectory() throws {
        let tmpDir = NSTemporaryDirectory() + "ProjectDiscoveryTest-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        // Create a Package.swift to simulate an SPM project
        FileManager.default.createFile(
            atPath: tmpDir + "/Package.swift",
            contents: nil
        )
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let result = try ProjectDiscovery.findProjectFile(in: tmpDir)
        #expect(result == (tmpDir as NSString).standardizingPath)
    }

    @Test("Throws noProjectFileFound for nonexistent path")
    func nonexistentPath() {
        #expect(throws: ProjectDiscoveryError.self) {
            try ProjectDiscovery.findProjectFile(in: "/nonexistent/path/to/nothing")
        }
    }
}
