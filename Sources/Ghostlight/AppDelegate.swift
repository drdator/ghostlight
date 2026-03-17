import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: GhostlightPanel!
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private var toggleMenuItem: NSMenuItem?
    var ghosttyApp: GhosttyApp!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        ghosttyApp = GhosttyApp()

        panel = GhostlightPanel(ghosttyApp: ghosttyApp)

        setupStatusItem()
        applyHotkeyConfig(ghosttyApp.config_)

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
        let toggleItem = NSMenuItem(title: "", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(toggleItem)
        toggleMenuItem = toggleItem
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
        updateToggleMenuItemTitle(with: ghosttyApp.config_)
    }

    private func applyHotkeyConfig(_ config: GhostlightConfig) {
        let hotkey = config.parsedHotkey()
        hotkeyManager = HotkeyManager(
            keyCode: hotkey.keyCode,
            modifiers: hotkey.modifiers
        ) { [weak self] in
            self?.togglePanel()
        }
        updateToggleMenuItemTitle(with: config)
    }

    private func updateToggleMenuItemTitle(with config: GhostlightConfig) {
        toggleMenuItem?.title = "Toggle Terminal (\(config.hotkeyDisplayString()))"
    }

    private func reloadHotkeyConfigIfNeeded() {
        let config = GhostlightConfig.load()
        guard config.hotkey != ghosttyApp.config_.hotkey else { return }
        ghosttyApp.config_ = config
        applyHotkeyConfig(config)
    }

    @objc func togglePanel() {
        reloadHotkeyConfigIfNeeded()
        panel.toggle()
    }

    @objc func reloadConfig() {
        let config = GhostlightConfig.load()
        ghosttyApp.config_ = config
        applyHotkeyConfig(config)
        panel.applyConfig(config, recreateSurface: true)
    }

    @objc func quit() {
        panel.destroySurface()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        panel?.destroySurface()
    }
}
