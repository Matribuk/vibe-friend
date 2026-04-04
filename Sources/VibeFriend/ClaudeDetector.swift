import Foundation

final class ClaudeDetector {

    enum Event {
        case running(pids: [Int32])
        case allStopped
    }

    // All AI coding CLI tools to track.
    private let targets: Set<String> = [
        "claude",    // Anthropic Claude Code
        "gemini",    // Google Gemini CLI
        "codex",     // OpenAI Codex CLI
        "aider",     // Aider
        "goose",     // Block Goose
        "opencode",  // OpenCode
        "cline",     // Cline
        "claw",      // Claw Code (open-source reimplementation)
    ]

    var onEvent: ((Event) -> Void)?

    private var timer: Timer?
    private var knownPIDs: Set<Int32> = []

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func poll() {
        let current = Set(agentPIDs())

        if !current.isEmpty {
            onEvent?(.running(pids: current.sorted()))
        } else if !knownPIDs.isEmpty {
            onEvent?(.allStopped)
        }

        knownPIDs = current
    }

    // Uses ps to find running agent PIDs (NSWorkspace only sees GUI apps, not CLI tools).
    private func agentPIDs() -> [Int32] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-eo", "pid,comm"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run(); task.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let pid = Int32(parts[0]) else { return nil }
            let comm = parts[1].trimmingCharacters(in: .whitespaces)
            let name = (comm as NSString).lastPathComponent
            return targets.contains(name) ? pid : nil
        }
    }
}
