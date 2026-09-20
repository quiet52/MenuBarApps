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
    public let quitAt: Date?
    public let memoryBytes: UInt64?
    
    public init(
        pid: pid_t?,
        bundleId: String,
        name: String,
        bundleURL: URL?,
        isRunning: Bool = true,
        isAccessory: Bool = true,
        quitAt: Date? = nil,
        memoryBytes: UInt64? = nil
    ) {
        self.id = bundleId.isEmpty ? (bundleURL?.path ?? UUID().uuidString) : bundleId
        self.pid = pid
        self.bundleId = bundleId
        self.name = name
        self.bundleURL = bundleURL
        self.isRunning = isRunning
        self.isAccessory = isAccessory
        self.quitAt = quitAt
        self.memoryBytes = memoryBytes
    }
    
    public var memoryString: String? {
        guard let bytes = memoryBytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isRunning)
        hasher.combine(quitAt)
        hasher.combine(memoryBytes)
    }
    
    public static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        return lhs.id == rhs.id && 
               lhs.isRunning == rhs.isRunning && 
               lhs.quitAt == rhs.quitAt &&
               lhs.memoryBytes == rhs.memoryBytes
    }
    
    public var icon: NSImage {
        if let bundleURL = bundleURL {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}
