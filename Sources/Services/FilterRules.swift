import AppKit
import Foundation

public final class FilterRules {
    public static let shared = FilterRules()
    
    private let defaultsKey = "com.quiet52.MenuBarApps.ignoredBundleIds"
    
    private init() {}
    
    public var ignoredBundleIds: Set<String> {
        get {
            let list = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
            return Set(list)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: defaultsKey)
        }
    }
    
    public func ignore(bundleId: String) {
        var current = ignoredBundleIds
        current.insert(bundleId)
        ignoredBundleIds = current
    }
    
    public func unignore(bundleId: String) {
        var current = ignoredBundleIds
        current.remove(bundleId)
        ignoredBundleIds = current
    }
    
    public func isIgnored(bundleId: String) -> Bool {
        return ignoredBundleIds.contains(bundleId)
    }
    
    public func isUserFacingApp(_ app: NSRunningApplication) -> Bool {
        // 包含常规 Dock 应用 (.regular) 和 辅助菜单栏应用 (.accessory)
        guard app.activationPolicy == .accessory || app.activationPolicy == .regular else { return false }
        
        // 自身排除
        if let currentBundleId = Bundle.main.bundleIdentifier,
           app.bundleIdentifier == currentBundleId {
            return false
        }
        if app.localizedName == "MenuBarApps" || app.bundleIdentifier == "com.quiet52.MenuBarApps" {
            return false
        }
        
        guard let path = app.bundleURL?.path else { return false }
        let bundleId = app.bundleIdentifier ?? ""
        let name = app.localizedName ?? ""
        
        // 用户自定义忽略
        if isIgnored(bundleId: bundleId) {
            return false
        }
        
        // 排除框架、XPC 服务与 Helper
        if path.contains("/Contents/Frameworks/") || 
           path.contains("/Contents/XPCServices/") ||
           path.contains("/XPCServices/") {
            return false
        }
        if path.components(separatedBy: ".app").count > 2 {
            return false
        }
        if bundleId.lowercased().contains(".helper") || bundleId.contains(".WebKit.") {
            return false
        }
        if name.localizedCaseInsensitiveContains("Helper") || 
           name.localizedCaseInsensitiveContains("(Renderer)") || 
           name.localizedCaseInsensitiveContains("Networking") {
            return false
        }
        
        // 排除底层系统目录与 CoreServices 守护进程
        if path.hasPrefix("/System/Library/CoreServices/") ||
           path.hasPrefix("/System/Volumes/") ||
           path.hasPrefix("/Library/Apple/") {
            return false
        }
        
        // 对于辅助应用，额外屏蔽所有 com.apple. 原生小组件 (如 WiFiAgent, ControlCenter)
        if app.activationPolicy == .accessory {
            if path.hasPrefix("/System/Library/") || bundleId.hasPrefix("com.apple.") {
                return false
            }
        }
        
        // 必须是标准 .app 包
        if !path.hasSuffix(".app") {
            return false
        }
        
        return true
    }
}
