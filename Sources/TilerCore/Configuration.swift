import Foundation

public struct AppRule: Equatable {
    public var bundle: String
    public var floating: Bool?
    public var workspace: String?
    public var ignore = false
}

public struct Configuration {
    public var innerGap = 12.0
    public var outerGap = 8.0
    public var suppressDock = false
    public var focusFollowsMouse = true
    public var bindings: [String: String] = [:]
    public var rules: [AppRule] = []
    public var assignments: [String: String] = [:]
    public static var path: String { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/mctiler/config.toml").path }
    public static var defaults: Configuration {
        var config = Configuration()
        for direction in ["left", "right", "up", "down"] {
            config.bindings["alt-\(direction)"] = "focus \(direction)"
            config.bindings["alt-shift-\(direction)"] = "move \(direction)"
            config.bindings["alt-ctrl-\(direction)"] = "resize \(direction) 10"
        }
        for n in 1...9 {
            config.bindings["alt-\(n)"] = "workspace \(n)"
            config.bindings["alt-shift-\(n)"] = "send \(n)"
        }
        config.bindings.merge([
            "alt-shift-escape": "fullscreen", "alt-ctrl-space": "workspace-floating",
            "alt-ctrl-f": "fullscreen", "alt-ctrl-h": "split horizontal", "alt-ctrl-v": "split vertical",
            "alt-ctrl-p": "select parent", "alt-ctrl-c": "select child",
            "alt-ctrl-r": "reload", "alt-ctrl-escape": "pause"
        ]) { _, new in new }
        return config
    }
    public static func load(path: String = Configuration.path) throws -> Configuration {
        guard FileManager.default.fileExists(atPath: path) else { return .defaults }
        return try parse(String(contentsOfFile: path, encoding: .utf8))
    }
    // Deliberately a documented TOML subset: scalar root options, string tables and
    // [[rules]]. Unsupported syntax is rejected rather than partially interpreted.
    public static func parse(_ text: String) throws -> Configuration {
        var result = Configuration.defaults, section = "", seen = Set<String>(), bindingsSeen = false
        func string(_ value: String) throws -> String {
            guard value.first == "\"", value.last == "\"", let data = value.data(using: .utf8), let decoded = try? JSONDecoder().decode(String.self, from: data) else {
                throw TilerError.message("Expected a double-quoted string")
            }
            return decoded
        }
        func boolean(_ value: String) throws -> Bool {
            guard value == "true" || value == "false" else { throw TilerError.message("Expected true or false") }
            return value == "true"
        }
        for (offset, raw) in text.components(separatedBy: .newlines).enumerated() {
            do {
                var quoted = false, escaped = false, line = ""
                for char in raw {
                    if char == "#" && !quoted { break }
                    line.append(char)
                    if escaped { escaped = false; continue }
                    if char == "\\" && quoted { escaped = true; continue }
                    if char == "\"" { quoted.toggle() }
                }
                line = line.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                if line == "[[rules]]" { section = "rules"; result.rules.append(AppRule(bundle: "")); continue }
                if line.hasPrefix("[") {
                    guard ["[bindings]", "[workspaces]"].contains(line), !seen.contains(line) else { throw TilerError.message("Unsupported or duplicate table \(line)") }
                    seen.insert(line); section = String(line.dropFirst().dropLast())
                    if section == "bindings", !bindingsSeen { result.bindings = [:]; bindingsSeen = true }
                    continue
                }
                guard let equals = line.firstIndex(of: "=") else { throw TilerError.message("Expected key = value") }
                let rawKey = line[..<equals].trimmingCharacters(in: .whitespaces)
                let key = rawKey.hasPrefix("\"") ? try string(rawKey) : rawKey
                guard !key.isEmpty else { throw TilerError.message("Empty key") }
                let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                let identity = "\(section).\(section == "rules" ? result.rules.count : 0).\(key)"
                guard seen.insert(identity).inserted else { throw TilerError.message("Duplicate key \(key)") }
                switch section {
                case "":
                    switch key {
                    case "inner-gap", "outer-gap":
                        guard let n = Double(value), n.isFinite, (0...200).contains(n) else { throw TilerError.message("Gap must be between 0 and 200") }
                        if key == "inner-gap" { result.innerGap = n } else { result.outerGap = n }
                    case "focus-follows-mouse": result.focusFollowsMouse = try boolean(value)
                    case "experimental-suppress-dock": result.suppressDock = try boolean(value)
                    default: throw TilerError.message("Unknown option \(key)")
                    }
                case "bindings":
                    _ = try Hotkey.parse(key)
                    let command = try string(value)
                    _ = try Command.parse(command.split(separator: " ").map(String.init))
                    result.bindings[key] = command
                case "workspaces":
                    guard (1...9).map(String.init).contains(key) else { throw TilerError.message("Workspace must be 1–9") }
                    result.assignments[key] = try string(value)
                case "rules":
                    let index = result.rules.count-1
                    switch key {
                    case "bundle": result.rules[index].bundle = try string(value)
                    case "floating": result.rules[index].floating = try boolean(value)
                    case "ignore": result.rules[index].ignore = try boolean(value)
                    case "workspace":
                        let name = try string(value)
                        guard (1...9).map(String.init).contains(name) else { throw TilerError.message("Workspace must be 1–9") }
                        result.rules[index].workspace = name
                    default: throw TilerError.message("Unknown rule key \(key)")
                    }
                default: throw TilerError.message("Unknown table")
                }
            } catch { throw TilerError.message("Config line \(offset+1): \(error.localizedDescription)") }
        }
        guard result.rules.allSatisfy({ !$0.bundle.isEmpty }) else { throw TilerError.message("Every rule needs a bundle ID") }
        let hotkeys = try result.bindings.keys.map(Hotkey.parse)
        guard Set(hotkeys).count == hotkeys.count else { throw TilerError.message("Duplicate normalized hotkey") }
        return result
    }
}

public struct Hotkey: Hashable {
    public let code: UInt32
    public let modifiers: UInt32
    // Carbon virtual key codes; keys refer to physical US positions, documented in config.
    public static let keys: [String: UInt32] = [
        "a":0, "s":1, "d":2, "f":3, "h":4, "g":5, "z":6, "x":7, "c":8, "v":9,
        "b":11, "q":12, "w":13, "e":14, "r":15, "y":16, "t":17, "1":18, "2":19,
        "3":20, "4":21, "6":22, "5":23, "9":25, "7":26, "8":28, "0":29,
        "o":31, "u":32, "i":34, "p":35, "enter":36, "l":37, "j":38, "k":40,
        "n":45, "m":46, "tab":48, "space":49, "escape":53, "left":123, "right":124,
        "down":125, "up":126
    ]
    public static func parse(_ value: String) throws -> Hotkey {
        let parts = value.lowercased().split(separator: "-").map(String.init)
        guard let last = parts.last, let code = keys[last], parts.count > 1 else { throw TilerError.message("Invalid hotkey \(value)") }
        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            let bit: UInt32
            switch part { case "cmd": bit = 256; case "shift": bit = 512; case "alt": bit = 2048; case "ctrl": bit = 4096; default: throw TilerError.message("Invalid modifier \(part)") }
            guard modifiers & bit == 0 else { throw TilerError.message("Repeated modifier in \(value)") }
            modifiers |= bit
        }
        return Hotkey(code: code, modifiers: modifiers)
    }
}
