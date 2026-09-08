import Foundation

public struct Rect: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var valid: Bool { [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
    public func inset(_ n: Double) -> Rect {
        Rect(x + n, y + n, max(1, width - 2*n), max(1, height - 2*n))
    }
    public func intersects(_ other: Rect) -> Bool {
        x < other.maxX && maxX > other.x && y < other.maxY && maxY > other.y
    }
    public func approximately(_ other: Rect, tolerance: Double = 3) -> Bool {
        abs(x-other.x) <= tolerance && abs(y-other.y) <= tolerance &&
        abs(width-other.width) <= tolerance && abs(height-other.height) <= tolerance
    }
    public func clamped(to area: Rect) -> Rect {
        let w = min(width, area.width), h = min(height, area.height)
        return Rect(min(max(x, area.x), area.maxX-w), min(max(y, area.y), area.maxY-h), w, h)
    }
}

public struct Display: Codable, Equatable {
    public var id: String
    public var frame: Rect
    public var usable: Rect
    public var fullscreen: Rect
    public init(id: String, frame: Rect, usable: Rect, fullscreen: Rect) {
        self.id = id; self.frame = frame; self.usable = usable; self.fullscreen = fullscreen
    }
}

public enum Axis: String, Codable { case horizontal, vertical }
public enum Direction: String, Codable {
    case left, right, up, down
    public var axis: Axis { self == .left || self == .right ? .horizontal : .vertical }
    public var sign: Double { self == .left || self == .up ? -1 : 1 }
}

public enum Parking {
    public static func isHidden(_ window: Rect, on display: Display, displays: [Display]) -> Bool {
        guard window.valid, !displays.contains(where: { $0.id != display.id && window.intersects($0.frame) }) else { return false }
        let overlapX = max(0, min(window.maxX, display.frame.maxX) - max(window.x, display.frame.x))
        // AppKit may clamp Y to keep a titlebar reachable. A <=2 point vertical
        // edge strip is still parked, provided it does not enter another screen.
        return overlapX <= 2 && (abs(window.x-display.frame.maxX) <= 2 || abs(window.maxX-display.frame.x) <= 2)
    }
    // AX clamps windows to leave a small visible strip. Reject corners that would expose
    // the parked rectangle on a neighbouring screen; do not assume monitor arrangement.
    public static func frame(for window: Rect, on display: Display, displays: [Display]) -> Rect? {
        let candidates = [
            Rect(display.frame.maxX - 1, display.frame.maxY - 1, window.width, window.height),
            Rect(display.frame.x - window.width + 1, display.frame.maxY - 1, window.width, window.height)
        ]
        return candidates.first { candidate in
            !displays.contains { $0.id != display.id && candidate.intersects($0.frame) }
        }
    }
}
