import AppKit
import ApplicationServices
import TilerCore

private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}
private func frameOf(_ element: AXUIElement) -> Rect? {
    guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
          let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero, dimensions = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
    let frame = Rect(point.x, point.y, dimensions.width, dimensions.height)
    return frame.valid ? frame : nil
}
private func writable(_ element: AXUIElement, _ name: String) -> Bool {
    var result = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(element, name as CFString, &result) == .success && result.boolValue
}

public final class MacWindowAdapter: WindowAdapter {
    private struct Entry {
        var element: AXUIElement
        var app: NSRunningApplication
        var title: String
    }
    private var entries: [String: Entry] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var observerTokens: [pid_t: ObserverToken] = [:]
    private var cooldown: [pid_t: Date] = [:]
    public let journal: RecoveryJournal
    public var onChange: (() -> Void)?
    public var parkingDisplays: [String: Display] = [:]
    public var displays: [Display] = []
    public private(set) var lastError: String?
    public init(journal: RecoveryJournal) { self.journal = journal }
    public static var trusted: Bool { AXIsProcessTrusted() }
    public static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    public func snapshot() -> WindowSnapshot {
        guard Self.trusted else { return WindowSnapshot(windows: [], complete: false) }
        var result: [ObservedWindow] = [], live = Set<String>(), complete = true
        let applications = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
        let appIDs = Set(applications.map(\.processIdentifier))
        for pid in Array(observers.keys) where !appIDs.contains(pid) {
            if let observer = observers.removeValue(forKey: pid) {
                let token = observerTokens.removeValue(forKey: pid)
                DispatchQueue.main.async {
                    CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                    withExtendedLifetime(token) {}
                }
            }
            cooldown[pid] = nil
        }
        var focused: String?
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for app in applications {
            let pid = app.processIdentifier
            if cooldown[pid].map({ $0 > Date() }) == true { complete = false; continue }
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.08)
            guard let rawWindows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] else {
                complete = false; cooldown[pid] = Date().addingTimeInterval(3); continue
            }
            installObserver(pid: pid, application: application)
            let focusedElement = pid == frontmost ? attribute(application, kAXFocusedWindowAttribute) : nil
            for element in rawWindows {
                AXUIElementSetMessagingTimeout(element, 0.08)
                let role = attribute(element, kAXRoleAttribute) as? String
                guard role == kAXWindowRole else { continue }
                guard let frame = frameOf(element) else { complete = false; continue }
                let id = entries.first { $0.value.app.processIdentifier == pid && CFEqual($0.value.element, element) }?.key ?? UUID().uuidString
                let title = attribute(element, kAXTitleAttribute) as? String ?? ""
                let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
                let canMove = writable(element, kAXPositionAttribute)
                guard canMove else { continue }
                let fixed = !writable(element, kAXSizeAttribute)
                let modal = attribute(element, kAXModalAttribute) as? Bool ?? false
                entries[id] = Entry(element: element, app: app, title: title); live.insert(id)
                if let focusedElement, CFEqual(focusedElement, element) { focused = id }
                result.append(ObservedWindow(id: id, frame: frame, bundle: app.bundleIdentifier ?? "", floating: fixed || modal || subrole == kAXDialogSubrole || subrole == kAXSystemDialogSubrole,
                    minimized: attribute(element, kAXMinimizedAttribute) as? Bool ?? false,
                    nativeFullscreen: attribute(element, "AXFullScreen") as? Bool ?? false,
                    dialog: modal || subrole == kAXDialogSubrole || subrole == kAXSystemDialogSubrole))
                if let observer = observers[pid], let token = observerTokens[pid] {
                    for name in [kAXUIElementDestroyedNotification, kAXMovedNotification, kAXResizedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
                        AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(token).toOpaque())
                    }
                }
            }
        }
        let stale = Set(entries.filter { !appIDs.contains($0.value.app.processIdentifier) || (complete && !live.contains($0.key)) }.keys)
        for id in stale { entries[id] = nil }
        if !stale.isEmpty { try? journal.remove(stale) }
        return WindowSnapshot(windows: result, focused: focused, complete: complete)
    }
    private final class ObserverToken {
        let callback: () -> Void
        init(_ callback: @escaping () -> Void) { self.callback = callback }
    }
    private func installObserver(pid: pid_t, application: AXUIElement) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            Unmanaged<ObserverToken>.fromOpaque(context).takeUnretainedValue().callback()
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let token = ObserverToken { [weak self] in self?.onChange?() }
        observerTokens[pid] = token; observers[pid] = observer
        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXApplicationActivatedNotification] {
            AXObserverAddNotification(observer, application, name as CFString, Unmanaged.passUnretained(token).toOpaque())
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    public func setFrame(_ frame: Rect, for id: String) -> Bool {
        guard let entry = entries[id], let current = frameOf(entry.element) else { return false }
        do { try journal.record(id: id, pid: entry.app.processIdentifier, launched: entry.app.launchDate, title: entry.title, current: current, target: frame) }
        catch { lastError = "Cannot save recovery journal: \(error.localizedDescription)"; return false }
        var result = setRawFrame(frame, element: entry.element)
        if let display = parkingDisplays[id], let actual = frameOf(entry.element), Parking.isHidden(actual, on: display, displays: displays) {
            result = true
            // Record AppKit's actual clamped parking geometry for crash recovery.
            do { try journal.record(id: id, pid: entry.app.processIdentifier, launched: entry.app.launchDate, title: entry.title, current: current, target: actual) }
            catch { lastError = "Cannot update recovery journal: \(error.localizedDescription)"; return false }
        }
        if !result { lastError = "An application rejected a window frame; retries are suspended until the target changes or management resumes." }
        return result
    }
    private func setRawFrame(_ frame: Rect, element: AXUIElement) -> Bool {
        var point = CGPoint(x: frame.x, y: frame.y), size = CGSize(width: frame.width, height: frame.height)
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else { return false }
        _ = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        if writable(element, kAXSizeAttribute) { _ = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, dimensions) }
        guard AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position) == .success, let actual = frameOf(element) else { return false }
        return actual.approximately(frame, tolerance: 4)
    }
    /// AX hit testing respects occlusion, including unmanaged windows and menus.
    public func window(at point: CGPoint) -> String? {
        // Menu-bar selection persists while a menu is open, even if the pointer
        // strays over another app. Do not activate that app and dismiss the menu.
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.08)
            if let bar = attribute(application, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID(),
               let selected = attribute(bar as! AXUIElement, kAXSelectedChildrenAttribute) as? [AXUIElement], !selected.isEmpty { return nil }
            if let focused = attribute(application, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID(),
               let role = attribute(focused as! AXUIElement, kAXRoleAttribute) as? String,
               [kAXMenuRole, kAXMenuItemRole, kAXMenuBarItemRole].contains(role) { return nil }
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.08)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        // Some apps omit AXWindow on content elements. Walk their AX parents
        // instead of treating those content areas as unmanaged windows.
        var element = hit
        for _ in 0..<32 {
            if let role = attribute(element, kAXRoleAttribute) as? String,
               [kAXMenuRole, kAXMenuItemRole, kAXMenuBarItemRole].contains(role) { return nil }
            if let id = entries.first(where: { CFEqual($0.value.element, element) })?.key { return id }
            if let window = attribute(element, kAXWindowAttribute),
               let id = entries.first(where: { CFEqual($0.value.element, window) })?.key { return id }
            guard let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID(),
                  !CFEqual(parent, element) else { return nil }
            element = parent as! AXUIElement
        }
        return nil
    }

    public func focus(_ id: String) -> Bool {
        guard let entry = entries[id] else { return false }
        let application = AXUIElementCreateApplication(entry.app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.08)
        _ = entry.app.activate(options: [])
        _ = AXUIElementSetAttributeValue(entry.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        if writable(application, kAXFocusedWindowAttribute) {
            _ = AXUIElementSetAttributeValue(application, kAXFocusedWindowAttribute as CFString, entry.element)
        }
        _ = raise(id)
        // Activation is asynchronous. A successful raise alone does not prove
        // that keyboard input will reach this window; the controller retries
        // briefly and checks the actual foreground app and focused AX window.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == entry.app.processIdentifier,
              let focused = attribute(application, kAXFocusedWindowAttribute) else { return false }
        return CFEqual(focused, entry.element)
    }
    public func raise(_ id: String) -> Bool {
        guard let entry = entries[id] else { return false }
        // Raising does not explicitly activate the application or set its main window.
        return AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString) == .success
    }
    public func recover(displays: [Display]) -> (restored: Int, remaining: Int) {
        guard Self.trusted, !displays.isEmpty else { return (0, journal.entries.count) }
        _ = snapshot()
        var removed = Set<String>(), restored = 0, used = Set<String>()
        for (key, record) in journal.entries {
            guard let app = NSRunningApplication(processIdentifier: record.pid), app.launchDate == record.launched else { removed.insert(key); continue }
            let candidates = entries.filter { id, entry in
                guard !used.contains(id), entry.app.processIdentifier == record.pid, let frame = frameOf(entry.element) else { return false }
                if id == key { return true }
                return entry.title == record.title && (frame.approximately(record.target, tolerance: 12) || frame.approximately(record.previous, tolerance: 12) || frame.approximately(record.original, tolerance: 12))
            }
            guard candidates.count == 1, let (id, entry) = candidates.first else { continue }
            let display = displays.first { record.original.intersects($0.frame) } ?? displays[0]
            if setRawFrame(record.original.clamped(to: display.usable), element: entry.element) { removed.insert(key); used.insert(id); restored += 1 }
        }
        do { try journal.remove(removed) } catch { lastError = error.localizedDescription }
        return (restored, journal.entries.count)
    }
}
