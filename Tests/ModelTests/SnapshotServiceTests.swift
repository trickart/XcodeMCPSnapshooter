import Foundation
import Synchronization
import Testing
@testable import Model

@Suite("SnapshotService Tests")
struct SnapshotServiceTests {

    // MARK: - Helper

    /// Create a connected MCPClient with a MockTransport that handles initialize.
    /// The onToolCall closure is invoked for each tools/call request.
    private func makeConnectedClient(
        onToolCall: @escaping @Sendable (String, [String: JSONValue]?) -> MCPToolCallResult
    ) async throws -> (MCPClient, MockTransport) {
        let transport = MockTransport()

        transport.onSend = { data in
            guard let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
                return
            }

            if request.method == "initialize" {
                let initResult = MCPInitializeResult(
                    protocolVersion: "2024-11-05",
                    capabilities: MCPServerCapabilities(),
                    serverInfo: MCPServerInfo(name: "test-server", version: "1.0.0")
                )
                let resultData = try! JSONEncoder().encode(initResult)
                let resultValue = try! JSONDecoder().decode(JSONValue.self, from: resultData)
                let response = JSONRPCResponse(id: request.id, result: resultValue)
                try! transport.injectResponse(response)
            } else if request.method == "tools/call" {
                // Extract tool name from params
                guard case .object(let params) = try? JSONDecoder().decode(JSONValue.self, from: data),
                      case .string(let toolName) = params["params"].flatMap({ value -> JSONValue? in
                          if case .object(let p) = value { return p["name"] }
                          return nil
                      }) else {
                    // Fallback: decode params from the request
                    if let paramsDict = request.params,
                       case .string(let name) = paramsDict["name"] {
                        let arguments: [String: JSONValue]?
                        if case .object(let args) = paramsDict["arguments"] {
                            arguments = args
                        } else {
                            arguments = nil
                        }
                        let toolResult = onToolCall(name, arguments)
                        let resultData = try! JSONEncoder().encode(toolResult)
                        let resultValue = try! JSONDecoder().decode(JSONValue.self, from: resultData)
                        let response = JSONRPCResponse(id: request.id, result: resultValue)
                        try! transport.injectResponse(response)
                    }
                    return
                }

                let arguments: [String: JSONValue]?
                if let paramsDict = request.params,
                   case .object(let args) = paramsDict["arguments"] {
                    arguments = args
                } else {
                    arguments = nil
                }
                let toolResult = onToolCall(toolName, arguments)
                let resultData = try! JSONEncoder().encode(toolResult)
                let resultValue = try! JSONDecoder().decode(JSONValue.self, from: resultData)
                let response = JSONRPCResponse(id: request.id, result: resultValue)
                try! transport.injectResponse(response)
            }
        }

        let client = MCPClient(transport: transport)
        try await client.connect()

        return (client, transport)
    }

    // MARK: - findPreviewFiles

    @Test("findPreviewFiles merges and deduplicates results from two grep calls")
    func findPreviewFilesMergesResults() async throws {
        let grepCallCount = Mutex<Int>(0)

        let (client, _) = try await makeConnectedClient { name, arguments in
            if name == "XcodeGrep" {
                let count = grepCallCount.withLock { value -> Int in
                    value += 1
                    return value
                }
                if count == 1 {
                    // First call: #Preview
                    let json = """
                    {"matchCount":2,"results":["Project/Views/A.swift","Project/Views/B.swift"],"searchPath":"","truncated":false}
                    """
                    return MCPToolCallResult(content: [.text(json)])
                } else {
                    // Second call: PreviewProvider
                    let json = """
                    {"matchCount":2,"results":["Project/Views/B.swift","Project/Views/C.swift"],"searchPath":"","truncated":false}
                    """
                    return MCPToolCallResult(content: [.text(json)])
                }
            }
            return MCPToolCallResult(content: [])
        }

        let service = SnapshotService(client: client)
        let files = try await service.findPreviewFiles(tabIdentifier: "tab1")

        // B.swift appears in both, should be deduplicated
        #expect(files.count == 3)
        #expect(files == ["Project/Views/A.swift", "Project/Views/B.swift", "Project/Views/C.swift"])

        await client.disconnect()
    }

    @Test("findPreviewFiles returns empty when no previews found")
    func findPreviewFilesEmpty() async throws {
        let (client, _) = try await makeConnectedClient { _, _ in
            let json = """
            {"matchCount":0,"results":[],"searchPath":"","truncated":false}
            """
            return MCPToolCallResult(content: [.text(json)])
        }

        let service = SnapshotService(client: client)
        let files = try await service.findPreviewFiles(tabIdentifier: "tab1")

        #expect(files.isEmpty)

        await client.disconnect()
    }

    // MARK: - captureAllSnapshots

    @Test("captureAllSnapshots collects results for each file")
    func captureAllSnapshotsCollectsResults() async throws {
        // Create a temp directory for output
        let tempDir = NSTemporaryDirectory() + "SnapshotServiceTest_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let (client, _) = try await makeConnectedClient { name, arguments in
            if name == "RenderPreview" {
                // Create a temporary file to simulate the snapshot
                let tmpFile = NSTemporaryDirectory() + "RenderPreview_\(UUID().uuidString)@2x.png"
                FileManager.default.createFile(atPath: tmpFile, contents: Data("fake png".utf8))

                let json = """
                {"previewSnapshotPath":"\(tmpFile)"}
                """
                return MCPToolCallResult(content: [.text(json)])
            }
            return MCPToolCallResult(content: [])
        }

        let service = SnapshotService(client: client)
        let results = await service.captureAllSnapshots(
            tabIdentifier: "tab1",
            filePaths: ["Project/Views/ContentView.swift", "Project/Views/SettingsView.swift"],
            outputDirectory: tempDir
        )

        #expect(results.count == 2)

        for result in results {
            switch result.result {
            case .success(let path):
                #expect(FileManager.default.fileExists(atPath: path))
            case .failure(let error):
                Issue.record("Unexpected failure: \(error)")
            }
        }

        await client.disconnect()
    }

    @Test("captureAllSnapshots reports progress")
    func captureAllSnapshotsReportsProgress() async throws {
        let tempDir = NSTemporaryDirectory() + "SnapshotServiceTest_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let (client, _) = try await makeConnectedClient { name, _ in
            if name == "RenderPreview" {
                let tmpFile = NSTemporaryDirectory() + "RenderPreview_\(UUID().uuidString)@2x.png"
                FileManager.default.createFile(atPath: tmpFile, contents: Data("fake".utf8))
                let json = "{\"previewSnapshotPath\":\"\(tmpFile)\"}"
                return MCPToolCallResult(content: [.text(json)])
            }
            return MCPToolCallResult(content: [])
        }

        let service = SnapshotService(client: client)
        let progressCalls = Mutex<[(Int, Int, String)]>([])

        _ = await service.captureAllSnapshots(
            tabIdentifier: "tab1",
            filePaths: ["Project/A.swift", "Project/B.swift"],
            outputDirectory: tempDir,
            progress: { current, total, file in
                progressCalls.withLock { $0.append((current, total, file)) }
            }
        )

        let calls = progressCalls.withLock { $0 }
        #expect(calls.count == 2)
        #expect(calls[0] == (1, 2, "Project/A.swift"))
        #expect(calls[1] == (2, 2, "Project/B.swift"))

        await client.disconnect()
    }
}
