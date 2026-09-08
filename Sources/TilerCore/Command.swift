import Foundation

public enum Command {
    case focus(Direction), move(Direction), resize(Direction, Double), split(Axis), select(Bool)
    case workspace(String), send(String), moveWorkspace(String), focusDisplay(String)
    case floating, workspaceFloating, fullscreen, reload, pause, resume, status, recover, quit
    public static func parse(_ args: [String]) throws -> Command {
        guard let first = args.first else { throw TilerError.message("Missing command") }
        let tail = Array(args.dropFirst())
        switch (first, tail.count) {
        case ("focus", 1), ("move", 1):
            guard let direction = Direction(rawValue: tail[0]) else { throw TilerError.message("Expected left, right, up, or down") }
            return first == "focus" ? .focus(direction) : .move(direction)
        case ("resize", 2):
            guard let direction = Direction(rawValue: tail[0]), let amount = Double(tail[1]), amount.isFinite, amount > 0, amount <= 500 else { throw TilerError.message("resize DIRECTION AMOUNT (1–500)") }
            return .resize(direction, amount)
        case ("split", 1):
            guard let axis = Axis(rawValue: tail[0]) else { throw TilerError.message("Expected horizontal or vertical") }; return .split(axis)
        case ("select", 1):
            guard ["parent", "child"].contains(tail[0]) else { throw TilerError.message("Expected parent or child") }; return .select(tail[0] == "parent")
        case ("workspace", 1), ("send", 1):
            guard (1...9).map(String.init).contains(tail[0]) else { throw TilerError.message("Workspace must be 1–9") }
            return first == "workspace" ? .workspace(tail[0]) : .send(tail[0])
        case ("move-workspace", 1): return .moveWorkspace(tail[0])
        case ("focus-display", 1): return .focusDisplay(tail[0])
        case ("floating", 0): return .floating
        case ("workspace-floating", 0): return .workspaceFloating
        case ("fullscreen", 0): return .fullscreen
        case ("reload", 0): return .reload
        case ("pause", 0): return .pause
        case ("resume", 0): return .resume
        case ("status", 0): return .status
        case ("recover", 0): return .recover
        case ("quit", 0): return .quit
        default: throw TilerError.message("Unknown command or incorrect arguments: \(args.joined(separator: " "))")
        }
    }
    public func apply(to desktop: Desktop) throws {
        switch self {
        case .focus(let direction): if let next = desktop.neighbor(direction) { desktop.focus(next) }
        case .move(let direction): try desktop.move(direction)
        case .resize(let direction, let amount): try desktop.resize(direction, amount: amount)
        case .split(let axis): try desktop.split(axis)
        case .select(let parent): try desktop.select(parent)
        case .workspace(let name): try desktop.switchWorkspace(name)
        case .send(let name): try desktop.sendWindow(to: name)
        case .moveWorkspace(let id): try desktop.moveWorkspace(to: id)
        case .focusDisplay(let id):
            guard desktop.displays.contains(where: { $0.id == id }) else { throw TilerError.message("Unknown display") }; desktop.focusedDisplay = id
        case .floating: try desktop.toggleFloating()
        case .workspaceFloating: try desktop.toggleWorkspaceFloating()
        case .fullscreen:
            guard let workspace = desktop.current, let id = desktop.focusedWindow else { throw TilerError.message("No focused window") }
            workspace.fullscreen = workspace.fullscreen == id ? nil : id
        default: throw TilerError.message("Command requires the running app")
        }
    }
    public static let help = """
    mctiler status | reload | pause | resume | recover | quit
    mctiler focus|move left|right|up|down
    mctiler resize left|right|up|down AMOUNT
    mctiler split horizontal|vertical
    mctiler select parent|child
    mctiler workspace|send 1…9
    mctiler focus-display|move-workspace DISPLAY_ID
    mctiler floating | workspace-floating | fullscreen
    mctiler check-config [PATH]
    mctiler check-hotkeys (pause management first)
    mctiler recover --standalone
    """
}
