import Foundation

// MARK: - Island

struct Island {
    let left: Int
    let right: Int
    let hue: CGFloat

    var center: CGFloat { CGFloat(left + right) / 2 }
    var halfWidth: CGFloat { CGFloat(right - left) / 2 }
    /// Max terrain height above row 0 (so total column height = maxHeight + 1 at center).
    var maxHeight: Int { max(1, (right - left) / 2) }

    /// Number of cells in column x (1 = only row 0, 2 = rows 0+1, …).
    func columnHeight(at x: Int) -> Int {
        let hw = halfWidth
        guard hw > 0, x >= left, x <= right else { return 0 }
        let dx = CGFloat(x) - center
        let ratio = max(0.0, 1.0 - (dx * dx) / (hw * hw))
        return 1 + Int((CGFloat(maxHeight) * sqrt(ratio)).rounded(.towardZero))
    }

    /// Horizontal distance from the nearest shore (0 = edge column at row 0).
    func edgeDist(at x: Int) -> Int { min(x - left, right - x) }

    /// Horizontal distance from air at a given row y (0 = column is at the edge of the island at this row).
    func rowEdgeDist(x: Int, row y: Int) -> Int {
        var le = x, re = x
        while le > left  && columnHeight(at: le - 1) >= y + 1 { le -= 1 }
        while re < right && columnHeight(at: re + 1) >= y + 1 { re += 1 }
        return min(x - le, re - x)
    }

    func blockType(at x: Int, row y: Int) -> BlockType {
        guard columnHeight(at: x) >= y + 1 else { return .water }
        let isTop = columnHeight(at: x) == y + 1

        if y == 0 {
            switch edgeDist(at: x) {
            case 0:      return .sand
            case 1, 2:   return .dirt
            default:     return .stone
            }
        } else {
            // Upper rows: grass on the very top, 2-cell dirt shell, stone inside
            if isTop { return .grass }
            if rowEdgeDist(x: x, row: y) <= 1 { return .dirt }
            return .stone
        }
    }
}

// MARK: - Generator

enum WorldGenerator {

    static func generate(gridWidth: Int, gridHeight: Int) -> (plan: [GridPos: PlacedBlock], islands: [Island]) {
        let islands = placeIslands(gridWidth: gridWidth, gridHeight: gridHeight)

        var plan: [GridPos: PlacedBlock] = [:]

        // Row 0: water everywhere, replaced by island base where applicable.
        for gx in 0..<gridWidth {
            if let island = islands.first(where: { $0.left <= gx && gx <= $0.right }) {
                let type = island.blockType(at: gx, row: 0)
                plan[GridPos(x: gx, y: 0)] = PlacedBlock(type: type, tintHue: island.hue)
            } else {
                plan[GridPos(x: gx, y: 0)] = PlacedBlock(type: .water)
            }
        }

        // Rows 1+: island terrain only.
        for island in islands {
            for gx in island.left...island.right {
                let h = island.columnHeight(at: gx)
                for gy in 1..<h {
                    let type = island.blockType(at: gx, row: gy)
                    plan[GridPos(x: gx, y: gy)] = PlacedBlock(type: type, tintHue: island.hue)
                }
            }
        }

        return (plan, islands)
    }

    // MARK: - Private

    private static func placeIslands(gridWidth: Int, gridHeight: Int) -> [Island] {
        let minSep   = 3
        let minWidth = 8
        let targetN  = Int.random(in: 2...4)
        let maxWidth = max(minWidth, gridWidth / targetN - minSep)

        var islands: [Island] = []
        var cursor  = minSep
        var hue: CGFloat = CGFloat.random(in: 0...1)

        for _ in 0..<targetN {
            guard cursor + minWidth < gridWidth - minSep else { break }
            let available = min(maxWidth, gridWidth - minSep - cursor)
            guard available >= minWidth else { break }
            let w    = Int.random(in: minWidth...available)
            let left = cursor
            let right = left + w - 1
            islands.append(Island(left: left, right: right, hue: hue))
            hue = (hue + 0.618).truncatingRemainder(dividingBy: 1.0)
            cursor = right + 1 + minSep + Int.random(in: 0...3)
        }

        // Guarantee at least 2 islands by halving grid if needed.
        if islands.count < 2 {
            islands.removeAll()
            let hw = gridWidth / 2
            let w  = max(minWidth, hw / 2 - minSep)
            islands.append(Island(left: minSep,           right: minSep + w - 1,     hue: 0.33))
            islands.append(Island(left: hw + minSep,      right: hw + minSep + w - 1, hue: 0.66))
        }

        return islands
    }
}
