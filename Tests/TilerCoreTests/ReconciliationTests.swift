import Testing
import Foundation
@testable import TilerCore

final class FakeAdapter: WindowAdapter {
    var observation = WindowSnapshot(windows: [])
    var attempts: [String] = []
    var rejecting = Set<String>()
    func snapshot() -> WindowSnapshot { observation }
    func setFrame(_ frame: Rect, for id: String) -> Bool { attempts.append(id); return !rejecting.contains(id) }
    func focus(_ id: String) -> Bool { true }
}

final class ReconciliationTests {
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
