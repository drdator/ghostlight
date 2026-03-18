import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var panels: [GhostlightPanel] = []
    private var hotkeyManagers: [HotkeyManager] = []
    private var statusItem: NSStatusItem?
    var ghosttyApp: GhosttyApp!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        ghosttyApp = GhosttyApp()

        let baseConfig = GhostlightConfig.load()
        createPanels(from: baseConfig)
        setupStatusItem()
    }

    private func createPanels(from baseConfig: GhostlightConfig) {
        if baseConfig.profiles.isEmpty {
            // No profiles — single default panel
            let panel = GhostlightPanel(ghosttyApp: ghosttyApp, config: baseConfig)
            panels.append(panel)
            registerHotkey(for: baseConfig, panel: panel)
        } else {
            // One panel per profile
            for profile in baseConfig.profiles {
                let resolved = baseConfig.resolved(with: profile)
                let panel = GhostlightPanel(
                    ghosttyApp: ghosttyApp,
                    config: resolved,
                    profileName: profile.name
                )
                panels.append(panel)
                registerHotkey(for: resolved, panel: panel)
            }
        }
    }

    private func registerHotkey(for config: GhostlightConfig, panel: GhostlightPanel) {
        let hotkey = config.parsedHotkey()
        let manager = HotkeyManager(
            keyCode: hotkey.keyCode,
            modifiers: hotkey.modifiers
        ) { [weak panel] in
            panel?.toggle()
        }
        hotkeyManagers.append(manager)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "GL"
            button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        }

        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        for panel in panels {
            let config = panel.currentConfig
            let label = panel.profileName ?? "Terminal"
            let title = "\(label) (\(config.hotkeyDisplayString()))"
            let item = NSMenuItem(title: title, action: #selector(togglePanel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = panel
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
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

        return menu
    }

    @objc func togglePanel(_ sender: NSMenuItem) {
        guard let panel = sender.representedObject as? GhostlightPanel else { return }
        panel.toggle()
    }

    @objc func reloadConfig() {
        // Tear down existing panels and hotkeys
        for panel in panels { panel.destroySurface() }
        panels.removeAll()
        hotkeyManagers.removeAll()

        // Recreate from fresh config
        let baseConfig = GhostlightConfig.load()
        createPanels(from: baseConfig)
        statusItem?.menu = buildMenu()
    }

    @objc func quit() {
        for panel in panels { panel.destroySurface() }
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        for panel in panels { panel.destroySurface() }
    }
}
