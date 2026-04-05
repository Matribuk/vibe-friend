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
    var petX: CGFloat
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

    // MARK: - Building mode
    weak var blockWorld: BlockWorld?
    private var isBuilding = false
    var buildTargetX: CGFloat? = nil
    private var pendingBuildEntry: (pos: GridPos, block: PlacedBlock)? = nil

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

        if isBuilding {
            if let target = buildTargetX {
                // Walk toward the target column.
                loadIfNeeded(petView.isOnWater ? dragFrames : walkFrames)
                let step: CGFloat = walkSpeed * 1.8
                if abs(petX - target) <= step {
                    petX = target
                    buildTargetX = nil
                    petView.isFacingLeft = direction.isFacingLeft
                    // Place the pending block from this position, then pull next.
                    if let entry = pendingBuildEntry, let world = blockWorld {
                        pendingBuildEntry = nil
                        world.placeBlock(gridX: entry.pos.x, gridY: entry.pos.y,
                                         type: entry.block.type, tintHue: entry.block.tintHue)
                    }
                    requestNextBlock()
                } else if petX < target {
                    petX += step
                    petView.isFacingLeft = false
                } else {
                    petX -= step
                    petView.isFacingLeft = true
                }
                spriteSheet.advance()
                petView.currentFrame = spriteSheet.currentFrame
            } else {
                // Queue empty — stand still and think.
                loadIfNeeded(thinkFrames)
                spriteSheet.advance()
                petView.currentFrame = spriteSheet.currentFrame
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
        loadIfNeeded(petView.isOnWater ? dragFrames : walkFrames)
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
        // Stand on top of the highest block in our column (if any), else dock floor.
        let midX = petX + petSize.width / 2
        petY = blockWorld?.floorY(at: midX) ?? layout.floorY
        petView.isOnWater = blockWorld?.topBlockType(at: midX) == .water
        let waterOffset: CGFloat = petView.isOnWater ? -6 : 0
        petWindow.setFrameOrigin(NSPoint(x: petX, y: petY + waterOffset))
        if !petWindow.isVisible { petWindow.orderFront(nil) }
    }

    // MARK: - Dock layout

    private func dockLayout() -> DockLayout {
        let now = Date()
        if let cached = cachedLayout, now.timeIntervalSince(layoutCacheTime) < 1.0 {
            return cached
        }
        let result = computeDockLayout(petWidth: petSize.width)
        cachedLayout = result
        layoutCacheTime = now
        return result
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

    // MARK: - Building

    func setBuilding(_ building: Bool) {
        guard building != isBuilding else { return }
        isBuilding = building
        if building {
            startAnimTimer(interval: 0.25 / 1.8)
            requestNextBlock()
        } else {
            buildTargetX = nil
            pendingBuildEntry = nil
            startAnimTimer(interval: 0.25)
        }
    }

    private func requestNextBlock() {
        guard let world = blockWorld, let (pos, block) = world.nextPlanEntry() else { return }
        pendingBuildEntry = (pos, block)
        let centerX = world.origin.x + (CGFloat(pos.x) + 0.5) * world.cellSize
        let layout = dockLayout()
        buildTargetX = max(layout.minX, min(centerX - petSize.width / 2, layout.maxX))
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
