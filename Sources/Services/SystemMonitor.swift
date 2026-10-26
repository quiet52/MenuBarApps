import Foundation
import Darwin
import IOKit

/// 系统资源概览：CPU、内存、GPU、网速。
/// 采样只在「面板可见」或「菜单栏显示网速」时进行，两者都关闭时不占用任何资源。
public final class SystemMonitor: ObservableObject {
    public static let shared = SystemMonitor()

    @Published public private(set) var cpuUsage: Double?
    @Published public private(set) var memoryUsedBytes: UInt64?
    @Published public private(set) var memoryTotalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published public private(set) var gpuUsage: Double?
    @Published public private(set) var downloadBytesPerSec: Double?
    @Published public private(set) var uploadBytesPerSec: Double?

    /// 菜单栏上显示的紧凑网速文本（如 "↓1.2M ↑340K"），未开启或尚无数据时为 nil
    @Published public private(set) var menuBarSpeedText: String?

    @Published public var isExpanded: Bool {
        didSet { UserDefaults.standard.set(isExpanded, forKey: Self.expandedKey) }
    }

    /// 是否在菜单栏图标旁显示实时网速（默认关闭）
    @Published public var showsSpeedInMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showsSpeedInMenuBar, forKey: Self.menuBarSpeedKey)
            if !showsSpeedInMenuBar {
                menuBarSpeedText = nil
            }
            updateTimerState()
        }
    }

    private static let expandedKey = "com.quiet52.MenuBarApps.systemOverviewExpanded"
    private static let menuBarSpeedKey = "com.quiet52.MenuBarApps.menuBarSpeed"
    private static let sampleInterval: TimeInterval = 1.0

    private var timer: Timer?
    private var isPanelVisible = false
    private var lastCPUTicks: (busy: UInt64, total: UInt64)?
    private var lastNetworkCounters: [String: (rx: UInt32, tx: UInt32)]?
    private var lastSampleDate: Date?

    private init() {
        isExpanded = UserDefaults.standard.object(forKey: Self.expandedKey) as? Bool ?? true
        showsSpeedInMenuBar = UserDefaults.standard.bool(forKey: Self.menuBarSpeedKey)
    }

    // MARK: - 启停

    public func setPanelVisible(_ visible: Bool) {
        isPanelVisible = visible
        updateTimerState()
    }

    private func updateTimerState() {
        if isPanelVisible || showsSpeedInMenuBar {
            startTimer()
        } else {
            stopTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        lastCPUTicks = nil
        lastNetworkCounters = nil
        lastSampleDate = nil
        sample()

        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 采样

    private func sample() {
        let now = Date()
        let elapsed = lastSampleDate.map { now.timeIntervalSince($0) } ?? 0
        lastSampleDate = now

        cpuUsage = sampleCPU()
        memoryUsedBytes = sampleMemoryUsed()
        gpuUsage = sampleGPU()

        let counters = sampleNetworkCounters()
        if let previous = lastNetworkCounters, let counters, elapsed > 0 {
            var received: UInt64 = 0
            var sent: UInt64 = 0
            for (name, current) in counters {
                guard let old = previous[name] else { continue }
                // 接口计数是 32 位，会回绕，用无符号减法求差值
                received += UInt64(current.rx &- old.rx)
                sent += UInt64(current.tx &- old.tx)
            }
            downloadBytesPerSec = Double(received) / elapsed
            uploadBytesPerSec = Double(sent) / elapsed
        } else {
            downloadBytesPerSec = nil
            uploadBytesPerSec = nil
        }
        lastNetworkCounters = counters

        menuBarSpeedText = showsSpeedInMenuBar
            ? Self.formatMenuBarSpeed(download: downloadBytesPerSec, upload: uploadBytesPerSec)
            : nil
    }

    /// 所有核心合计的占用率，两次采样求差值。第一次采样返回 nil。
    private func sampleCPU() -> Double? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let ticks = info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: ticks)), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var busy: UInt64 = 0
        var total: UInt64 = 0
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * Int(CPU_STATE_MAX)
            let user = UInt64(ticks[base + Int(CPU_STATE_USER)])
            let system = UInt64(ticks[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(ticks[base + Int(CPU_STATE_NICE)])
            let idle = UInt64(ticks[base + Int(CPU_STATE_IDLE)])
            busy += user + system + nice
            total += user + system + nice + idle
        }

        defer { lastCPUTicks = (busy, total) }
        guard let last = lastCPUTicks, total > last.total else { return nil }
        return Double(busy - last.busy) / Double(total - last.total)
    }

    /// 已用内存 = 应用内存 + 联动内存(wired) + 压缩内存，与活动监视器的口径一致。
    private func sampleMemoryUsed() -> UInt64? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let page = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let appPages = internalPages > purgeable ? internalPages - purgeable : 0
        let wired = UInt64(stats.wire_count)
        let compressed = UInt64(stats.compressor_page_count)
        return (appPages + wired + compressed) * page
    }

    /// 取所有 IOAccelerator 中最忙的一个设备的利用率（Apple Silicon 上为 GPU 占用）。非公开接口，取不到返回 nil。
    private func sampleGPU() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var busiest: Double?
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = properties?.takeRetainedValue() as? [String: Any],
                  let stats = dict["PerformanceStatistics"] as? [String: Any],
                  let utilization = stats["Device Utilization %"] as? NSNumber else {
                continue
            }
            busiest = max(busiest ?? 0, utilization.doubleValue / 100)
        }
        return busiest
    }

    /// 物理网卡（en*）的收发字节计数，按接口分别记录，便于逐个求差值。
    private func sampleNetworkCounters() -> [String: (rx: UInt32, tx: UInt32)]? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var counters: [String: (rx: UInt32, tx: UInt32)] = [:]
        for ifa in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard ifa.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.pointee.ifa_data else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            counters[name] = (stats.ifi_ibytes, stats.ifi_obytes)
        }
        return counters
    }

    // MARK: - 菜单栏文本

    /// 例如 "↓1.2M ↑340K"；任一速率缺失时返回 nil
    static func formatMenuBarSpeed(download: Double?, upload: Double?) -> String? {
        guard let download, let upload else { return nil }
        return "↓\(compactRate(download)) ↑\(compactRate(upload))"
    }

    private static func compactRate(_ bytesPerSec: Double) -> String {
        let units = ["B", "K", "M", "G"]
        var value = bytesPerSec
        var index = 0
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        let number = String(format: value < 10 && index > 0 ? "%.1f" : "%.0f", value)
        return number + units[index]
    }
}
