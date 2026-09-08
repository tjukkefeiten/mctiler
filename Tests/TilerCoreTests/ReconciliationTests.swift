import Testing
import Foundation
@testable import TilerCore

final class FakeAdapter: WindowAdapter {
    var observation = WindowSnapshot(windows: [])
    var attempts: [String] = []
    var rejecting = Set<String>()
    var raised: [String] = []
    var focusAttempts: [String] = []
    var focusResults: [Bool] = []
    func snapshot() -> WindowSnapshot { observation }
    func setFrame(_ frame: Rect, for id: String) -> Bool { attempts.append(id); return !rejecting.contains(id) }
    func focus(_ id: String) -> Bool { focusAttempts.append(id); return focusResults.isEmpty ? true : focusResults.removeFirst() }
    func raise(_ id: String) -> Bool { raised.append(id); return true }
}

final class ReconciliationTests {
    @Test func testDiscoveryAndIncrementalCreationUseSameQuadrants() {
        func make() -> (Desktop, Reconciler) {
            let d = Desktop()
            d.updateDisplays([Display(id: "main", frame: Rect(0,0,1200,800), usable: Rect(0,24,1200,716), fullscreen: Rect(0,24,1200,776))])
            return (d, Reconciler(desktop: d, adapter: FakeAdapter(), configuration: .defaults))
        }
        let (batch, batchReconciler) = make(), (incremental, incrementalReconciler) = make()
        let observed = (1...5).map { ObservedWindow(id: String($0), frame: Rect(0,0,400,300)) }
        batchReconciler.ingest(WindowSnapshot(windows: observed, focused: "1"))
        for count in 1...5 {
            incrementalReconciler.ingest(WindowSnapshot(windows: Array(observed.prefix(count)), focused: "1"))
        }
        #expect(batch.layout(batch.current!, on: batch.displays[0]) == incremental.layout(incremental.current!, on: incremental.displays[0]))
        let tree = batch.current!.tree.children.map(\.id)
        batchReconciler.ingest(WindowSnapshot(windows: observed, focused: "2"))
        #expect(batch.current!.tree.children.map(\.id) == tree)
    }
    @Test func testFullscreenRaisesOwnedDialogsAfterFullscreenWindow() throws {
        let (d, adapter, r) = setup()
        r.ingest(WindowSnapshot(windows:[ObservedWindow(id:"a",frame:Rect(0,24,400,300),bundle:"app"), ObservedWindow(id:"dialog",frame:Rect(100,100,200,100),bundle:"app",floating:true,dialog:true)],focused:"a"))
        try Command.fullscreen.apply(to:d)
        _ = r.restoreStacking()
        #expect(adapter.raised == ["a", "dialog"])
    }
    @Test func testFloatingStaysAboveTilesWithoutRepeatedRaiseLoop() throws {
        let (d, adapter, r) = setup()
        let snapshot = WindowSnapshot(windows: [ObservedWindow(id:"a",frame:Rect(0,24,400,300)), ObservedWindow(id:"b",frame:Rect(400,24,400,300))],focused:"a")
        r.ingest(snapshot)
        try d.toggleFloating()
        _ = r.restoreStacking()
        #expect(adapter.raised == ["a"])
        r.ingest(snapshot); _ = r.restoreStacking()
        #expect(adapter.raised == ["a"])
        r.ingest(WindowSnapshot(windows:snapshot.windows,focused:"b")); _ = r.restoreStacking()
        #expect(adapter.raised == ["a", "a"])
        #expect(d.focusedWindow == "b")
        d.focus("a"); try d.toggleFloating(); _ = r.restoreStacking(force:true)
        #expect(adapter.raised == ["a", "a"])
        #expect(d.current?.tree.windows == ["a", "b"])
    }
    @Test func testStackingExcludesHiddenWindowsAndUnmanagedFocus() throws {
        let (d, adapter, r) = setup()
        let windows = [ObservedWindow(id:"a",frame:Rect(0,24,400,300),floating:true), ObservedWindow(id:"b",frame:Rect(400,24,400,300))]
        r.ingest(WindowSnapshot(windows:windows,focused:"a"))
        try d.sendWindow(to:"2"); _ = r.restoreStacking()
        #expect(adapter.raised.isEmpty)
        try d.switchWorkspace("2")
        r.ingest(WindowSnapshot(windows:windows,focused:nil)); _ = r.restoreStacking(force:true)
        #expect(adapter.raised.isEmpty)
    }
    func setup() -> (Desktop, FakeAdapter, Reconciler) {
        let desktop = Desktop()
        desktop.updateDisplays([Display(id: "main", frame: Rect(0,0,1000,800), usable: Rect(0,24,1000,700), fullscreen: Rect(0,24,1000,776))])
        let adapter = FakeAdapter()
        return (desktop, adapter, Reconciler(desktop: desktop, adapter: adapter, configuration: .defaults))
    }
    @Test func testDuplicateEventsAndIncompleteEnumerationDoNotLoseWindows() {
        let (d, _, r) = setup()
        let snapshot = WindowSnapshot(windows: [ObservedWindow(id: "a", frame: Rect(0,0,400,300))], focused: "a")
        r.ingest(snapshot); r.ingest(snapshot)
        #expect(d.current!.tree.windows == ["a"])
        r.ingest(WindowSnapshot(windows: [], complete: false)); #expect(d.windows["a"] != nil)
        r.ingest(WindowSnapshot(windows: [])); #expect(d.windows["a"] == nil)
    }
    @Test func testRepeatedFocusNotificationPreservesParentSelection() throws {
        let (d, _, r) = setup()
        let snapshot = WindowSnapshot(windows: [ObservedWindow(id: "a", frame: Rect(0,0,400,300))], focused: "a")
        r.ingest(snapshot); try d.select(true)
        let selected = d.current!.selected
        r.ingest(snapshot); #expect(d.current!.selected == selected)
    }
    @Test func testEmptyWorkspaceDoesNotBounceBackToParkedFocusedWindow() throws {
        let (d, _, r) = setup()
        let snapshot = WindowSnapshot(windows: [ObservedWindow(id:"a",frame:Rect(0,0,400,300))],focused:"a")
        r.ingest(snapshot); try d.switchWorkspace("2")
        r.ingest(snapshot)
        #expect(d.current?.name == "2")
        r.ingest(WindowSnapshot(windows:snapshot.windows,focused:nil))
        r.ingest(snapshot)
        #expect(d.current?.name == "1")
    }
    @Test func testRejectedGeometryDoesNotRetryForeverOrBlockOtherWindows() {
        let (_, adapter, r) = setup(); adapter.rejecting = ["bad"]
        let targets = ["bad": Rect(0,0,500,500), "good": Rect(500,0,500,500)]
        #expect(r.apply(targets, actual: [:]) == ["bad"])
        _ = r.apply(targets, actual: ["good": targets["good"]!])
        #expect(adapter.attempts == ["bad", "good"])
        r.resetFailures(); _ = r.apply(targets, actual: ["good": targets["good"]!])
        #expect(adapter.attempts == ["bad", "good", "bad"])
    }
    @Test func testMinimizedAndNativeFullscreenWindowsAreExcluded() throws {
        let (d, _, r) = setup()
        r.ingest(WindowSnapshot(windows: [ObservedWindow(id:"a",frame:Rect(0,0,400,300)), ObservedWindow(id:"b",frame:Rect(0,0,400,300), minimized:true), ObservedWindow(id:"c",frame:Rect(0,0,400,300),nativeFullscreen:true)], focused:"a"))
        #expect(Set(d.layout(d.current!, on: d.displays[0]).keys) == ["a"])
        try Command.fullscreen.apply(to:d)
        r.ingest(WindowSnapshot(windows:[ObservedWindow(id:"a",frame:Rect(0,0,400,300),minimized:true)]))
        #expect(d.current!.fullscreen == nil)
    }
    @Test func testFloatingMouseMovementIsRememberedButOwnMoveIsNotReingested() {
        let (d, _, r) = setup()
        let original = Rect(100,100,400,300), target = Rect(200,200,400,300)
        r.ingest(WindowSnapshot(windows:[ObservedWindow(id:"a",frame:original,floating:true)],focused:"a"))
        _ = r.apply(["a":target],actual:["a":original])
        r.ingest(WindowSnapshot(windows:[ObservedWindow(id:"a",frame:target,floating:true)]))
        #expect(d.windows["a"]!.floatingFrame == original)
        let mouseFrame = Rect(300,300,400,300)
        r.ingest(WindowSnapshot(windows:[ObservedWindow(id:"a",frame:mouseFrame,floating:true)]))
        #expect(d.windows["a"]!.floatingFrame == mouseFrame)
    }
}
