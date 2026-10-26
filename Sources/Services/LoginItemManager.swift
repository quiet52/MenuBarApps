import Foundation
import ServiceManagement

/// 开机自启动（macOS 13+ SMAppService）
public enum LoginItemManager {
    public static var isEnabled: Bool {
        return SMAppService.mainApp.status == .enabled
    }

    /// 需要在「系统设置 → 通用 → 登录项」中手动批准
    public static var requiresApproval: Bool {
        return SMAppService.mainApp.status == .requiresApproval
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
