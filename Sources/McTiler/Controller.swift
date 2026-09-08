import AppKit
import TilerCore
import TilerIPC
import MacAdapter

final class Controller {
    let queue = DispatchQueue(label: "mctiler.windows", qos: .userInitiated)
    let desktop = Desktop()
    let adapter: MacWindowAdapter
    let reconciler: Reconciler
    var config: Configuration
    var paused = true
    var statusNote = "Starting"
    var onStatus: ((String, String) -> Void)?
    var onBindings: (([String: String]) throws -> Void)?
    var onQuit: (() -> Void)?
    private var pending = false // main-thread event coalescing
    private var focusGrace = Date.distantPast
    private var lastSnapshot = WindowSnapshot(windows: [])
    init() throws {
        config = try Configuration.load()
        adapter = MacWindowAdapter(journal: try RecoveryJournal())
        reconciler = Reconciler(desktop: desktop, adapter: adapter, configuration: config)
        adapter.onChange = { [weak self] in DispatchQueue.main.async { self?.schedule() } }
    }
    func start(displays: [Display], startPaused: Bool = false) {
        queue.async {
            self.desktop.updateDisplays(displays)
            self.applyConfiguration()
            if !MacWindowAdapter.trusted {
                self.statusNote = "Grant Accessibility access, then choose Resume"
            } else {
                let recovered = self.adapter.recover(displays: displays)
                self.paused = startPaused || recovered.remaining > 0
                self.statusNote = recovered.remaining > 0 ? "\(recovered.remaining) recovery entries need attention; choose Recover" : (startPaused ? "Started paused; choose Resume to manage windows" : "Running")
                if !self.paused {
                    do { try DispatchQueue.main.sync { try self.onBindings?(self.config.bindings) }; self.reconcile() }
                    catch { self.paused = true; self.statusNote = error.localizedDescription }
                }
            }
            self.publish()
        }
    }
    func schedule(displays: [Display]? = nil) {
        if let displays { queue.async { self.desktop.updateDisplays(displays); self.reconciler.resetFailures() } }
        guard !pending else { return }; pending = true
        DispatchQueue.main.asyncAfter(deadline: .now()+0.12) {
            self.queue.async {
                if !self.paused { self.reconcile() }
                self.publish()
                DispatchQueue.main.async { self.pending = false }
            }
        }
    }
    func execute(_ args: [String]) -> Response {
        do {
            let command = try Command.parse(args)
            switch command {
            case .status: return Response(message: statusJSON())
            case .pause:
                paused = true
                try DispatchQueue.main.sync { try onBindings?([:]) }
                let result = adapter.recover(displays: desktop.displays)
                statusNote = "Paused; restored \(result.restored), unresolved \(result.remaining)"
                // AX objects are retained, but all layout targets need fresh validation.
                reconciler.resetFailures()
            case .recover:
                paused = true
                try DispatchQueue.main.sync { try onBindings?([:]) }
                let result = adapter.recover(displays: desktop.displays)
                statusNote = "Recovery: restored \(result.restored), unresolved \(result.remaining). Paused."
                reconciler.resetFailures()
            case .resume:
                guard MacWindowAdapter.trusted else { throw TilerError.message("Accessibility permission is required. Enable McTiler in System Settings → Privacy & Security → Accessibility.") }
                if !adapter.journal.entries.isEmpty && paused {
                    let result = adapter.recover(displays: desktop.displays)
                    guard result.remaining == 0 else { throw TilerError.message("Recovery has \(result.remaining) unresolved windows; keep them open and retry Recover") }
                }
                try DispatchQueue.main.sync { try onBindings?(config.bindings) }
                paused = false; statusNote = "Running"; reconciler.resetFailures(); reconcile()
            case .reload:
                let next = try Configuration.load()
                // Registration happens on main; the window queue never blocks main via execute.
                try DispatchQueue.main.sync { try onBindings?(paused ? [:] : next.bindings) }
                config = next; applyConfiguration(); reconciler.resetFailures()
                statusNote = "Configuration reloaded (application rules apply to newly discovered windows)"
                if !paused { reconcile() }
            case .quit:
                paused = true
                try DispatchQueue.main.sync { try onBindings?([:]) }
                let result = adapter.recover(displays: desktop.displays)
                guard result.remaining == 0 else { throw TilerError.message("\(result.remaining) windows could not be restored. McTiler remains paused; use Recover before quitting.") }
                statusNote = "Quitting McTiler"
                DispatchQueue.main.asyncAfter(deadline: .now()+0.2) { self.onQuit?() }
            default:
                guard !paused else { throw TilerError.message("McTiler is paused; use resume") }
                guard MacWindowAdapter.trusted else { paused = true; throw TilerError.message("Accessibility permission was revoked") }
                let snapshot = adapter.snapshot()
                reconciler.ingest(snapshot, allowFocus: Date() > focusGrace); lastSnapshot = snapshot
                try command.apply(to: desktop)
                focusGrace = Date().addingTimeInterval(0.6)
                applyLayout(snapshot)
                if !paused, let focused = desktop.focusedWindow { _ = adapter.focus(focused) }
            }
            publish()
            return Response(message: statusNote)
        } catch { statusNote = error.localizedDescription; publish(); return Response(ok: false, message: statusNote) }
    }
    private func applyConfiguration() {
        desktop.innerGap = config.innerGap; desktop.outerGap = config.outerGap
        reconciler.configuration = config
        for (name, id) in config.assignments { desktop.workspaces[name]?.preferredDisplay = id }
        // Assign hidden workspaces immediately where possible, without duplicate visibility.
        var assigned = Set<String>()
        for (name, id) in config.assignments.sorted(by: { $0.key < $1.key }) where desktop.displays.contains(where: { $0.id == id }) && assigned.insert(id).inserted {
            if let source = desktop.visible.first(where: { $0.value == name })?.key, source != id {
                let other = desktop.visible[id]; desktop.visible[source] = other
            }
            desktop.visible[id] = name
        }
    }
    private func reconcile() {
        guard MacWindowAdapter.trusted else {
            paused = true; try? DispatchQueue.main.sync { try onBindings?([:]) }
            statusNote = "Accessibility access lost; restore permission and choose Recover, then Resume"; return
        }
        let snapshot = adapter.snapshot(); lastSnapshot = snapshot
        reconciler.ingest(snapshot, allowFocus: Date() > focusGrace)
        applyLayout(snapshot)
    }
    private func applyLayout(_ snapshot: WindowSnapshot) {
        guard !desktop.displays.isEmpty else { return }
        let actual = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.id, $0.frame) })
        // Native fullscreen is not part of our workspace model. Avoid moving windows
        // behind an app's native Space when it is foreground.
        if let id = snapshot.focused, desktop.windows[id]?.nativeFullscreen == true { statusNote = "Native fullscreen app active; layout suspended until it returns"; return }
        var targets: [String: Rect] = [:], parked = Set<String>()
        adapter.parkingDisplays = [:]; adapter.displays = desktop.displays
        for (displayID, name) in desktop.visible {
            guard let display = desktop.displays.first(where: { $0.id == displayID }), let workspace = desktop.workspaces[name] else { continue }
            targets.merge(desktop.layout(workspace, on: display)) { _, new in new }
        }
        for window in desktop.windows.values where targets[window.id] == nil && !window.minimized && !window.nativeFullscreen {
            guard let frame = actual[window.id] else { continue }
            let display = desktop.displays.first { $0.id == desktop.workspaces[window.workspace]?.preferredDisplay } ?? desktop.displays[0]
            adapter.parkingDisplays[window.id] = display
            if Parking.isHidden(frame, on: display, displays: desktop.displays) {
                targets[window.id] = frame; parked.insert(window.id); continue
            }
            guard let parking = Parking.frame(for: frame, on: display, displays: desktop.displays) else {
                pauseForFailure("Display arrangement has no safe parking corner"); return
            }
            targets[window.id] = parking; parked.insert(window.id)
        }
        let failed = Set(reconciler.apply(targets, actual: actual))
        if !failed.isDisjoint(with: parked) { pauseForFailure("An application rejected workspace parking"); return }
        if !failed.isEmpty { statusNote = adapter.lastError ?? "\(failed.count) windows have constrained geometry" }
        else { statusNote = "Running" }
    }
    private func pauseForFailure(_ reason: String) {
        paused = true
        try? DispatchQueue.main.sync { try onBindings?([:]) }
        let recovery = adapter.recover(displays: desktop.displays)
        statusNote = "\(reason). Paused; \(recovery.remaining) unresolved recovery entries."
        reconciler.resetFailures()
    }
    private func statusJSON() -> String {
        let object: [String: Any] = [
            "paused": paused, "message": statusNote, "focusedWorkspace": desktop.current?.name ?? "",
            "focusedWindow": desktop.focusedWindow ?? "", "windows": desktop.windows.count,
            "visibleWorkspaces": desktop.visible,
            "displays": desktop.displays.map { ["id": $0.id, "width": String($0.frame.width), "height": String($0.frame.height)] },
            "dockSuppression": ["requested": config.suppressDock, "available": DockSuppression.available, "explanation": DockSuppression.explanation],
            "recoveryEntries": adapter.journal.entries.count
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) else { return statusNote }
        return text
    }
    private func publish() {
        let title = paused ? "McT ‖" : "McT \(desktop.current?.name ?? "–")\(desktop.current?.floating == true ? " F" : " T")\(desktop.current?.fullscreen != nil ? " ▣" : "")"
        let note = statusNote + (config.suppressDock ? "\n" + DockSuppression.explanation : "")
        DispatchQueue.main.async { self.onStatus?(title, note) }
    }
}
