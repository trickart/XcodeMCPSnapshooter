import ArgumentParser
import Foundation
import Model

@main
struct XcodeMCPSnapshooter: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xmsnap",
        abstract: "CLI tool to connect to the Xcode MCP server and take snapshots"
    )

    func run() async throws {
        let serverPath = "/usr/bin/xcrun"
        let transport = StdioTransport(serverPath: serverPath, arguments: ["mcpbridge"])
        let client = MCPClient(transport: transport)

        print("Connecting to MCP server...")

        do {
            try await client.connect()

            let info = await client.serverInfo
            if let info {
                print("Connected to: \(info.name) v\(info.version)")
            }

            print("Xcode may show a permission dialog. Please click \"Allow\" to continue.")

            // Call XcodeListWindows to get the project list
            let result = try await client.callTool(name: "XcodeListWindows")
            let projects = XcodeWindowParser.parseProjects(from: result)

            print("\nOpen Projects (\(projects.count)):")
            for (index, project) in projects.enumerated() {
                print("  \(index + 1). \(project.name)")
                print("     Path: \(project.workspacePath)")
            }

            await client.disconnect()
            print("\nDisconnected.")
        } catch {
            await client.disconnect()
            throw error
        }
    }
}
