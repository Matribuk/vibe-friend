import AppKit

/// Shared dock detection used by both PetInstance and PetController.
struct DockLayout {
    let minX: CGFloat
    let maxX: CGFloat
    let floorY: CGFloat
    /// True when the dock is visible at the bottom (as opposed to hidden / side-mounted).
    let dockAtBottom: Bool
}

func computeDockLayout(petWidth: CGFloat = 0) -> DockLayout {
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let sw = screen.frame.width
    let sh = screen.frame.height
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return DockLayout(minX: screen.frame.minX,
                          maxX: screen.frame.maxX - petWidth,
                          floorY: screen.visibleFrame.minY,
                          dockAtBottom: false)
    }

    for dict in list {
        guard let owner = dict[kCGWindowOwnerName as String] as? String, owner == "Dock",
              let bd = dict[kCGWindowBounds as String] as? NSDictionary else { continue }
        var r = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(bd, &r) else { continue }

        // Bottom dock
        if r.width >= sw * 0.3 && (r.origin.y + r.height) >= sh * 0.8 {
            if let (dMinX, dMaxX) = dockIconArea(screenWidth: sw) {
                return DockLayout(minX: dMinX, maxX: dMaxX - petWidth,
                                  floorY: screen.visibleFrame.minY,
                                  dockAtBottom: true)
            }
            return DockLayout(minX: r.origin.x, maxX: r.origin.x + r.width - petWidth,
                              floorY: screen.visibleFrame.minY,
                              dockAtBottom: true)
        }

        // Side dock
        if r.height >= sh * 0.3 {
            return DockLayout(minX: screen.visibleFrame.minX,
                              maxX: screen.visibleFrame.maxX - petWidth,
                              floorY: screen.frame.minY,
                              dockAtBottom: false)
        }
    }

    return DockLayout(minX: screen.frame.minX,
                      maxX: screen.frame.maxX - petWidth,
                      floorY: screen.frame.minY,
                      dockAtBottom: false)
}

private func dockIconArea(screenWidth: CGFloat) -> (CGFloat, CGFloat)? {
    guard let prefs = UserDefaults(suiteName: "com.apple.dock") else { return nil }
    let tileSize = prefs.double(forKey: "tilesize")
    guard tileSize > 0 else { return nil }

    let slotWidth = tileSize * 1.25
    let apps   = (prefs.array(forKey: "persistent-apps")   as? [[String: Any]])?.count ?? 0
    let others = (prefs.array(forKey: "persistent-others") as? [[String: Any]])?.count ?? 0
    let recent = prefs.integer(forKey: "RecentApps")

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
