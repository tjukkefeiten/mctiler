import Foundation

/// Captures layout slots before native dragging occludes the destination window.
public struct TileDrag {
    public let sessionID = UUID()
    public let startPoint: (x: Double, y: Double)?
    public let source: String
    public let originalFrame: Rect
    public let slots: [String: Rect]
    public let visibleWorkspaces: [String: String]
    public let displays: [Display]
    public init(source: String, originalFrame: Rect, slots: [String: Rect], visibleWorkspaces: [String: String] = [:], displays: [Display] = [], startPoint: (x: Double, y: Double)? = nil) {
        self.startPoint = startPoint
        self.source = source; self.originalFrame = originalFrame; self.slots = slots
        self.visibleWorkspaces = visibleWorkspaces; self.displays = displays
    }
    public func isWindowMove(finalFrame: Rect, dropPoint: (x: Double, y: Double)? = nil) -> Bool {
        guard finalFrame.valid,
              abs(finalFrame.x-originalFrame.x) > 4 || abs(finalFrame.y-originalFrame.y) > 4 else { return false }
        if abs(finalFrame.width-originalFrame.width) <= 4 && abs(finalFrame.height-originalFrame.height) <= 4 { return true }
        // Native apps can restore/adjust size when dragged across displays.
        // Require an interior grab and window translation consistent with the
        // pointer; a resize-handle drag must not masquerade as a window move.
        guard let start = startPoint, let drop = dropPoint,
              start.x > originalFrame.x+8, start.x < originalFrame.maxX-8,
              start.y > originalFrame.y+8, start.y < originalFrame.maxY-8,
              let from = displays.first(where: { Self.contains($0.frame, start) }),
              let to = displays.first(where: { Self.contains($0.frame, drop) }), from.id != to.id else { return false }
        let translated = Rect(originalFrame.x+drop.x-start.x, originalFrame.y+drop.y-start.y, finalFrame.width, finalFrame.height)
        let clamped = translated.clamped(to: to.usable)
        func matchesPosition(_ expected: Rect) -> Bool {
            abs(expected.x-finalFrame.x) <= 12 && abs(expected.y-finalFrame.y) <= 12
        }
        // A native size restoration can change the horizontal grab offset.
        // Accept a continued interior title-bar grab across displays as well.
        let titleBarFollowsPointer = start.y-originalFrame.y <= 64
            && drop.y-finalFrame.y >= 8 && drop.y-finalFrame.y <= 64
            && drop.x > finalFrame.x+8 && drop.x < finalFrame.maxX-8
        return matchesPosition(translated) || matchesPosition(clamped) || titleBarFollowsPointer
    }
    private static func contains(_ frame: Rect, _ point: (x: Double, y: Double)) -> Bool {
        point.x >= frame.x && point.x < frame.maxX && point.y >= frame.y && point.y < frame.maxY
    }
    public func destination(x: Double, y: Double, finalFrame: Rect) -> String? {
        guard isWindowMove(finalFrame: finalFrame, dropPoint: (x, y)) else { return nil }
        let hits = slots.filter { id, frame in
            id != source && x >= frame.x && x < frame.maxX && y >= frame.y && y < frame.maxY
        }
        return hits.count == 1 ? hits.first?.key : nil
    }
}

extension Desktop {
    /// Swap within a workspace; insert into the visible workspace across displays. Validate the captured layout before changing any membership.
    @discardableResult
    public func completeTileDrag(_ drag: TileDrag, x: Double, y: Double, finalFrame: Rect) -> Bool {
        guard isDraggableTile(drag.source), drag.isWindowMove(finalFrame: finalFrame, dropPoint: (x, y)),
              (drag.visibleWorkspaces.isEmpty || drag.visibleWorkspaces == visible),
              (drag.displays.isEmpty || drag.displays == displays),
              tileSlots() == drag.slots else { return false }
        guard let display = displays.first(where: {
            x >= $0.usable.x && x < $0.usable.maxX && y >= $0.usable.y && y < $0.usable.maxY
        }), let name = visible[display.id],
              let workspace = workspaces[name], !workspace.floating, workspace.fullscreen == nil else { return false }
        if name == windows[drag.source]?.workspace {
            guard let target = drag.destination(x: x, y: y, finalFrame: finalFrame) else { return false }
            return swapTiles(drag.source, target)
        }
        focus(drag.source)
        do { try sendWindow(to: name) } catch { return false }
        focus(drag.source)
        return true
    }
    public func isDraggableTile(_ id: String) -> Bool {
        guard let state = windows[id], !state.floating, !state.minimized, !state.nativeFullscreen,
              let workspace = workspaces[state.workspace], !workspace.floating, workspace.fullscreen == nil,
              visible.values.contains(state.workspace) else { return false }
        return workspace.tree.leaf(id) != nil
    }
    public func tileSlots() -> [String: Rect] {
        var result: [String: Rect] = [:]
        for display in displays {
            guard let name = visible[display.id], let workspace = workspaces[name] else { continue }
            result.merge(layout(workspace, on: display).filter { isDraggableTile($0.key) }) { _, new in new }
        }
        return result
    }
    @discardableResult
    public func swapTiles(_ source: String, _ destination: String) -> Bool {
        guard source != destination, isDraggableTile(source), isDraggableTile(destination),
              let sourceName = windows[source]?.workspace, let destinationName = windows[destination]?.workspace,
              let sourceWorkspace = workspaces[sourceName], let destinationWorkspace = workspaces[destinationName],
              let sourceLeaf = sourceWorkspace.tree.leaf(source), let destinationLeaf = destinationWorkspace.tree.leaf(destination) else { return false }
        // Window identities move between slots; container weights and geometry stay.
        sourceWorkspace.automaticLayout = false; destinationWorkspace.automaticLayout = false
        sourceLeaf.window = destination; destinationLeaf.window = source
        windows[source]?.workspace = destinationName; windows[destination]?.workspace = sourceName
        if sourceName != destinationName {
            sourceWorkspace.insertionOrder = sourceWorkspace.insertionOrder.map { $0 == source ? destination : $0 }
            destinationWorkspace.insertionOrder = destinationWorkspace.insertionOrder.map { $0 == destination ? source : $0 }
            if sourceWorkspace.focused == source { sourceWorkspace.focused = destination }
            sourceWorkspace.selected = sourceWorkspace.focused.flatMap { sourceWorkspace.tree.leaf($0)?.id }
        }
        focus(source)
        return true
    }
}
