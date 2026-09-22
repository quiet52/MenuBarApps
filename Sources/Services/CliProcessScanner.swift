import Foundation
import Darwin

public struct CliServiceRule {
    public let defaultName: String
    public let iconName: String
    public let match: (String, String) -> Bool
    
    public init(defaultName: String, iconName: String = "sparkles", match: @escaping (String, String) -> Bool) {
        self.defaultName = defaultName
        self.iconName = iconName
        self.match = match
    }
}

public final class CliProcessScanner {
    public static let shared = CliProcessScanner()
    
    private let rules: [CliServiceRule] = [
        // 1. 本地大模型与推理服务
        CliServiceRule(defaultName: "Ollama", iconName: "sparkles") { exec, cmd in
            exec == "ollama" || cmd.contains("ollama serve") || cmd.contains("ollama run")
        },
        CliServiceRule(defaultName: "vLLM Server", iconName: "cpu") { exec, cmd in
            exec.contains("vllm") || cmd.contains("vllm.entrypoints")
        },
        CliServiceRule(defaultName: "Llama Server", iconName: "cpu") { exec, cmd in
            exec.contains("llama-server") || exec.contains("llama.cpp") || cmd.contains("llama-server")
        },
        CliServiceRule(defaultName: "LocalAI", iconName: "cpu") { exec, cmd in
            exec.contains("local-ai") || exec.contains("localai") || cmd.contains("local-ai")
        },
        
        // 2. 流行 TUI / CLI AI 智能体与编程助手
        CliServiceRule(defaultName: "Claude Code", iconName: "sparkles") { exec, cmd in
            exec == "claude" || exec == "claude-code" || cmd.contains("claude-code") ||
            cmd.contains("@anthropic-ai/claude-code") || (exec.contains("node") && cmd.contains("claude"))
        },
        CliServiceRule(defaultName: "Kimi Code", iconName: "sparkles") { exec, cmd in
            exec.contains("kimi") || cmd.contains("kimi-code") || cmd.contains("kimi code") || (exec.contains("node") && cmd.contains("kimi"))
        },
        CliServiceRule(defaultName: "Pi Agent", iconName: "sparkles") { exec, cmd in
            exec == "pi" || exec == "pi-agent" || exec == "pi_agent" ||
            cmd.contains("pi-agent") || cmd.contains("pi agent") || cmd.contains("pi_agent") || (exec.contains("python") && cmd.contains("pi_agent"))
        },
        CliServiceRule(defaultName: "Aider AI", iconName: "sparkles") { exec, cmd in
            exec == "aider" || cmd.contains("aider") || (exec.contains("python") && cmd.contains("aider"))
        },
        CliServiceRule(defaultName: "Open Interpreter", iconName: "sparkles") { exec, cmd in
            exec == "interpreter" || cmd.contains("open-interpreter")
        },
        
        // 3. 常用开发者常驻后台服务
        CliServiceRule(defaultName: "Redis", iconName: "externaldrive.fill") { exec, _ in
            exec == "redis-server"
        },
        CliServiceRule(defaultName: "PostgreSQL", iconName: "externaldrive.fill") { exec, _ in
            exec == "postgres"
        },
        CliServiceRule(defaultName: "Nginx", iconName: "network") { exec, _ in
            exec == "nginx"
        }
    ]
    
    private init() {}
    
    public func scanActiveCliServices() -> [AppItem] {
        var pids = [pid_t](repeating: 0, count: 2048)
        let bytesUsed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        guard bytesUsed > 0 else { return [] }
        let count = Int(bytesUsed) / MemoryLayout<pid_t>.size
        
        let currentPid = getpid()
        let currentUid = getuid()
        var results: [AppItem] = []
        
        for i in 0..<count {
            let pid = pids[i]
            if pid <= 0 || pid == currentPid { continue }
            
            // 快速校验所属用户 (仅扫描当前登录用户的常驻进程)
            var bsdInfo = proc_bsdinfo()
            let bsdLen = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.stride))
            if bsdLen == Int32(MemoryLayout<proc_bsdinfo>.stride) {
                if bsdInfo.pbi_uid != currentUid { continue }
            }
            
            // 获取可执行文件路径
            var pathBuffer = [CChar](repeating: 0, count: 4096)
            let len = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            if len <= 0 { continue }
            let path = String(cString: pathBuffer)
            let execName = (path as NSString).lastPathComponent.lowercased()
            
            // 候选粗筛（优化 CPU 开销）
            let isCandidate = execName.contains("ollama") || execName.contains("claude") ||
                              execName.contains("kimi") || execName.contains("pi") ||
                              execName.contains("aider") || execName.contains("node") ||
                              execName.contains("python") || execName.contains("redis") ||
                              execName.contains("postgres") || execName.contains("nginx") ||
                              execName.contains("vllm") || execName.contains("llama") ||
                              execName.contains("interpreter")
            if !isCandidate { continue }
            
            // 获取完整命令行参数
            guard let rawCmdLine = getCommandLine(pid: pid) else { continue }
            let lowerCmdLine = rawCmdLine.lowercased()
            
            // 细粒度规则匹配
            for rule in rules {
                if rule.match(execName, lowerCmdLine) {
                    let mem = AppManager.getMemoryUsage(pid: pid)
                    
                    var displayName = rule.defaultName
                    if lowerCmdLine.contains("serve") {
                        displayName += " (serve)"
                    }
                    
                    let shortCmd = rawCmdLine.count > 55 ? String(rawCmdLine.prefix(52)) + "..." : rawCmdLine
                    
                    let item = AppItem(
                        pid: pid,
                        bundleId: "cli.\(rule.defaultName.lowercased().replacingOccurrences(of: " ", with: "_"))",
                        name: displayName,
                        bundleURL: URL(fileURLWithPath: path),
                        isRunning: true,
                        isAccessory: true,
                        isCliProcess: true,
                        commandLine: shortCmd,
                        memoryBytes: mem
                    )
                    results.append(item)
                    break
                }
            }
        }
        
        return results
    }
    
    private func getCommandLine(pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        if sysctl(&mib, 3, nil, &size, nil, 0) != 0 || size <= 0 {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        if sysctl(&mib, 3, &buffer, &size, nil, 0) != 0 {
            return nil
        }
        return buffer.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return nil }
            var argc: Int32 = 0
            memcpy(&argc, base, MemoryLayout<Int32>.size)
            var offset = MemoryLayout<Int32>.size
            while offset < size && base[offset] != 0 { offset += 1 }
            while offset < size && base[offset] == 0 { offset += 1 }
            var args: [String] = []
            for _ in 0..<argc {
                if offset >= size { break }
                let str = String(cString: base + offset)
                args.append(str)
                offset += str.utf8.count + 1
            }
            return args.joined(separator: " ")
        }
    }
}
