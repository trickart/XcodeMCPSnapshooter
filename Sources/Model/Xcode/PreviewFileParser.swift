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
        let contentText = result.content.compactMap { content -> String? in
            if case .text(let text) = content { return text }
            return nil
        }.joined()

        let text = contentText.isEmpty ? (result.message ?? "") : contentText
        let unwrapped = XcodeWindowParser.unwrapMessageJSON(text)

        guard let data = unwrapped.data(using: .utf8) else {
            return []
        }

        let parsed = try JSONDecoder().decode(GrepResponse.self, from: data)
        if parsed.matchCount == 0 {
            return []
        }
        return parsed.results
    }
}

// MARK: - Internal types

extension PreviewFileParser {
    struct GrepResponse: Decodable {
        var matchCount: Int
        var results: [String]
    }
}
