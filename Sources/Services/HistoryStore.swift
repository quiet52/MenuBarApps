import AppKit
import Foundation

public final class HistoryStore {
    public static let shared = HistoryStore()
    
    private let defaultsKey = "com.quiet52.MenuBarApps.recentQuitHistory"
    private let maxHistoryCount = 20
    
    private struct HistoryRecord: Codable {
        let bundleId: String
        let name: String
        let bundlePath: String
        let isAccessory: Bool
        let quitTimestamp: TimeInterval
    }
    
    private init() {}
    
    public func recordQuit(item: AppItem) {
        guard let path = item.bundleURL?.path else { return }
        var records = loadRawRecords()
        
        // 彻底移除旧有的同 bundleId 或同路径的历史项，确保时间戳为最新
        records.removeAll { 
            (!item.bundleId.isEmpty && $0.bundleId == item.bundleId) || 
            $0.bundlePath == path 
        }
        
        let newRecord = HistoryRecord(
            bundleId: item.bundleId,
            name: item.name,
            bundlePath: path,
            isAccessory: item.isAccessory,
            quitTimestamp: Date().timeIntervalSince1970
        )
        records.insert(newRecord, at: 0)
        
        if records.count > maxHistoryCount {
            records = Array(records.prefix(maxHistoryCount))
        }
        saveRawRecords(records)
    }
    
    public func recordQuit(app: NSRunningApplication) {
        guard let path = app.bundleURL?.path else { return }
        let name = app.localizedName ?? "未命名应用"
        let bundleId = app.bundleIdentifier ?? ""
        let isAccessory = app.activationPolicy == .accessory
        
        var records = loadRawRecords()
        records.removeAll { 
            (!bundleId.isEmpty && $0.bundleId == bundleId) || 
            $0.bundlePath == path 
        }
        
        let newRecord = HistoryRecord(
            bundleId: bundleId,
            name: name,
            bundlePath: path,
            isAccessory: isAccessory,
            quitTimestamp: Date().timeIntervalSince1970
        )
        records.insert(newRecord, at: 0)
        
        if records.count > maxHistoryCount {
            records = Array(records.prefix(maxHistoryCount))
        }
        saveRawRecords(records)
    }
    
    public func remove(bundleId: String) {
        var records = loadRawRecords()
        records.removeAll { $0.bundleId == bundleId }
        saveRawRecords(records)
    }
    
    public func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
    
    public func getRecentQuitApps(excludingRunning runningBundleIds: Set<String>, excludingPaths: Set<String>) -> [AppItem] {
        let records = loadRawRecords()
        return records.compactMap { record in
            // 如果已经在运行中，则不展示在最近退出中
            if !record.bundleId.isEmpty && runningBundleIds.contains(record.bundleId) {
                return nil
            }
            if excludingPaths.contains(record.bundlePath) {
                return nil
            }
            // 验证该 App 是否仍然存在于磁盘中
            guard FileManager.default.fileExists(atPath: record.bundlePath) else {
                return nil
            }
            let url = URL(fileURLWithPath: record.bundlePath)
            return AppItem(
                pid: nil,
                bundleId: record.bundleId,
                name: record.name,
                bundleURL: url,
                isRunning: false,
                isAccessory: record.isAccessory,
                quitAt: Date(timeIntervalSince1970: record.quitTimestamp)
            )
        }
    }
    
    private func loadRawRecords() -> [HistoryRecord] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let list = try? JSONDecoder().decode([HistoryRecord].self, from: data) else {
            return []
        }
        return list
    }
    
    private func saveRawRecords(_ records: [HistoryRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
