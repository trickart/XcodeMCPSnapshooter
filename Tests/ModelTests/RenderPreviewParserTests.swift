import Foundation
import Testing
@testable import Model

@Suite("RenderPreviewParser Tests")
struct RenderPreviewParserTests {

    @Test("Parses snapshot path from RenderPreview JSON response")
    func parseSnapshotPath() throws {
        let json = """
        {"previewSnapshotPath":"/var/folders/xx/tmp/RenderPreview_result_abc@2x.png"}
        """
        let result = MCPToolCallResult(content: [.text(json)])

        let path = try RenderPreviewParser.parseSnapshotPath(from: result)

        #expect(path == "/var/folders/xx/tmp/RenderPreview_result_abc@2x.png")
    }

    @Test("Parses snapshot path from message-wrapped response")
    func parseFromMessageWrapped() throws {
        let inner = """
        {"previewSnapshotPath":"/tmp/snapshot.png"}
        """
        let wrapped = "{\"message\":\(inner.debugDescription)}"
        let result = MCPToolCallResult(content: [.text(wrapped)])

        let path = try RenderPreviewParser.parseSnapshotPath(from: result)

        #expect(path == "/tmp/snapshot.png")
    }

    @Test("Falls back to message field when content is empty")
    func parseFromMessageField() throws {
        let json = """
        {"previewSnapshotPath":"/tmp/preview.png"}
        """
        let result = MCPToolCallResult(content: [], message: json)

        let path = try RenderPreviewParser.parseSnapshotPath(from: result)

        #expect(path == "/tmp/preview.png")
    }

    @Test("Throws on empty snapshot path")
    func throwsOnEmptyPath() throws {
        let json = """
        {"previewSnapshotPath":""}
        """
        let result = MCPToolCallResult(content: [.text(json)])

        #expect(throws: RenderPreviewParserError.self) {
            try RenderPreviewParser.parseSnapshotPath(from: result)
        }
    }

    @Test("Throws on invalid JSON")
    func throwsOnInvalidJSON() throws {
        let result = MCPToolCallResult(content: [.text("not json")])

        #expect(throws: (any Error).self) {
            try RenderPreviewParser.parseSnapshotPath(from: result)
        }
    }

    @Test("Throws on missing previewSnapshotPath key")
    func throwsOnMissingKey() throws {
        let json = """
        {"someOtherKey":"value"}
        """
        let result = MCPToolCallResult(content: [.text(json)])

        #expect(throws: (any Error).self) {
            try RenderPreviewParser.parseSnapshotPath(from: result)
        }
    }
}
