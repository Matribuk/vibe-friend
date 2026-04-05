import AppKit

final class IdleMonitor {

    var onIdle: (() -> Void)?
    var onActive: (() -> Void)?

    var threshold: TimeInterval
    private var lastActivity: Date = .now
    private var checkTimer: Timer?
    private var monitors: [Any] = []
    private(set) var isIdle = false

    init(threshold: TimeInterval = 30) {
        self.threshold = threshold
    }

    func start() {
        lastActivity = .now
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .keyDown, .scrollWheel, .leftMouseDragged
        ]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.recordActivity()
        }) { monitors.append(m) }

        checkTimer = makeCommonTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkIdle()
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func recordActivity() {
        lastActivity = .now
        guard isIdle else { return }
        isIdle = false
        onActive?()
    }

    private func checkIdle() {
        guard !isIdle, Date.now.timeIntervalSince(lastActivity) >= threshold else { return }
        isIdle = true
        onIdle?()
    }
}
