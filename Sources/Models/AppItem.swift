import AppKit
import SwiftUI

public struct AppItem: Identifiable, Hashable {
    public let id: String
    public let pid: pid_t?
    public let bundleId: String
    public let name: String
    public let bundleURL: URL?
    public let isRunning: Bool
    public let isAccessory: Bool
    public let isCliProcess: Bool
    public let commandLine: String?
    public let fullCommandLine: String?
    public let quitAt: Date?
    /// 内存占用（phys_footprint，与活动监视器一致；图形应用已包含其 Helper 子进程）
    public let memoryBytes: UInt64?
    /// 合并统计的进程数（主进程 + Helper / 子进程）
    public let processCount: Int
    /// 进程启动时间，用于终止前确认 PID 未被复用
    public let processStartTime: UInt64?
    /// 是否支持「一键重启」
    public let canRestart: Bool

    public init(
        id: String? = nil,
        pid: pid_t?,
        bundleId: String,
        name: String,
        bundleURL: URL?,
        isRunning: Bool = true,
        isAccessory: Bool = true,
        isCliProcess: Bool = false,
        commandLine: String? = nil,
        fullCommandLine: String? = nil,
        quitAt: Date? = nil,
        memoryBytes: UInt64? = nil,
        processCount: Int = 1,
        processStartTime: UInt64? = nil,
        canRestart: Bool = true
    ) {
        if let id = id {
            self.id = id
        } else if isCliProcess {
            self.id = "cli_\(pid ?? 0)_\(name)"
        } else {
            self.id = bundleId.isEmpty ? (bundleURL?.path ?? UUID().uuidString) : bundleId
        }
        self.pid = pid
        self.bundleId = bundleId
        self.name = name
        self.bundleURL = bundleURL
        self.isRunning = isRunning
        self.isAccessory = isAccessory
        self.isCliProcess = isCliProcess
        self.commandLine = commandLine
        self.fullCommandLine = fullCommandLine
        self.quitAt = quitAt
        self.memoryBytes = memoryBytes
        self.processCount = processCount
        self.processStartTime = processStartTime
        self.canRestart = canRestart
    }

    public var memoryString: String? {
        guard let bytes = memoryBytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(pid)
        hasher.combine(isRunning)
        hasher.combine(quitAt)
        hasher.combine(memoryBytes)
        hasher.combine(processCount)
    }

    public static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        return lhs.id == rhs.id &&
               lhs.pid == rhs.pid &&
               lhs.isRunning == rhs.isRunning &&
               lhs.isCliProcess == rhs.isCliProcess &&
               lhs.quitAt == rhs.quitAt &&
               lhs.memoryBytes == rhs.memoryBytes &&
               lhs.processCount == rhs.processCount
    }

    // 图标缓存：避免每次界面刷新都去 NSWorkspace 重新读取图标
    private static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        return cache
    }()

    public var icon: NSImage {
        let key = (bundleURL?.path ?? "__generic_app__") as NSString
        if let cached = AppItem.iconCache.object(forKey: key) {
            return cached
        }
        let image: NSImage
        if let bundleURL = bundleURL {
            image = NSWorkspace.shared.icon(forFile: bundleURL.path)
        } else {
            image = NSWorkspace.shared.icon(for: .application)
        }
        AppItem.iconCache.setObject(image, forKey: key)
        return image
    }
}
