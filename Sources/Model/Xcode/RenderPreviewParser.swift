import Foundation

/// Utility for parsing RenderPreview results to extract snapshot file paths
public enum RenderPreviewParser {

    /// Extract the snapshot file path from a RenderPreview MCPToolCallResult.
    ///
    /// The expected JSON format is:
    /// ```
    /// {"previewSnapshotPath":"/var/folders/.../RenderPreview_result_xxx@2x.png"}
    /// ```
    public static func parseSnapshotPath(from result: MCPToolCallResult) throws -> String {
        let contentText = result.content.compactMap { content -> String? in
            if case .text(let text) = content { return text }
            return nil
        }.joined()

        let text = contentText.isEmpty ? (result.message ?? "") : contentText
        let unwrapped = XcodeWindowParser.unwrapMessageJSON(text)

        guard let data = unwrapped.data(using: .utf8) else {
            throw RenderPreviewParserError.invalidResponse("Empty response")
        }

        let parsed = try JSONDecoder().decode(RenderPreviewResponse.self, from: data)

        guard !parsed.previewSnapshotPath.isEmpty else {
            throw RenderPreviewParserError.invalidResponse("Empty snapshot path")
        }

        return parsed.previewSnapshotPath
    }
}

// MARK: - Error type

public enum RenderPreviewParserError: Error, CustomStringConvertible {
    case invalidResponse(String)

    public var description: String {
        switch self {
        case .invalidResponse(let detail):
            return "Invalid RenderPreview response: \(detail)"
        }
    }
}

// MARK: - Internal types

extension RenderPreviewParser {
    struct RenderPreviewResponse: Decodable {
        var previewSnapshotPath: String
    }
}
