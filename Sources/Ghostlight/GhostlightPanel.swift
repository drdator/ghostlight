import AppKit
import CLibGhostty

class GhostlightPanel {
    let panel: NSPanel
    let terminalView: TerminalView
    private let ghosttyApp: GhosttyApp
    private var isVisible = false
    private var panelDelegate: NSWindowDelegate?
    private var containerView: NSView!
    private var borderOverlay: BorderOverlayView?

    init(ghosttyApp: GhosttyApp) {
        self.ghosttyApp = ghosttyApp

        let cfg = ghosttyApp.config_
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: cfg.windowWidth, height: cfg.windowHeight),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Hide window buttons
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // Container view handles background, corner radius, clipping
        let contentBounds = panel.contentView?.bounds ?? .zero
        containerView = NSView(frame: contentBounds)
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        containerView.layer!.cornerRadius = cfg.cornerRadius
        containerView.layer!.masksToBounds = true
        containerView.layer!.backgroundColor = Self.blendedPaddingColor(base: ghosttyApp.backgroundColor, overlay: cfg.parsedPaddingColor()).cgColor
        panel.contentView?.addSubview(containerView)

        // Terminal view with padding inside container
        let insetFrame = contentBounds.insetBy(dx: cfg.windowPadding, dy: cfg.windowPadding)
        terminalView = TerminalView(frame: insetFrame)
        terminalView.autoresizingMask = [.width, .height]
        terminalView.ghosttyApp = ghosttyApp
        ghosttyApp.activeTerminalView = terminalView
        containerView.addSubview(terminalView)

        // Border overlay on top of everything (Metal can't cover this)
        let overlay = BorderOverlayView(frame: contentBounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.cornerRadius = cfg.cornerRadius
        overlay.borderColor = cfg.parsedBorderColor()
        panel.contentView?.addSubview(overlay)
        borderOverlay = overlay

        // Close panel via its delegate
        panelDelegate = PanelDelegate(owner: self)
        panel.delegate = panelDelegate
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        // Reload config visuals (don't recreate the pre-spawned surface)
        ghosttyApp.config_ = GhostlightConfig.load()
        applyConfig(ghosttyApp.config_)

        if terminalView.surface == nil {
            terminalView.createSurface()
        }

        panel.center()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(terminalView)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        if let surface = terminalView.surface {
            ghostty_surface_set_focus(surface, true)
            ghostty_surface_set_occlusion(surface, false)
        }

        isVisible = true
    }

    func hide() {
        // Destroy old shell and pre-create a fresh one so it's ready instantly
        terminalView.destroySurface()
        terminalView.createSurface()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })

        isVisible = false
    }

    func applyConfig(_ cfg: GhostlightConfig, recreateSurface: Bool = false) {
        panel.setContentSize(NSSize(width: cfg.windowWidth, height: cfg.windowHeight))

        if let layer = containerView.layer {
            layer.cornerRadius = cfg.cornerRadius
            layer.backgroundColor = Self.blendedPaddingColor(base: ghosttyApp.backgroundColor, overlay: cfg.parsedPaddingColor()).cgColor
        }

        borderOverlay?.cornerRadius = cfg.cornerRadius
        borderOverlay?.borderColor = cfg.parsedBorderColor()

        // Update terminal view inset
        let contentBounds = containerView.bounds
        terminalView.frame = contentBounds.insetBy(dx: cfg.windowPadding, dy: cfg.windowPadding)

        if recreateSurface {
            terminalView.destroySurface()
            terminalView.createSurface()
        }
    }

    private static func blendedPaddingColor(base: NSColor, overlay: NSColor?) -> NSColor {
        guard let overlay else { return base }
        let b = base.usingColorSpace(.sRGB) ?? base
        let o = overlay.usingColorSpace(.sRGB) ?? overlay
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        var or_: CGFloat = 0, og: CGFloat = 0, ob: CGFloat = 0, oa: CGFloat = 0
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        o.getRed(&or_, green: &og, blue: &ob, alpha: &oa)
        return NSColor(
            red: br * (1 - oa) + or_ * oa,
            green: bg * (1 - oa) + og * oa,
            blue: bb * (1 - oa) + ob * oa,
            alpha: 1.0
        )
    }

    func destroySurface() {
        terminalView.destroySurface()
    }
}

// MARK: - Border Overlay (draws on top of Metal layer)

private class BorderOverlayView: NSView {
    var cornerRadius: CGFloat = 12
    var borderColor: NSColor? {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let color = borderColor else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: cornerRadius, yRadius: cornerRadius)
        path.lineWidth = 1.0
        color.setStroke()
        path.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil // click-through
    }
}

// MARK: - Panel Delegate

private class PanelDelegate: NSObject, NSWindowDelegate {
    weak var owner: GhostlightPanel?

    init(owner: GhostlightPanel) {
        self.owner = owner
    }

    func windowWillClose(_ notification: Notification) {
        owner?.hide()
    }
}
