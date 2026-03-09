import ArgumentParser

@main
struct XcodeMCPSnapshooter: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xmsnap",
        abstract: "CLI tool to connect to the Xcode MCP server and take preview snapshots",
        subcommands: [Snapshot.self, Setup.self],
        defaultSubcommand: Snapshot.self
    )
}
