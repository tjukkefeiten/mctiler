import Foundation

public final class Node: Codable {
    public var id: String = UUID().uuidString
    public var window: String?
    public var axis: Axis
    public var weight: Double = 1
    public var children: [Node]
    public init(window: String? = nil, axis: Axis = .horizontal, children: [Node] = []) {
        self.window = window; self.axis = axis; self.children = children
    }
    public var windows: [String] { window.map { [$0] } ?? children.flatMap(\.windows) }
    public func find(_ id: String) -> Node? { self.id == id ? self : children.lazy.compactMap { $0.find(id) }.first }
    public func leaf(_ window: String) -> Node? { self.window == window ? self : children.lazy.compactMap { $0.leaf(window) }.first }
    public func parent(of id: String) -> Node? {
        children.contains { $0.id == id } ? self : children.lazy.compactMap { $0.parent(of: id) }.first
    }
    public func remove(_ window: String) {
        children.removeAll { $0.window == window }
        for child in children { child.remove(window) }
        children.removeAll { $0.window == nil && $0.children.isEmpty }
        for index in children.indices where children[index].window == nil && children[index].children.count == 1 {
            let old = children[index]
            children[index] = old.children[0]
            children[index].weight = old.weight
        }
    }
    public func frames(in area: Rect, gap: Double, included: Set<String>) -> [String: Rect] {
        if let window { return included.contains(window) ? [window: area] : [:] }
        let active = children.filter { !$0.windows.allSatisfy { !included.contains($0) } }
        guard !active.isEmpty else { return [:] }
        let total = active.reduce(0) { $0 + max(0.05, $1.weight) }
        let length = axis == .horizontal ? area.width : area.height
        let effectiveGap = min(gap, max(0, (length - Double(active.count)) / Double(max(1, active.count - 1))))
        let available = max(Double(active.count), length - effectiveGap * Double(active.count - 1))
        var offset = 0.0, result: [String: Rect] = [:]
        for (index, child) in active.enumerated() {
            let size = index == active.count - 1 ? max(1, length-offset) : max(1, (available * max(0.05, child.weight)/total).rounded())
            let frame = axis == .horizontal ? Rect(area.x+offset, area.y, size, area.height) : Rect(area.x, area.y+offset, area.width, size)
            result.merge(child.frames(in: frame, gap: gap, included: included)) { _, new in new }
            offset += size + effectiveGap
        }
        return result
    }
}

public struct WindowState: Codable {
    public var id: String
    public var workspace: String
    public var floating: Bool
    public var floatingFrame: Rect
    public var minimized: Bool = false
    public var nativeFullscreen: Bool = false
    public var dialog = false
    public var bundle = ""
    public init(id: String, workspace: String, floating: Bool, frame: Rect) {
        self.id = id; self.workspace = workspace; self.floating = floating; self.floatingFrame = frame
    }
}

public final class Workspace: Codable {
    public var name: String
    public var tree = Node()
    public var floating = false
    public var automaticLayout = true
    public var insertionOrder: [String] = []
    private var automaticTiles: [String] = []
    public var focused: String?
    public var selected: String?
    public var fullscreen: String?
    public var preferredDisplay: String?
    public init(_ name: String) { self.name = name }
    fileprivate func refreshAutomaticLayout(windows: [String: WindowState]) {
        guard automaticLayout else { return }
        let tiled = insertionOrder.filter { id in
            guard let state = windows[id] else { return false }
            return !state.floating && !state.minimized && !state.nativeFullscreen
        }
        guard tiled != automaticTiles || Set(tree.windows) != Set(insertionOrder) else { return }
        automaticTiles = tiled
        let leaves = Dictionary(uniqueKeysWithValues: tree.windows.compactMap { id in tree.leaf(id).map { (id, $0) } })
        func leaf(_ id: String) -> Node {
            let node = leaves[id] ?? Node(window: id); node.weight = 1; return node
        }
        let tiles = tiled.map(leaf)
        var columns: [Node] = []
        if let first = tiles.first {
            columns.append(tiles.count > 2 ? Node(axis: .vertical, children: [first, tiles[2]]) : first)
        }
        if tiles.count > 1 {
            var right = [tiles[1]]
            if tiles.count > 3 {
                var tail = tiles.last!
                if tiles.count > 4 {
                    for index in stride(from: tiles.count-2, through: 3, by: -1) {
                        tail = Node(axis: (index-3).isMultiple(of: 2) ? .horizontal : .vertical, children: [tiles[index], tail])
                    }
                }
                right.append(tail)
            }
            columns.append(right.count == 1 ? right[0] : Node(axis: .vertical, children: right))
        }
        tree.axis = .horizontal
        tree.children = columns + insertionOrder.filter { !tiled.contains($0) }.map(leaf)
        if let selected, tree.find(selected) == nil { self.selected = focused.flatMap { tree.leaf($0)?.id } }
    }
}

public final class Desktop {
    public var windows: [String: WindowState] = [:]
    public var workspaces: [String: Workspace] = [:]
    public var displays: [Display] = []
    public var visible: [String: String] = [:] // display ID -> workspace
    public var focusedDisplay: String?
    public var innerGap = 8.0
    public var outerGap = 8.0
    public init() { for n in 1...9 { workspaces[String(n)] = Workspace(String(n)) } }
    public var current: Workspace? { focusedDisplay.flatMap { visible[$0] }.flatMap { workspaces[$0] } }
    public var focusedWindow: String? { current?.focused }
    public func updateDisplays(_ new: [Display]) {
        let newIDs = Set(new.map(\.id))
        visible = visible.filter { newIDs.contains($0.key) }
        displays = new
        for display in new where visible[display.id] == nil {
            let used = Set(visible.values)
            let names = workspaces.keys.sorted()
            let name = names.first { workspaces[$0]?.preferredDisplay == display.id }
                ?? names.first { workspaces[$0]?.preferredDisplay == nil && !used.contains($0) }
                ?? names.first { !used.contains($0) }
            if let name {
                // Reclaim a workspace temporarily shown on a surviving screen.
                if let owner = visible.first(where: { $0.value == name })?.key, owner != display.id {
                    let replacement = names.first { !used.contains($0) && workspaces[$0]?.preferredDisplay == owner }
                        ?? names.first { !used.contains($0) }
                    visible[owner] = replacement
                }
                visible[display.id] = name
                if workspaces[name]?.preferredDisplay == nil { workspaces[name]?.preferredDisplay = display.id }
            }
        }
        if focusedDisplay == nil || !newIDs.contains(focusedDisplay!) { focusedDisplay = new.first?.id }
    }
    public func switchWorkspace(_ name: String) throws {
        guard let workspace = workspaces[name], let display = focusedDisplay else { throw TilerError.message("Unknown workspace or no display") }
        if let owner = visible.first(where: { $0.value == name })?.key { focusedDisplay = owner }
        else {
            visible[display] = name
            if workspace.preferredDisplay == nil || displays.contains(where: { $0.id == workspace.preferredDisplay }) { workspace.preferredDisplay = display }
        }
    }
    public func addWindow(_ id: String, frame: Rect, floating: Bool = false, workspace name: String? = nil, focus: Bool = true) {
        guard windows[id] == nil, let workspace = name.flatMap({ workspaces[$0] }) ?? current else { return }
        windows[id] = WindowState(id: id, workspace: workspace.name, floating: floating, frame: frame)
        insert(Node(window: id), into: workspace)
        if focus { workspace.focused = id; workspace.selected = workspace.tree.leaf(id)?.id }
    }
    private func insert(_ node: Node, into workspace: Workspace) {
        if let id = node.window { workspace.insertionOrder.append(id) }
        if workspace.automaticLayout {
            workspace.tree.children.append(node)
            workspace.refreshAutomaticLayout(windows: windows)
            return
        }
        if let selected = workspace.selected, let target = workspace.tree.find(selected) {
            if target.window == nil { target.children.append(node) }
            else if let parent = workspace.tree.parent(of: selected), let index = parent.children.firstIndex(where: { $0.id == selected }) {
                parent.children.insert(node, at: index+1)
            } else { workspace.tree.children.append(node) }
        } else { workspace.tree.children.append(node) }
    }
    public func removeWindow(_ id: String) {
        guard let window = windows.removeValue(forKey: id), let workspace = workspaces[window.workspace] else { return }
        workspace.tree.remove(id)
        workspace.insertionOrder.removeAll { $0 == id }
        workspace.refreshAutomaticLayout(windows: windows)
        if workspace.fullscreen == id { workspace.fullscreen = nil }
        if workspace.focused == id { workspace.focused = workspace.tree.windows.first; workspace.selected = workspace.focused.flatMap { workspace.tree.leaf($0)?.id } }
        if let selected = workspace.selected, workspace.tree.find(selected) == nil { workspace.selected = workspace.focused.flatMap { workspace.tree.leaf($0)?.id } }
    }
    public func focus(_ id: String) {
        guard let state = windows[id], !state.minimized, !state.nativeFullscreen, let workspace = workspaces[state.workspace] else { return }
        try? switchWorkspace(state.workspace)
        if workspace.fullscreen != id && !(state.dialog && state.bundle == workspace.fullscreen.flatMap { windows[$0]?.bundle }) { workspace.fullscreen = nil }
        workspace.focused = id; workspace.selected = workspace.tree.leaf(id)?.id
    }
    public func layout(_ workspace: Workspace, on display: Display) -> [String: Rect] {
        workspace.refreshAutomaticLayout(windows: windows)
        let members = windows.values.filter { $0.workspace == workspace.name && !$0.minimized && !$0.nativeFullscreen }
        if let full = workspace.fullscreen, members.contains(where: { $0.id == full }) {
            var frames = [full: display.fullscreen]
            for member in members where member.dialog && member.bundle == windows[full]?.bundle && member.id != full {
                frames[member.id] = member.floatingFrame.clamped(to: display.fullscreen)
            }
            return frames
        }
        let tiled = Set(members.filter { !$0.floating && !workspace.floating }.map(\.id))
        var frames = workspace.tree.frames(in: display.usable.inset(outerGap), gap: innerGap, included: tiled)
        for window in members where window.floating || workspace.floating { frames[window.id] = window.floatingFrame.clamped(to: display.usable) }
        return frames
    }
    public func toggleFloating() throws {
        guard let id = focusedWindow else { throw TilerError.message("No focused window") }
        if let workspace = current, let display = displays.first(where: { $0.id == focusedDisplay }), !workspace.floating, windows[id]?.floating == false,
           let frame = layout(workspace, on: display)[id] { windows[id]?.floatingFrame = frame }
        current?.fullscreen = nil
        windows[id]?.floating.toggle()
        current?.refreshAutomaticLayout(windows: windows)
    }
    public func toggleWorkspaceFloating() throws {
        guard let workspace = current, let display = displays.first(where: { $0.id == focusedDisplay }) else { throw TilerError.message("No workspace") }
        workspace.fullscreen = nil
        if !workspace.floating { for (id, frame) in layout(workspace, on: display) { windows[id]?.floatingFrame = frame } }
        workspace.floating.toggle()
    }
    public func split(_ axis: Axis) throws {
        guard let workspace = current else { throw TilerError.message("No workspace") }
        workspace.refreshAutomaticLayout(windows: windows)
        workspace.automaticLayout = false
        guard let selected = workspace.selected, let node = workspace.tree.find(selected) else { workspace.tree.axis = axis; return }
        if node.window == nil { node.axis = axis; return }
        guard let parent = workspace.tree.parent(of: selected), let index = parent.children.firstIndex(where: { $0.id == selected }) else { return }
        let wrapper = Node(axis: axis, children: [node]); wrapper.weight = node.weight; node.weight = 1
        parent.children[index] = wrapper
    }
    public func select(_ parent: Bool) throws {
        guard let workspace = current, let selected = workspace.selected, let node = workspace.tree.find(selected) else { throw TilerError.message("No selection") }
        workspace.automaticLayout = false
        workspace.selected = parent ? workspace.tree.parent(of: selected)?.id ?? selected : node.children.first?.id ?? selected
    }
    public func neighbor(_ direction: Direction) -> String? {
        guard let workspace = current, let id = workspace.focused, let display = displays.first(where: { $0.id == focusedDisplay }) else { return nil }
        // Navigation remains available while fullscreen; compute ordinary layout temporarily.
        let full = workspace.fullscreen; workspace.fullscreen = nil
        let frames = layout(workspace, on: display); workspace.fullscreen = full
        guard let origin = frames[id] else { return nil }
        return frames.filter { key, rect in
            key != id && (direction.axis == .horizontal ? rect.midX-origin.midX : rect.midY-origin.midY) * direction.sign > 1
        }.min { a, b in
            func score(_ rect: Rect) -> Double {
                let primary = direction.axis == .horizontal ? abs(rect.midX-origin.midX) : abs(rect.midY-origin.midY)
                let cross = direction.axis == .horizontal ? abs(rect.midY-origin.midY) : abs(rect.midX-origin.midX)
                return primary + cross * 2
            }
            let lhs = score(a.value), rhs = score(b.value)
            return lhs == rhs ? a.key < b.key : lhs < rhs
        }?.key
    }
    public func move(_ direction: Direction) throws {
        guard let workspace = current, let id = workspace.focused else { throw TilerError.message("No focused window") }
        if workspace.floating || windows[id]?.floating == true {
            if direction.axis == .horizontal { windows[id]?.floatingFrame.x += direction.sign * 30 }
            else { windows[id]?.floatingFrame.y += direction.sign * 30 }
            return
        }
        guard let selected = workspace.selected, let node = workspace.tree.find(selected) else { return }
        workspace.automaticLayout = false
        var cursor = node
        while let parent = workspace.tree.parent(of: cursor.id) {
            if parent.axis == direction.axis, let index = parent.children.firstIndex(where: { $0.id == cursor.id }) {
                let next = index + Int(direction.sign)
                if parent.children.indices.contains(next) { parent.children.swapAt(index, next); return }
            }
            cursor = parent
        }
    }
    public func resize(_ direction: Direction, amount: Double) throws {
        guard let workspace = current, let id = workspace.focused else { throw TilerError.message("No focused window") }
        if workspace.floating || windows[id]?.floating == true {
            guard var window = windows[id] else { return }
            if direction.axis == .horizontal { window.floatingFrame.width = max(100, window.floatingFrame.width + direction.sign * amount) }
            else { window.floatingFrame.height = max(80, window.floatingFrame.height + direction.sign * amount) }
            windows[id] = window
            return
        }
        guard let selected = workspace.selected, var node = workspace.tree.find(selected) else { return }
        workspace.automaticLayout = false
        while let parent = workspace.tree.parent(of: node.id) {
            if parent.axis == direction.axis, parent.children.count > 1 {
                let delta = direction.sign * amount / 100
                node.weight = min(20, max(0.1, node.weight + delta)); return
            }
            node = parent
        }
    }
    public func sendWindow(to name: String) throws {
        guard let id = focusedWindow, let destination = workspaces[name], var window = windows[id] else { throw TilerError.message("No window or unknown workspace") }
        guard window.workspace != name else { return }
        removeWindow(id); window.workspace = name; windows[id] = window
        insert(Node(window: id), into: destination)
        destination.focused = id; destination.selected = destination.tree.leaf(id)?.id
    }
    public func moveWorkspace(to displayID: String) throws {
        guard displays.contains(where: { $0.id == displayID }), let source = focusedDisplay, let name = visible[source] else { throw TilerError.message("Unknown display") }
        if source == displayID { return }
        let other = visible[displayID]
        visible[displayID] = name; visible[source] = other
        workspaces[name]?.preferredDisplay = displayID
        if let other { workspaces[other]?.preferredDisplay = source }
        focusedDisplay = displayID
    }
}

public enum TilerError: Error, LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
