import Foundation

public struct ScratchpadState: Codable {
    public var hidden = true
    public var wasFloating: Bool
    public var display: String
    public var returnFocus: String?
}

extension Desktop {
    public var shownScratchpad: String? {
        scratchpadOrder.first { windows[$0]?.scratchpad?.hidden == false }
    }

    /// Keep the window's leaf so hiding and releasing on the same workspace
    /// preserves its position in a manual split tree.
    public func moveToScratchpad() throws {
        guard let id = focusedWindow, let state = windows[id], !state.minimized, !state.nativeFullscreen,
              let display = displays.first(where: { $0.id == focusedDisplay }) else {
            throw TilerError.message("No eligible focused window")
        }
        if state.scratchpad == nil {
            windows[id]?.scratchpad = ScratchpadState(wasFloating: state.floating, display: display.id)
            windows[id]?.floating = true
            if !state.floating && workspaces[state.workspace]?.floating != true {
                windows[id]?.floatingFrame = centeredScratchpad(width: display.usable.width * 0.6, height: display.usable.height * 0.6, on: display)
            }
            scratchpadOrder.append(id)
        }
        hideScratchpad(id)
        workspaces[state.workspace]?.refreshAutomaticLayout(windows: windows)
        lastScratchpadShown = id
    }

    /// Show/hide the most recently selected entry. `next` cycles in insertion
    /// order instead, skipping minimized and application-native fullscreen windows.
    public func showScratchpad(next: Bool = false) throws {
        guard let workspace = current, let display = displays.first(where: { $0.id == focusedDisplay }) else {
            throw TilerError.message("No workspace or display")
        }
        let eligible = scratchpadOrder.filter {
            windows[$0].map { $0.scratchpad != nil && !$0.minimized && !$0.nativeFullscreen } ?? false
        }
        guard !eligible.isEmpty else { throw TilerError.message("No available scratchpad windows") }
        if !next, let shown = shownScratchpad, windows[shown]?.workspace == workspace.name, eligible.contains(shown) {
            hideScratchpad(shown)
            return
        }
        let id: String
        if next, let last = lastScratchpadShown, let index = scratchpadOrder.firstIndex(of: last) {
            let rotated = Array(scratchpadOrder.dropFirst(index + 1)) + Array(scratchpadOrder.prefix(index + 1))
            id = rotated.first { eligible.contains($0) }!
        } else {
            id = lastScratchpadShown.flatMap { eligible.contains($0) ? $0 : nil } ?? eligible[0]
        }
        if let shown = shownScratchpad { hideScratchpad(shown) }
        let previousFocus = workspace.focused
        try transferWindow(id, to: workspace.name)
        if let state = windows[id], state.scratchpad?.display != display.id {
            windows[id]?.floatingFrame = centeredScratchpad(width: state.floatingFrame.width, height: state.floatingFrame.height, on: display)
        } else if let frame = windows[id]?.floatingFrame {
            windows[id]?.floatingFrame = frame.clamped(to: display.usable)
        }
        windows[id]?.scratchpad?.hidden = false
        windows[id]?.scratchpad?.display = display.id
        windows[id]?.scratchpad?.returnFocus = previousFocus
        lastScratchpadShown = id
        focus(id)
    }

    public func releaseScratchpad() throws {
        guard let id = focusedWindow, let state = windows[id]?.scratchpad, !state.hidden,
              let workspace = current else { throw TilerError.message("Focus a shown scratchpad window first") }
        windows[id]?.floating = state.wasFloating
        windows[id]?.scratchpad = nil
        scratchpadOrder.removeAll { $0 == id }
        if lastScratchpadShown == id { lastScratchpadShown = nil }
        workspace.refreshAutomaticLayout(windows: windows)
    }

    public func hideInactiveScratchpads() {
        for id in scratchpadOrder where windows[id].map({ !visible.values.contains($0.workspace) }) == true {
            hideScratchpad(id)
        }
    }

    private func hideScratchpad(_ id: String) {
        guard let state = windows[id], state.scratchpad != nil, let workspace = workspaces[state.workspace] else { return }
        windows[id]?.scratchpad?.hidden = true
        if workspace.fullscreen == id { workspace.fullscreen = nil }
        if workspace.focused == id {
            if let previous = state.scratchpad?.returnFocus, let target = windows[previous],
               previous != id, target.workspace == workspace.name, !target.minimized, !target.nativeFullscreen, target.scratchpad?.hidden != true {
                workspace.focused = previous
                workspace.selected = workspace.tree.leaf(previous)?.id
            } else { restoreWorkspaceFocus(workspace) }
        }
    }

    func restoreWorkspaceFocus(_ workspace: Workspace) {
        workspace.focused = workspace.tree.windows.first { id in
            windows[id].map { !$0.minimized && !$0.nativeFullscreen && $0.scratchpad?.hidden != true } ?? false
        }
        workspace.selected = workspace.focused.flatMap { workspace.tree.leaf($0)?.id }
    }

    private func centeredScratchpad(width: Double, height: Double, on display: Display) -> Rect {
        let width = min(width, display.usable.width), height = min(height, display.usable.height)
        return Rect(display.usable.midX - width / 2, display.usable.midY - height / 2, width, height)
    }
}
