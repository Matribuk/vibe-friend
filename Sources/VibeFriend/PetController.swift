import AppKit

/// Manages one PetInstance per running claude process.
final class PetController {

    private let claudeDetector = ClaudeDetector()
    private var instances: [Int32: PetInstance] = [:]
    private var hues: [Int32: CGFloat] = [:]
    private var pollTimer: Timer?
    private var nextHue: CGFloat = CGFloat.random(in: 0...1)

    private let idleMonitor = IdleMonitor(threshold: .infinity)

    /// nil = building mode disabled; otherwise seconds of idle before triggering.
    var buildingIdleThreshold: TimeInterval? {
        didSet {
            idleMonitor.threshold = buildingIdleThreshold ?? .infinity
            // If just disabled while building, exit.
            if buildingIdleThreshold == nil, blockWorld != nil { exitBuildingMode() }
        }
    }
    private var blockWorld: BlockWorld?
    private var blockOverlay: BlockOverlayWindow?

    var petScale: CGFloat = 1.0 {
        didSet { instances.values.forEach { $0.resize(scale: petScale) } }
    }

    var isMonochrome: Bool = false {
        didSet {
            instances.forEach { pid, instance in
                instance.updateTint(hues[pid], monochrome: isMonochrome)
            }
        }
    }



    // MARK: - Lifecycle

    func start() {
        claudeDetector.onEvent = { [weak self] event in
            self?.handleClaudeEvent(event)
        }
        claudeDetector.start()

        pollTimer = makeCommonTimer(withTimeInterval: 1.0 / 10.0, repeats: true) { [weak self] _ in
            self?.updateBlockWorldOrigin()
            self?.instances.values.forEach { $0.update() }
        }

        idleMonitor.onIdle   = { [weak self] in self?.enterBuildingMode() }
        idleMonitor.onActive = { [weak self] in self?.exitBuildingMode()  }
        idleMonitor.start()
    }

    func stop() {
        pollTimer?.invalidate()
        claudeDetector.stop()
        idleMonitor.stop()
        instances.values.forEach { $0.animTimer?.invalidate() }
        instances.removeAll()
        blockWorld?.stop()
        blockOverlay?.hide()
    }

    // MARK: - Idle / building

    private func enterBuildingMode() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let cellSize: CGFloat = max(20, PetInstance.baseSize.width * petScale * 0.45)

        // Use the exact pet walking zone as world bounds — pets use petWidth-adjusted maxX.
        let petLayout = computeDockLayout(petWidth: PetInstance.baseSize.width * petScale)
        let worldMinX = petLayout.minX
        let worldWidth = max(cellSize, petLayout.maxX - petLayout.minX)

        let world = BlockWorld(
            cellSize: cellSize,
            origin:   CGPoint(x: worldMinX, y: petLayout.floorY),
            width:    worldWidth,
            height:   screen.visibleFrame.height * 0.5
        )
        blockWorld = world

        let overlay = BlockOverlayWindow()
        overlay.blockWorld = world

        blockOverlay = overlay
        overlay.show()

        // Generate and load plan before pets start pulling from it.
        let (plan, _) = WorldGenerator.generate(gridWidth: world.gridWidth, gridHeight: world.gridHeight)
        world.loadPlan(plan)

        instances.values.forEach {
            $0.blockWorld = world
            $0.setBuilding(true)
        }
    }

    private func updateBlockWorldOrigin() {
        guard let world = blockWorld else { return }
        let petLayout = computeDockLayout(petWidth: PetInstance.baseSize.width * petScale)

        // If Y changed, just shift the world down/up.
        if abs(world.origin.y - petLayout.floorY) > 1 {
            world.origin = CGPoint(x: world.origin.x, y: petLayout.floorY)
            world.onUpdate?()
        }

        // If X bounds changed significantly (fullscreen ↔ dock), restart with new world.
        let worldMaxX = world.origin.x + CGFloat(world.gridWidth) * world.cellSize
        let boundsChanged = abs(world.origin.x - petLayout.minX) > world.cellSize
                         || abs(worldMaxX - petLayout.maxX) > world.cellSize
        guard boundsChanged else { return }

        exitBuildingMode()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard self?.blockWorld == nil else { return }   // don't restart if already re-entered
            self?.enterBuildingMode()
        }
    }

    private func exitBuildingMode() {
        instances.values.forEach { $0.setBuilding(false); $0.blockWorld = nil }
        blockWorld?.clear()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.blockWorld?.stop()
            self?.blockWorld = nil
            self?.blockOverlay?.hide()
            self?.blockOverlay = nil
        }
    }

    // MARK: - Claude events

    private func handleClaudeEvent(_ event: ClaudeDetector.Event) {
        switch event {
        case .running(let pids):
            let current = Set(pids)
            let known   = Set(instances.keys)

            for pid in current.subtracting(known) {
                let ttyPath = self.ttyPath(forPID: pid)
                let screen = NSScreen.main ?? NSScreen.screens[0]
                let mid = screen.visibleFrame.midX
                let spread = screen.visibleFrame.width * 0.15
                let startX = mid + CGFloat.random(in: -spread...spread)
                let hue = nextHue
                nextHue = (nextHue + 0.618).truncatingRemainder(dividingBy: 1.0)
                hues[pid] = hue
                let inst = PetInstance(pid: pid, ttyPath: ttyPath, startX: startX,
                                       tintHue: hue, monochrome: isMonochrome, scale: petScale)
                if let world = blockWorld {
                    inst.blockWorld = world
                    inst.setBuilding(true)
                }
                instances[pid] = inst
            }

            for pid in known.subtracting(current) {
                instances[pid]?.fadeOut { [weak self] in
                    self?.instances.removeValue(forKey: pid)
                    self?.hues.removeValue(forKey: pid)
                }
            }

        case .allStopped:
            instances.values.forEach { $0.fadeOut {} }
            instances.removeAll()
            hues.removeAll()
        }
    }

    // MARK: - Process helpers

    private func ttyPath(forPID pid: Int32) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "tty=", "-p", "\(pid)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run(); task.waitUntilExit()
        let tty = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tty.isEmpty, tty != "??" else { return nil }
        return "/dev/\(tty)"
    }
}
