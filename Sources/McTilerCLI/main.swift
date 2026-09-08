import AppKit
import Carbon
import TilerCore
import TilerIPC
import MacAdapter

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] {
        print(Command.help)
    } else if arguments == ["check-hotkeys"] {
        let config = try Configuration.load()
        var registered: [EventHotKeyRef] = [], failures: [String] = []
        defer { for reference in registered { UnregisterEventHotKey(reference) } }
        for (index, name) in config.bindings.keys.sorted().enumerated() {
            let key = try Hotkey.parse(name)
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(key.code, key.modifiers, EventHotKeyID(signature: 0x4D435443, id: UInt32(index+1)), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { registered.append(reference) }
            else { failures.append("\(name): macOS error \(result)") }
        }
        guard failures.isEmpty else { throw TilerError.message("Unavailable hotkeys (pause McTiler and other managers first):\n" + failures.joined(separator: "\n")) }
        print("All \(registered.count) configured hotkeys can be registered; temporary registrations released on exit")
    } else if arguments.first == "check-config" {
        guard arguments.count <= 2 else { throw TilerError.message("check-config [PATH]") }
        let path = arguments.count == 2 ? arguments[1] : Configuration.path
        let config = try Configuration.load(path: path)
        print("Configuration valid: \(config.bindings.count) bindings, \(config.rules.count) rules")
        if config.suppressDock { print(DockSuppression.explanation) }
    } else if arguments == ["recover", "--standalone"] {
        let lock = try InstanceLock()
        defer { withExtendedLifetime(lock) {} }
        guard MacWindowAdapter.trusted else { throw TilerError.message("Standalone recovery needs Accessibility permission for this executable or its launching terminal. Alternatively relaunch McTiler.app for recovery.") }
        let adapter = MacWindowAdapter(journal: try RecoveryJournal())
        let result = adapter.recover(displays: MacDisplays.read())
        print("Restored \(result.restored) windows; \(result.remaining) unresolved entries")
        if result.remaining > 0 { exit(1) }
    } else {
        _ = try Command.parse(arguments)
        let response = try Client.send(arguments)
        print(response.message)
        if !response.ok { exit(1) }
    }
} catch {
    FileHandle.standardError.write(Data("mctiler: \(error.localizedDescription)\n".utf8)); exit(1)
}
