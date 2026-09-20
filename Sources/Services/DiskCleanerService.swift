import Foundation
import Combine

public final class DiskCleanerService: ObservableObject {
    public static let shared = DiskCleanerService()
    
    @Published public var items: [CleanerItem] = []
    @Published public var isScanning: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var statusMessage: String = ""
    @Published public var lastFreedBytes: Int64 = 0
    
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
    
    public func scan() {
        guard !isScanning else { return }
        isScanning = true
        statusMessage = "正在扫描系统与项目缓存..."
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var discovered: [CleanerItem] = []
            let fm = FileManager.default
            let home = NSHomeDirectory()
            
            // 1. 静态白名单规则库
            let predefinedRules: [(String, String, CleanerCategory, String)] = [
                ("Chrome 浏览器网页缓存", "\(home)/Library/Caches/Google", .browser, "网页历史图片、视频与字体缓存"),
                ("Safari 浏览器缓存", "\(home)/Library/Caches/com.apple.Safari", .browser, "Safari 离线数据与网页缓存"),
                ("Edge 浏览器缓存", "\(home)/Library/Caches/com.microsoft.edgemac", .browser, "微软 Edge 网页浏览临时数据"),
                ("Homebrew 安装包下载缓存", "\(home)/Library/Caches/Homebrew", .package, "已安装软件包的离线安装镜像 (.tar.gz)"),
                ("Python pip 依赖包缓存", "\(home)/Library/Caches/pip", .package, "pip 下载的 wheel 与编译缓存"),
                ("npm 依赖缓存库", "\(home)/.npm/_cacache", .package, "npm 离线包文件与版本缓存"),
                ("Node-gyp 编译工具缓存", "\(home)/Library/Caches/node-gyp", .package, "Node 本地模块编译 C/C++ 头文件"),
                ("Playwright 测试浏览器缓存", "\(home)/Library/Caches/ms-playwright", .systemTemp, "自动化测试工具下载的独立浏览器内核"),
                ("软件自动更新包残留", "\(home)/Library/Caches/pen-updater", .systemTemp, "已更新软件遗留的安装安装镜像"),
                ("Xcode 编译中间构建缓存", "\(home)/Library/Developer/Xcode/DerivedData", .developer, "Xcode 历史大型编译产物与索引 (DerivedData)"),
                ("SwiftPM 依赖仓库缓存", "\(home)/Library/Caches/org.swift.swiftpm", .developer, "Swift 依赖源码包清单与签出缓存")
            ]
            
            for (title, path, category, subtitle) in predefinedRules {
                if fm.fileExists(atPath: path) {
                    let url = URL(fileURLWithPath: path)
                    let size = self.calculateDirectorySize(at: url)
                    if size > 1024 * 1024 { // 过滤小于 1MB 的微小项
                        discovered.append(CleanerItem(
                            title: title,
                            subtitle: subtitle,
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
                            (".build", "Swift 项目中间构建缓存 (.build)", CleanerCategory.developer),
                            (".audio-work", "临时音频切片与语音转写缓存", CleanerCategory.systemTemp),
                            ("__pycache__", "Python 字节码缓存 (__pycache__)", CleanerCategory.developer)
                        ]
                        
                        for (hiddenName, cacheDesc, cat) in devCaches {
                            let targetPath = "\(subPath)/\(hiddenName)"
                            if fm.fileExists(atPath: targetPath) {
                                let targetURL = URL(fileURLWithPath: targetPath)
                                let size = self.calculateDirectorySize(at: targetURL)
                                if size > 1024 * 1024 {
                                    let projectName = subURL.lastPathComponent
                                    discovered.append(CleanerItem(
                                        title: "\(projectName) - \(hiddenName)",
                                        subtitle: cacheDesc,
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
