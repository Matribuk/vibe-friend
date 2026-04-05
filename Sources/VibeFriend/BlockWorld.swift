import AppKit

// MARK: - Block types

enum BlockType: Int, CaseIterable {
    case grass, dirt, stone, wood, sand, water

    var faceColor: NSColor {
        switch self {
        case .grass: return NSColor(red: 0.34, green: 0.67, blue: 0.27, alpha: 1)
        case .dirt:  return NSColor(red: 0.60, green: 0.42, blue: 0.22, alpha: 1)
        case .stone: return NSColor(red: 0.55, green: 0.55, blue: 0.57, alpha: 1)
        case .wood:  return NSColor(red: 0.62, green: 0.46, blue: 0.26, alpha: 1)
        case .sand:  return NSColor(red: 0.91, green: 0.84, blue: 0.60, alpha: 1)
        case .water: return NSColor(red: 0.18, green: 0.45, blue: 0.78, alpha: 1)
        }
    }
    var darkColor:  NSColor { faceColor.shadow(withLevel: 0.28) ?? faceColor }
    var lightColor: NSColor { faceColor.highlight(withLevel: 0.18) ?? faceColor }
}

// MARK: - Data

struct GridPos: Hashable { let x: Int; let y: Int }

struct PlacedBlock {
    var type: BlockType
    var alpha: CGFloat = 1
    var tintHue: CGFloat? = nil   // island color tint
}

struct FallingBlock {
    let gridX: Int
    let gridY: Int            // target row — stored to avoid float rounding on landing
    let type: BlockType
    var screenY: CGFloat      // current Y position (falling)
    let targetScreenY: CGFloat
    var velocity: CGFloat = 0
    let tintHue: CGFloat?
}

// MARK: - World

final class BlockWorld {

    let cellSize: CGFloat
    var origin: CGPoint       // screen-space bottom-left of grid
    let gridWidth: Int        // number of columns
    let gridHeight: Int       // maximum rows (above dock)

    private(set) var grid:    [GridPos: PlacedBlock] = [:]
    private(set) var falling: [FallingBlock]         = []
    private(set) var quadtree: Quadtree

    var onUpdate:       (() -> Void)?
    var onPlanComplete: (() -> Void)?

    private var physicsTimer: Timer?
    private var planTimer:    Timer?
    private(set) var planQueue: [(GridPos, PlacedBlock)] = []

    init(cellSize: CGFloat, origin: CGPoint, width: CGFloat, height: CGFloat) {
        self.cellSize   = cellSize
        self.origin     = origin
        self.gridWidth  = max(1, Int(width  / cellSize))
        self.gridHeight = max(1, Int(height / cellSize))
        let bounds = CGRect(x: origin.x, y: origin.y, width: width, height: height)
        self.quadtree   = Quadtree(bounds: bounds)

        physicsTimer = makeCommonTimer(withTimeInterval: 1 / 60.0, repeats: true) { [weak self] _ in
            self?.physicsStep()
        }
    }

    // MARK: - Plan loading

    /// Load a pre-generated world plan. Pets pull entries via `nextPlanEntry()`.
    func loadPlan(_ plan: [GridPos: PlacedBlock]) {
        planTimer?.invalidate(); planTimer = nil
        planQueue = plan.sorted { a, b in
            a.key.y != b.key.y ? a.key.y < b.key.y : a.key.x < b.key.x
        }
    }

    /// Pet pulls the next block to place. Returns nil when plan is complete.
    func nextPlanEntry() -> (GridPos, PlacedBlock)? {
        guard !planQueue.isEmpty else {
            onPlanComplete?()
            return nil
        }
        return planQueue.removeFirst()
    }

    /// Pet places a block — drops one cell from just above the target position.
    func placeBlock(gridX gx: Int, gridY gy: Int, type: BlockType, tintHue: CGFloat?) {
        guard gy < gridHeight else { return }
        let targetY = origin.y + CGFloat(gy) * cellSize
        falling.append(FallingBlock(gridX: gx, gridY: gy, type: type,
                                    screenY: targetY + cellSize,
                                    targetScreenY: targetY,
                                    velocity: 0, tintHue: tintHue))
        onUpdate?()
    }

    // MARK: - Public API

    /// Height for *spawning* — counts landed blocks + in-flight blocks to avoid overlap.
    func stackHeight(at gx: Int) -> Int {
        let landed   = landedHeight(at: gx)
        let inflight = falling.filter { $0.gridX == gx }.map { $0.gridY + 1 }.max() ?? 0
        return max(landed, inflight)
    }

    /// Height for *standing* — only landed blocks so pets don't float above in-flight blocks.
    private func landedHeight(at gx: Int) -> Int {
        (0..<gridHeight).reversed()
            .first { grid[GridPos(x: gx, y: $0)] != nil }
            .map { $0 + 1 } ?? 0
    }

    /// Block type of the top landed block in the column under worldX.
    func topBlockType(at worldX: CGFloat) -> BlockType? {
        let gx = gridX(for: worldX)
        let h = landedHeight(at: gx)
        guard h > 0 else { return nil }
        return grid[GridPos(x: gx, y: h - 1)]?.type
    }

    /// Screen-space Y to stand on — based on landed blocks only.
    func floorY(at worldX: CGFloat) -> CGFloat? {
        let gx = gridX(for: worldX)
        let h = landedHeight(at: gx)
        guard h > 0 else { return nil }
        return origin.y + CGFloat(h) * cellSize
    }

    /// Fade out and remove all blocks.
    func clear() {
        planTimer?.invalidate(); planTimer = nil
        planQueue.removeAll()
        grid.removeAll()
        falling.removeAll()
        rebuildQuadtree()
        onUpdate?()
    }

    func stop() {
        physicsTimer?.invalidate(); physicsTimer = nil
        planTimer?.invalidate();    planTimer    = nil
    }

    // MARK: - Coordinate helpers

    func worldRect(gx: Int, gy: Int) -> CGRect {
        CGRect(x: origin.x + CGFloat(gx) * cellSize,
               y: origin.y + CGFloat(gy) * cellSize,
               width: cellSize, height: cellSize)
    }

    // MARK: - Private

    private func gridX(for worldX: CGFloat) -> Int {
        max(0, min(Int((worldX - origin.x) / cellSize), gridWidth - 1))
    }

    private func physicsStep() {
        guard !falling.isEmpty else { return }
        let g: CGFloat = 2.0

        for i in falling.indices.reversed() {
            falling[i].velocity += g
            falling[i].screenY  -= falling[i].velocity

            if falling[i].screenY <= falling[i].targetScreenY {
                let fb = falling[i]
                grid[GridPos(x: fb.gridX, y: fb.gridY)] = PlacedBlock(type: fb.type,
                                                                        tintHue: fb.tintHue)
                falling.remove(at: i)
                rebuildQuadtree()
            }
        }
        onUpdate?()
    }

    private func rebuildQuadtree() {
        quadtree.clear()
        for (pos, _) in grid {
            quadtree.insert(gridX: pos.x, gridY: pos.y, worldRect: worldRect(gx: pos.x, gy: pos.y))
        }
    }
}
