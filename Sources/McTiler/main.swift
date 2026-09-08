import AppKit
import TilerCore
import TilerIPC
import MacAdapter

final class AppDelegate: NSObject, NSApplicationDelegate {
    var instance: InstanceLock?
    var controller: Controller?
    var server: Server?
    var hotkeys = Hotkeys()
    var statusItem: NSStatusItem?
    var statusMenuItem: NSMenuItem?
    var timer: Timer?
    var mayTerminate = false
    var signals: [DispatchSourceSignal] = []
    var activeBindings: [String: String] = [:]
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            instance = try InstanceLock()
            let controller = try Controller(); self.controller = controller
            createMenu()
            controller.onStatus = { [weak self] title, note in
                self?.statusItem?.button?.title = title
                self?.statusItem?.button?.toolTip = note
                self?.statusMenuItem?.title = note.components(separatedBy: "\n").first ?? note
            }
            controller.onBindings = { [weak self] bindings in
                guard let self else { return }
                let old = self.activeBindings
                do { try self.hotkeys.register(bindings); self.activeBindings = bindings }
                catch { try? self.hotkeys.register(old); throw error }
            }
            controller.onQuit = { [weak self] in self?.mayTerminate = true; NSApp.terminate(nil) }
            hotkeys.perform = { [weak self] command in self?.run(command) }
            let server = Server(); self.server = server
            try server.start { [weak controller] arguments in
                guard let controller else { return Response(ok: false, message: "Shutting down") }
                return controller.queue.sync { controller.execute(arguments) }
            }
            controller.start(displays: MacDisplays.read(), startPaused: CommandLine.arguments.contains("--paused"))
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.controller?.schedule() }
            NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
            for name in [NSWorkspace.didWakeNotification, NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
                NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceChanged), name: name, object: nil)
            }
            for number in [SIGTERM, SIGINT] {
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
                source.setEventHandler { [weak self] in self?.run("quit") }; source.resume(); signals.append(source)
            }
        } catch { showError(error.localizedDescription); mayTerminate = true; NSApp.terminate(nil) }
    }
    func createMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength); statusItem = item
        item.button?.title = "McT …"
        let menu = NSMenu()
        let status = NSMenuItem(title: "Starting", action: nil, keyEquivalent: ""); menu.addItem(status); statusMenuItem = status
        menu.addItem(.separator())
        for (title, command) in [("Grant Accessibility Access…", "permission"), ("Reload Configuration", "reload"), ("Pause and Restore Windows", "pause"), ("Resume", "resume"), ("Recover Windows", "recover"), ("Quit McTiler", "quit")] {
            let entry = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = command; menu.addItem(entry)
        }
        item.menu = menu
    }
    @objc func menuAction(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        if command == "permission" { MacWindowAdapter.requestPermission(); return }
        run(command)
    }
    func run(_ command: String) {
        guard let controller else { return }
        controller.queue.async {
            let response = controller.execute(command.split(separator: " ").map(String.init))
            if !response.ok { NSLog("McTiler: %@", response.message) }
        }
    }
    @objc func displaysChanged() { controller?.schedule(displays: MacDisplays.read()) }
    @objc func workspaceChanged() { controller?.schedule(displays: MacDisplays.read()) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if mayTerminate { return .terminateNow }
        run("quit"); return .terminateCancel
    }
    func showError(_ message: String) {
        let alert = NSAlert(); alert.messageText = "McTiler"; alert.informativeText = message; alert.runModal()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
