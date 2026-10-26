import Foundation
import Darwin

/// 按进程计算 CPU 占用率：两次采样之间的 CPU 时间增量 ÷ 墙钟时间增量（100% = 占满一个核心）。
/// 只在后台刷新线程调用，内部加锁以防并发。
public final class CpuUsageSampler {
    public static let shared = CpuUsageSampler()

    private struct Sample {
        let cpuSeconds: Double
        let uptime: TimeInterval
        let percent: Double?
    }

    /// 两次采样间隔太短时沿用上次结果，避免抖动
    private static let minInterval: TimeInterval = 0.5
    /// 间隔太长（例如面板长时间隐藏）时数据不再有参考意义，重新开始采样
    private static let maxInterval: TimeInterval = 10
    private static let maxTrackedProcesses = 4096

    private let lock = NSLock()
    private var samples: [pid_t: Sample] = [:]
    private let timebase: mach_timebase_info_data_t

    private init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        timebase = info
    }

    /// 进程的 CPU 占用百分比；第一次采样或间隔不合适时返回 nil
    public func usage(pid: pid_t) -> Double? {
        guard let cpuSeconds = cumulativeCpuSeconds(pid: pid) else { return nil }
        let now = ProcessInfo.processInfo.systemUptime

        lock.lock()
        defer { lock.unlock() }

        if samples.count > Self.maxTrackedProcesses {
            samples.removeAll(keepingCapacity: true)
        }

        guard let last = samples[pid] else {
            samples[pid] = Sample(cpuSeconds: cpuSeconds, uptime: now, percent: nil)
            return nil
        }

        let elapsed = now - last.uptime
        if elapsed < Self.minInterval {
            return last.percent
        }
        guard elapsed <= Self.maxInterval else {
            samples[pid] = Sample(cpuSeconds: cpuSeconds, uptime: now, percent: nil)
            return nil
        }

        let percent = max(0, (cpuSeconds - last.cpuSeconds) / elapsed * 100)
        samples[pid] = Sample(cpuSeconds: cpuSeconds, uptime: now, percent: percent)
        return percent
    }

    /// 进程累计的用户态 + 内核态 CPU 时间（秒）。rusage 中的时间单位是 mach 绝对时间，需要换算。
    private func cumulativeCpuSeconds(pid: pid_t) -> Double? {
        guard let usage = ProcessInspector.rusageInfo(pid: pid) else { return nil }
        let ticks = Double(usage.ri_user_time &+ usage.ri_system_time)
        return ticks * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }
}
