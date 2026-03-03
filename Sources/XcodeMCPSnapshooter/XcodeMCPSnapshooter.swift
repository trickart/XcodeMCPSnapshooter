import ArgumentParser
import Foundation
import Model

@main
struct XcodeMCPSnapshooter: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xmsnap",
        abstract: "CLI tool to connect to the Xcode MCP server and take snapshots"
    )

    @Option(name: [.short, .long], help: "Path to the Xcode project or directory to target")
    var project: String?

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

            // Determine the target path
            let targetPath = project ?? FileManager.default.currentDirectoryPath

            // Resolve to a concrete project file path
            let resolvedPath = try ProjectDiscovery.findProjectFile(in: targetPath)

            // Match against open Xcode projects
            let matched = try ProjectDiscovery.matchProject(path: resolvedPath, in: projects)

            print("\nSelected Project:")
            print("  Name: \(matched.name)")
            print("  Path: \(matched.workspacePath)")
            print("  Tab:  \(matched.tabIdentifiers.first ?? "N/A")")

            await client.disconnect()
            print("\nDisconnected.")
        } catch {
            await client.disconnect()
            throw error
        }
    }
}
