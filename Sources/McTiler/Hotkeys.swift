import AppKit
import Carbon
import TilerCore

final class Hotkeys {
    private var registrations: [EventHotKeyRef] = []
    private var commands: [UInt32: String] = [:]
    private var handler: EventHandlerRef?
    var perform: ((String) -> Void)?
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue()
            if let command = owner.commands[id.id] { owner.perform?(command) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ bindings: [String: String]) throws {
        // Remove existing bindings first; caller restores the prior set on failure.
        clear()
        do {
            for (offset, pair) in bindings.sorted(by: { $0.key < $1.key }).enumerated() {
                let key = try Hotkey.parse(pair.key), id = UInt32(offset+1)
                var reference: EventHotKeyRef?
                let result = RegisterEventHotKey(key.code, key.modifiers, EventHotKeyID(signature: 0x4D43544C, id: id), GetApplicationEventTarget(), 0, &reference)
                guard result == noErr, let reference else { throw TilerError.message("Cannot register \(pair.key) (macOS error \(result)); another app may own it") }
                registrations.append(reference); commands[id] = pair.value
            }
        } catch { clear(); throw error }
    }
    func clear() { for ref in registrations { UnregisterEventHotKey(ref) }; registrations = []; commands = [:] }
    deinit { clear(); if let handler { RemoveEventHandler(handler) } }
}
