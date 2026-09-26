import Foundation

/// Only pointer movement into a new eligible window requests focus.
public final class PointerFocus {
    private var position: (Double, Double)?
    private var hovered: String?
    public init() {}
    public func reset() { position = nil; hovered = nil }
    public func update(x: Double, y: Double, enabled: Bool, moved: () -> Void = {}, target: () -> String?) -> String? {
        let previous = position
        position = (x, y)
        guard enabled else { hovered = nil; return nil }
        guard let previous, previous.0 != x || previous.1 != y else { return nil }
        moved()
        let next = target()
        defer { hovered = next }
        return next != hovered ? next : nil
    }
}

extension Desktop {
    /// Display targeting must not depend on there being a window to hit-test.
    @discardableResult
    public func focusDisplayFromPointer(x: Double, y: Double) -> Bool {
        guard let display = displays.first(where: {
            x >= $0.frame.x && x < $0.frame.maxX && y >= $0.frame.y && y < $0.frame.maxY
        }), visible[display.id] != nil, display.id != focusedDisplay else { return false }
        focusedDisplay = display.id
        return true
    }

    public func canFocusFromPointer(_ id: String) -> Bool {
        guard let state = windows[id], !state.minimized, !state.nativeFullscreen, state.scratchpad?.hidden != true,
              let workspace = workspaces[state.workspace], visible.values.contains(state.workspace) else { return false }
        guard let full = workspace.fullscreen else { return true }
        return id == full || (state.dialog && state.bundle == windows[full]?.bundle)
    }
}
