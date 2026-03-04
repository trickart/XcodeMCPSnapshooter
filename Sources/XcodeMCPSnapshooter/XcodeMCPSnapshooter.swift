import ArgumentParser
import Foundation
import Model

@main
struct XcodeMCPSnapshooter: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xmsnap",
        abstract: "CLI tool to connect to the Xcode MCP server and take preview snapshots"
    )

    @Option(name: [.short, .long], help: "Path to the Xcode project or directory to target")
    var project: String?

    @Option(name: [.short, .long], help: "Output directory for snapshots (default: ./snapshots)")
    var output: String = "./snapshots"

    @Option(name: .long, help: "Render timeout in seconds per preview (default: 120)")
    var renderTimeout: Int = 120

    @Flag(name: [.short, .long], help: "List preview files only without capturing snapshots")
    var list: Bool = false

    @Argument(help: "File name patterns to filter preview files (e.g., ContentView.swift Views/)")
    var fileFilters: [String] = []

    func run() async throws {
        let serverPath = "/usr/bin/xcrun"
        let transport = StdioTransport(serverPath: serverPath, arguments: ["mcpbridge"])
        let client = MCPClient(transport: transport)

        print("Connecting to MCP server...")

        do {
            try await client.connect()

            let info = await client.serverInfo
            if let info {
                print("Connected to: \(info.name) v\(info.version)")
            }

            print("Xcode may show a permission dialog. Please click \"Allow\" to continue.")

            // Call XcodeListWindows with extended timeout for permission dialog
            let result: MCPToolCallResult
            do {
                result = try await withProgressReporting(interval: .seconds(5)) {
                    try await client.callTool(
                        name: "XcodeListWindows",
                        timeout: .seconds(30)
                    )
                }
            } catch let error as MCPClientError {
                switch error {
                case .timeout:
                    throw PermissionError.timeout
                default:
                    throw error
                }
            }
            let projects = XcodeWindowParser.parseProjects(from: result)

            // Determine the target path
            let targetPath = project ?? FileManager.default.currentDirectoryPath

            // Resolve to a concrete project file path
            let resolvedPath = try ProjectDiscovery.findProjectFile(in: targetPath)

            // Match against open Xcode projects
            let matched = try ProjectDiscovery.matchProject(path: resolvedPath, in: projects)

            print("\nSelected Project:")
            print("  Name: \(matched.name)")
            print("  Path: \(matched.workspacePath)")

            guard let tabIdentifier = matched.tabIdentifiers.first else {
                print("Error: No tab identifier available for the project.")
                await client.disconnect()
                return
            }
            print("  Tab:  \(tabIdentifier)")

            // Find preview targets (files + preview indices)
            let service = SnapshotService(client: client, renderTimeout: renderTimeout)
            let allTargets = try await service.findPreviewTargets(tabIdentifier: tabIdentifier)
            let targets = filterTargets(allTargets, by: fileFilters)

            if !fileFilters.isEmpty {
                let allFiles = Set(allTargets.map(\.filePath))
                let matchedFiles = Set(targets.map(\.filePath))
                print("\nFilter patterns: \(fileFilters.joined(separator: ", "))")
                print("Matched \(matchedFiles.count) of \(allFiles.count) preview file(s) (\(targets.count) preview(s)).")
            }

            if targets.isEmpty {
                print("\nNo preview files found in the project.")
                await client.disconnect()
                return
            }

            // If --list flag, show file list and stop
            if list {
                let grouped = Dictionary(grouping: targets, by: \.filePath)
                let uniqueFiles = grouped.keys.sorted()
                print("\nFound \(targets.count) preview(s) in \(uniqueFiles.count) file(s):")
                for file in uniqueFiles {
                    let count = grouped[file]!.count
                    if count > 1 {
                        print("  - \(file) (\(count) previews)")
                    } else {
                        print("  - \(file)")
                    }
                }
                await client.disconnect()
                print("\nDisconnected.")
                return
            }

            // Capture snapshots
            let outputDir = (output as NSString).standardizingPath
            print("\nCapturing \(targets.count) snapshot(s) to: \(outputDir)")

            let results = await service.captureAllSnapshots(
                tabIdentifier: tabIdentifier,
                targets: targets,
                outputDirectory: outputDir,
                progress: { current, total, displayName in
                    let text = "  [\(current)/\(total)] Rendering \(displayName)..."
                    print("\r\u{1B}[2K\(text)", terminator: "")
                    fflush(stdout)
                    if current == total {
                        print()  // final newline
                    }
                }
            )

            // Print summary
            let succeeded = results.filter { if case .success = $0.result { return true } else { return false } }
            let failed = results.filter { if case .failure = $0.result { return true } else { return false } }

            print("\nSnapshot Summary:")
            print("  Total:     \(results.count)")
            print("  Succeeded: \(succeeded.count)")
            print("  Failed:    \(failed.count)")

            for result in succeeded {
                if case .success(let path) = result.result {
                    print("  OK: \(result.sourceFilePath) -> \(path)")
                }
            }

            for result in failed {
                if case .failure(let error) = result.result {
                    print("  FAIL: \(result.sourceFilePath) - \(error)")
                }
            }

            if !succeeded.isEmpty {
                print("\nSnapshots saved to: \(outputDir)")
            }

            await client.disconnect()
            print("\nDisconnected.")
        } catch {
            await client.disconnect()
            throw error
        }
    }

    private func filterTargets(_ targets: [PreviewTarget], by patterns: [String]) -> [PreviewTarget] {
        guard !patterns.isEmpty else { return targets }
        return targets.filter { target in
            patterns.contains { pattern in
                target.filePath.localizedCaseInsensitiveContains(pattern)
            }
        }
    }
}

// MARK: - Permission Dialog Support

enum PermissionError: Error, LocalizedError {
    case timeout

    var errorDescription: String? {
        switch self {
        case .timeout:
            return """
                Timed out waiting for Xcode permission dialog response.
                If you clicked "Don't Allow", grant access and re-run the command.
                Otherwise, re-run and click "Allow" when the dialog appears.
                """
        }
    }
}

/// Runs `operation` while printing progress messages at the given `interval`.
func withProgressReporting<T: Sendable>(
    interval: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let start = ContinuousClock.now

    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            while !Task.isCancelled {
                try await Task.sleep(for: interval)
                let elapsed = Int((ContinuousClock.now - start) / .seconds(1))
                print("\r\u{1B}[2K  Still waiting for Xcode response... (\(elapsed)s elapsed)", terminator: "")
                fflush(stdout)
            }
            throw CancellationError()
        }

        let result = try await group.next()!
        group.cancelAll()
        // Clear the progress line
        print("\r\u{1B}[2K", terminator: "")
        fflush(stdout)
        return result
    }
}
