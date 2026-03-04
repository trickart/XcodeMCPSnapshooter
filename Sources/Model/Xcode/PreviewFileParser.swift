import Foundation

/// Utility for parsing XcodeGrep results to extract preview file paths
public enum PreviewFileParser {

    /// Extract file paths from an XcodeGrep MCPToolCallResult.
    ///
    /// The expected JSON format is:
    /// ```
    /// {"matchCount":11,"results":["Project/Views/A.swift",...],"searchPath":"","truncated":false}
    /// ```
    public static func parseFilePaths(from result: MCPToolCallResult) throws -> [String] {
        let parsed = try decodeGrepResponse(from: result)
        if parsed.matchCount == 0 {
            return []
        }
        return parsed.results
    }

    /// Extract the match count from an XcodeGrep MCPToolCallResult.
    ///
    /// Works with any output mode (`filesWithMatches`, `content`, `count`).
    /// Returns the `matchCount` field from the JSON response.
    public static func parseMatchCount(from result: MCPToolCallResult) throws -> Int {
        let parsed = try decodeGrepResponse(from: result)
        return parsed.matchCount
    }

    private static func decodeGrepResponse(from result: MCPToolCallResult) throws -> GrepResponse {
        let contentText = result.content.compactMap { content -> String? in
            if case .text(let text) = content { return text }
            return nil
        }.joined()

        let text = contentText.isEmpty ? (result.message ?? "") : contentText
        guard !text.isEmpty else {
            return GrepResponse(matchCount: 0, results: [])
        }
        let unwrapped = XcodeWindowParser.unwrapMessageJSON(text)

        guard let data = unwrapped.data(using: .utf8) else {
            return GrepResponse(matchCount: 0, results: [])
        }

        return try JSONDecoder().decode(GrepResponse.self, from: data)
    }
}

// MARK: - Internal types

extension PreviewFileParser {
    struct GrepResponse: Decodable {
        var matchCount: Int
        var results: [String]
    }
}
