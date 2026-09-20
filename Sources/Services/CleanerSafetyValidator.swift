import Foundation

/// 磁盘清理核心安全网关 (双锁防线)
/// 任何待清理的目标路径在执行物理删除前，必须无条件通过本网关的校验，
/// 坚决杜绝任何误删系统核心、用户个人资料、钥匙串、配置或代码工程的风险。
public enum CleanerSafetyValidator {
    
    /// 绝对禁止删除的单一路径（完全匹配）
    private static var forbiddenExactPaths: Set<String> {
        let home = NSHomeDirectory()
        return [
            "/",
            "/System",
            "/Library",
            "/Applications",
            "/usr",
            "/bin",
            "/sbin",
            "/etc",
            "/var",
            "/private",
            "/Users",
            home,
            "\(home)/Library",
            "\(home)/Library/Caches",
            "\(home)/Library/Developer",
            "\(home)/Library/Developer/Xcode",
            "\(home)/Library/Developer/Xcode/DerivedData"
        ]
    }
    
    /// 绝对禁止删除的目录树（其本身及所有子目录/文件均严禁触碰）
    private static var forbiddenDirectoryTrees: [String] {
        let home = NSHomeDirectory()
        return [
            "/System",
            "/usr",
            "/bin",
            "/sbin",
            "/etc",
            "/var",
            "/private",
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
            "\(home)/Movies",
            "\(home)/Music",
            "\(home)/Pictures",
            "\(home)/Library/Application Support", // 用户的书签、微信记录、数据库全在此处，严禁触碰
            "\(home)/Library/Preferences",
            "\(home)/Library/Keychains",
            "\(home)/Library/Containers",
            "\(home)/.ssh",
            "\(home)/.gnupg",
            "\(home)/.config"
        ]
    }
    
    /// 核心校验入口：判断目标 URL 是否 100% 符合安全删除白名单
    public static func isSafeToDelete(url: URL) -> Bool {
        // 1. 解析真实物理路径（阻断符号链接欺骗与 .. 路径穿越）
        let rawPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard !rawPath.isEmpty else { return false }
        
        let home = NSHomeDirectory()
        
        // 2. 深度防御：路径层级至少需要 4 层（如 /Users/xxx/Library/Caches）
        let components = rawPath.split(separator: "/")
        guard components.count >= 4 else { return false }
        
        // 3. 第一道防线：检查精确禁止路径
        if forbiddenExactPaths.contains(rawPath) {
            return false
        }
        
        // 4. 第二道防线：检查严密保护的目录树（桌面、文稿、个人配置、密码库等）
        for tree in forbiddenDirectoryTrees {
            if rawPath == tree || rawPath.hasPrefix("\(tree)/") {
                return false
            }
        }
        
        // 5. 第三道防线：必须严格满足以下合规白名单之一：
        
        // A. 位于 ~/Library/Caches/ 的子目录（不包含 ~/Library/Caches 本身）
        if rawPath.hasPrefix("\(home)/Library/Caches/") {
            return true
        }
        
        // B. 位于 Xcode DerivedData 的项目构建子目录
        if rawPath.hasPrefix("\(home)/Library/Developer/Xcode/DerivedData/") {
            return true
        }
        
        // C. 位于 npm 官方离线缓存库
        if rawPath.hasPrefix("\(home)/.npm/_cacache") {
            return true
        }
        
        // D. 严格限用于开发项目子目录下的构建中间件 (.build 或 __pycache__)
        let lastComponent = url.lastPathComponent
        if (lastComponent == ".build" || lastComponent == "__pycache__") && rawPath.hasPrefix("\(home)/") {
            return true
        }
        
        // 任何未明确匹配白名单的未知路径一律拒绝
        return false
    }
}
