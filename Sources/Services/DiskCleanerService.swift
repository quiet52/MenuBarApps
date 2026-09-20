import Foundation
import Combine
import AppKit

public final class DiskCleanerService: ObservableObject {
    public static let shared = DiskCleanerService()
    
    @Published public var items: [CleanerItem] = []
    @Published public var isScanning: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var statusMessage: String = ""
    @Published public var lastFreedBytes: Int64 = 0
    
    // MARK: - 明细下钻状态
    @Published public var activeDetailItem: CleanerItem? = nil
    @Published public var currentDetailSubItems: [CleanerSubItem] = []
    @Published public var isLoadingSubItems: Bool = false
    
    public init() {
        // 初始触发一次扫描
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.scan()
        }
    }
    
    public var selectedBytes: Int64 {
        items.filter { $0.isSelected }.reduce(0) { $0 + $1.sizeBytes }
    }
    
    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }
    
    public var selectedBytesString: String {
        ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)
    }
    
    public var totalBytesString: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    public func toggleSelection(for id: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isSelected.toggle()
        }
    }
    
    public func selectAll() {
        for idx in items.indices {
            items[idx].isSelected = true
        }
    }
    
    public func deselectAll() {
        for idx in items.indices {
            items[idx].isSelected = false
        }
    }
    
    // MARK: - 下钻明细与访达交互
    public func openDetail(for item: CleanerItem) {
        activeDetailItem = item
        currentDetailSubItems = []
        isLoadingSubItems = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let subItems = self.analyzeSubItems(for: item.url)
            DispatchQueue.main.async {
                self.currentDetailSubItems = subItems
                self.isLoadingSubItems = false
            }
        }
    }
    
    public func closeDetail() {
        activeDetailItem = nil
        currentDetailSubItems = []
        isLoadingSubItems = false
    }
    
    public func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    public func cleanSingleItem(_ item: CleanerItem) {
        guard !isCleaning else { return }
        isCleaning = true
        statusMessage = "正在清理 \(item.title)..."
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            let path = item.url.path
            var freed: Int64 = 0
            
            if fm.fileExists(atPath: path) {
                do {
                    if path.contains("/Library/Caches/") {
                        try fm.removeItem(at: item.url)
                        try fm.createDirectory(at: item.url, withIntermediateDirectories: true)
                    } else {
                        try fm.removeItem(at: item.url)
                    }
                    freed = item.sizeBytes
                } catch {
                    print("单项清理失败: \(path), error: \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.isCleaning = false
                self.lastFreedBytes = freed
                let freedStr = ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
                self.statusMessage = "成功释放 \(item.title) (\(freedStr))！"
                self.closeDetail()
                self.scan()
            }
        }
    }
    
    public func scan() {
        guard !isScanning else { return }
        isScanning = true
        statusMessage = "正在扫描系统与项目缓存..."
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var discovered: [CleanerItem] = []
            let fm = FileManager.default
            let home = NSHomeDirectory()
            
            // 1. 静态白名单规则库 (名称, 路径, 分类, 描述, 安全说明)
            let predefinedRules: [(String, String, CleanerCategory, String, String)] = [
                ("Chrome 浏览器网页缓存", "\(home)/Library/Caches/Google", .browser, "网页历史图片、视频与字体缓存", "仅包含网页渲染、离线图片与流媒体临时分片。清理后浏览器会自动重建，绝不影响保存的密码、登录状态、书签或浏览历史。"),
                ("Safari 浏览器缓存", "\(home)/Library/Caches/com.apple.Safari", .browser, "Safari 离线数据与网页缓存", "包含 Safari 离线浏览网页临时文件。清理后不影响登录状态、书签与阅读列表。"),
                ("Edge 浏览器缓存", "\(home)/Library/Caches/com.microsoft.edgemac", .browser, "微软 Edge 网页浏览临时数据", "仅为 Edge 网页资源缓存，清理后不影响任何账户设置与收藏夹。"),
                ("Homebrew 安装包下载缓存", "\(home)/Library/Caches/Homebrew", .package, "已安装软件包的离线安装镜像 (.tar.gz)", "已安装完成的软件包离线压缩包 (.tar.gz) 镜像残留。安装完毕后已无用途，删除后完全不影响软件正常运行。"),
                ("Python pip 依赖包缓存", "\(home)/Library/Caches/pip", .package, "pip 下载的 wheel 与编译缓存", "pip 下载并解压过的 wheel 离线包。本地已安装的 Python 库不受任何影响，下次安装新包仍可按需在线拉取。"),
                ("npm 依赖缓存库", "\(home)/.npm/_cacache", .package, "npm 离线包文件与版本缓存", "npm 全局离线 tarball 包缓存。本地项目的 node_modules 不受任何影响。"),
                ("Node-gyp 编译工具缓存", "\(home)/Library/Caches/node-gyp", .package, "Node 本地模块编译 C/C++ 头文件", "Node.js 本地 C++ 插件编译头文件缓存，清理后无害。"),
                ("Playwright 测试浏览器缓存", "\(home)/Library/Caches/ms-playwright", .systemTemp, "自动化测试工具下载的独立浏览器内核", "Playwright 框架自动下载的独立浏览器内核，若当前无测试需求可安全释放数 GB 磁盘空间。"),
                ("软件自动更新包残留", "\(home)/Library/Caches/pen-updater", .systemTemp, "已更新软件遗留的安装镜像", "软件更新完毕后遗留的安装 dmg/pkg 包，已完全无保留价值。"),
                ("Xcode 编译中间构建缓存", "\(home)/Library/Developer/Xcode/DerivedData", .developer, "Xcode 历史大型编译产物与索引 (DerivedData)", "Xcode 项目的编译索引、符号与中间构建体。删除后 Xcode 会在下次编译时按需干净重建，常用于解决各种诡异的编译红错。"),
                ("SwiftPM 依赖仓库缓存", "\(home)/Library/Caches/org.swift.swiftpm", .developer, "Swift 依赖源码包清单与签出缓存", "Swift Package Manager 依赖仓库签出清单。不影响源码，构建时 SPM 会自动重新校验。")
            ]
            
            for (title, path, category, subtitle, rationale) in predefinedRules {
                if fm.fileExists(atPath: path) {
                    let url = URL(fileURLWithPath: path)
                    let size = self.calculateDirectorySize(at: url)
                    if size > 1024 * 1024 { // 过滤小于 1MB 的微小项
                        discovered.append(CleanerItem(
                            title: title,
                            subtitle: subtitle,
                            safetyRationale: rationale,
                            category: category,
                            url: url,
                            sizeBytes: size,
                            isSelected: true
                        ))
                    }
                }
            }
            
            // 2. 动态扫描用户项目目录 (~/project) 下的隐藏构建缓存 (.build, .audio-work 等)
            let projectDir = "\(home)/project"
            if fm.fileExists(atPath: projectDir) {
                let projectURL = URL(fileURLWithPath: projectDir)
                if let enumerator = fm.enumerator(
                    at: projectURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsSubdirectoryDescendants]
                ) {
                    for case let subURL as URL in enumerator {
                        let subPath = subURL.path
                        // 检查子目录里的隐藏缓存
                        let devCaches = [
                            (".build", "Swift 项目中间构建缓存 (.build)", CleanerCategory.developer, "Swift 编译生成的二进制与中间目标文件。完全不影响源码，下次编译会干净重新生成。"),
                            (".audio-work", "临时音频切片与语音转写缓存", CleanerCategory.systemTemp, "本地语音识别与切片处理生成的临时音频工件，已完成转写的内容无需保留此类中间文件。"),
                            ("__pycache__", "Python 字节码缓存 (__pycache__)", CleanerCategory.developer, "Python 运行自动生成的 .pyc 字节码缓存。完全不影响 Python 代码，执行时会自动重新编译。")
                        ]
                        
                        for (hiddenName, cacheDesc, cat, rationale) in devCaches {
                            let targetPath = "\(subPath)/\(hiddenName)"
                            if fm.fileExists(atPath: targetPath) {
                                let targetURL = URL(fileURLWithPath: targetPath)
                                let size = self.calculateDirectorySize(at: targetURL)
                                if size > 1024 * 1024 {
                                    let projectName = subURL.lastPathComponent
                                    discovered.append(CleanerItem(
                                        title: "\(projectName) - \(hiddenName)",
                                        subtitle: cacheDesc,
                                        safetyRationale: rationale,
                                        category: cat,
                                        url: targetURL,
                                        sizeBytes: size,
                                        isSelected: true
                                    ))
                                }
                            }
                        }
                    }
                }
            }
            
            // 按体积从大到小排序
            discovered.sort { $0.sizeBytes > $1.sizeBytes }
            
            DispatchQueue.main.async {
                self.items = discovered
                self.isScanning = false
                let totalStr = ByteCountFormatter.string(fromByteCount: self.totalBytes, countStyle: .file)
                self.statusMessage = discovered.isEmpty ? "系统非常干净，未发现冗余缓存" : "发现 \(discovered.count) 项可清理缓存，共 \(totalStr)"
            }
        }
    }
    
    public func analyzeSubItems(for url: URL) -> [CleanerSubItem] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        var subItems: [CleanerSubItem] = []
        
        for childURL in contents {
            let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let childPath = childURL.path
            let childName = childURL.lastPathComponent
            
            let size: Int64
            if isDir {
                size = calculateDirectorySize(at: childURL)
            } else {
                let res = try? childURL.resourceValues(forKeys: [.fileSizeKey])
                size = Int64(res?.fileSize ?? 0)
            }
            
            if size > 10 * 1024 { // >10KB
                subItems.append(CleanerSubItem(
                    id: childPath,
                    name: childName,
                    path: childPath,
                    sizeBytes: size,
                    isDirectory: isDir
                ))
            }
        }
        
        // 如果顶层只有一个子文件夹（例如 Google -> Chrome），自动下钻一层展开更具体的明细
        if subItems.count == 1 && subItems[0].isDirectory {
            let nestedURL = URL(fileURLWithPath: subItems[0].path)
            let nested = analyzeSubItems(for: nestedURL)
            if !nested.isEmpty {
                return nested
            }
        }
        
        subItems.sort { $0.sizeBytes > $1.sizeBytes }
        return Array(subItems.prefix(15))
    }
    
    public func cleanSelected() {
        guard !isCleaning else { return }
        isCleaning = true
        statusMessage = "正在安全清理选中的缓存..."
        
        let targets = items.filter { $0.isSelected }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            var freed: Int64 = 0
            
            for item in targets {
                let path = item.url.path
                if fm.fileExists(atPath: path) {
                    do {
                        // 如果是应用系统缓存目录 (位于 ~/Library/Caches)，清空后重新建立空目录，防止软件报错
                        if path.contains("/Library/Caches/") {
                            try fm.removeItem(at: item.url)
                            try fm.createDirectory(at: item.url, withIntermediateDirectories: true)
                        } else {
                            // 项目 .build、DerivedData 等直接彻底移除
                            try fm.removeItem(at: item.url)
                        }
                        freed += item.sizeBytes
                    } catch {
                        print("清理失败: \(path), error: \(error)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.lastFreedBytes = freed
                self.isCleaning = false
                let freedStr = ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
                self.statusMessage = "成功释放 \(freedStr) 存储空间！"
                // 刷新扫描
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.scan()
                }
            }
        }
    }
    
    private func calculateDirectorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: []
        ) else {
            return 0
        }
        
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
               values.isDirectory != true,
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
