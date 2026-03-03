# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

XcodeMCPSnapshooter (`xmsnap`) is a CLI tool that connects to the Xcode MCP server via JSON-RPC 2.0 over stdio to capture SwiftUI preview snapshots. Built with Swift 6.2, targeting macOS 26+.

## Build & Test Commands

```bash
swift build                          # Build the project
swift test                           # Run all tests
swift test --filter MCPClientTests   # Run a single test suite
swift run xmsnap --help              # Show CLI usage
```

## Architecture

**Transport layer** (`MCPTransport` protocol / `StdioTransport`) handles JSON-RPC communication over stdio with an Xcode MCP server process. `MCPClient` is an **actor** that manages connection state, request/response matching via `CheckedContinuation`, and tool invocation.

**Parser enums** (`XcodeWindowParser`, `PreviewFileParser`, `RenderPreviewParser`) extract typed data from raw MCP tool call results. These are stateless with static methods only.

**`SnapshotService`** orchestrates the end-to-end flow: discover preview files via `XcodeGlob` → render each via `RenderPreview` → copy snapshot images to output directory.

**CLI entry point** (`XcodeMCPSnapshooter`) uses swift-argument-parser. The only external dependency.

## Conventions

- All code comments, doc comments, and commit messages in **English**
- Swift Testing framework (`@Test`, `@Suite`) for tests — not XCTest
- Tests use `MockTransport` (in `Tests/ModelTests/MockTransport.swift`) to inject JSON-RPC responses
- All public types conform to `Sendable` for concurrency safety
- Parsers are implemented as caseless enums with static methods
