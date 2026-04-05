import AppKit

// MARK: - Block image cache

private enum BlockImages {
    static let cache: [BlockType: NSImage] = {
        var map: [BlockType: NSImage] = [:]
        let files: [(BlockType, String)] = [
            (.grass, "grass"), (.dirt, "dirt"), (.stone, "stone"),
            (.sand, "sand"),   (.water, "water")
        ]
        for (type, name) in files {
            if let url = Bundle.module.url(forResource: name, withExtension: "svg"),
               let img = NSImage(contentsOf: url) {
                map[type] = img
            }
        }
        return map
    }()
}

// MARK: - View

final class BlockOverlayView: NSView {

    var blockWorld: BlockWorld?

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    // MARK: - Draw

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        guard let world = blockWorld else { return }

        // Static blocks
        for (pos, block) in world.grid {
            let r = viewRect(world.worldRect(gx: pos.x, gy: pos.y))
            drawBlock(type: block.type, in: r, alpha: block.alpha, tintHue: block.tintHue)
        }

        // Falling blocks
        for fb in world.falling {
            let wr = CGRect(x: world.origin.x + CGFloat(fb.gridX) * world.cellSize,
                            y: fb.screenY,
                            width: world.cellSize, height: world.cellSize)
            drawBlock(type: fb.type, in: viewRect(wr), tintHue: fb.tintHue)
        }

    }

    // MARK: - Block drawing

    private func drawBlock(type: BlockType, in r: CGRect, alpha: CGFloat = 1, tintHue: CGFloat? = nil) {
        guard r.intersects(bounds) else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha)

        // Snap both edges to pixel grid — shared boundary, no gap and no overlap.
        let x1 = r.minX.rounded(.down), y1 = r.minY.rounded(.down)
        let x2 = r.maxX.rounded(.down), y2 = r.maxY.rounded(.down)
        let pr = CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)

        if let img = BlockImages.cache[type] {
            img.draw(in: pr)
        } else {
            type.faceColor.setFill(); pr.fill()
        }

        // Island color tint overlay
        if let hue = tintHue {
            NSColor(hue: hue, saturation: 0.65, brightness: 1.0, alpha: 0.22).setFill()
            pr.fill()
        }

        // Cel-shading border on non-water blocks
        if type != .water {
            NSColor.black.setStroke()
            let border = NSBezierPath(rect: pr.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1.5
            border.stroke()
        }

        ctx.restoreGState()
    }

    // MARK: - Coordinate conversion

    /// Convert screen-space rect to this view's local coordinates.
    private func viewRect(_ screenRect: CGRect) -> CGRect {
        CGRect(x: screenRect.minX - frame.origin.x,
               y: screenRect.minY - frame.origin.y,
               width: screenRect.width, height: screenRect.height)
    }
}

// MARK: - Window

final class BlockOverlayWindow: NSWindow {

    private let overlayView = BlockOverlayView()

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        super.init(contentRect: screen.frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        isOpaque          = false
        backgroundColor   = .clear
        // One level below .floating so pet windows always render above blocks.
        level             = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hasShadow         = false
        isReleasedWhenClosed = false

        overlayView.frame = CGRect(origin: .zero, size: screen.frame.size)
        overlayView.wantsLayer = true
        contentView = overlayView
    }

    var blockWorld: BlockWorld? {
        get { overlayView.blockWorld }
        set {
            overlayView.blockWorld = newValue
            newValue?.onUpdate = { [weak self] in
                DispatchQueue.main.async { self?.overlayView.needsDisplay = true }
            }
        }
    }

    func show() { orderFront(nil) }
    func hide() { orderOut(nil)  }
}
