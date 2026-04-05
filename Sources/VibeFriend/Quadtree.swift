import CoreGraphics

/// 2D quadtree storing (gridX, gridY) block coordinates.
/// All coordinates are in screen space; each item occupies a `cellSize`-square rect.
final class Quadtree {

    let bounds: CGRect
    private let depth: Int
    private static let maxDepth = 6
    private static let maxItems = 8

    private var items: [(rect: CGRect, x: Int, y: Int)] = []
    private(set) var children: [Quadtree]?

    init(bounds: CGRect, depth: Int = 0) {
        self.bounds = bounds
        self.depth  = depth
    }

    // MARK: - Mutation

    func clear() {
        items.removeAll()
        children = nil
    }

    func insert(gridX: Int, gridY: Int, worldRect: CGRect) {
        guard bounds.intersects(worldRect) else { return }
        if let ch = children {
            ch.forEach { $0.insert(gridX: gridX, gridY: gridY, worldRect: worldRect) }
            return
        }
        items.append((worldRect, gridX, gridY))
        if items.count > Self.maxItems, depth < Self.maxDepth { subdivide() }
    }

    // MARK: - Query

    /// Returns all (gridX, gridY) whose world rect overlaps `worldRect`.
    func query(worldRect: CGRect) -> [(x: Int, y: Int)] {
        guard bounds.intersects(worldRect) else { return [] }
        if let ch = children { return ch.flatMap { $0.query(worldRect: worldRect) } }
        return items.filter { $0.rect.intersects(worldRect) }.map { ($0.x, $0.y) }
    }

    // MARK: - Debug

    /// All node bounds (for gizmo rendering).
    var allNodeBounds: [CGRect] {
        var result = [bounds]
        children?.forEach { result += $0.allNodeBounds }
        return result
    }

    // MARK: - Private

    private func subdivide() {
        let hw = bounds.width / 2, hh = bounds.height / 2
        children = [
            Quadtree(bounds: CGRect(x: bounds.minX, y: bounds.minY, width: hw, height: hh), depth: depth+1),
            Quadtree(bounds: CGRect(x: bounds.midX, y: bounds.minY, width: hw, height: hh), depth: depth+1),
            Quadtree(bounds: CGRect(x: bounds.minX, y: bounds.midY, width: hw, height: hh), depth: depth+1),
            Quadtree(bounds: CGRect(x: bounds.midX, y: bounds.midY, width: hw, height: hh), depth: depth+1),
        ]
        let old = items; items.removeAll()
        old.forEach { item in children!.forEach { $0.insert(gridX: item.x, gridY: item.y, worldRect: item.rect) } }
    }
}
