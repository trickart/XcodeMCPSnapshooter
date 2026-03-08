import Foundation

/// Formats snapshot results into various output formats
public enum SnapshotFormatter {

    /// Format snapshot results according to the specified output format
    public static func format(
        results: [SnapshotResult],
        outputDirectory: String,
        format: OutputFormat
    ) -> String {
        switch format {
        case .default:
            return formatDefault(results: results, outputDirectory: outputDirectory)
        case .json:
            return formatJSON(results: results, outputDirectory: outputDirectory)
        case .markdown:
            return formatMarkdown(results: results, outputDirectory: outputDirectory)
        case .html:
            return formatHTML(results: results, outputDirectory: outputDirectory)
        }
    }

    // MARK: - Default

    private static func formatDefault(results: [SnapshotResult], outputDirectory: String) -> String {
        let succeeded = results.filter { if case .success = $0.result { return true } else { return false } }
        let failed = results.filter { if case .failure = $0.result { return true } else { return false } }

        var lines: [String] = []
        lines.append("Snapshot Summary:")
        lines.append("  Total:     \(results.count)")
        lines.append("  Succeeded: \(succeeded.count)")
        lines.append("  Failed:    \(failed.count)")

        for result in succeeded {
            if case .success(let path) = result.result {
                lines.append("  OK: \(result.sourceFilePath) -> \(path)")
            }
        }

        for result in failed {
            if case .failure(let error) = result.result {
                lines.append("  FAIL: \(result.sourceFilePath) - \(error)")
            }
        }

        if !succeeded.isEmpty {
            lines.append("")
            lines.append("Snapshots saved to: \(outputDirectory)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON

    private struct JSONReport: Encodable {
        let total: Int
        let succeeded: Int
        let failed: Int
        let outputDirectory: String
        let results: [JSONResultEntry]
    }

    private struct JSONResultEntry: Encodable {
        let sourceFile: String
        let previewIndex: Int
        let status: String
        let outputPath: String?
        let error: String?
    }

    private static func formatJSON(results: [SnapshotResult], outputDirectory: String) -> String {
        let succeededCount = results.filter { if case .success = $0.result { return true } else { return false } }.count
        let failedCount = results.count - succeededCount

        let entries = results.map { result -> JSONResultEntry in
            switch result.result {
            case .success(let path):
                let fileName = URL(fileURLWithPath: path).lastPathComponent
                return JSONResultEntry(
                    sourceFile: result.sourceFilePath,
                    previewIndex: result.previewIndex,
                    status: "success",
                    outputPath: fileName,
                    error: nil
                )
            case .failure(let error):
                return JSONResultEntry(
                    sourceFile: result.sourceFilePath,
                    previewIndex: result.previewIndex,
                    status: "failed",
                    outputPath: nil,
                    error: error.description
                )
            }
        }

        let report = JSONReport(
            total: results.count,
            succeeded: succeededCount,
            failed: failedCount,
            outputDirectory: outputDirectory,
            results: entries
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return jsonString
    }

    // MARK: - Markdown

    private static func formatMarkdown(results: [SnapshotResult], outputDirectory: String) -> String {
        let succeeded = results.filter { if case .success = $0.result { return true } else { return false } }
        let failed = results.filter { if case .failure = $0.result { return true } else { return false } }

        var lines: [String] = []
        lines.append("## Snapshot Summary")
        lines.append("")
        lines.append("| Metric | Count |")
        lines.append("|--------|-------|")
        lines.append("| Total | \(results.count) |")
        lines.append("| Succeeded | \(succeeded.count) |")
        lines.append("| Failed | \(failed.count) |")

        if !succeeded.isEmpty {
            lines.append("")
            lines.append("### Succeeded")
            lines.append("")
            lines.append("| Source File | Output |")
            lines.append("|------------|--------|")
            for result in succeeded {
                if case .success(let path) = result.result {
                    let fileName = URL(fileURLWithPath: path).lastPathComponent
                    lines.append("| \(result.sourceFilePath) | \(fileName) |")
                }
            }
        }

        if !failed.isEmpty {
            lines.append("")
            lines.append("### Failed")
            lines.append("")
            lines.append("| Source File | Error |")
            lines.append("|------------|-------|")
            for result in failed {
                if case .failure(let error) = result.result {
                    lines.append("| \(result.sourceFilePath) | \(error) |")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - HTML

    private static func formatHTML(results: [SnapshotResult], outputDirectory: String) -> String {
        let succeeded = results.filter { if case .success = $0.result { return true } else { return false } }
        let failed = results.filter { if case .failure = $0.result { return true } else { return false } }

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Snapshot Summary</title>
        <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 2rem; background: #f5f5f5; }
        h1 { color: #333; }
        .summary { display: flex; gap: 1rem; margin-bottom: 2rem; }
        .stat { background: #fff; padding: 1rem 1.5rem; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .stat .label { font-size: 0.85rem; color: #666; }
        .stat .value { font-size: 1.5rem; font-weight: bold; }
        .stat.success .value { color: #34c759; }
        .stat.failure .value { color: #ff3b30; }
        .gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 1rem; }
        .card { background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.1); cursor: pointer; display: flex; flex-direction: column; align-items: center; justify-content: center; }
        .card img { width: 100%; height: auto; display: block; }
        .card .info { padding: 0.75rem; font-size: 0.85rem; color: #333; word-break: break-all; }
        .error-list { margin-top: 2rem; }
        .error-item { background: #fff0f0; padding: 0.75rem; border-radius: 8px; margin-bottom: 0.5rem; border-left: 4px solid #ff3b30; }
        .error-item .file { font-weight: 600; }
        .error-item .msg { color: #666; font-size: 0.85rem; }
        .overlay { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); z-index: 1000; cursor: pointer; justify-content: center; align-items: center; }
        .overlay.active { display: flex; }
        .overlay img { max-width: 90%; max-height: 90%; border-radius: 8px; box-shadow: 0 4px 20px rgba(0,0,0,0.5); }
        </style>
        </head>
        <body>
        <h1>Snapshot Summary</h1>
        <div class="summary">
        <div class="stat"><div class="label">Total</div><div class="value">\(results.count)</div></div>
        <div class="stat success"><div class="label">Succeeded</div><div class="value">\(succeeded.count)</div></div>
        <div class="stat failure"><div class="label">Failed</div><div class="value">\(failed.count)</div></div>
        </div>
        """

        if !succeeded.isEmpty {
            html += "<div class=\"gallery\">\n"
            for result in succeeded {
                if case .success(let path) = result.result {
                    let fileName = URL(fileURLWithPath: path).lastPathComponent
                    let escapedSource = escapeHTML(result.sourceFilePath)
                    html += """
                    <div class="card"><img src="\(fileName)" alt="\(escapedSource)"><div class="info">\(escapedSource)</div></div>

                    """
                }
            }
            html += "</div>\n"
        }

        if !failed.isEmpty {
            html += "<div class=\"error-list\">\n"
            html += "<h2>Failed</h2>\n"
            for result in failed {
                if case .failure(let error) = result.result {
                    let escapedSource = escapeHTML(result.sourceFilePath)
                    let escapedError = escapeHTML(error.description)
                    html += """
                    <div class="error-item"><div class="file">\(escapedSource)</div><div class="msg">\(escapedError)</div></div>

                    """
                }
            }
            html += "</div>\n"
        }

        html += """
        <div class="overlay" id="overlay" onclick="this.classList.remove('active')">
        <img id="overlay-img" src="" alt="">
        </div>
        <script>
        document.querySelectorAll('.card').forEach(card => {
          card.onclick = e => { const img = card.querySelector('img'); if (img) { document.getElementById('overlay-img').src = img.src; document.getElementById('overlay').classList.add('active'); } };
        });
        document.onkeydown = e => { if (e.key === 'Escape') document.getElementById('overlay').classList.remove('active'); };
        </script>
        """
        html += "</body>\n</html>"
        return html
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
