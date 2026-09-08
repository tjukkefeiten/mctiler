import Testing
import Foundation
@testable import TilerCore

final class ConfigurationTests {
    @Test func testAllDefaultHotkeysUseOptionAndLeaveCommandAvailable() throws {
        let bindings = Configuration.defaults.bindings
        #expect(bindings.count == 39)
        for key in bindings.keys {
            let hotkey = try Hotkey.parse(key)
            #expect(hotkey.modifiers & 2048 != 0)
            #expect(hotkey.modifiers & 256 == 0)
        }
        #expect(bindings["alt-shift-escape"] == "fullscreen")
        #expect(bindings["alt-ctrl-space"] == "workspace-floating")
        #expect(bindings["alt-ctrl-escape"] == "pause")
        #expect(bindings["alt-ctrl-f"] == "fullscreen")
    }
    @Test func testShippedExampleMatchesDefaultBindings() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let example = try Configuration.load(path: root.appendingPathComponent("config.example.toml").path)
        #expect(example.bindings == Configuration.defaults.bindings)
    }
    @Test func testCustomModifiersRemainSupportedAndMigrationCollisionsAreRejected() throws {
        let config = try Configuration.parse("[bindings]\ncmd-f = \"fullscreen\"\nalt-shift-escape = \"floating\"")
        #expect(config.bindings["cmd-f"] == "fullscreen")
        #expect(config.bindings.count == 2)
        #expect(throws: (any Error).self) {
            _ = try Configuration.parse("[bindings]\nalt-shift-escape = \"floating\"\nshift-alt-escape = \"pause\"")
        }
    }
    @Test func testDefaultsAndCommandsAgree() throws {
        for (key, value) in Configuration.defaults.bindings {
            _ = try Hotkey.parse(key); _ = try Command.parse(value.split(separator:" ").map(String.init))
        }
    }
    @Test func testDocumentedConfigSubset() throws {
        let config = try Configuration.parse("""
        inner-gap = 12
        experimental-suppress-dock = true
        [bindings]
        cmd-f = "fullscreen" # comment
        [workspaces]
        "1" = "display-id"
        [[rules]]
        bundle = "com.apple.Terminal"
        workspace = "2"
        floating = false
        """)
        #expect(config.innerGap == 12); #expect(config.suppressDock)
        #expect(config.bindings == ["cmd-f":"fullscreen"])
        #expect(config.rules[0].workspace == "2")
        #expect(config.assignments["1"] == "display-id")
    }
    @Test func testInvalidConfigRejected() {
        for value in ["inner-gap = nan", "outer-gap = -1", "unknown = true", "inner-gap = 1\ninner-gap = 2", "[[rules]]\nfloating = true", "[bindings]\ncmd-f = \"made-up\"", "[bindings]\ncmd-shift-f = \"fullscreen\"\nshift-cmd-f = \"floating\"", "[workspaces]\n10 = \"display\""] {
            #expect(throws: (any Error).self) { _ = try Configuration.parse(value) }
        }
    }
    @Test func testCommandValidation() {
        for args in [["fullscreen","extra"],["workspace","10"],["resize","left","nan"],["resize","up","-1"],["select","invalid"]] {
            #expect(throws: (any Error).self) { _ = try Command.parse(args) }
        }
    }
}
