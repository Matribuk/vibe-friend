import AppKit

/// Manages one PetInstance per running claude process.
final class PetController {

    private let claudeDetector = ClaudeDetector()
    private var instances: [Int32: PetInstance] = [:]
    private var pollTimer: Timer?
    private var nextHue: CGFloat = CGFloat.random(in: 0...1)

    // MARK: - Lifecycle

    func start() {
        claudeDetector.onEvent = { [weak self] event in
            self?.handleClaudeEvent(event)
        }
        claudeDetector.start()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 10.0, repeats: true) { [weak self] _ in
            self?.instances.values.forEach { $0.update() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        claudeDetector.stop()
        instances.values.forEach { $0.animTimer?.invalidate() }
        instances.removeAll()
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
                let startX = screen.visibleFrame.midX
                let tint = nextHue
                nextHue = (nextHue + 0.618).truncatingRemainder(dividingBy: 1.0)
                instances[pid] = PetInstance(pid: pid, ttyPath: ttyPath, startX: startX, tintHue: tint)
            }

            for pid in known.subtracting(current) {
                instances[pid]?.fadeOut { [weak self] in
                    self?.instances.removeValue(forKey: pid)
                }
            }

        case .allStopped:
            instances.values.forEach { $0.fadeOut {} }
            instances.removeAll()
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
