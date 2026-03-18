import AppKit
import CLibGhostty
import QuartzCore

class GhosttyApp {
    var app: ghostty_app_t?
    var config: ghostty_config_t?
    var backgroundColor: NSColor = NSColor(white: 0.12, alpha: 1.0)
    private(set) var terminalViews = NSHashTable<TerminalView>.weakObjects()
    private var tickTimer: Timer?

    init() {
        config = ghostty_config_new()
        guard let config else { return }

        ghostty_config_load_default_files(config)
        ghostty_config_finalize(config)

        // Read the background color from the finalized config
        var bgColor = ghostty_config_color_s(r: 0, g: 0, b: 0)
        let key = "background"
        if ghostty_config_get(config, &bgColor, key, UInt(key.utf8.count)) {
            backgroundColor = NSColor(
                red: CGFloat(bgColor.r) / 255.0,
                green: CGFloat(bgColor.g) / 255.0,
                blue: CGFloat(bgColor.b) / 255.0,
                alpha: 1.0
            )
        }

        var rt = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: ghostlightWakeup,
            action_cb: ghostlightAction,
            read_clipboard_cb: ghostlightReadClipboard,
            confirm_read_clipboard_cb: ghostlightConfirmReadClipboard,
            write_clipboard_cb: ghostlightWriteClipboard,
            close_surface_cb: ghostlightCloseSurface
        )

        app = ghostty_app_new(&rt, config)
        guard app != nil else {
            fputs("ghostlight: failed to create ghostty app\n", stderr)
            return
        }

        // Tick at display refresh rate
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(tickTimer!, forMode: .common)
    }

    func registerTerminalView(_ view: TerminalView) {
        terminalViews.add(view)
    }

    func unregisterTerminalView(_ view: TerminalView) {
        terminalViews.remove(view)
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)

        // Only draw surfaces in visible windows — prewarmed surfaces in
        // hidden panels have no valid Metal drawable.
        for view in terminalViews.allObjects {
            if let surface = view.surface, view.window?.isVisible == true {
                ghostty_surface_draw(surface)
                view.layer?.setNeedsDisplay()
            }
        }
        CATransaction.flush()
    }

    deinit {
        tickTimer?.invalidate()
        if let app { ghostty_app_free(app) }
        if let config { ghostty_config_free(config) }
    }
}

// MARK: - Runtime Callbacks (C-compatible free functions)

// App-level callbacks receive runtime userdata (GhosttyApp)

private func ghostlightWakeup(_ userdata: UnsafeMutableRawPointer?) {
    guard let userdata else { return }
    let app = Unmanaged<GhosttyApp>.fromOpaque(userdata).takeUnretainedValue()
    DispatchQueue.main.async { app.tick() }
}

private func ghostlightAction(
    _ appHandle: UnsafeMutableRawPointer?,
    _ target: ghostty_target_s,
    _ action: ghostty_action_s
) -> Bool {
    guard let appHandle else { return false }
    guard let userdata = ghostty_app_userdata(appHandle) else { return false }
    let app = Unmanaged<GhosttyApp>.fromOpaque(userdata).takeUnretainedValue()

    switch action.tag {
    case GHOSTTY_ACTION_SET_TITLE:
        return true

    case GHOSTTY_ACTION_MOUSE_SHAPE:
        let shape = action.action.mouse_shape
        DispatchQueue.main.async {
            switch shape {
            case GHOSTTY_MOUSE_SHAPE_TEXT: NSCursor.iBeam.set()
            case GHOSTTY_MOUSE_SHAPE_POINTER: NSCursor.pointingHand.set()
            case GHOSTTY_MOUSE_SHAPE_DEFAULT: NSCursor.arrow.set()
            case GHOSTTY_MOUSE_SHAPE_CROSSHAIR: NSCursor.crosshair.set()
            default: NSCursor.arrow.set()
            }
        }
        return true

    case GHOSTTY_ACTION_MOUSE_VISIBILITY:
        let vis = action.action.mouse_visibility
        DispatchQueue.main.async {
            if vis == GHOSTTY_MOUSE_VISIBLE {
                NSCursor.unhide()
            } else {
                NSCursor.hide()
            }
        }
        return true

    case GHOSTTY_ACTION_QUIT:
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return true

    case GHOSTTY_ACTION_CLOSE_WINDOW:
        // Use the target surface to find which terminal view to close
        if target.tag == GHOSTTY_TARGET_SURFACE {
            let surfacePtr = target.target.surface
            if let ud = ghostty_surface_userdata(surfacePtr) {
                let view = Unmanaged<TerminalView>.fromOpaque(ud).takeUnretainedValue()
                DispatchQueue.main.async { view.onSurfaceClosed?() }
            }
        }
        return true

    case GHOSTTY_ACTION_RENDER:
        DispatchQueue.main.async {
            for view in app.terminalViews.allObjects {
                view.needsDisplay = true
            }
        }
        return true

    case GHOSTTY_ACTION_COLOR_CHANGE:
        return true

    case GHOSTTY_ACTION_PRESENT_TERMINAL,
         GHOSTTY_ACTION_CELL_SIZE,
         GHOSTTY_ACTION_RENDERER_HEALTH,
         GHOSTTY_ACTION_PWD,
         GHOSTTY_ACTION_SCROLLBAR,
         GHOSTTY_ACTION_RING_BELL,
         GHOSTTY_ACTION_SET_TAB_TITLE,
         GHOSTTY_ACTION_PROGRESS_REPORT,
         GHOSTTY_ACTION_COMMAND_FINISHED:
        return true

    case GHOSTTY_ACTION_SIZE_LIMIT:
        let limits = action.action.size_limit
        if target.tag == GHOSTTY_TARGET_SURFACE {
            DispatchQueue.main.async {
                let surfacePtr = target.target.surface
                if let ud = ghostty_surface_userdata(surfacePtr) {
                    let view = Unmanaged<TerminalView>.fromOpaque(ud).takeUnretainedValue()
                    guard let panel = view.window else { return }
                    var minSize = panel.minSize
                    var maxSize = panel.maxSize
                    if limits.min_width > 0 { minSize.width = CGFloat(limits.min_width) }
                    if limits.min_height > 0 { minSize.height = CGFloat(limits.min_height) }
                    if limits.max_width > 0 { maxSize.width = CGFloat(limits.max_width) }
                    if limits.max_height > 0 { maxSize.height = CGFloat(limits.max_height) }
                    panel.minSize = minSize
                    panel.maxSize = maxSize
                }
            }
        }
        return true

    case GHOSTTY_ACTION_OPEN_CONFIG:
        DispatchQueue.main.async {
            let path = ghostty_config_open_path()
            if path.ptr != nil && path.len > 0 {
                let data = Data(bytes: path.ptr, count: Int(path.len))
                let str = String(data: data, encoding: .utf8) ?? ""
                if let url = URL(string: "file://\(str)") {
                    NSWorkspace.shared.open(url)
                }
                ghostty_string_free(path)
            }
        }
        return true

    case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
        return true

    default:
        return false
    }
}

// Surface-level callbacks receive surface userdata (TerminalView)

private func ghostlightReadClipboard(
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ state: UnsafeMutableRawPointer?
) -> Bool {
    guard let userdata else { return false }
    let view = Unmanaged<TerminalView>.fromOpaque(userdata).takeUnretainedValue()
    guard let surface = view.surface else { return false }

    let str = NSPasteboard.general.string(forType: .string) ?? ""
    let strCopy = strdup(str)
    DispatchQueue.main.async {
        ghostty_surface_complete_clipboard_request(surface, strCopy, state, true)
        free(strCopy)
    }
    return true
}

private func ghostlightConfirmReadClipboard(
    _ userdata: UnsafeMutableRawPointer?,
    _ contents: UnsafePointer<CChar>?,
    _ state: UnsafeMutableRawPointer?,
    _ request: ghostty_clipboard_request_e
) {
    guard let userdata else { return }
    let view = Unmanaged<TerminalView>.fromOpaque(userdata).takeUnretainedValue()
    guard let surface = view.surface else { return }
    let contentsCopy = contents != nil ? strdup(contents!) : nil
    DispatchQueue.main.async {
        ghostty_surface_complete_clipboard_request(surface, contentsCopy, state, true)
        free(contentsCopy)
    }
}

private func ghostlightWriteClipboard(
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ content: UnsafePointer<ghostty_clipboard_content_s>?,
    _ count: Int,
    _ confirm: Bool
) {
    guard let content, count > 0 else { return }
    // Copy string before async dispatch — content pointer may be freed after return
    let str = content.pointee.data.map { String(cString: $0) }
    DispatchQueue.main.async {
        guard let str else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(str, forType: .string)
    }
}

private func ghostlightCloseSurface(
    _ userdata: UnsafeMutableRawPointer?,
    _ processAlive: Bool
) {
    guard let userdata else { return }
    let view = Unmanaged<TerminalView>.fromOpaque(userdata).takeUnretainedValue()
    DispatchQueue.main.async { view.onSurfaceClosed?() }
}
