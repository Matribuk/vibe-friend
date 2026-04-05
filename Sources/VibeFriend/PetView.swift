import AppKit


final class PetView: NSView {

    var currentFrame: NSImage? { didSet { needsDisplay = true } }
    var isFacingLeft: Bool = false { didSet { needsDisplay = true } }
    var isOnWater: Bool = false { didSet { needsDisplay = true } }

    // Drag callbacks — set by PetInstance
    var onDragBegan: ((NSPoint) -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Hit testing

    // Only respond to clicks on opaque pixels — transparent areas pass through to apps below.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let img = currentFrame,
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ix = Int(point.x / bounds.width  * CGFloat(cg.width))
        let iy = Int((bounds.height - point.y) / bounds.height * CGFloat(cg.height))
        guard ix >= 0, iy >= 0, ix < cg.width, iy < cg.height else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                                   bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: -CGFloat(ix), y: -(CGFloat(cg.height) - CGFloat(iy) - 1),
                                width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return pixel[3] > 30 ? self : nil
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        onDragBegan?(pt)
    }

    override func mouseDragged(with event: NSEvent) {
        onDragMoved?(NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnded?()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        guard let image = currentFrame else { return }
        drawSprite(image, in: bounds)
        if isOnWater { drawBoat(in: bounds) }
    }

    private func drawBoat(in rect: NSRect) {
        let bw = rect.width * 1.1
        let bh = max(10, rect.height * 0.13)
        let bx = (rect.width - bw) / 2
        let by: CGFloat = 0

        let hull = NSBezierPath()
        hull.move(to: NSPoint(x: bx,              y: by + bh * 0.55))
        hull.line(to: NSPoint(x: bx + bw,         y: by + bh * 0.55))
        hull.line(to: NSPoint(x: bx + bw * 0.82,  y: by))
        hull.line(to: NSPoint(x: bx + bw * 0.18,  y: by))
        hull.close()
        NSColor(red: 0.55, green: 0.36, blue: 0.18, alpha: 1).setFill()
        hull.fill()

        NSColor(red: 0.72, green: 0.52, blue: 0.28, alpha: 1).setFill()
        NSRect(x: bx, y: by + bh * 0.50, width: bw, height: bh * 0.14).fill()

        hull.lineWidth = 1
        NSColor.black.withAlphaComponent(0.55).setStroke()
        hull.stroke()
    }

    private func drawSprite(_ image: NSImage, in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        if isFacingLeft {
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.scaleBy(x: -1, y: 1)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
        }
        image.draw(in: rect)
        ctx.restoreGState()
    }
}
