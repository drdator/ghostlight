import AppKit
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: GhostlightPanel!
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    var ghosttyApp: GhosttyApp!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        ghosttyApp = GhosttyApp()

        panel = GhostlightPanel(ghosttyApp: ghosttyApp)

        setupStatusItem()

        // Global hotkey: Option+Space
        hotkeyManager = HotkeyManager(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey)
        ) { [weak self] in
            self?.togglePanel()
        }

        ghosttyApp.onSurfaceClosed = { [weak self] in
            self?.panel.hide()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "GL"
            button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Toggle Terminal (Opt+Space)",
            action: #selector(togglePanel),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "Reload Config",
            action: #selector(reloadConfig),
            keyEquivalent: "r"
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Ghostlight",
            action: #selector(quit),
            keyEquivalent: "q"
        ))
        statusItem?.menu = menu
    }

    @objc func togglePanel() {
        panel.toggle()
    }

    @objc func reloadConfig() {
        ghosttyApp.config_ = GhostlightConfig.load()
        panel.applyConfig(ghosttyApp.config_, recreateSurface: true)
    }

    @objc func quit() {
        panel.destroySurface()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        panel?.destroySurface()
    }
}
