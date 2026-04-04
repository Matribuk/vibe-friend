import AppKit

final class SpriteSheet {

    private var frames: [NSImage] = []
    private var frameIndex = 0

    var currentFrame: NSImage? { frames.isEmpty ? nil : frames[frameIndex] }
    var hasFrames: Bool { !frames.isEmpty }

    func load(_ names: [String], hue: CGFloat? = nil) {
        frames = names.compactMap { name in
            guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
                  let img = NSImage(contentsOf: url) else { return nil }
            return hue.map { recolor(img, targetHue: Float($0)) } ?? img
        }
        frameIndex = 0
    }

    func advance() {
        guard !frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % frames.count
    }

    func reset() {
        frameIndex = 0
    }

    // MARK: - Hue replacement

    // Replaces orange-red pixels (hue 0–36° or 324–360°, s>30%, v>20%) with targetHue.
    // Black borders and transparent pixels are left untouched.
    private func recolor(_ image: NSImage, targetHue: Float) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let w = cgImage.width, h = cgImage.height
        let bytesPerRow = w * 4
        var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)
        guard let ctx = CGContext(data: &pixels, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = pixels[i + 3]
            guard a > 10 else { continue }
            let fa = Float(a) / 255.0
            let r = Float(pixels[i])     / (255.0 * fa)
            let g = Float(pixels[i + 1]) / (255.0 * fa)
            let b = Float(pixels[i + 2]) / (255.0 * fa)

            let (h, s, v) = rgbToHSB(r, g, b)
            guard (h < 0.10 || h > 0.90) && s > 0.30 && v > 0.20 else { continue }

            let (nr, ng, nb) = hsbToRGB(targetHue, s, v)
            pixels[i]     = UInt8(clamping: Int((nr * fa * 255).rounded()))
            pixels[i + 1] = UInt8(clamping: Int((ng * fa * 255).rounded()))
            pixels[i + 2] = UInt8(clamping: Int((nb * fa * 255).rounded()))
        }

        guard let newCG = ctx.makeImage() else { return image }
        return NSImage(cgImage: newCG, size: image.size)
    }

    private func rgbToHSB(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let s: Float = mx == 0 ? 0 : d / mx
        var h: Float = 0
        if d > 0 {
            if mx == r      { h = (g - b) / d }
            else if mx == g { h = 2 + (b - r) / d }
            else            { h = 4 + (r - g) / d }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, s, mx)
    }

    private func hsbToRGB(_ h: Float, _ s: Float, _ v: Float) -> (Float, Float, Float) {
        guard s > 0 else { return (v, v, v) }
        let i = Int(h * 6) % 6
        let f = h * 6 - Float(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
