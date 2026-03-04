import Foundation

/// A specific preview definition to capture
public struct PreviewTarget: Sendable, Equatable {
    /// The source Swift file containing the Preview
    public let filePath: String
    /// Zero-based index of the preview definition within the file
    public let previewIndex: Int
    /// Total number of preview definitions in the file
    public let previewCount: Int

    public init(filePath: String, previewIndex: Int, previewCount: Int) {
        self.filePath = filePath
        self.previewIndex = previewIndex
        self.previewCount = previewCount
    }
}

/// Result of a single snapshot capture attempt
public struct SnapshotResult: Sendable {
    /// The source Swift file containing the Preview
    public let sourceFilePath: String
    /// Zero-based index of the preview definition within the file
    public let previewIndex: Int
    /// Success: saved file path, Failure: error
    public let result: Result<String, SnapshotError>

    public init(sourceFilePath: String, previewIndex: Int = 0, result: Result<String, SnapshotError>) {
        self.sourceFilePath = sourceFilePath
        self.previewIndex = previewIndex
        self.result = result
    }
}

/// Errors that can occur during snapshot operations
public enum SnapshotError: Error, CustomStringConvertible, Sendable {
    case renderFailed(String)
    case parseFailed(String)
    case copyFailed(source: String, destination: String, underlying: String)

    public var description: String {
        switch self {
        case .renderFailed(let detail):
            return "Render failed: \(detail)"
        case .parseFailed(let detail):
            return "Parse failed: \(detail)"
        case .copyFailed(let source, let destination, let underlying):
            return "Copy failed from \(source) to \(destination): \(underlying)"
        }
    }
}

/// Orchestrates preview file discovery and snapshot capture
public struct SnapshotService: Sendable {
    private let client: MCPClient
    private let renderTimeout: Int

    /// - Parameters:
    ///   - client: Connected MCPClient instance
    ///   - renderTimeout: Timeout in seconds for each RenderPreview call (default: 120)
    public init(client: MCPClient, renderTimeout: Int = 120) {
        self.client = client
        self.renderTimeout = renderTimeout
    }

    /// Find all Swift files containing #Preview or PreviewProvider in the project.
    ///
    /// Calls XcodeGrep twice (for `#Preview` and `PreviewProvider`), merges and deduplicates results.
    public func findPreviewFiles(tabIdentifier: String) async throws -> [String] {
        let previewMacroResult = try await client.callTool(
            name: "XcodeGrep",
            arguments: [
                "tabIdentifier": .string(tabIdentifier),
                "pattern": .string("#Preview"),
                "outputMode": .string("filesWithMatches"),
            ]
        )
        let previewMacroPaths = try PreviewFileParser.parseFilePaths(from: previewMacroResult)

        let providerResult = try await client.callTool(
            name: "XcodeGrep",
            arguments: [
                "tabIdentifier": .string(tabIdentifier),
                "pattern": .string("PreviewProvider"),
                "outputMode": .string("filesWithMatches"),
            ]
        )
        let providerPaths = try PreviewFileParser.parseFilePaths(from: providerResult)

        // Merge and deduplicate while preserving order
        var seen = Set<String>()
        var merged: [String] = []
        for path in previewMacroPaths + providerPaths {
            if seen.insert(path).inserted {
                merged.append(path)
            }
        }

        return merged
    }

    /// Find all preview targets (file + index pairs) in the project.
    ///
    /// For each preview file, counts the number of `#Preview` and `PreviewProvider`
    /// definitions and creates a PreviewTarget for each one.
    public func findPreviewTargets(tabIdentifier: String) async throws -> [PreviewTarget] {
        let files = try await findPreviewFiles(tabIdentifier: tabIdentifier)
        var targets: [PreviewTarget] = []

        for file in files {
            let count = try await countPreviewsInFile(tabIdentifier: tabIdentifier, filePath: file)
            let effectiveCount = max(1, count)
            for index in 0..<effectiveCount {
                targets.append(PreviewTarget(filePath: file, previewIndex: index, previewCount: effectiveCount))
            }
        }

        return targets
    }

    /// Count preview definitions (`#Preview` and `PreviewProvider`) in a single file.
    private func countPreviewsInFile(tabIdentifier: String, filePath: String) async throws -> Int {
        let result = try await client.callTool(
            name: "XcodeGrep",
            arguments: [
                "tabIdentifier": .string(tabIdentifier),
                "pattern": .string("#Preview|PreviewProvider"),
                "path": .string(filePath),
                "outputMode": .string("content"),
            ]
        )
        return try PreviewFileParser.parseMatchCount(from: result)
    }

    /// Capture a snapshot for a single preview definition.
    ///
    /// - Parameters:
    ///   - tabIdentifier: The Xcode workspace tab identifier
    ///   - sourceFilePath: Path to the Swift file within the Xcode project
    ///   - previewIndex: Zero-based index of the preview definition in the file (default: 0)
    ///   - previewCount: Total number of previews in the file, used for filename formatting (default: 1)
    ///   - outputDirectory: Directory to copy the snapshot to
    /// - Returns: A SnapshotResult with the saved file path or error
    public func captureSnapshot(
        tabIdentifier: String,
        sourceFilePath: String,
        previewIndex: Int = 0,
        previewCount: Int = 1,
        outputDirectory: String
    ) async -> SnapshotResult {
        do {
            var arguments: [String: JSONValue] = [
                "tabIdentifier": .string(tabIdentifier),
                "sourceFilePath": .string(sourceFilePath),
                "timeout": .int(renderTimeout),
            ]
            if previewIndex > 0 {
                arguments["previewDefinitionIndexInFile"] = .int(previewIndex)
            }

            let result = try await client.callTool(
                name: "RenderPreview",
                arguments: arguments
            )

            let snapshotPath = try RenderPreviewParser.parseSnapshotPath(from: result)

            // Derive output filename from source file path
            // e.g. "Project/Views/ContentView.swift" -> "ContentView.png" (single preview)
            //    or "Project/Views/ContentView.swift" -> "ContentView_0.png" (multiple previews)
            let baseName = URL(fileURLWithPath: sourceFilePath)
                .deletingPathExtension()
                .lastPathComponent
            let fileName: String
            if previewCount > 1 {
                fileName = "\(baseName)_\(previewIndex).png"
            } else {
                fileName = "\(baseName).png"
            }
            let destinationPath = (outputDirectory as NSString)
                .appendingPathComponent(fileName)

            // Copy snapshot to output directory
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                atPath: outputDirectory,
                withIntermediateDirectories: true
            )

            if fileManager.fileExists(atPath: destinationPath) {
                try fileManager.removeItem(atPath: destinationPath)
            }
            try fileManager.copyItem(atPath: snapshotPath, toPath: destinationPath)

            return SnapshotResult(sourceFilePath: sourceFilePath, previewIndex: previewIndex, result: .success(destinationPath))
        } catch {
            let snapshotError: SnapshotError
            if let renderError = error as? RenderPreviewParserError {
                snapshotError = .parseFailed(renderError.description)
            } else {
                snapshotError = .renderFailed(error.localizedDescription)
            }
            return SnapshotResult(sourceFilePath: sourceFilePath, previewIndex: previewIndex, result: .failure(snapshotError))
        }
    }

    /// Capture snapshots for all given preview targets sequentially.
    ///
    /// Sequential execution ensures Xcode stability. Individual failures are collected
    /// in the results rather than stopping the entire process.
    ///
    /// - Parameters:
    ///   - tabIdentifier: The Xcode workspace tab identifier
    ///   - targets: Preview targets to capture (file + preview index pairs)
    ///   - outputDirectory: Directory to save snapshots
    ///   - progress: Optional callback for progress reporting (current, total, display name)
    /// - Returns: Array of SnapshotResult for each target
    public func captureAllSnapshots(
        tabIdentifier: String,
        targets: [PreviewTarget],
        outputDirectory: String,
        progress: (@Sendable (Int, Int, String) -> Void)? = nil
    ) async -> [SnapshotResult] {
        var results: [SnapshotResult] = []

        for (index, target) in targets.enumerated() {
            let displayName: String
            if target.previewCount > 1 {
                displayName = "\(target.filePath) [preview \(target.previewIndex + 1)/\(target.previewCount)]"
            } else {
                displayName = target.filePath
            }
            progress?(index + 1, targets.count, displayName)

            let result = await captureSnapshot(
                tabIdentifier: tabIdentifier,
                sourceFilePath: target.filePath,
                previewIndex: target.previewIndex,
                previewCount: target.previewCount,
                outputDirectory: outputDirectory
            )
            results.append(result)
        }

        return results
    }

    /// Capture snapshots for all given preview files sequentially.
    ///
    /// Convenience overload that assumes each file has a single preview definition.
    public func captureAllSnapshots(
        tabIdentifier: String,
        filePaths: [String],
        outputDirectory: String,
        progress: (@Sendable (Int, Int, String) -> Void)? = nil
    ) async -> [SnapshotResult] {
        let targets = filePaths.map { PreviewTarget(filePath: $0, previewIndex: 0, previewCount: 1) }
        return await captureAllSnapshots(
            tabIdentifier: tabIdentifier,
            targets: targets,
            outputDirectory: outputDirectory,
            progress: progress
        )
    }
}
