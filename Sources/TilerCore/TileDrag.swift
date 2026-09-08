import Foundation

/// Captures layout slots before native dragging occludes the destination window.
public struct TileDrag {
    public let source: String
    public let originalFrame: Rect
    public let slots: [String: Rect]
    public init(source: String, originalFrame: Rect, slots: [String: Rect]) {
        self.source = source; self.originalFrame = originalFrame; self.slots = slots
    }
    public func destination(x: Double, y: Double, finalFrame: Rect) -> String? {
        // A content drag or resize must never rearrange the layout. Native
        // cancelled moves also return to the original position.
        guard abs(finalFrame.x-originalFrame.x) > 4 || abs(finalFrame.y-originalFrame.y) > 4,
              abs(finalFrame.width-originalFrame.width) <= 4,
              abs(finalFrame.height-originalFrame.height) <= 4 else { return nil }
        let hits = slots.filter { id, frame in
            id != source && x >= frame.x && x < frame.maxX && y >= frame.y && y < frame.maxY
        }
        return hits.count == 1 ? hits.first?.key : nil
    }
}

extension Desktop {
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
