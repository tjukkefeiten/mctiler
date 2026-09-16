import Testing
@testable import TilerCore

struct StackingTests {
    @Test func restoresFloatAfterDelayedActivationWithoutStealingFocus() {
        let d = Desktop()
        d.updateDisplays([Display(id: "main", frame: Rect(0,0,1000,800), usable: Rect(0,24,1000,776), fullscreen: Rect(0,24,1000,776))])
        let adapter = FakeAdapter()
        let r = Reconciler(desktop: d, adapter: adapter, configuration: .defaults)
        let windows = [ObservedWindow(id: "settings", frame: Rect(100,100,400,300), floating: true),
                       ObservedWindow(id: "tile", frame: Rect(0,24,1000,776))]
        r.ingest(WindowSnapshot(windows: windows, focused: "settings"))
        d.focus("tile")
        _ = adapter.focus("tile")
        _ = r.restoreStacking(force: true)
        #expect(adapter.raised == ["settings"])
        // Simulate activation completing after the immediate raise.
        adapter.raised = []
        var pending: [() -> Void] = []
        let coordinator = StackingCoordinator { _, work in pending.append(work) }
        coordinator.request(isCurrent: { true }) {
            _ = r.restoreStacking(force: true, foreground: WindowSnapshot(windows: windows, focused: "tile"))
        }
        #expect(pending.count == 3)
        while !pending.isEmpty { pending.removeFirst()() }
        #expect(adapter.raised == ["settings", "settings", "settings"])
        #expect(adapter.focusAttempts == ["tile"])
        #expect(d.focusedWindow == "tile")
    }
    @Test func cancelsOldRequestsAndSkipsPauseOrDrag() {
        var pending: [() -> Void] = [], calls: [String] = [], active = true
        let coordinator = StackingCoordinator { _, work in pending.append(work) }
        coordinator.request(isCurrent: { true }) { calls.append("old") }
        coordinator.request(isCurrent: { active }) { calls.append("new") }
        for _ in 0..<3 { pending.removeFirst()() }
        #expect(calls.isEmpty)
        pending.removeFirst()()
        #expect(calls == ["new"])
        active = false
        while !pending.isEmpty { pending.removeFirst()() }
        #expect(calls == ["new"])
        coordinator.request(isCurrent: { true }) { calls.append("cancelled") }
        coordinator.cancel()
        while !pending.isEmpty { pending.removeFirst()() }
        #expect(calls == ["new"])
    }
    @Test func freshUnmanagedForegroundOverridesCachedManagedFocus() {
        let (d, adapter, r) = ReconciliationTests().setup()
        let windows = [ObservedWindow(id: "settings", frame: Rect(100,100,400,300), floating: true)]
        r.ingest(WindowSnapshot(windows: windows, focused: "settings"))
        _ = r.restoreStacking(force: true, foreground: WindowSnapshot(windows: windows, focused: nil))
        #expect(adapter.raised.isEmpty)
        #expect(d.focusedWindow == "settings")
        _ = r.restoreStacking(force: true, foreground: WindowSnapshot(windows: windows, focused: "settings"))
        #expect(adapter.raised == ["settings"])
    }
}
