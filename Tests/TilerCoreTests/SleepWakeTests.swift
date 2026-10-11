import Testing
import Foundation
@testable import TilerCore

final class SleepWakeTests {
    let external = Display(id: "external", frame: Rect(0,0,1600,1000), usable: Rect(0,24,1600,976), fullscreen: Rect(0,24,1600,976))
    let builtIn = Display(id: "built-in", frame: Rect(-1200,200,1200,800), usable: Rect(-1200,224,1200,776), fullscreen: Rect(-1200,224,1200,776))
    let frame = Rect(100,100,400,300)

    @Test func testScreenLockWithoutSessionSwitchOrSleep() {
        let wake = SleepWakeRecovery()
        wake.screenDidLock(displays: [external], windows: ["a"])
        wake.screenDidLock(displays: [], windows: [])
        #expect(wake.lockCount == 1)
        #expect(wake.sleeping && wake.screenLocked)
        #expect(!wake.finishIfReady(WindowSnapshot(windows: []), at: 100))
        wake.screenDidUnlock(displays: [external], at: 101)
        #expect(!wake.finishIfReady(WindowSnapshot(windows: []), at: 102))
        #expect(wake.finishIfReady(WindowSnapshot(windows: [ObservedWindow(id: "a", frame: frame)]), at: 103))
    }

    @Test func testSessionActivationAndWakeDoNotOverrideScreenLock() {
        let wake = SleepWakeRecovery()
        wake.screenDidLock(displays: [external], windows: ["a"])
        wake.sessionDidResignActive(displays: [], windows: [])
        wake.willSleep(displays: [], windows: [])
        wake.didWake(displays: [external], at: 10)
        wake.sessionDidBecomeActive(displays: [external], at: 11)
        #expect(wake.sleeping)
        #expect(wake.expectedWindows == ["a"])
        wake.screenDidUnlock(displays: [external], at: 12)
        #expect(!wake.sleeping)
        #expect(wake.wakeStarted == 12)
    }

    @Test func testLockUnlockWithoutSleepRetainsBaseline() {
        let wake = SleepWakeRecovery()
        wake.sessionDidResignActive(displays: [external, builtIn], windows: ["a", "b"])
        #expect(wake.sleeping && wake.sessionInactive)
        #expect(!wake.finishIfReady(WindowSnapshot(windows: []), at: 100))
        // Duplicate notifications and empty enumerations must not replace the baseline.
        wake.sessionDidResignActive(displays: [], windows: [])
        wake.sessionDidBecomeActive(displays: [external, builtIn], at: 101)
        wake.sessionDidBecomeActive(displays: [external, builtIn], at: 102)
        #expect(wake.wakeStarted == 101)
        #expect(!wake.finishIfReady(WindowSnapshot(windows: []), at: 103))
        #expect(wake.missingWindows == ["a", "b"])
        let snapshot = WindowSnapshot(windows: [ObservedWindow(id: "a", frame: frame), ObservedWindow(id: "b", frame: frame)])
        #expect(wake.finishIfReady(snapshot, at: 104))
        #expect(!wake.suspended)
    }

    @Test func testSleepAndInactiveSessionRequireBothToResume() {
        for unlockFirst in [false, true] {
            let wake = SleepWakeRecovery()
            wake.sessionDidResignActive(displays: [external], windows: ["a"])
            wake.willSleep(displays: [], windows: [])
            let snapshot = WindowSnapshot(windows: [ObservedWindow(id: "a", frame: frame)])
            if unlockFirst { wake.sessionDidBecomeActive(displays: [external], at: 10) }
            else { wake.didWake(displays: [external], at: 10) }
            #expect(wake.sleeping)
            #expect(!wake.finishIfReady(snapshot, at: 100))
            if unlockFirst { wake.didWake(displays: [external], at: 101) }
            else { wake.sessionDidBecomeActive(displays: [external], at: 101) }
            #expect(wake.expectedWindows == ["a"])
            #expect(!wake.finishIfReady(snapshot, at: 101))
            #expect(wake.finishIfReady(snapshot, at: 102))
        }
    }

    @Test func testWakeWaitsForDisplaysAndKnownWindowsDespiteCompleteEmptySnapshot() throws {
        let d = Desktop(); d.updateDisplays([external, builtIn])
        try d.switchWorkspace("7")
        d.addWindow("external-window", frame: frame)
        d.addWindow("hidden-window", frame: frame, workspace: "4", focus: false)
        d.focusedDisplay = builtIn.id
        try d.switchWorkspace("9")
        let floatingFrame = Rect(-1000,300,400,300)
        d.addWindow("floating-window", frame: floatingFrame, floating: true)
        let originalVisible = d.visible
        let memberships = d.windows.mapValues(\.workspace)
        let trees = d.workspaces.mapValues { $0.tree.id }
        let adapter = FakeAdapter()
        let reconciler = Reconciler(desktop: d, adapter: adapter, configuration: .defaults)
        let wake = SleepWakeRecovery()
        wake.willSleep(displays: d.displays, windows: Set(d.windows.keys))
        #expect(wake.suspended)
        #expect(!wake.finishIfReady(WindowSnapshot(windows: []), at: 100))
        wake.didWake(displays: [builtIn], at: 100)
        // Successful AX calls can still return no windows while waking.
        #expect(!wake.finishIfReady(WindowSnapshot(windows: []), at: 102))
        let observed = memberships.keys.sorted().map { ObservedWindow(id: $0, frame: frame) }
        let snapshot = WindowSnapshot(windows: observed, focused: "hidden-window")
        #expect(!wake.finishIfReady(snapshot, at: 103))
        #expect(wake.missingDisplays == [external.id])
        wake.observeDisplays([external, builtIn], at: 104)
        #expect(!wake.finishIfReady(snapshot, at: 104.5))
        #expect(wake.finishIfReady(snapshot, at: 105))
        d.updateDisplays(wake.displays)
        reconciler.ingest(snapshot, allowFocus: false, allowFloatingUpdates: false)
        #expect(d.windows.mapValues(\.workspace) == memberships)
        #expect(d.visible == originalVisible)
        #expect(d.workspaces.mapValues { $0.tree.id } == trees)
        #expect(d.windows["floating-window"]?.floatingFrame == floatingFrame)
        #expect(wake.lastResult == "restored")
        #expect(!wake.suspended)
        // The stale AX focus sampled during wake must not activate a hidden workspace.
        reconciler.ingest(snapshot)
        #expect(d.visible == originalVisible)
    }

    @Test func testWindowEnumerationCanRecoverAfterDisplayTopologySettles() {
        let wake = SleepWakeRecovery()
        wake.willSleep(displays: [external], windows: ["a", "b"])
        wake.didWake(displays: [external], at: 0)
        let partial = WindowSnapshot(windows: [ObservedWindow(id: "a", frame: frame)], complete: false)
        #expect(!wake.finishIfReady(partial, at: 2))
        #expect(wake.missingWindows == ["b"])
        // An unrelated inaccessible app need not block recovery of every known window.
        let restored = WindowSnapshot(windows: partial.windows + [ObservedWindow(id: "b", frame: frame)], complete: false)
        #expect(wake.finishIfReady(restored, at: 3))
    }

    @Test func testTimeoutAllowsUnpluggedMonitorAndClosedWindowThenRestoresLateDisplay() throws {
        let d = Desktop(); d.updateDisplays([external, builtIn])
        try d.switchWorkspace("7"); d.addWindow("external-window", frame: frame)
        d.focusedDisplay = builtIn.id
        try d.switchWorkspace("9"); d.addWindow("closed-during-sleep", frame: frame)
        let wake = SleepWakeRecovery()
        wake.willSleep(displays: d.displays, windows: Set(d.windows.keys))
        wake.didWake(displays: [builtIn], at: 0)
        let snapshot = WindowSnapshot(windows: [ObservedWindow(id: "external-window", frame: frame)])
        #expect(!wake.finishIfReady(snapshot, at: 9))
        #expect(wake.finishIfReady(snapshot, at: 10))
        #expect(wake.lastResult == "timed out waiting for displays/windows")
        d.updateDisplays(wake.displays)
        let r = Reconciler(desktop: d, adapter: FakeAdapter(), configuration: .defaults)
        r.ingest(snapshot, allowFocus: false, allowFloatingUpdates: false)
        #expect(d.windows["closed-during-sleep"] == nil)
        #expect(d.windows["external-window"]?.workspace == "7")
        #expect(d.visible == [builtIn.id: "9"])
        // Access the disconnected monitor's workspace while waiting for it.
        try d.switchWorkspace("7")
        d.updateDisplays([external, builtIn])
        #expect(d.visible == [external.id: "7", builtIn.id: "9"])
        #expect(d.windows["external-window"]?.workspace == "7")
    }

    @Test func testNoDisplaysNeverResumesEvenAfterTimeout() {
        let wake = SleepWakeRecovery()
        wake.willSleep(displays: [external], windows: [])
        wake.didWake(displays: [], at: 0)
        #expect(!wake.finishIfReady(WindowSnapshot(windows: []), at: 100))
        #expect(wake.suspended)
        wake.observeDisplays([builtIn], at: 101)
        #expect(wake.finishIfReady(WindowSnapshot(windows: []), at: 101))
    }

    @Test func testRepeatedNotificationsDoNotExtendDeadlineAndSecondSleepKeepsBaseline() {
        let wake = SleepWakeRecovery()
        wake.willSleep(displays: [external, builtIn], windows: ["a"])
        wake.didWake(displays: [builtIn], at: 0)
        wake.didWake(displays: [builtIn], at: 8)
        #expect(wake.wakeStarted == 0)
        wake.willSleep(displays: [builtIn], windows: [])
        #expect(!wake.finishIfReady(WindowSnapshot(windows: []), at: 20))
        wake.didWake(displays: [builtIn], at: 30)
        #expect(wake.expectedDisplays == [external.id, builtIn.id])
        #expect(wake.expectedWindows == ["a"])
        #expect(!wake.finishIfReady(WindowSnapshot(windows: []), at: 39))
        #expect(wake.finishIfReady(WindowSnapshot(windows: []), at: 40))
    }

    @Test func testGeometryChangesRestartSettlingButEnumerationOrderDoesNot() {
        let wake = SleepWakeRecovery()
        wake.willSleep(displays: [external, builtIn], windows: [])
        wake.didWake(displays: [external, builtIn], at: 0)
        wake.observeDisplays([builtIn, external], at: 0.8)
        #expect(wake.finishIfReady(WindowSnapshot(windows: []), at: 1))
        wake.willSleep(displays: [external], windows: [])
        wake.didWake(displays: [external], at: 10)
        let resized = Display(id: external.id, frame: frame, usable: frame, fullscreen: frame)
        wake.observeDisplays([resized], at: 10.8)
        #expect(!wake.finishIfReady(WindowSnapshot(windows: []), at: 11))
        #expect(wake.finishIfReady(WindowSnapshot(windows: []), at: 12))
    }

    @Test func testAllDisplaysDisappearAndReturnInReverseOrder() throws {
        let d = Desktop(); d.updateDisplays([external, builtIn])
        try d.switchWorkspace("7"); d.addWindow("a", frame: frame)
        d.focusedDisplay = builtIn.id
        try d.switchWorkspace("9"); d.addWindow("b", frame: frame)
        let memberships = d.windows.mapValues(\.workspace)
        d.updateDisplays([])
        d.updateDisplays([builtIn])
        #expect(d.visible[builtIn.id] == "9")
        d.updateDisplays([builtIn, external])
        #expect(d.visible == [external.id: "7", builtIn.id: "9"])
        #expect(d.windows.mapValues(\.workspace) == memberships)
    }

    @Test func testExplicitWorkspaceMoveSupersedesRememberedDisplaySelection() throws {
        let d = Desktop(); d.updateDisplays([external, builtIn])
        try d.switchWorkspace("7")
        d.updateDisplays([builtIn])
        // Configuration can reassign an absent display's workspace explicitly.
        d.workspaces["7"]?.preferredDisplay = builtIn.id
        try d.switchWorkspace("7")
        d.updateDisplays([external, builtIn])
        #expect(d.visible[builtIn.id] == "7")
        #expect(d.visible[external.id] != "7")
        #expect(Set(d.visible.values).count == 2)
    }
}
