import Foundation
import Testing
@testable import Model

@Suite("PreviewFileParser Tests")
struct PreviewFileParserTests {

    @Test("Parses file paths from XcodeGrep JSON response")
    func parseFilePaths() throws {
        let json = """
        {"matchCount":3,"results":["Project/Views/ContentView.swift","Project/Views/SettingsView.swift","Project/Views/DetailView.swift"],"searchPath":"","truncated":false}
        """
        let result = MCPToolCallResult(content: [.text(json)])

        let paths = try PreviewFileParser.parseFilePaths(from: result)

        #expect(paths.count == 3)
        #expect(paths[0] == "Project/Views/ContentView.swift")
        #expect(paths[1] == "Project/Views/SettingsView.swift")
        #expect(paths[2] == "Project/Views/DetailView.swift")
    }

    @Test("Parses file paths from message-wrapped response")
    func parseFromMessageWrapped() throws {
        let inner = """
        {"matchCount":1,"results":["Project/Views/A.swift"],"searchPath":"","truncated":false}
        """
        let wrapped = "{\"message\":\(inner.debugDescription)}"
        let result = MCPToolCallResult(content: [.text(wrapped)])

        let paths = try PreviewFileParser.parseFilePaths(from: result)

        #expect(paths.count == 1)
        #expect(paths[0] == "Project/Views/A.swift")
    }

    @Test("Returns empty array for zero matches")
    func parseEmptyResults() throws {
        let json = """
        {"matchCount":0,"results":["No matches found"],"searchPath":"","truncated":false}
        """
        let result = MCPToolCallResult(content: [.text(json)])

        let paths = try PreviewFileParser.parseFilePaths(from: result)

        #expect(paths.isEmpty)
    }

    @Test("Falls back to message field when content is empty")
    func parseFromMessageField() throws {
        let json = """
        {"matchCount":1,"results":["Project/Views/B.swift"],"searchPath":"","truncated":false}
        """
        let result = MCPToolCallResult(content: [], message: json)

        let paths = try PreviewFileParser.parseFilePaths(from: result)

        #expect(paths.count == 1)
        #expect(paths[0] == "Project/Views/B.swift")
    }

    @Test("Throws on invalid JSON")
    func parseInvalidJSON() throws {
        let result = MCPToolCallResult(content: [.text("not json")])

        #expect(throws: (any Error).self) {
            try PreviewFileParser.parseFilePaths(from: result)
        }
    }

    // MARK: - parseMatchCount

    @Test("Parses match count from XcodeGrep content mode response")
    func parseMatchCount() throws {
        let json = """
        {"matchCount":3,"results":["A.swift:10:#Preview {","A.swift:30:#Preview {","A.swift:50:PreviewProvider"],"searchPath":"","truncated":false}
        """
        let result = MCPToolCallResult(content: [.text(json)])

        let count = try PreviewFileParser.parseMatchCount(from: result)
        #expect(count == 3)
    }

    @Test("parseMatchCount returns 0 for empty response")
    func parseMatchCountEmpty() throws {
        let json = """
        {"matchCount":0,"results":[],"searchPath":"","truncated":false}
        """
        let result = MCPToolCallResult(content: [.text(json)])

        let count = try PreviewFileParser.parseMatchCount(from: result)
        #expect(count == 0)
    }

    @Test("parseMatchCount returns 0 for empty data")
    func parseMatchCountEmptyData() throws {
        let result = MCPToolCallResult(content: [])

        let count = try PreviewFileParser.parseMatchCount(from: result)
        #expect(count == 0)
    }
}
