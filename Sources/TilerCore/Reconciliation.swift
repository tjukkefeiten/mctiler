import Foundation

public struct ObservedWindow {
    public var id: String
    public var frame: Rect
    public var bundle: String
    public var floating: Bool
    public var minimized: Bool
    public var nativeFullscreen: Bool
    public var dialog: Bool
    public init(id: String, frame: Rect, bundle: String = "", floating: Bool = false, minimized: Bool = false, nativeFullscreen: Bool = false, dialog: Bool = false) {
        self.id = id; self.frame = frame; self.bundle = bundle; self.floating = floating
        self.minimized = minimized; self.nativeFullscreen = nativeFullscreen
        self.dialog = dialog
    }
}

public struct WindowSnapshot {
    public var windows: [ObservedWindow]
    public var focused: String?
    public var complete: Bool
    public init(windows: [ObservedWindow], focused: String? = nil, complete: Bool = true) { self.windows = windows; self.focused = focused; self.complete = complete }
}

public protocol WindowAdapter: AnyObject {
    func snapshot() -> WindowSnapshot
    func setFrame(_ frame: Rect, for id: String) -> Bool
    func focus(_ id: String) -> Bool
    func raise(_ id: String) -> Bool
}

public final class Reconciler {
    public let desktop: Desktop
    public let adapter: WindowAdapter
    public var configuration: Configuration
    public private(set) var rejected: [String: Rect] = [:]
    public private(set) var expected: [String: Rect] = [:]
    private var lastObservedFocus: String?
    private var stackingDirty = true
    private var lastOverlayOrder: [String] = []
    private var lastObservedWindows = Set<String>()
    public init(desktop: Desktop, adapter: WindowAdapter, configuration: Configuration) {
        self.desktop = desktop; self.adapter = adapter; self.configuration = configuration
    }
    public func ingest(_ snapshot: WindowSnapshot, allowFocus: Bool = true) {
        let live = Set(snapshot.windows.map(\.id))
        if live != lastObservedWindows { stackingDirty = true }
        lastObservedWindows = live
        if snapshot.complete {
            for id in Array(desktop.windows.keys) where !live.contains(id) { desktop.removeWindow(id); expected[id] = nil; rejected[id] = nil }
        }
        for observed in snapshot.windows {
            let rule = configuration.rules.first { $0.bundle == observed.bundle }
            if rule?.ignore == true && desktop.windows[observed.id] == nil { continue }
            if desktop.windows[observed.id] == nil {
                desktop.addWindow(observed.id, frame: observed.frame, floating: rule?.floating ?? observed.floating, workspace: rule?.workspace, focus: false)
            }
            desktop.windows[observed.id]?.minimized = observed.minimized
            desktop.windows[observed.id]?.nativeFullscreen = observed.nativeFullscreen
            desktop.windows[observed.id]?.dialog = observed.dialog
            desktop.windows[observed.id]?.bundle = observed.bundle
            if observed.minimized || observed.nativeFullscreen {
                if let name = desktop.windows[observed.id]?.workspace, desktop.workspaces[name]?.fullscreen == observed.id { desktop.workspaces[name]?.fullscreen = nil }
            }
            if let state = desktop.windows[observed.id], let workspace = desktop.workspaces[state.workspace],
               desktop.visible.values.contains(state.workspace), workspace.fullscreen == nil,
               state.floating || workspace.floating,
               expected[observed.id].map({ !$0.approximately(observed.frame) }) ?? true {
                desktop.windows[observed.id]?.floatingFrame = observed.frame
            }
        }
        let focusChanged = snapshot.focused != lastObservedFocus
        if focusChanged { stackingDirty = true }
        lastObservedFocus = snapshot.focused
        // macOS can retain a parked window as its focused AX element when the
        // destination workspace is empty. Only an actual focus change activates
        // its workspace; polling must not bounce back to the old workspace.
        if allowFocus, focusChanged, let focused = snapshot.focused, focused != desktop.focusedWindow { desktop.focus(focused) }
        for workspace in desktop.workspaces.values {
            if workspace.focused == nil || desktop.windows[workspace.focused!].map({ $0.minimized || $0.nativeFullscreen }) ?? true {
                workspace.focused = workspace.tree.windows.first { desktop.windows[$0].map { !$0.minimized && !$0.nativeFullscreen } ?? false }
                workspace.selected = workspace.focused.flatMap { workspace.tree.leaf($0)?.id }
            }
        }
    }
    public func apply(_ targets: [String: Rect], actual: [String: Rect]) -> [String] {
        var failures: [String] = []
        for id in targets.keys.sorted() {
            guard let frame = targets[id], frame.valid else { continue }
            if actual[id]?.approximately(frame) == true { expected[id] = frame; rejected[id] = nil; continue }
            if rejected[id]?.approximately(frame) == true { failures.append(id); continue }
            stackingDirty = true
            if adapter.setFrame(frame, for: id) { expected[id] = frame; rejected[id] = nil }
            else { rejected[id] = frame; failures.append(id) }
        }
        return failures
    }
    public func restoreStacking(force: Bool = false) -> [String] {
        var order: [String] = []
        for display in desktop.displays {
            guard let name = desktop.visible[display.id], let workspace = desktop.workspaces[name] else { continue }
            let visible = Set(desktop.layout(workspace, on: display).keys)
            if let full = workspace.fullscreen, visible.contains(full) { order.append(full) }
            if workspace.floating {
                if let focused = workspace.focused, visible.contains(focused), !order.contains(focused) { order.append(focused) }
            } else {
                order += workspace.tree.windows.filter { visible.contains($0) && desktop.windows[$0]?.floating == true && $0 != workspace.fullscreen }
            }
        }
        if let focused = desktop.focusedWindow, focused != desktop.current?.fullscreen, let index = order.firstIndex(of: focused) {
            order.remove(at: index); order.append(focused)
        }
        guard force || stackingDirty || order != lastOverlayOrder else { return [] }
        // Do not raise managed windows over an unrelated foreground application.
        guard let observed = lastObservedFocus, desktop.windows[observed] != nil else { return [] }
        lastOverlayOrder = order; stackingDirty = false
        return order.filter { !adapter.raise($0) }
    }
    public func resetFailures() { rejected = [:]; expected = [:]; stackingDirty = true }
}
