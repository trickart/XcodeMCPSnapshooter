import AppKit
import ArgumentParser
@preconcurrency import ApplicationServices
import Foundation

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check and guide Accessibility permission setup for automatic dialog handling"
    )

    func run() async throws {
        let isTrusted = AXIsProcessTrusted()

        // Open Xcode Settings > Intelligence regardless of Accessibility permission
        print("Opening Xcode Settings > Intelligence...")
        print()
        print("Please enable \"Allow external agents to use Xcode tools\"")
        print("under Model Context Protocol section.")
        openXcodeIntelligenceSettings(canUseAccessibility: isTrusted)

        if isTrusted {
            print()
            print("✓ Accessibility permission is already granted.")
            print("  xmsnap can automatically handle Xcode permission dialogs.")
        } else {
            print()
            print("Accessibility permission is required to automatically click")
            print("the \"Allow\" button on Xcode's permission dialog.")
            print()
            print("Note: Permission is granted to the terminal application")
            print("(e.g., Terminal.app, iTerm2), not to xmsnap itself.")
            print()
            print("Opening System Settings > Accessibility...")

            // Prompt system dialog + open settings
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    private func openXcodeIntelligenceSettings(canUseAccessibility: Bool) {
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dt.Xcode"
        ).first != nil else {
            print("  Xcode is not running. Launch Xcode and re-run this command.")
            return
        }

        if canUseAccessibility {
            // Use AppleScript with System Events to open Settings and navigate to Intelligence
            let source = """
            tell application "Xcode" to activate
            delay 0.5
            tell application "System Events"
                keystroke "," using {command down}
            end tell
            delay 0.5
            tell application "System Events"
                tell process "Xcode"
                    tell outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1
                        repeat with r in rows
                            try
                                if name of static text 1 of UI element 1 of r is "Intelligence" then
                                    select r
                                    exit repeat
                                end if
                            end try
                        end repeat
                    end tell
                end tell
            end tell
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                print("  Could not navigate to Intelligence tab automatically.")
                print("  Please open Xcode > Settings > Intelligence manually.")
            }
        } else {
            // Without Accessibility, just activate Xcode and open Settings with Cmd+,
            let source = """
            tell application "Xcode" to activate
            delay 0.5
            tell application "System Events"
                keystroke "," using {command down}
            end tell
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                print("  Could not open Xcode Settings automatically.")
            }
            print("  Navigate to Intelligence tab manually.")
        }
    }
}
