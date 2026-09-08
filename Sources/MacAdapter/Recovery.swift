import Foundation
import TilerCore

public struct RecoveryEntry: Codable {
    public var id: String
    public var pid: Int32
    public var launched: Date?
    public var title: String
    public var original: Rect
    public var previous: Rect
    public var target: Rect
}

public final class RecoveryJournal {
    public private(set) var entries: [String: RecoveryEntry] = [:]
    public let url: URL
    public init(url: URL? = nil) throws {
        self.url = url ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/McTiler/recovery.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            entries = try JSONDecoder().decode([String: RecoveryEntry].self, from: Data(contentsOf: self.url))
        }
    }
    public func record(id: String, pid: Int32, launched: Date?, title: String, current: Rect, target: Rect) throws {
        let original = entries[id]?.original ?? current
        let entry = RecoveryEntry(id: id, pid: pid, launched: launched, title: title, original: original, previous: current, target: target)
        var next = entries; next[id] = entry
        try save(next); entries = next
    }
    public func remove(_ ids: Set<String>) throws {
        let next = entries.filter { !ids.contains($0.key) }
        try save(next); entries = next
    }
    private func save(_ next: [String: RecoveryEntry]) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(next)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        // Ensure recovery intent reaches disk before mutating a window.
        let file = try FileHandle(forWritingTo: url); try file.synchronize(); try file.close()
    }
}
