import AppKit

private enum AnimationState { case idle, walking, turning }
private enum Direction {
    case left, right
    var isFacingLeft: Bool { self == .left }
}

final class PetInstance {

    let pid: Int32

    static let baseSize = CGSize(width: 64, height: 125)
    private var scale: CGFloat = 1.0
    private var petSize: CGSize { CGSize(width: Self.baseSize.width * scale, height: Self.baseSize.height * scale) }
    private let walkSpeed: CGFloat = 4.0

    private let petWindow: NSWindow
    private let petView: PetView
    private let spriteSheet = SpriteSheet()

    private var animState: AnimationState = .idle
    private var direction: Direction = .right
    private var petX: CGFloat
    private var petY: CGFloat = 0

    private let ttyPath: String?
    private var tintHue: CGFloat?
    private var isMonochrome: Bool = false
    private var isThinking = true   // assume active on spawn; TTY timer corrects within 0.5s
    private var ttyTimer: Timer?

    // Frame sets — names match Resources/*.png (walk mirrored for left via isFacingLeft)
    private let walkFrames        = ["walk_right_new3", "walk_right_new4", "walk_right_new5"]
    private let thinkFrames       = ["think_new", "think_new2"]
    private let toThinkTransition = ["idle_new"]
    private let toWalkTransition  = ["idle_new2"]
    private let turnFrames        = ["walk_right_new3"]
    private let dragFrames        = ["drag"]

    private var currentFrameNames: [String] = []
    private var transitionTarget: [String]? = nil
    private var transitionFramesLeft = 0

    private var isDragging = false
    private var dragOffsetX: CGFloat = 0
    private var dragOffsetY: CGFloat = 0
    private var isFalling = false
    private var fallVelocity: CGFloat = 0
    private var fallTimer: Timer?

    // Cached dock layout — recomputed at most once per second.
    private var cachedLayout: DockLayout?
    private var layoutCacheTime: Date = .distantPast

    var animTimer: Timer?

    init(pid: Int32, ttyPath: String?, startX: CGFloat, tintHue: CGFloat?, monochrome: Bool = false, scale: CGFloat = 1.0) {
        self.pid = pid
        self.ttyPath = ttyPath
        self.tintHue = tintHue
        self.isMonochrome = monochrome
        self.scale = scale
        self.petX = startX

        let size = CGSize(width: Self.baseSize.width * scale, height: Self.baseSize.height * scale)
        petWindow = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                             backing: .buffered, defer: false)
        petWindow.isOpaque = false
        petWindow.backgroundColor = .clear
        petWindow.level = .floating
        petWindow.ignoresMouseEvents = false
        petWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        petWindow.hasShadow = false
        petWindow.isReleasedWhenClosed = false
        petWindow.alphaValue = 0

        petView = PetView(frame: NSRect(origin: .zero, size: size))
        petView.wantsLayer = true
        petWindow.contentView = petView

        loadIfNeeded(walkFrames)
        animState = .walking
        startAnimTimer()
        startTTYTimer()
        setupDrag()
        showPet()
    }

    // MARK: - Animation

    private func startAnimTimer(interval: TimeInterval = 0.25) {
        animTimer?.invalidate()
        animTimer = makeCommonTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.stepAnimation()
        }
    }

    private func stepAnimation() {
        guard !isDragging else { return }
        guard animState == .walking || animState == .turning else { return }

        // Play transition frame then switch to target set.
        if transitionFramesLeft > 0 {
            spriteSheet.advance()
            petView.currentFrame = spriteSheet.currentFrame
            transitionFramesLeft -= 1
            if transitionFramesLeft == 0, let target = transitionTarget {
                transitionTarget = nil
                loadIfNeeded(target)
            }
            return
        }

        if !isThinking {
            // TTY inactive → think animation in place.
            loadIfNeeded(thinkFrames)
            spriteSheet.advance()
            petView.currentFrame = spriteSheet.currentFrame
            return
        }

        if animState == .turning {
            loadIfNeeded(turnFrames)
            spriteSheet.advance()
            petView.currentFrame = spriteSheet.currentFrame
            animState = .walking
            return
        }

        // Walking
        loadIfNeeded(walkFrames)
        let layout = dockLayout()
        guard layout.maxX > layout.minX else { return }

        if direction == .right {
            petX += walkSpeed
            if petX >= layout.maxX { petX = layout.maxX; direction = .left; animState = .turning }
        } else {
            petX -= walkSpeed
            if petX <= layout.minX { petX = layout.minX; direction = .right; animState = .turning }
        }

        spriteSheet.advance()
        petView.currentFrame = spriteSheet.currentFrame
        petView.isFacingLeft = direction.isFacingLeft
    }

    private func loadIfNeeded(_ names: [String]) {
        guard names != currentFrameNames else { return }
        forceLoad(names)
    }

    private func forceLoad(_ names: [String]) {
        currentFrameNames = names
        spriteSheet.load(names, hue: tintHue, grayscale: isMonochrome)
        petView.currentFrame = spriteSheet.currentFrame
    }

    // MARK: - Position update (30fps)

    func update() {
        guard animState != .idle, !isDragging, !isFalling else { return }
        let layout = dockLayout()
        petX = max(layout.minX, min(petX, layout.maxX))
        petY = layout.floorY
        petWindow.setFrameOrigin(NSPoint(x: petX, y: petY))
        if !petWindow.isVisible { petWindow.orderFront(nil) }
    }

    // MARK: - Dock layout

    private struct DockLayout {
        let minX: CGFloat
        let maxX: CGFloat
        let floorY: CGFloat
    }

    private func dockLayout() -> DockLayout {
        let now = Date()
        if let cached = cachedLayout, now.timeIntervalSince(layoutCacheTime) < 1.0 {
            return cached
        }
        let result = computeDockLayout()
        cachedLayout = result
        layoutCacheTime = now
        return result
    }

    private func computeDockLayout() -> DockLayout {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sw = screen.frame.width
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return DockLayout(minX: screen.frame.minX,
                              maxX: screen.frame.maxX - petSize.width,
                              floorY: screen.visibleFrame.minY)
        }

        let sh = screen.frame.height
        for dict in list {
            guard let owner = dict[kCGWindowOwnerName as String] as? String, owner == "Dock",
                  let bd = dict[kCGWindowBounds as String] else { continue }
            var r = CGRect.zero
            guard let cfDict = bd as? NSDictionary,
                  CGRectMakeWithDictionaryRepresentation(cfDict, &r) else { continue }

            if r.width >= sw * 0.3 && (r.origin.y + r.height) >= sh * 0.8 {
                if let (dMinX, dMaxX) = dockIconArea(screenWidth: sw) {
                    return DockLayout(minX: dMinX, maxX: dMaxX - petSize.width,
                                      floorY: screen.visibleFrame.minY)
                }
                return DockLayout(minX: r.origin.x, maxX: r.origin.x + r.width - petSize.width,
                                  floorY: screen.visibleFrame.minY)
            }

            if r.height >= sh * 0.3 {
                return DockLayout(minX: screen.visibleFrame.minX,
                                  maxX: screen.visibleFrame.maxX - petSize.width,
                                  floorY: screen.frame.minY)
            }
        }

        return DockLayout(minX: screen.frame.minX,
                          maxX: screen.frame.maxX - petSize.width,
                          floorY: screen.frame.minY)
    }

    private func dockIconArea(screenWidth: CGFloat) -> (CGFloat, CGFloat)? {
        guard let prefs = UserDefaults(suiteName: "com.apple.dock") else { return nil }
        let tileSize = prefs.double(forKey: "tilesize")
        guard tileSize > 0 else { return nil }

        let slotWidth = tileSize * 1.25
        let apps    = (prefs.array(forKey: "persistent-apps")   as? [[String: Any]])?.count ?? 0
        let others  = (prefs.array(forKey: "persistent-others") as? [[String: Any]])?.count ?? 0
        let recent  = prefs.integer(forKey: "RecentApps")

        var dividers = 0
        if apps > 0 && (others > 0 || recent > 0) { dividers += 1 }
        if others > 0 && recent > 0 { dividers += 1 }

        let totalIcons = apps + others + recent
        guard totalIcons > 0 else { return nil }

        let dockWidth = CGFloat(totalIcons) * slotWidth + CGFloat(dividers) * 12.0
        let padded    = dockWidth * 1.15
        let dockX     = (screenWidth - padded) / 2.0

        return (max(0, dockX), min(screenWidth, dockX + padded))
    }

    // MARK: - Drag

    private func setupDrag() {
        petView.onDragBegan = { [weak self] localPoint in
            guard let self else { return }
            self.fallTimer?.invalidate(); self.fallTimer = nil
            self.isFalling = false
            self.isDragging = true
            self.dragOffsetX = localPoint.x
            self.dragOffsetY = localPoint.y
            self.forceLoad(self.dragFrames)
            self.petView.isFacingLeft = self.direction.isFacingLeft
        }

        petView.onDragMoved = { [weak self] screenPoint in
            guard let self else { return }
            let layout = self.dockLayout()
            let newX = screenPoint.x - self.dragOffsetX
            let clampedX = max(layout.minX, min(newX, layout.maxX))
            if clampedX < self.petX { self.petView.isFacingLeft = true }
            else if clampedX > self.petX { self.petView.isFacingLeft = false }
            self.petX = clampedX
            self.petY = screenPoint.y - self.dragOffsetY  // free vertical movement
            self.petWindow.setFrameOrigin(NSPoint(x: self.petX, y: self.petY))
        }

        petView.onDragEnded = { [weak self] in
            guard let self else { return }
            self.isDragging = false
            let layout = self.dockLayout()
            self.petX = max(layout.minX, min(self.petX, layout.maxX))
            if self.petY > layout.floorY {
                self.startFall(to: layout.floorY)
            } else {
                self.petY = layout.floorY
                self.resumeAfterDrag()
            }
        }
    }

    private func startFall(to floorY: CGFloat) {
        isFalling = true
        fallVelocity = 0
        fallTimer = makeCommonTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.fallVelocity += 2.0          // gravity (points/frame²)
            self.petY -= self.fallVelocity
            if self.petY <= floorY {
                self.petY = floorY
                self.fallTimer?.invalidate(); self.fallTimer = nil
                self.isFalling = false
                self.resumeAfterDrag()
                return
            }
            self.petWindow.setFrameOrigin(NSPoint(x: self.petX, y: self.petY))
        }
    }

    private func resumeAfterDrag() {
        currentFrameNames = []
        loadIfNeeded(isThinking ? walkFrames : thinkFrames)
    }

    // MARK: - Thinking detection

    private func startTTYTimer() {
        ttyTimer = makeCommonTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateThinkingState()
        }
    }

    private func updateThinkingState() {
        guard let path = ttyPath,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else { return }
        let active = Date().timeIntervalSince(mtime) < 0.5
        guard active != isThinking else { return }
        isThinking = active
        if active {
            // TTY went active → idle_new2 transition, then walk
            startAnimTimer(interval: 0.25)
            forceLoad(toWalkTransition)
            transitionTarget = walkFrames
            transitionFramesLeft = 2
        } else {
            // TTY went inactive → idle_new transition, then think (2× slower)
            startAnimTimer(interval: 1.0)
            forceLoad(toThinkTransition)
            transitionTarget = thinkFrames
            transitionFramesLeft = 2
        }
    }

    // MARK: - Tint

    func updateTint(_ hue: CGFloat?, monochrome: Bool) {
        tintHue = hue
        isMonochrome = monochrome
        forceLoad(currentFrameNames)
    }

    func resize(scale newScale: CGFloat) {
        scale = newScale
        let size = petSize
        petWindow.setContentSize(size)
        petView.frame = NSRect(origin: .zero, size: size)
    }

    // MARK: - Lifecycle

    func fadeOut(completion: @escaping () -> Void) {
        animTimer?.invalidate(); animTimer = nil
        ttyTimer?.invalidate(); ttyTimer = nil
        fallTimer?.invalidate(); fallTimer = nil
        animState = .idle
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.6
            petWindow.animator().alphaValue = 0
        }, completionHandler: {
            self.petWindow.orderOut(nil)
            completion()
        })
    }

    private func showPet() {
        update()
        petWindow.alphaValue = 0
        petWindow.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            petWindow.animator().alphaValue = 1.0
        }
    }
}
