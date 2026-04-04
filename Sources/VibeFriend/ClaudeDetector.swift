import Foundation
import Darwin

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

    // Step 1: fast sysctl scan — uses p_comm first, then KERN_PROCARGS2 for the real executable
    //         name when p_comm looks non-standard (e.g. claude sets p_comm to its version string).
    // Step 2: for interpreter processes (node/python), check their args via ps (per-PID, fast).
    private func agentPIDs() -> [Int32] {
        let allProcs = sysctlProcessList()
        var results: [Int32] = []
        var interpreterPIDs: [Int32] = []

        for (pid, comm) in allProcs {
            // comm might be the real name, or it might be something set by the process (e.g. "2.1.92").
            // Fall back to the executable basename from KERN_PROCARGS2 when needed.
            let name: String
            if nativeTargets.contains(comm) || interpreters.contains(comm) {
                name = comm
            } else {
                // Check actual executable path for processes with non-standard p_comm.
                name = executableBasename(for: pid) ?? comm
            }

            if nativeTargets.contains(name) {
                results.append(pid)
            } else if interpreters.contains(name) {
                interpreterPIDs.append(pid)
            }
        }

        // For each interpreter process, fetch its args individually.
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

    // Returns [(pid, p_comm)] for all running processes using sysctl — no subprocess, no hang risk.
    private func sysctlProcessList() -> [(Int32, String)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }

        return procs.compactMap { p -> (Int32, String)? in
            let pid = p.kp_proc.p_pid
            guard pid > 0 else { return nil }
            var comm = p.kp_proc.p_comm
            let name = withUnsafePointer(to: &comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) {
                    String(cString: $0)
                }
            }
            return (pid, name)
        }
    }

    // Returns the last component of the executable path for a PID via KERN_PROCARGS2.
    // This is the real binary name even when the process has changed its p_comm.
    private func executableBasename(for pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
        // Format: [int argc][null-terminated executable path][args...]
        let path = buf.withUnsafeBufferPointer { ptr in
            String(cString: ptr.baseAddress!.advanced(by: MemoryLayout<Int32>.size))
        }
        guard !path.isEmpty else { return nil }
        return (path as NSString).lastPathComponent
    }

    private func runPS(_ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return "" }

        // Read with a 3-second timeout to guard against any hung process.
        var output = ""
        let sema = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            sema.signal()
        }
        if sema.wait(timeout: .now() + 3) == .timedOut {
            task.terminate()
        } else {
            task.waitUntilExit()
        }
        return output
    }
}
