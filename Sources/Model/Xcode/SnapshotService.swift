import Foundation

/// Result of a single snapshot capture attempt
public struct SnapshotResult: Sendable {
    /// The source Swift file containing the Preview
    public let sourceFilePath: String
    /// Success: saved file path, Failure: error
    public let result: Result<String, SnapshotError>

    public init(sourceFilePath: String, result: Result<String, SnapshotError>) {
        self.sourceFilePath = sourceFilePath
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

    /// Capture a snapshot for a single preview file.
    ///
    /// - Parameters:
    ///   - tabIdentifier: The Xcode workspace tab identifier
    ///   - sourceFilePath: Path to the Swift file within the Xcode project
    ///   - outputDirectory: Directory to copy the snapshot to
    /// - Returns: A SnapshotResult with the saved file path or error
    public func captureSnapshot(
        tabIdentifier: String,
        sourceFilePath: String,
        outputDirectory: String
    ) async -> SnapshotResult {
        do {
            let result = try await client.callTool(
                name: "RenderPreview",
                arguments: [
                    "tabIdentifier": .string(tabIdentifier),
                    "sourceFilePath": .string(sourceFilePath),
                    "timeout": .int(renderTimeout),
                ]
            )

            let snapshotPath = try RenderPreviewParser.parseSnapshotPath(from: result)

            // Derive output filename from source file path
            // e.g. "Project/Views/ContentView.swift" -> "ContentView.png"
            let baseName = URL(fileURLWithPath: sourceFilePath)
                .deletingPathExtension()
                .lastPathComponent
            let destinationPath = (outputDirectory as NSString)
                .appendingPathComponent("\(baseName).png")

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

            return SnapshotResult(sourceFilePath: sourceFilePath, result: .success(destinationPath))
        } catch {
            let snapshotError: SnapshotError
            if let renderError = error as? RenderPreviewParserError {
                snapshotError = .parseFailed(renderError.description)
            } else {
                snapshotError = .renderFailed(error.localizedDescription)
            }
            return SnapshotResult(sourceFilePath: sourceFilePath, result: .failure(snapshotError))
        }
    }

    /// Capture snapshots for all given preview files sequentially.
    ///
    /// Sequential execution ensures Xcode stability. Individual failures are collected
    /// in the results rather than stopping the entire process.
    ///
    /// - Parameters:
    ///   - tabIdentifier: The Xcode workspace tab identifier
    ///   - filePaths: Preview file paths to capture
    ///   - outputDirectory: Directory to save snapshots
    ///   - progress: Optional callback for progress reporting
    /// - Returns: Array of SnapshotResult for each file
    public func captureAllSnapshots(
        tabIdentifier: String,
        filePaths: [String],
        outputDirectory: String,
        progress: (@Sendable (Int, Int, String) -> Void)? = nil
    ) async -> [SnapshotResult] {
        var results: [SnapshotResult] = []

        for (index, filePath) in filePaths.enumerated() {
            progress?(index + 1, filePaths.count, filePath)

            let result = await captureSnapshot(
                tabIdentifier: tabIdentifier,
                sourceFilePath: filePath,
                outputDirectory: outputDirectory
            )
            results.append(result)
        }

        return results
    }
}
