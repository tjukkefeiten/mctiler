import Foundation

/// Only pointer movement into a new eligible window requests focus.
public final class PointerFocus {
    private var position: (Double, Double)?
    private var hovered: String?
    public init() {}
    public func reset() { position = nil; hovered = nil }
    public func update(x: Double, y: Double, enabled: Bool, target: () -> String?) -> String? {
        let previous = position
        position = (x, y)
        guard enabled else { hovered = nil; return nil }
        guard let previous, previous.0 != x || previous.1 != y else { return nil }
        let next = target()
        defer { hovered = next }
        return next != hovered ? next : nil
    }
}

extension Desktop {
    public func canFocusFromPointer(_ id: String) -> Bool {
        guard let state = windows[id], !state.minimized, !state.nativeFullscreen,
              let workspace = workspaces[state.workspace], visible.values.contains(state.workspace) else { return false }
        guard let full = workspace.fullscreen else { return true }
        return id == full || (state.dialog && state.bundle == windows[full]?.bundle)
    }
}
