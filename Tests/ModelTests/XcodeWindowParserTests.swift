import Foundation
import Testing
@testable import Model

@Suite("XcodeWindowParser Tests")
struct XcodeWindowParserTests {

    @Test("Parse a single project")
    func singleProject() {
        let text = "* tabIdentifier: windowtab2, workspacePath: /Users/test/MyApp.xcworkspace\n"
        let projects = XcodeWindowParser.parseProjects(from: text)

        #expect(projects.count == 1)
        #expect(projects[0].name == "MyApp")
        #expect(projects[0].workspacePath == "/Users/test/MyApp.xcworkspace")
        #expect(projects[0].tabIdentifiers == ["windowtab2"])
    }

    @Test("Deduplicates entries with the same workspace")
    func deduplicatesSameWorkspace() {
        let text = """
        * tabIdentifier: windowtab2, workspacePath: /Users/test/MyApp.xcworkspace
        * tabIdentifier: windowtab3, workspacePath: /Users/test/MyApp.xcworkspace
        * tabIdentifier: windowtab4, workspacePath: /Users/test/MyApp.xcworkspace
        * tabIdentifier: windowtab2, workspacePath: /Users/test/MyApp.xcworkspace
        """
        let projects = XcodeWindowParser.parseProjects(from: text)

        #expect(projects.count == 1)
        #expect(projects[0].tabIdentifiers == ["windowtab2", "windowtab3", "windowtab4"])
    }

    @Test("Distinguishes multiple projects")
    func multipleProjects() {
        let text = """
        * tabIdentifier: windowtab2, workspacePath: /Users/test/AppA.xcworkspace
        * tabIdentifier: windowtab3, workspacePath: /Users/test/AppB.xcodeproj
        * tabIdentifier: windowtab4, workspacePath: /Users/test/AppA.xcworkspace
        """
        let projects = XcodeWindowParser.parseProjects(from: text)

        #expect(projects.count == 2)
        #expect(projects[0].name == "AppA")
        #expect(projects[0].tabIdentifiers == ["windowtab2", "windowtab4"])
        #expect(projects[1].name == "AppB")
        #expect(projects[1].tabIdentifiers == ["windowtab3"])
    }

    @Test("Empty text returns an empty array")
    func emptyText() {
        let projects = XcodeWindowParser.parseProjects(from: "")
        #expect(projects.isEmpty)
    }

    @Test("Invalid lines are skipped")
    func invalidLinesSkipped() {
        let text = """
        some random text
        * tabIdentifier: windowtab2, workspacePath: /Users/test/MyApp.xcworkspace
        another invalid line
        """
        let projects = XcodeWindowParser.parseProjects(from: text)

        #expect(projects.count == 1)
        #expect(projects[0].name == "MyApp")
    }

    @Test("Can parse from MCPToolCallResult")
    func parseFromToolCallResult() {
        let text = "* tabIdentifier: windowtab7, workspacePath: /Users/test/Project\n"
        let result = MCPToolCallResult(content: [.text(text)])
        let projects = XcodeWindowParser.parseProjects(from: result)

        #expect(projects.count == 1)
        #expect(projects[0].name == "Project")
        #expect(projects[0].workspacePath == "/Users/test/Project")
    }

    @Test("Falls back to message when content is empty")
    func fallbackToMessage() {
        let message = """
        * tabIdentifier: tab1, workspacePath: /Users/test/AppA.xcworkspace
        * tabIdentifier: tab2, workspacePath: /Users/test/AppB.xcodeproj
        """
        let result = MCPToolCallResult(content: [], message: message)
        let projects = XcodeWindowParser.parseProjects(from: result)

        #expect(projects.count == 2)
        #expect(projects[0].name == "AppA")
        #expect(projects[0].tabIdentifiers == ["tab1"])
        #expect(projects[1].name == "AppB")
        #expect(projects[1].tabIdentifiers == ["tab2"])
    }

    @Test("Content takes priority over message")
    func contentPriorityOverMessage() {
        let contentText = "* tabIdentifier: tab1, workspacePath: /Users/test/FromContent.xcworkspace\n"
        let message = "* tabIdentifier: tab2, workspacePath: /Users/test/FromMessage.xcworkspace\n"
        let result = MCPToolCallResult(content: [.text(contentText)], message: message)
        let projects = XcodeWindowParser.parseProjects(from: result)

        #expect(projects.count == 1)
        #expect(projects[0].name == "FromContent")
    }

    @Test("Unwraps JSON-wrapped message in text content")
    func unwrapsJSONMessage() {
        // Xcode MCP bridge wraps the actual data in {"message":"..."} inside text content
        let innerText = "* tabIdentifier: tab1, workspacePath: /Users/test/App.xcworkspace\n* tabIdentifier: tab2, workspacePath: /Users/test/Other.xcodeproj\n"
        let jsonText = "{\"message\":\"\(innerText.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "/", with: "\\/"))\"}"
        let result = MCPToolCallResult(content: [.text(jsonText)])
        let projects = XcodeWindowParser.parseProjects(from: result)

        #expect(projects.count == 2)
        #expect(projects[0].name == "App")
        #expect(projects[0].tabIdentifiers == ["tab1"])
        #expect(projects[1].name == "Other")
        #expect(projects[1].tabIdentifiers == ["tab2"])
    }
}
