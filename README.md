# xmsnap

A CLI tool that captures SwiftUI preview snapshots by connecting to Xcode's MCP server via JSON-RPC 2.0 over stdio.

## Features

- Automatically discovers SwiftUI preview files (`#Preview` and `PreviewProvider`) in your Xcode project
- Renders previews through Xcode's MCP bridge and saves snapshot images
- Supports file name pattern filtering to target specific previews
- List mode to inspect available preview files without capturing
- Real-time progress display during snapshot capture
- Universal binary (arm64 + x86_64) via GitHub Actions release workflow

## Requirements

- macOS 26+
- Xcode (with the target project open)
- Swift 6.2+

## Installation

### Homebrew tap

```bash
brew install trickart/tap/xmsnap
```

### [nest](https://github.com/mtj0928/nest)

```bash
nest install trickart/XcodeMCPSnapshooter
```

### [mint](https://github.com/yonaskolb/Mint)

```bash
mint install trickart/XcodeMCPSnapshooter
```

### Build from source

```bash
git clone https://github.com/user/XcodeMCPSnapshooter.git
cd XcodeMCPSnapshooter
swift build -c release
# Binary is at .build/release/xmsnap
```

### From GitHub Releases

Download the `xmsnap.artifactbundle.zip` from the [Releases](../../releases) page. The artifact bundle contains a universal macOS binary.

## Usage

### Capture all preview snapshots in the current directory's project

```bash
xmsnap
```

#### Specify a project path and output directory

```bash
xmsnap --project ./MyApp -o ./screenshots
```

#### List preview files without capturing

```bash
xmsnap --list
```

#### Filter by file name patterns

```bash
xmsnap ContentView.swift SettingsView.swift
```

#### Set a custom render timeout (in seconds)

```bash
xmsnap --render-timeout 180
```

### Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--project <path>` | `-p` | Path to the Xcode project or directory | Current directory |
| `--output <dir>` | `-o` | Output directory for snapshot images | `./snapshots` |
| `--render-timeout <sec>` | | Render timeout per preview in seconds | `120` |
| `--list` | `-l` | List preview files only, skip capturing | `false` |
| `<file-filters>` | | File name patterns to filter previews | (all) |

### How it works

1. Launches the Xcode MCP bridge (`xcrun mcpbridge`) and establishes a JSON-RPC 2.0 connection
2. Queries open Xcode windows to find your project
3. Searches for files containing `#Preview` or `PreviewProvider`
4. Renders each preview through Xcode and copies the snapshot image to the output directory

> **Note:** When running for the first time, Xcode may display a permission dialog. Click "Allow" to proceed.

## Architecture

```
Sources/
├── Model/
│   ├── Client/         # MCPClient actor — manages connection and request/response matching
│   ├── JSONRPC/        # JSON-RPC 2.0 message types (JSONValue, Request, Response, Notification)
│   ├── MCP/            # MCP protocol types (initialization, tools, content)
│   ├── Transport/      # MCPTransport protocol and StdioTransport implementation
│   └── Xcode/          # SnapshotService, parsers, and project discovery
└── XcodeMCPSnapshooter/
    └── XcodeMCPSnapshooter.swift   # CLI entry point (swift-argument-parser)
```

Key design decisions:

- **Actor-based concurrency** — `MCPClient` is an actor that safely manages connection state and request/response matching via `CheckedContinuation`
- **Stateless parsers** — `XcodeWindowParser`, `PreviewFileParser`, and `RenderPreviewParser` are caseless enums with static methods
- **Protocol-driven transport** — `MCPTransport` protocol enables easy testing with `MockTransport`
- **Sequential rendering** — Snapshots are captured one at a time for Xcode stability

## Development

```bash
# Build
swift build

# Run all tests
swift test

# Run a specific test suite
swift test --filter MCPClientTests

# Show CLI help
swift run xmsnap --help
```

## Dependencies

- [swift-argument-parser](https://github.com/apple/swift-argument-parser) (v1.7.0+) — CLI argument parsing

## License

[MIT](LICENSE)
