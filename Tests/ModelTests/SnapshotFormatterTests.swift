import Foundation
import Testing
@testable import Model

@Suite("SnapshotFormatter Tests")
struct SnapshotFormatterTests {

    // MARK: - Test Data

    private static let successResult = SnapshotResult(
        sourceFilePath: "Project/Views/ContentView.swift",
        previewIndex: 0,
        result: .success("/output/ContentView.png")
    )

    private static let failureResult = SnapshotResult(
        sourceFilePath: "Project/Views/BrokenView.swift",
        previewIndex: 0,
        result: .failure(.renderFailed("timeout"))
    )

    private static let mixedResults = [successResult, failureResult]

    // MARK: - Default Format

    @Test("Default format matches expected summary output")
    func defaultFormat() {
        let output = SnapshotFormatter.format(
            results: Self.mixedResults,
            outputDirectory: "./snapshots",
            format: .default
        )

        #expect(output.contains("Snapshot Summary:"))
        #expect(output.contains("Total:     2"))
        #expect(output.contains("Succeeded: 1"))
        #expect(output.contains("Failed:    1"))
        #expect(output.contains("OK: Project/Views/ContentView.swift -> /output/ContentView.png"))
        #expect(output.contains("FAIL: Project/Views/BrokenView.swift - Render failed: timeout"))
        #expect(output.contains("Snapshots saved to: ./snapshots"))
    }

    // MARK: - JSON Format

    @Test("JSON format produces valid JSON with correct fields")
    func jsonFormat() throws {
        let output = SnapshotFormatter.format(
            results: Self.mixedResults,
            outputDirectory: "./snapshots",
            format: .json
        )

        let data = try #require(output.data(using: .utf8))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["total"] as? Int == 2)
        #expect(json["succeeded"] as? Int == 1)
        #expect(json["failed"] as? Int == 1)
        #expect(json["outputDirectory"] as? String == "./snapshots")

        let results = try #require(json["results"] as? [[String: Any]])
        #expect(results.count == 2)

        let first = results[0]
        #expect(first["sourceFile"] as? String == "Project/Views/ContentView.swift")
        #expect(first["previewIndex"] as? Int == 0)
        #expect(first["status"] as? String == "success")
        #expect(first["outputPath"] as? String == "ContentView.png")

        let second = results[1]
        #expect(second["status"] as? String == "failed")
        #expect(second["error"] as? String == "Render failed: timeout")
    }

    // MARK: - Markdown Format

    @Test("Markdown format contains table structure")
    func markdownFormat() {
        let output = SnapshotFormatter.format(
            results: Self.mixedResults,
            outputDirectory: "./snapshots",
            format: .markdown
        )

        #expect(output.contains("## Snapshot Summary"))
        #expect(output.contains("| Total | 2 |"))
        #expect(output.contains("| Succeeded | 1 |"))
        #expect(output.contains("| Failed | 1 |"))
        #expect(output.contains("### Succeeded"))
        #expect(output.contains("### Failed"))
        #expect(output.contains("| Project/Views/ContentView.swift | ContentView.png |"))
        #expect(output.contains("| Project/Views/BrokenView.swift | Render failed: timeout |"))
    }

    // MARK: - HTML Format

    @Test("HTML format contains valid HTML structure")
    func htmlFormat() {
        let output = SnapshotFormatter.format(
            results: Self.mixedResults,
            outputDirectory: "./snapshots",
            format: .html
        )

        #expect(output.contains("<!DOCTYPE html>"))
        #expect(output.contains("<html"))
        #expect(output.contains("</html>"))
        #expect(output.contains("Snapshot Summary"))
        #expect(output.contains("<img src=\"ContentView.png\""))
        #expect(output.contains("Render failed: timeout"))
        #expect(output.contains("overlay"))
        #expect(output.contains("<script>"))
    }

    // MARK: - Empty Results

    @Test("All formats handle empty results")
    func emptyResults() throws {
        for format in OutputFormat.allCases {
            let output = SnapshotFormatter.format(
                results: [],
                outputDirectory: "./snapshots",
                format: format
            )
            #expect(!output.isEmpty, "Output should not be empty for format: \(format)")
        }
    }

    // MARK: - Default format without successes omits saved-to line

    @Test("Default format with only failures omits saved-to line")
    func defaultFormatOnlyFailures() {
        let output = SnapshotFormatter.format(
            results: [Self.failureResult],
            outputDirectory: "./snapshots",
            format: .default
        )

        #expect(!output.contains("Snapshots saved to:"))
    }
}
