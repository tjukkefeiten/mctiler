import Testing
import Foundation
@testable import TilerCore

final class ScratchpadTests {
    let main = Display(id: "main", frame: Rect(0,0,1200,800), usable: Rect(0,24,1200,716), fullscreen: Rect(0,24,1200,776))
    let external = Display(id: "external", frame: Rect(-900,100,900,700), usable: Rect(-900,124,900,676), fullscreen: Rect(-900,124,900,676))
    let frame = Rect(100,100,400,300)
    func desktop() -> Desktop {
        let d = Desktop(); d.updateDisplays([main]); return d
    }
    func add(_ id: String, to d: Desktop, floating: Bool = false) { d.addWindow(id, frame: frame, floating: floating) }
    func command(_ action: String, on d: Desktop) throws { try Command.parse(["scratchpad", action]).apply(to: d) }

    @Test func hidingCompactsTilesAndShowingFloatsWithoutOccupyingATile() throws {
        let d = desktop(); add("a", to: d); add("b", to: d); add("pad", to: d)
        try command("move", on: d)
        #expect(d.windows["pad"]?.scratchpad?.hidden == true)
        #expect(d.scratchpadOrder == ["pad"])
        let tiled = d.layout(d.current!, on: main)
        #expect(Set(tiled.keys) == ["a", "b"])
        #expect(tiled["a"]?.height == main.usable.height - 16)
        #expect(!d.isDraggableTile("pad"))
        d.focus("b")
        try command("show", on: d)
        let shown = d.layout(d.current!, on: main)
        #expect(shown["a"] == tiled["a"] && shown["b"] == tiled["b"])
        #expect(shown["pad"]?.midX == main.usable.midX)
        #expect(shown["pad"]?.width == main.usable.width * 0.6)
        #expect(d.focusedWindow == "pad")
        #expect(d.canFocusFromPointer("pad"))
        try command("show", on: d)
        #expect(d.focusedWindow == "b")
        #expect(d.layout(d.current!, on: main) == tiled)
    }

    @Test func hiddenAXFocusAndParkingFramesDoNotSummonOrMoveScratchpad() throws {
        let d = desktop(); add("a", to: d); add("pad", to: d)
        try command("move", on: d)
        let saved = d.windows["pad"]!.floatingFrame
        let adapter = FakeAdapter(), r = Reconciler(desktop: d, adapter: FakeAdapter(), configuration: .defaults)
        let parked = Parking.frame(for: saved, on: main, displays: [main])!
        let snapshot = WindowSnapshot(windows: [ObservedWindow(id: "a", frame: frame), ObservedWindow(id: "pad", frame: parked)], focused: "pad")
        r.ingest(snapshot)
        #expect(d.focusedWindow == "a")
        #expect(d.windows["pad"]?.floatingFrame == saved)
        #expect(!d.canFocusFromPointer("pad"))
        #expect(d.shownScratchpad == nil)
        try d.switchWorkspace("2")
        r.ingest(WindowSnapshot(windows: snapshot.windows))
        r.ingest(snapshot)
        #expect(d.current?.name == "2")
        #expect(d.workspaces["1"]?.focused == "a")
        let stacking = Reconciler(desktop: d, adapter: adapter, configuration: .defaults)
        stacking.ingest(snapshot)
        _ = stacking.restoreStacking(force: true)
        #expect(adapter.raised.isEmpty)
    }

    @Test func showingOnAnotherMonitorTransfersMembershipAndRecenters() throws {
        let d = desktop(); d.updateDisplays([main, external]); add("pad", to: d)
        try command("move", on: d); try command("show", on: d)
        let order = d.scratchpadOrder
        d.focusedDisplay = external.id
        add("other", to: d)
        try command("show", on: d)
        #expect(d.windows["pad"]?.workspace == "2")
        #expect(d.workspaces["1"]?.tree.windows.isEmpty == true)
        #expect(d.workspaces["2"]?.tree.windows.filter { $0 == "pad" }.count == 1)
        #expect(d.scratchpadOrder == order)
        #expect(d.focusedWindow == "pad")
        let shown = d.layout(d.current!, on: external)["pad"]!
        #expect(shown.midX == external.usable.midX)
        #expect(shown.midY == external.usable.midY)
        #expect(shown.width <= external.usable.width && shown.height <= external.usable.height)
        try command("show", on: d)
        #expect(d.focusedWindow == "other")
    }

    @Test func cyclingSkipsUnavailableWindowsAndCleansUpClosedEntries() throws {
        let d = desktop()
        for id in ["a", "b", "c"] { add(id, to: d); try command("move", on: d) }
        try command("show", on: d)
        #expect(d.shownScratchpad == "c")
        try command("next", on: d)
        #expect(d.shownScratchpad == "a")
        d.windows["b"]?.minimized = true
        try command("next", on: d)
        #expect(d.shownScratchpad == "c")
        d.windows["a"]?.nativeFullscreen = true
        try command("next", on: d)
        #expect(d.shownScratchpad == "c")
        let r = Reconciler(desktop: d, adapter: FakeAdapter(), configuration: .defaults)
        r.ingest(WindowSnapshot(windows: [ObservedWindow(id: "a", frame: frame), ObservedWindow(id: "b", frame: frame)]))
        #expect(d.scratchpadOrder == ["a", "b"])
        #expect(d.shownScratchpad == nil)
        try command("show", on: d)
        #expect(d.shownScratchpad == "a")
        #expect(d.windows.values.filter { $0.scratchpad?.hidden == false }.count == 1)
    }

    @Test func switchingAwayHidesScratchpadAndReturningDoesNotRevealIt() throws {
        let d = desktop(); add("pad", to: d)
        try command("move", on: d); try command("show", on: d)
        try d.switchWorkspace("3")
        #expect(d.shownScratchpad == nil)
        try d.switchWorkspace("1")
        #expect(d.layout(d.current!, on: main).isEmpty)
        #expect(d.focusedWindow == nil)
        try command("show", on: d)
        #expect(d.focusedWindow == "pad")
    }

    @Test func releaseRestoresManualTilePositionAndWeights() throws {
        let d = desktop(); add("a", to: d); try d.split(.vertical); add("pad", to: d); add("c", to: d)
        d.focus("pad"); try d.resize(.down, amount: 20)
        let before = d.layout(d.current!, on: main)
        let leaf = d.current!.tree.leaf("pad")!.id
        try command("move", on: d); try command("show", on: d)
        #expect(throws: (any Error).self) { try d.toggleFloating() }
        try command("release", on: d)
        #expect(d.windows["pad"]?.scratchpad == nil)
        #expect(d.windows["pad"]?.floating == false)
        #expect(d.scratchpadOrder.isEmpty)
        #expect(d.current!.tree.leaf("pad")!.id == leaf)
        #expect(d.layout(d.current!, on: main) == before)
    }

    @Test func floatingMovementIsRememberedAndReleaseRemainsFloating() throws {
        let d = desktop(); add("pad", to: d, floating: true)
        try command("move", on: d); try command("show", on: d)
        let moved = Rect(200,200,500,350)
        let r = Reconciler(desktop: d, adapter: FakeAdapter(), configuration: .defaults)
        r.ingest(WindowSnapshot(windows: [ObservedWindow(id: "pad", frame: moved)], focused: "pad"))
        try command("show", on: d); try command("show", on: d)
        #expect(d.layout(d.current!, on: main)["pad"] == moved)
        try command("release", on: d)
        #expect(d.windows["pad"]?.floating == true)
        #expect(d.windows["pad"]?.floatingFrame == moved)
    }

    @Test func sendingToNumberedWorkspaceReleasesScratchpad() throws {
        let d = desktop(); add("pad", to: d)
        try command("move", on: d); try command("show", on: d)
        try d.sendWindow(to: "4")
        #expect(d.windows["pad"]?.workspace == "4")
        #expect(d.windows["pad"]?.floating == false)
        #expect(d.windows["pad"]?.scratchpad == nil)
        #expect(d.scratchpadOrder.isEmpty)
        #expect(d.current?.name == "1")
        #expect(d.current?.focused == nil)
    }

    @Test func fullscreenAndWorkspaceFloatingCannotRevealHiddenScratchpad() throws {
        let d = desktop(); add("a", to: d); add("pad", to: d)
        try Command.fullscreen.apply(to: d)
        try command("move", on: d)
        #expect(d.current?.fullscreen == nil)
        try d.toggleWorkspaceFloating()
        #expect(d.layout(d.current!, on: main)["pad"] == nil)
        try Command.fullscreen.apply(to: d)
        try command("show", on: d)
        #expect(d.current?.fullscreen == nil)
        try Command.fullscreen.apply(to: d)
        try command("show", on: d)
        #expect(d.current?.fullscreen == nil)
        #expect(d.focusedWindow == "a")
        #expect(d.layout(d.current!, on: main)["pad"] == nil)
    }

    @Test func monitorDisconnectAndEmptySnapshotsPreserveOnlyLiveScratchpadEntries() throws {
        let d = desktop(); d.updateDisplays([main, external]); d.focusedDisplay = external.id
        add("pad", to: d); try command("move", on: d); try command("show", on: d)
        d.updateDisplays([main])
        #expect(d.shownScratchpad == nil)
        let r = Reconciler(desktop: d, adapter: FakeAdapter(), configuration: .defaults)
        r.ingest(WindowSnapshot(windows: [], complete: false))
        #expect(d.scratchpadOrder == ["pad"])
        try command("show", on: d)
        #expect(d.windows["pad"]?.workspace == "1")
        r.ingest(WindowSnapshot(windows: []))
        #expect(d.scratchpadOrder.isEmpty)
        #expect(d.shownScratchpad == nil)
    }

    @Test func scratchpadIsRaisedOnlyWhenShownAndFocusReturnsToSurvivingWindow() throws {
        let d = desktop(); add("a", to: d); add("b", to: d); add("pad", to: d)
        try command("move", on: d); d.focus("b"); try command("show", on: d)
        let adapter = FakeAdapter(), snapshot = WindowSnapshot(windows: ["a", "b", "pad"].map { ObservedWindow(id: $0, frame: frame) }, focused: "pad")
        let r = Reconciler(desktop: d, adapter: adapter, configuration: .defaults)
        r.ingest(snapshot); _ = r.restoreStacking(force: true)
        #expect(adapter.raised == ["pad"])
        d.removeWindow("b")
        try command("show", on: d)
        #expect(d.focusedWindow == "a")
        adapter.raised = []
        _ = r.restoreStacking(force: true)
        #expect(adapter.raised.isEmpty)
    }

    @Test func invalidRequestsDoNotMutateMembershipAndAllBindingsParse() throws {
        let d = desktop()
        for action in ["move", "show", "next", "release"] {
            #expect(throws: (any Error).self) { try command(action, on: d) }
        }
        add("pad", to: d); d.windows["pad"]?.nativeFullscreen = true
        #expect(throws: (any Error).self) { try command("move", on: d) }
        #expect(d.scratchpadOrder.isEmpty)
        d.windows["pad"]?.nativeFullscreen = false
        try command("move", on: d); try command("show", on: d); try command("move", on: d)
        #expect(d.scratchpadOrder == ["pad"])
        #expect(d.windows["pad"]?.scratchpad?.wasFloating == false)
        #expect(throws: (any Error).self) { try command("release", on: d) }
        for args in [["scratchpad"], ["scratchpad", "unknown"], ["scratchpad", "show", "extra"]] {
            #expect(throws: (any Error).self) { _ = try Command.parse(args) }
        }
        let bindings = ["alt-shift-s": "scratchpad move", "alt-s": "scratchpad show", "alt-ctrl-s": "scratchpad next", "alt-ctrl-shift-s": "scratchpad release"]
        for (key, value) in bindings { #expect(Configuration.defaults.bindings[key] == value) }
        let config = try Configuration.parse("[bindings]\nalt-s = \"scratchpad show\"")
        #expect(config.bindings == ["alt-s": "scratchpad show"])
    }
}
