import ArgumentParser
@preconcurrency import ApplicationServices
import Foundation

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check and guide Accessibility permission setup for automatic dialog handling"
    )

    func run() async throws {
        let isTrusted = AXIsProcessTrusted()

        if isTrusted {
            print("✓ Accessibility permission is already granted.")
            print("  xmsnap can automatically handle Xcode permission dialogs.")
            return
        }

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
