import AppKit
import Carbon
import CLibGhostty
import QuartzCore

class TerminalView: NSView {
    var surface: ghostty_surface_t?
    weak var ghosttyApp: GhosttyApp?
    var onCopyVisibleContentAndClose: (() -> Void)?
    var onSurfaceClosed: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        layer.isOpaque = true
        layer.pixelFormat = .bgra8Unorm
        return layer
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func updateLayer() {
        guard let surface else { return }
        ghostty_surface_draw(surface)
    }

    // MARK: - Surface Lifecycle

    func createSurface(fontSize: Float = 0, workingDirectory: String = "") {
        guard let appHandle = ghosttyApp?.app else { return }

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform.macos = ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        )
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = Double(window?.backingScaleFactor ?? 2.0)
        config.font_size = fontSize
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        var dir = workingDirectory
        if dir.hasPrefix("~") {
            dir = NSString(string: dir).expandingTildeInPath
        }
        if dir.isEmpty {
            surface = ghostty_surface_new(appHandle, &config)
        } else {
            dir.withCString { cStr in
                config.working_directory = cStr
                surface = ghostty_surface_new(appHandle, &config)
            }
        }
        guard let surface else { return }

        let scale = Double(window?.backingScaleFactor ?? 2.0)
        ghostty_surface_set_content_scale(surface, scale, scale)

        let size = frame.size
        ghostty_surface_set_size(
            surface,
            UInt32(size.width * scale),
            UInt32(size.height * scale)
        )

        updateTrackingAreas()
    }

    func destroySurface() {
        if let surface {
            ghostty_surface_free(surface)
            self.surface = nil
        }
    }

    func sendText(_ text: String) {
        guard let surface else { return }
        let utf8 = Array(text.utf8)
        utf8.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            base.withMemoryRebound(to: CChar.self, capacity: buf.count) { ptr in
                ghostty_surface_text(surface, ptr, UInt(buf.count))
            }
        }
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface else { return }
        let scale = Double(window?.backingScaleFactor ?? 2.0)
        ghostty_surface_set_size(
            surface,
            UInt32(newSize.width * scale),
            UInt32(newSize.height * scale)
        )
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let surface, let window else { return }
        let scale = window.backingScaleFactor
        (layer as? CAMetalLayer)?.contentsScale = scale
        ghostty_surface_set_content_scale(surface, scale, scale)
        let size = frame.size
        ghostty_surface_set_size(
            surface,
            UInt32(size.width * scale),
            UInt32(size.height * scale)
        )
    }

    // MARK: - Tracking Areas

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard let surface else { return }

        let chars = event.characters ?? ""
        let consumed: Bool = chars.withCString { cStr in
            var key = ghostty_input_key_s()
            key.action = GHOSTTY_ACTION_PRESS
            key.mods = Self.convertMods(event.modifierFlags)
            key.consumed_mods = GHOSTTY_MODS_NONE
            key.keycode = UInt32(event.keyCode)
            key.text = cStr
            key.composing = false
            key.unshifted_codepoint = 0
            if let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first {
                key.unshifted_codepoint = scalar.value
            }
            return ghostty_surface_key(surface, key)
        }

        if !consumed {
            interpretKeyEvents([event])
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else { return }
        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_RELEASE
        key.mods = Self.convertMods(event.modifierFlags)
        key.consumed_mods = GHOSTTY_MODS_NONE
        key.keycode = UInt32(event.keyCode)
        key.text = nil
        key.composing = false
        key.unshifted_codepoint = 0
        _ = ghostty_surface_key(surface, key)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else { return }
        // Determine if a modifier was pressed or released by checking current flags
        let mods = Self.convertMods(event.modifierFlags)
        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_PRESS
        key.mods = mods
        key.consumed_mods = GHOSTTY_MODS_NONE
        key.keycode = UInt32(event.keyCode)
        key.text = nil
        key.composing = false
        key.unshifted_codepoint = 0
        _ = ghostty_surface_key(surface, key)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let surface else { return false }
        let modifiers = normalizedModifierFlags(event)

        if isEnterKey(event) {
            if modifiers == [.command] {
                guard copyLastCommandOutputToClipboard() else {
                    NSSound.beep()
                    return true
                }
                onCopyVisibleContentAndClose?()
                return true
            }

            if modifiers == [.command, .shift] {
                guard copyScreenContentsToClipboard() else {
                    NSSound.beep()
                    return true
                }
                onCopyVisibleContentAndClose?()
                return true
            }
        }

        // Handle Cmd+V paste directly — avoids ghostty clipboard callback issues
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "v" {
            let str = NSPasteboard.general.string(forType: .string) ?? ""
            if !str.isEmpty {
                let utf8 = Array(str.utf8)
                utf8.withUnsafeBufferPointer { buf in
                    guard let base = buf.baseAddress else { return }
                    base.withMemoryRebound(to: CChar.self, capacity: buf.count) { ptr in
                        ghostty_surface_text(surface, ptr, UInt(buf.count))
                    }
                }
            }
            return true
        }

        // Handle Cmd+C copy
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "c" {
            if ghostty_surface_has_selection(surface) {
                var text = ghostty_text_s()
                if ghostty_surface_read_selection(surface, &text), let ptr = text.text {
                    let data = Data(bytes: ptr, count: Int(text.text_len))
                    let str = String(data: data, encoding: .utf8) ?? ""
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(str, forType: .string)
                    ghostty_surface_free_text(surface, &text)
                }
                return true
            }
        }

        let chars = event.characters ?? ""
        let handled: Bool = chars.withCString { cStr in
            var key = ghostty_input_key_s()
            key.action = GHOSTTY_ACTION_PRESS
            key.mods = Self.convertMods(event.modifierFlags)
            key.consumed_mods = GHOSTTY_MODS_NONE
            key.keycode = UInt32(event.keyCode)
            key.text = cStr
            key.composing = false
            key.unshifted_codepoint = 0
            if let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first {
                key.unshifted_codepoint = scalar.value
            }
            return ghostty_surface_key(surface, key)
        }

        return handled
    }

    // MARK: - Mouse Input

    private func mousePoint(from event: NSEvent) -> (Double, Double) {
        let point = convert(event.locationInWindow, from: nil)
        let scale = Double(window?.backingScaleFactor ?? 2.0)
        return (point.x * scale, (frame.height - point.y) * scale)
    }

    override func mouseDown(with event: NSEvent) {
        guard let surface else { return }
        let (x, y) = mousePoint(from: event)
        let mods = Self.convertMods(event.modifierFlags)
        ghostty_surface_mouse_pos(surface, x, y, mods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        let (x, y) = mousePoint(from: event)
        let mods = Self.convertMods(event.modifierFlags)
        ghostty_surface_mouse_pos(surface, x, y, mods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let (x, y) = mousePoint(from: event)
        ghostty_surface_mouse_pos(surface, x, y, Self.convertMods(event.modifierFlags))
    }

    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return }
        let mods = Self.convertMods(event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = Self.convertMods(event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, mods)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_scroll(
            surface,
            event.scrollingDeltaX,
            event.scrollingDeltaY,
            0 // scroll mods packed int — 0 for default behavior
        )
    }

    // MARK: - Helpers

    static func convertMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { raw |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }

    private func copyLastCommandOutputToClipboard() -> Bool {
        guard let surface else { return false }

        var text = ghostty_text_s()
        guard ghostty_surface_read_last_output(surface, &text), let ptr = text.text else { return false }
        defer { ghostty_surface_free_text(surface, &text) }

        let data = Data(bytes: ptr, count: Int(text.text_len))
        let string = String(data: data, encoding: .utf8) ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        return true
    }

    private func copyScreenContentsToClipboard() -> Bool {
        guard let surface else { return false }

        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN,
                coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                x: 0,
                y: 0
            ),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN,
                coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                x: 0,
                y: 0
            ),
            rectangle: false
        )
        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text), let ptr = text.text else { return false }
        defer { ghostty_surface_free_text(surface, &text) }

        let data = Data(bytes: ptr, count: Int(text.text_len))
        let string = String(data: data, encoding: .utf8) ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        return true
    }

    private func isEnterKey(_ event: NSEvent) -> Bool {
        event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter)
    }

    private func normalizedModifierFlags(_ event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.numericPad)
    }

    deinit {
        destroySurface()
    }
}

// MARK: - NSTextInputClient

extension TerminalView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let surface else { return }
        let str: String
        if let s = string as? String {
            str = s
        } else if let s = (string as? NSAttributedString)?.string {
            str = s
        } else {
            return
        }

        let utf8 = Array(str.utf8)
        utf8.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            base.withMemoryRebound(to: CChar.self, capacity: buf.count) { ptr in
                ghostty_surface_text(surface, ptr, UInt(buf.count))
            }
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let surface else { return }
        let str: String
        if let s = string as? String {
            str = s
        } else if let s = (string as? NSAttributedString)?.string {
            str = s
        } else {
            return
        }

        let utf8 = Array(str.utf8)
        utf8.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            base.withMemoryRebound(to: CChar.self, capacity: buf.count) { ptr in
                ghostty_surface_preedit(surface, ptr, UInt(buf.count))
            }
        }
    }

    func unmarkText() {
        guard let surface else { return }
        ghostty_surface_preedit(surface, nil, 0)
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool { false }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface, let window else { return .zero }
        var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        let scale = window.backingScaleFactor
        let viewPoint = NSPoint(x: x / scale, y: frame.height - (y / scale))
        let windowPoint = convert(viewPoint, to: nil)
        let screenPoint = window.convertPoint(toScreen: windowPoint)
        return NSRect(x: screenPoint.x, y: screenPoint.y, width: w / scale, height: h / scale)
    }

    func characterIndex(for point: NSPoint) -> Int { 0 }
}
