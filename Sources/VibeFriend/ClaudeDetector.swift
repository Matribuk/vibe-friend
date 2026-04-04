import Foundation

// Schedules a timer in .common mode so it fires during menu tracking too.
func makeCommonTimer(withTimeInterval interval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer {
    let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
    RunLoop.main.add(timer, forMode: .common)
    return timer
}

final class ClaudeDetector {

    enum Event {
        case running(pids: [Int32])
        case allStopped
    }

    // Native binary names matched against `comm`.
    private let nativeTargets: Set<String> = [
        "claude",    // Anthropic Claude Code
        "codex",     // OpenAI Codex CLI
        "goose",     // Block Goose
        "opencode",  // OpenCode
        "cline",     // Cline
        "claw",      // Claw Code
    ]

    // Tools that run inside an interpreter — matched against the script path in args.
    private let interpretedTargets: Set<String> = [
        "gemini",    // Google Gemini CLI (Node.js)
        "aider",     // Aider (Python)
    ]

    // Interpreter binary names that may wrap an interpreted target.
    private let interpreters: Set<String> = ["node", "python3", "python"]

    var onEvent: ((Event) -> Void)?

    private var timer: Timer?
    private var knownPIDs: Set<Int32> = []
    private var isPolling = false

    func start() {
        poll()
        timer = makeCommonTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func poll() {
        guard !isPolling else { return }
        isPolling = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let pids = self.agentPIDs()
            DispatchQueue.main.async {
                self.isPolling = false
                let current = Set(pids)
                if !current.isEmpty {
                    self.onEvent?(.running(pids: current.sorted()))
                } else if !self.knownPIDs.isEmpty {
                    self.onEvent?(.allStopped)
                }
                self.knownPIDs = current
            }
        }
    }

    // Step 1: fast scan with `comm` for native binaries.
    // Step 2: for interpreter processes (node/python), check their args for interpreted targets.
    private func agentPIDs() -> [Int32] {
        let allProcs = runPS(["-eo", "pid,comm"])
        var results: [Int32] = []
        var interpreterPIDs: [Int32] = []

        for line in allProcs.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
            let name = (String(parts[1]) as NSString).lastPathComponent
            if nativeTargets.contains(name) {
                results.append(pid)
            } else if interpreters.contains(name) {
                interpreterPIDs.append(pid)
            }
        }

        // For each interpreter process, fetch its args individually (avoids bulk args scan hanging).
        // Group by detected tool name — keep only the lowest PID (main process) per tool.
        var interpretedByTool: [String: Int32] = [:]
        for pid in interpreterPIDs.sorted() {
            let args = runPS(["-o", "args=", "-p", "\(pid)"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let words = args.split(separator: " ")
            for word in words.dropFirst() {
                let script = (String(word) as NSString).lastPathComponent
                if interpretedTargets.contains(script) {
                    if interpretedByTool[script] == nil {
                        interpretedByTool[script] = pid
                    }
                    break
                }
            }
        }
        results.append(contentsOf: interpretedByTool.values)

        return results
    }

    private func runPS(_ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run(); task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
