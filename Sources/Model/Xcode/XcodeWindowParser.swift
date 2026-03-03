import Foundation

/// Utility for parsing XcodeListWindows results
public enum XcodeWindowParser {

    /// Generate a project list from the text content of an MCPToolCallResult.
    /// Entries with the same workspacePath are merged, preserving insertion order.
    public static func parseProjects(from result: MCPToolCallResult) -> [XcodeProject] {
        let contentText = result.content.compactMap { content -> String? in
            if case .text(let text) = content { return text }
            return nil
        }.joined()

        let text = contentText.isEmpty ? (result.message ?? "") : contentText

        // The Xcode MCP bridge wraps actual data in a JSON object like
        // {"message":"* tabIdentifier: ..."}. Unwrap if needed.
        let unwrapped = Self.unwrapMessageJSON(text)
        return parseProjects(from: unwrapped)
    }

    /// If `text` is a JSON object with a `message` string field, return the
    /// message value; otherwise return the original text.
    static func unwrapMessageJSON(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? String else {
            return text
        }
        return message
    }

    /// Generate a project list from raw text
    public static func parseProjects(from text: String) -> [XcodeProject] {
        let entries = text.components(separatedBy: "\n").compactMap { line in
            parseWindowEntry(line)
        }

        // Group by workspacePath (preserve insertion order, skip duplicate tabs)
        var seen: [String: Int] = [:]
        var projects: [XcodeProject] = []

        for entry in entries {
            if let index = seen[entry.workspacePath] {
                if !projects[index].tabIdentifiers.contains(entry.tabIdentifier) {
                    let existing = projects[index]
                    projects[index] = XcodeProject(
                        workspacePath: existing.workspacePath,
                        tabIdentifiers: existing.tabIdentifiers + [entry.tabIdentifier]
                    )
                }
            } else {
                seen[entry.workspacePath] = projects.count
                projects.append(XcodeProject(
                    workspacePath: entry.workspacePath,
                    tabIdentifiers: [entry.tabIdentifier]
                ))
            }
        }

        return projects
    }

    /// Parse a line in the format "* tabIdentifier: xxx, workspacePath: yyy"
    static func parseWindowEntry(_ line: String) -> XcodeWindowEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("*") else { return nil }

        guard let tabRange = trimmed.range(of: "tabIdentifier: "),
              let wpRange = trimmed.range(of: ", workspacePath: ") else {
            return nil
        }

        let tabIdentifier = String(trimmed[tabRange.upperBound..<wpRange.lowerBound])
        let workspacePath = String(trimmed[wpRange.upperBound...])

        guard !tabIdentifier.isEmpty, !workspacePath.isEmpty else { return nil }

        return XcodeWindowEntry(tabIdentifier: tabIdentifier, workspacePath: workspacePath)
    }
}
