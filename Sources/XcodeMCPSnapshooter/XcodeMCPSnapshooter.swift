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

    @Option(name: .long, parsing: .upToNextOption,
            help: "Patterns to exclude preview files (e.g., --exclude Tests/ --exclude Generated)")
    var exclude: [String] = []

    @Flag(name: .long, help: "Suppress progress and informational messages")
    var quiet: Bool = false

    @Argument(help: "File name patterns to filter preview files (e.g., ContentView.swift Views/)")
    var fileFilters: [String] = []

    func run() async throws {
        let serverPath = "/usr/bin/xcrun"
        let transport = StdioTransport(serverPath: serverPath, arguments: ["mcpbridge"])
        let client = MCPClient(transport: transport)

        log("Connecting to MCP server...")

        do {
            try await client.connect()

            let info = await client.serverInfo
            if let info {
                log("Connected to: \(info.name) v\(info.version)")
            }

            log("Xcode may show a permission dialog. Please click \"Allow\" to continue.")

            // Call XcodeListWindows with extended timeout for permission dialog
            let result: MCPToolCallResult
            do {
                result = try await withProgressReporting(interval: .seconds(5), quiet: quiet) {
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

            log("\nSelected Project:")
            log("  Name: \(matched.name)")
            log("  Path: \(matched.workspacePath)")

            guard let tabIdentifier = matched.tabIdentifiers.first else {
                log("Error: No tab identifier available for the project.")
                await client.disconnect()
                return
            }
            log("  Tab:  \(tabIdentifier)")

            // Find preview targets (files + preview indices)
            let service = SnapshotService(client: client, renderTimeout: renderTimeout)
            let allTargets = try await service.findPreviewTargets(tabIdentifier: tabIdentifier)
            let included = filterTargets(allTargets, by: fileFilters)
            let targets = excludeTargets(included, by: exclude)

            if !fileFilters.isEmpty || !exclude.isEmpty {
                let allFiles = Set(allTargets.map(\.filePath))
                let matchedFiles = Set(targets.map(\.filePath))
                if !fileFilters.isEmpty {
                    log("\nInclude patterns: \(fileFilters.joined(separator: ", "))")
                }
                if !exclude.isEmpty {
                    log("\nExclude patterns: \(exclude.joined(separator: ", "))")
                }
                log("Matched \(matchedFiles.count) of \(allFiles.count) preview file(s) (\(targets.count) preview(s)).")
            }

            if targets.isEmpty {
                log("\nNo preview files found in the project.")
                await client.disconnect()
                return
            }

            // If --list flag, show file list and stop
            if list {
                let grouped = Dictionary(grouping: targets, by: \.filePath)
                let uniqueFiles = grouped.keys.sorted()
                if !quiet { print() }
                print("Found \(targets.count) preview(s) in \(uniqueFiles.count) file(s):")
                for file in uniqueFiles {
                    let count = grouped[file]!.count
                    if count > 1 {
                        print("  - \(file) (\(count) previews)")
                    } else {
                        print("  - \(file)")
                    }
                }
                await client.disconnect()
                log("\nDisconnected.")
                return
            }

            // Capture snapshots
            let outputDir = (output as NSString).standardizingPath
            log("\nCapturing \(targets.count) snapshot(s) to: \(outputDir)")

            let results = await service.captureAllSnapshots(
                tabIdentifier: tabIdentifier,
                targets: targets,
                outputDirectory: outputDir,
                progress: { current, total, displayName in
                    let text = "  [\(current)/\(total)] Rendering \(displayName)..."
                    self.logInline("\r\u{1B}[2K\(text)")
                    if current == total {
                        self.log("")  // final newline
                    }
                }
            )

            // Print summary
            let succeeded = results.filter { if case .success = $0.result { return true } else { return false } }
            let failed = results.filter { if case .failure = $0.result { return true } else { return false } }

            if !quiet { print() }
            print("Snapshot Summary:")
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
                log("\nSnapshots saved to: \(outputDir)")
            }

            await client.disconnect()
            log("\nDisconnected.")
        } catch {
            await client.disconnect()
            throw error
        }
    }

    private func log(_ message: String) {
        guard !quiet else { return }
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private func logInline(_ message: String) {
        guard !quiet else { return }
        FileHandle.standardError.write(Data(message.utf8))
    }

    private func filterTargets(_ targets: [PreviewTarget], by patterns: [String]) -> [PreviewTarget] {
        guard !patterns.isEmpty else { return targets }
        return targets.filter { target in
            patterns.contains { pattern in
                target.filePath.localizedCaseInsensitiveContains(pattern)
            }
        }
    }

    private func excludeTargets(_ targets: [PreviewTarget], by patterns: [String]) -> [PreviewTarget] {
        guard !patterns.isEmpty else { return targets }
        return targets.filter { target in
            !patterns.contains { pattern in
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
    quiet: Bool = false,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    guard !quiet else {
        return try await operation()
    }

    let start = ContinuousClock.now

    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            while !Task.isCancelled {
                try await Task.sleep(for: interval)
                let elapsed = Int((ContinuousClock.now - start) / .seconds(1))
                let message = "\r\u{1B}[2K  Still waiting for Xcode response... (\(elapsed)s elapsed)"
                FileHandle.standardError.write(Data(message.utf8))
            }
            throw CancellationError()
        }

        let result = try await group.next()!
        group.cancelAll()
        // Clear the progress line
        FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
        return result
    }
}
