import Testing
@testable import TilerCore

struct PointerFocusTests {
    @Test func movementAndWindowEntryRequired() {
        let pointer = PointerFocus()
        #expect(pointer.update(x: 10, y: 10, enabled: true) { "a" } == nil)
        #expect(pointer.update(x: 11, y: 10, enabled: true) { "a" } == "a")
        #expect(pointer.update(x: 12, y: 10, enabled: true) { "a" } == nil)
        #expect(pointer.update(x: 12, y: 10, enabled: true) { "b" } == nil)
        #expect(pointer.update(x: 13, y: 10, enabled: true) { "b" } == "b")
        #expect(pointer.update(x: 14, y: 10, enabled: true) { nil } == nil)
        #expect(pointer.update(x: 15, y: 10, enabled: true) { "b" } == "b")
    }
    @Test func rapidEntriesDoNotRequireFurtherMovementAfterArrival() {
        let pointer = PointerFocus()
        _ = pointer.update(x: 0, y: 0, enabled: true) { "a" }
        #expect(pointer.update(x: 10, y: 0, enabled: true) { "a" } == "a")
        #expect(pointer.update(x: 500, y: 0, enabled: true) { "b" } == "b")
        #expect(pointer.update(x: 500, y: 0, enabled: true) { "b" } == nil)
        #expect(pointer.update(x: 10, y: 0, enabled: true) { "a" } == "a")
    }
    @Test func suppressionAndResetDoNotStealFocusAtRest() {
        let pointer = PointerFocus()
        #expect(pointer.update(x: 1, y: 1, enabled: false) { Issue.record("Suppressed hit test"); return "a" } == nil)
        #expect(pointer.update(x: 1, y: 1, enabled: true) { "a" } == nil)
        #expect(pointer.update(x: 2, y: 1, enabled: true) { "a" } == "a")
        pointer.reset()
        #expect(pointer.update(x: 2, y: 1, enabled: true) { "b" } == nil)
    }
    @Test func onlyVisibleEligibleWindowsCanReceivePointerFocus() throws {
        let d = Desktop()
        d.updateDisplays([Display(id: "main", frame: Rect(0,0,1000,800), usable: Rect(0,24,1000,776), fullscreen: Rect(0,24,1000,776))])
        for id in ["a", "b"] { d.addWindow(id, frame: Rect(0,24,500,400)) }
        d.addWindow("hidden", frame: Rect(0,0,100,100), workspace: "2")
        #expect(!d.canFocusFromPointer("hidden"))
        #expect(!d.canFocusFromPointer("unknown"))
        #expect(d.canFocusFromPointer("a"))
        d.windows["a"]?.minimized = true
        #expect(!d.canFocusFromPointer("a"))
        d.windows["a"]?.minimized = false
        d.windows["a"]?.nativeFullscreen = true
        #expect(!d.canFocusFromPointer("a"))
        d.windows["a"]?.nativeFullscreen = false
        d.current?.fullscreen = "b"; d.windows["b"]?.bundle = "app"
        #expect(!d.canFocusFromPointer("a"))
        #expect(d.canFocusFromPointer("b"))
        d.windows["a"]?.dialog = true; d.windows["a"]?.bundle = "app"
        #expect(d.canFocusFromPointer("a"))
    }
    @Test func configurationDefaultsOnAndCanDisable() throws {
        #expect(Configuration.defaults.focusFollowsMouse)
        #expect(try Configuration.parse("focus-follows-mouse = false").focusFollowsMouse == false)
        #expect(throws: (any Error).self) { try Configuration.parse("focus-follows-mouse = 1") }
    }
}
