import Foundation

/// Holds reconciliation until the pre-sleep windows and displays return. The
/// timeout permits continued use when a monitor was actually unplugged or an app
/// quit during sleep. Display/workspace restoration also works after this timeout.
public final class SleepWakeRecovery {
    private var systemSleeping = false
    public private(set) var sessionInactive = false
    public private(set) var screenLocked = false
    public private(set) var lockCount = 0
    public var sleeping: Bool { systemSleeping || sessionInactive || screenLocked }
    public private(set) var wakeStarted: TimeInterval?
    public private(set) var displays: [Display] = []
    public private(set) var expectedDisplays = Set<String>()
    public private(set) var expectedWindows = Set<String>()
    public private(set) var missingWindows = Set<String>()
    public private(set) var lastResult = "none"
    private var stableSince: TimeInterval = 0
    private let quietPeriod: TimeInterval
    private let maximumWait: TimeInterval

    public init(quietPeriod: TimeInterval = 1, maximumWait: TimeInterval = 10) {
        self.quietPeriod = quietPeriod; self.maximumWait = maximumWait
    }
    public var suspended: Bool { sleeping || wakeStarted != nil }
    public var phase: String { sleeping ? "sleeping" : (wakeStarted == nil ? "awake" : "settling") }
    public var missingDisplays: Set<String> { expectedDisplays.subtracting(displays.map(\.id)) }

    public func willSleep(displays: [Display], windows: Set<String>) {
        suspend(displays: displays, windows: windows)
        systemSleeping = true
    }
    public func sessionDidResignActive(displays: [Display], windows: Set<String>) {
        suspend(displays: displays, windows: windows)
        sessionInactive = true
    }
    public func screenDidLock(displays: [Display], windows: Set<String>) {
        suspend(displays: displays, windows: windows)
        if !screenLocked { lockCount += 1 }
        screenLocked = true
    }
    public func screenDidUnlock(displays: [Display], at now: TimeInterval) {
        guard screenLocked else { return }
        screenLocked = false
        resume(displays: displays, at: now)
    }
    private func suspend(displays: [Display], windows: Set<String>) {
        // A second sleep during wake recovery must retain the original baseline.
        if !suspended {
            expectedDisplays = Set(displays.map(\.id))
            expectedWindows = windows
            missingWindows = windows
            self.displays = displays
        }
        wakeStarted = nil
    }
    public func didWake(displays: [Display], at now: TimeInterval) {
        guard systemSleeping else { return }
        systemSleeping = false
        resume(displays: displays, at: now)
    }
    public func sessionDidBecomeActive(displays: [Display], at now: TimeInterval) {
        guard sessionInactive else { return }
        sessionInactive = false
        resume(displays: displays, at: now)
    }
    private func resume(displays: [Display], at now: TimeInterval) {
        self.displays = displays
        guard !sleeping else { return }
        wakeStarted = now; stableSince = now
    }
    public func observeDisplays(_ displays: [Display], at now: TimeInterval) {
        if self.displays.sorted(by: { $0.id < $1.id }) != displays.sorted(by: { $0.id < $1.id }) {
            self.displays = displays; stableSince = now
        }
    }
    public func finishIfReady(_ snapshot: WindowSnapshot, at now: TimeInterval) -> Bool {
        guard !sleeping, let started = wakeStarted else { return false }
        missingWindows = expectedWindows.subtracting(snapshot.windows.map(\.id))
        guard !displays.isEmpty else { return false }
        let restored = missingDisplays.isEmpty && missingWindows.isEmpty && now - stableSince >= quietPeriod
        guard restored || now - started >= maximumWait else { return false }
        lastResult = restored ? "restored" : "timed out waiting for displays/windows"
        wakeStarted = nil
        return true
    }
}
