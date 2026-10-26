import Foundation
import Darwin

// MARK: - 进程快照

/// 一次刷新内采集到的单个进程信息（仅当前登录用户）
public struct ProcessEntry {
    public let pid: pid_t
    public let ppid: pid_t
    public let path: String
    /// 进程启动时间（微秒），用于防止 PID 被系统复用后误杀其他进程
    public let startTime: UInt64
}

/// 底层进程查询工具（libproc / sysctl），均可在后台线程调用
public enum ProcessInspector {

    /// 采集当前用户的全部进程。每次刷新只调用一次，供应用内存聚合与终端服务识别共用。
    public static func snapshot() -> [ProcessEntry] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
        let capacity = Int(needed) / MemoryLayout<pid_t>.size + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(capacity * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        let count = min(capacity, Int(bytes) / MemoryLayout<pid_t>.size)

        let uid = getuid()
        let selfPid = getpid()
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        var result: [ProcessEntry] = []
        result.reserveCapacity(count)

        for i in 0..<count {
            let pid = pids[i]
            if pid <= 0 || pid == selfPid { continue }
            guard let info = bsdInfo(pid), info.pbi_uid == uid else { continue }
            let len = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            guard len > 0 else { continue }
            result.append(ProcessEntry(
                pid: pid,
                ppid: pid_t(info.pbi_ppid),
                path: String(cString: pathBuffer),
                startTime: startTime(from: info)
            ))
        }
        return result
    }

    static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        return ret == size ? info : nil
    }

    private static func startTime(from info: proc_bsdinfo) -> UInt64 {
        return UInt64(info.pbi_start_tvsec) * 1_000_000 + UInt64(info.pbi_start_tvusec)
    }

    /// 进程启动时间（微秒）
    public static func startTime(of pid: pid_t) -> UInt64? {
        guard let info = bsdInfo(pid) else { return nil }
        return startTime(from: info)
    }

    /// 进程是否仍存活；传入 startTime 时还会校验是不是「同一个」进程（防 PID 复用）
    public static func isAlive(pid: pid_t, startTime expected: UInt64?) -> Bool {
        guard let info = bsdInfo(pid) else {
            // 拿不到信息时用 kill(0) 兜底判断
            if kill(pid, 0) == 0 { return true }
            return errno == EPERM
        }
        if let expected = expected {
            return startTime(from: info) == expected
        }
        return true
    }

    /// 读取进程的 rusage_info_v2（内存与 CPU 时间共用）
    static func rusageInfo(pid: pid_t) -> rusage_info_v2? {
        var usage = rusage_info_v2()
        let ret = withUnsafeMutablePointer(to: &usage) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V2, rebound)
            }
        }
        return ret == 0 ? usage : nil
    }

    /// 与「活动监视器 → 内存」一致的口径 (phys_footprint)；失败时回退到常驻内存 RSS
    public static func memoryFootprint(pid: pid_t) -> UInt64? {
        if let usage = rusageInfo(pid: pid) {
            return usage.ri_phys_footprint
        }

        var taskInfo = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size) == size {
            return taskInfo.pti_resident_size
        }
        return nil
    }

    /// 读取完整命令行参数 (KERN_PROCARGS2)
    public static func arguments(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        if sysctl(&mib, 3, nil, &size, nil, 0) != 0 || size <= MemoryLayout<Int32>.size {
            return nil
        }
        // 多分配 1 字节并置 0，保证任何情况下 String(cString:) 都不会越界
        var buffer = [CChar](repeating: 0, count: size + 1)
        if sysctl(&mib, 3, &buffer, &size, nil, 0) != 0 {
            return nil
        }
        let total = min(size, buffer.count - 1)
        buffer[total] = 0

        return buffer.withUnsafeBufferPointer { ptr -> [String]? in
            guard let base = ptr.baseAddress else { return nil }
            var argc: Int32 = 0
            memcpy(&argc, base, MemoryLayout<Int32>.size)
            var offset = MemoryLayout<Int32>.size
            // 跳过可执行文件路径及其后的填充 0
            while offset < total && base[offset] != 0 { offset += 1 }
            while offset < total && base[offset] == 0 { offset += 1 }

            var args: [String] = []
            var index: Int32 = 0
            while index < argc && offset < total {
                let str = String(cString: base + offset)
                args.append(str)
                offset += str.utf8.count + 1
                index += 1
            }
            return args
        }
    }
}

// MARK: - 终端 / AI 服务识别

public struct CliServiceRule {
    public let name: String
    /// 可执行文件名完全匹配（小写）
    public let execNames: Set<String>
    /// 可执行文件路径包含（小写），用于 Claude Code 原生安装 (~/.local/share/claude/versions/x.y.z)
    public let pathPatterns: [String]
    /// 仅对 node / python 等解释器进程检查的命令行特征（小写）
    public let commandPatterns: [String]
    /// 支持「重启」的子命令（目前只有 `ollama serve` 能可靠地自行拉起）
    public let restartableSubcommand: String?

    public init(
        name: String,
        execNames: Set<String> = [],
        pathPatterns: [String] = [],
        commandPatterns: [String] = [],
        restartableSubcommand: String? = nil
    ) {
        self.name = name
        self.execNames = execNames
        self.pathPatterns = pathPatterns
        self.commandPatterns = commandPatterns
        self.restartableSubcommand = restartableSubcommand
    }
}

public final class CliProcessScanner {
    public static let shared = CliProcessScanner()

    private let rules: [CliServiceRule] = [
        // 1. 本地大模型与推理服务
        CliServiceRule(name: "Ollama", execNames: ["ollama"], restartableSubcommand: "serve"),
        CliServiceRule(name: "vLLM Server", execNames: ["vllm"], commandPatterns: ["vllm.entrypoints", "/bin/vllm "]),
        CliServiceRule(name: "Llama Server", execNames: ["llama-server"]),
        CliServiceRule(name: "LocalAI", execNames: ["local-ai", "localai"]),

        // 2. TUI / CLI AI 编程助手
        CliServiceRule(
            name: "Claude Code",
            execNames: ["claude"],
            pathPatterns: ["/claude/versions/"],
            commandPatterns: ["@anthropic-ai/claude-code", "claude-code/cli.js"]
        ),
        CliServiceRule(name: "Codex CLI", execNames: ["codex"], commandPatterns: ["@openai/codex"]),
        CliServiceRule(name: "Gemini CLI", execNames: ["gemini"], commandPatterns: ["@google/gemini-cli"]),
        CliServiceRule(name: "Kimi Code", execNames: ["kimi"], commandPatterns: ["kimi-cli", "kimi_cli", "kimi-code"]),
        CliServiceRule(name: "Pi Agent", execNames: ["pi", "pi-agent"], commandPatterns: ["pi-coding-agent", "pi-agent", "pi_agent"]),
        CliServiceRule(name: "Aider AI", execNames: ["aider"], commandPatterns: ["/bin/aider", "-m aider"]),
        CliServiceRule(name: "Open Interpreter", execNames: ["interpreter"], commandPatterns: ["/bin/interpreter", "open-interpreter"]),

        // 3. 常用开发者常驻服务（多进程服务会自动合并为一行）
        CliServiceRule(name: "Redis", execNames: ["redis-server"]),
        CliServiceRule(name: "PostgreSQL", execNames: ["postgres", "postmaster"]),
        CliServiceRule(name: "MySQL", execNames: ["mysqld"]),
        CliServiceRule(name: "MongoDB", execNames: ["mongod"]),
        CliServiceRule(name: "Nginx", execNames: ["nginx"])
    ]

    private init() {}

    private func isInterpreter(_ execName: String) -> Bool {
        return execName == "node" || execName == "bun" || execName == "deno" ||
               execName.hasPrefix("python")
    }

    private func matchRule(execName: String, lowerPath: String, pid: pid_t, args: inout [String]?) -> CliServiceRule? {
        if let rule = rules.first(where: { $0.execNames.contains(execName) }) {
            return rule
        }
        if let rule = rules.first(where: { r in r.pathPatterns.contains(where: { lowerPath.contains($0) }) }) {
            return rule
        }
        // 只有解释器进程才需要读取命令行（sysctl 开销较大）
        guard isInterpreter(execName) else { return nil }
        if args == nil {
            args = ProcessInspector.arguments(pid: pid)
        }
        guard let list = args else { return nil }
        let cmd = list.joined(separator: " ").lowercased()
        return rules.first(where: { r in r.commandPatterns.contains(where: { cmd.contains($0) }) })
    }

    /// 从进程快照中识别终端 / AI 常驻服务。
    /// 同一服务的子进程（如 postgres worker、ollama runner）会合并到最上层父进程，内存一并累加。
    public func scanActiveCliServices(in processes: [ProcessEntry]) -> [AppItem] {
        struct Match {
            let entry: ProcessEntry
            let rule: CliServiceRule
            let args: [String]?
        }

        var matches: [pid_t: Match] = [:]
        var parentOf: [pid_t: pid_t] = [:]

        for entry in processes {
            parentOf[entry.pid] = entry.ppid
            let lowerPath = entry.path.lowercased()
            // .app 内的进程属于图形应用，由「菜单栏 / 窗口应用」分组负责（内存会聚合到对应应用上）
            if lowerPath.contains(".app/") { continue }
            let execName = (lowerPath as NSString).lastPathComponent
            var args: [String]? = nil
            if let rule = matchRule(execName: execName, lowerPath: lowerPath, pid: entry.pid, args: &args) {
                matches[entry.pid] = Match(entry: entry, rule: rule, args: args)
            }
        }

        // 找到每个匹配进程最上层的同类祖先
        func rootPid(of pid: pid_t, ruleName: String) -> pid_t {
            var root = pid
            var current = pid
            var depth = 0
            while depth < 16, let parent = parentOf[current], parent > 1 {
                if let m = matches[parent], m.rule.name == ruleName {
                    root = parent
                }
                current = parent
                depth += 1
            }
            return root
        }

        var memoryByRoot: [pid_t: UInt64] = [:]
        var cpuByRoot: [pid_t: Double] = [:]
        var childCountByRoot: [pid_t: Int] = [:]
        for (pid, match) in matches {
            let root = rootPid(of: pid, ruleName: match.rule.name)
            memoryByRoot[root, default: 0] += ProcessInspector.memoryFootprint(pid: pid) ?? 0
            if let cpu = CpuUsageSampler.shared.usage(pid: pid) {
                cpuByRoot[root, default: 0] += cpu
            }
            if root != pid {
                childCountByRoot[root, default: 0] += 1
            }
        }

        var results: [AppItem] = []
        for (root, totalMemory) in memoryByRoot {
            guard let match = matches[root] else { continue }
            let args = match.args ?? ProcessInspector.arguments(pid: root) ?? []
            let fullCmd = args.isEmpty ? match.entry.path : args.joined(separator: " ")
            let subcommand = args.dropFirst().first?.lowercased()

            var displayName = match.rule.name
            if match.rule.name == "Ollama", let sub = subcommand, !sub.hasPrefix("-") {
                displayName += " (\(sub))"
            }
            let canRestart = match.rule.restartableSubcommand != nil && subcommand == match.rule.restartableSubcommand

            let shortCmd = fullCmd.count > 60 ? String(fullCmd.prefix(57)) + "..." : fullCmd

            results.append(AppItem(
                pid: root,
                bundleId: "cli.\(match.rule.name.lowercased().replacingOccurrences(of: " ", with: "_"))",
                name: displayName,
                bundleURL: URL(fileURLWithPath: match.entry.path),
                isRunning: true,
                isAccessory: true,
                isCliProcess: true,
                commandLine: shortCmd,
                fullCommandLine: fullCmd,
                memoryBytes: totalMemory > 0 ? totalMemory : nil,
                cpuPercent: cpuByRoot[root],
                processCount: 1 + (childCountByRoot[root] ?? 0),
                processStartTime: match.entry.startTime,
                canRestart: canRestart
            ))
        }
        return results
    }
}
