import Foundation
import Combine
import AppKit

public final class DiskCleanerService: ObservableObject {
    public static let shared = DiskCleanerService()

    @Published public var items: [CleanerItem] = []
    @Published public var isScanning: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var hasScanned: Bool = false
    @Published public var statusMessage: String = ""
    @Published public var lastFreedBytes: Int64 = 0

    // MARK: - 明细下钻状态
    @Published public var activeDetailItem: CleanerItem? = nil
    @Published public var currentDetailSubItems: [CleanerSubItem] = []
    @Published public var isLoadingSubItems: Bool = false
    
    // MARK: - 清理二次确认状态
    // 注意：不使用 SwiftUI 的 @State —— 新版 SDK 中 @State 是宏，
    // 只装了 Command Line Tools（未装 Xcode）时缺少宏插件会导致编译失败。
    @Published public var isConfirmingClean: Bool = false
    @Published public var isConfirmingSingleClean: Bool = false

    private let workQueue = DispatchQueue(label: "com.quiet52.MenuBarApps.cleaner", qos: .userInitiated)

    /// 不在启动时自动扫描：只有用户切到「磁盘清理」页时才扫描，避免开机就大量读盘
    public init() {}

    public var selectedItems: [CleanerItem] {
        items.filter { $0.isSelected }
    }

    public var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.sizeBytes }
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

    /// 只勾选「无代价」的推荐项
    public func selectRecommended() {
        for idx in items.indices {
            items[idx].isSelected = items[idx].isRecommended
        }
    }

    public func scanIfNeeded() {
        if !hasScanned && !isScanning {
            scan()
        }
    }

    // MARK: - 下钻明细与访达交互
    public func openDetail(for item: CleanerItem) {
        activeDetailItem = item
        isConfirmingSingleClean = false
        currentDetailSubItems = []
        isLoadingSubItems = true

        workQueue.async { [weak self] in
            guard let self = self else { return }
            let subItems: [CleanerSubItem]
            if item.targets.count > 1 {
                // 聚合项（例如多个 __pycache__）：直接列出每个目标目录
                subItems = item.targets.map { url in
                    CleanerSubItem(
                        id: url.path,
                        name: self.relativeName(of: url, base: item.url),
                        path: url.path,
                        sizeBytes: self.calculateDirectorySize(at: url),
                        isDirectory: true
                    )
                }
                .sorted { $0.sizeBytes > $1.sizeBytes }
            } else {
                subItems = self.analyzeSubItems(for: item.url)
            }
            DispatchQueue.main.async {
                // 用户可能已经返回或切换到其他项
                guard self.activeDetailItem?.id == item.id else { return }
                self.currentDetailSubItems = Array(subItems.prefix(30))
                self.isLoadingSubItems = false
            }
        }
    }

    private func relativeName(of url: URL, base: URL) -> String {
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        if url.path.hasPrefix(basePath) {
            return String(url.path.dropFirst(basePath.count))
        }
        return url.lastPathComponent
    }

    public func closeDetail() {
        activeDetailItem = nil
        isConfirmingSingleClean = false
        currentDetailSubItems = []
        isLoadingSubItems = false
    }

    public func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - 安全清理核心逻辑
    public func cleanSingleItem(_ item: CleanerItem) {
        guard !isCleaning else { return }
        isCleaning = true
        statusMessage = "正在清理 \(item.title)..."

        workQueue.async { [weak self] in
            guard let self = self else { return }
            let freed = self.performSafeCleaning(for: item)

            DispatchQueue.main.async {
                self.isCleaning = false
                self.lastFreedBytes = freed
                let freedStr = ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
                self.statusMessage = freed > 0 ? "已释放 \(item.title)：\(freedStr)" : "\(item.title) 没有可清理的内容（文件可能正被占用）"
                self.closeDetail()
                self.scan(keepStatus: true)
            }
        }
    }

    public func cleanSelected() {
        guard !isCleaning else { return }
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        isCleaning = true
        statusMessage = "正在清理选中的 \(targets.count) 项..."

        workQueue.async { [weak self] in
            guard let self = self else { return }
            let freed = targets.reduce(Int64(0)) { $0 + self.performSafeCleaning(for: $1) }

            DispatchQueue.main.async {
                self.lastFreedBytes = freed
                self.isCleaning = false
                let freedStr = ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
                self.statusMessage = "已释放 \(freedStr) 存储空间"
                self.scan(keepStatus: true)
            }
        }
    }

    /// 执行单项清理（每个被删除的路径都必须经过安全网关），返回实际释放的字节数
    private func performSafeCleaning(for item: CleanerItem) -> Int64 {
        let fm = FileManager.default
        var freed: Int64 = 0

        for target in item.targets {
            guard fm.fileExists(atPath: target.path) else { continue }

            if item.clearsContentsOnly {
                // 缓存根目录：保留目录本身（权限、属性与所有者），只清理其中的内容
                guard CleanerSafetyValidator.isSafeToClearContents(of: target) else {
                    print("⚠️ [安全网关拦截] 拒绝清理目录内容: \(target.path)")
                    continue
                }
                let children = (try? fm.contentsOfDirectory(at: target, includingPropertiesForKeys: nil, options: [])) ?? []
                for child in children {
                    freed += removeSafely(child)
                }
            } else {
                freed += removeSafely(target)
            }
        }
        return freed
    }

    /// 删除单个路径，按「删除前大小 - 删除后剩余大小」统计真实释放量（部分文件被占用时也准确）
    private func removeSafely(_ url: URL) -> Int64 {
        guard CleanerSafetyValidator.isSafeToDelete(url: url) else {
            print("⚠️ [安全网关拦截] 目标路径未通过安全校验，拒绝清理: \(url.path)")
            return 0
        }
        let fm = FileManager.default
        let before = calculateDirectorySize(at: url)
        do {
            try fm.removeItem(at: url)
            return before
        } catch {
            // 部分文件正被运行中的软件占用：统计已经删掉的部分
            let remaining = fm.fileExists(atPath: url.path) ? calculateDirectorySize(at: url) : 0
            return max(0, before - remaining)
        }
    }

    // MARK: - 扫描逻辑 (纯白名单)

    private struct PredefinedRule {
        let title: String
        let path: String
        let category: CleanerCategory
        let subtitle: String
        let rationale: String
        var costNote: String? = nil
        var recommended: Bool = true
    }

    public func scan() {
        scan(keepStatus: false)
    }

    private func scan(keepStatus: Bool) {
        guard !isScanning else { return }
        isScanning = true
        if !keepStatus {
            statusMessage = "正在扫描缓存..."
        }
        // 重新扫描后保留用户手动调整过的勾选状态
        let previousSelection = Dictionary(items.map { ($0.id, $0.isSelected) }, uniquingKeysWith: { first, _ in first })

        workQueue.async { [weak self] in
            guard let self = self else { return }
            var discovered: [CleanerItem] = []
            let fm = FileManager.default
            let home = NSHomeDirectory()
            let derivedData = "\(home)/Library/Developer/Xcode/DerivedData"

            // 1. 通用标准白名单规则库
            let predefinedRules: [PredefinedRule] = [
                PredefinedRule(title: "Chrome 浏览器网页缓存", path: "\(home)/Library/Caches/Google/Chrome", category: .browser,
                               subtitle: "网页图片、流媒体视频与字体缓存",
                               rationale: "仅包含网页渲染、离线图片与流媒体临时分片。清理后浏览器会自动重建，不影响保存的密码、登录状态、书签或浏览历史。",
                               costNote: "清理后首次打开常用网站会稍慢"),
                PredefinedRule(title: "Safari 浏览器缓存", path: "\(home)/Library/Caches/com.apple.Safari", category: .browser,
                               subtitle: "Safari 离线数据与网页缓存",
                               rationale: "包含 Safari 网页临时文件。清理后不影响登录状态、书签与阅读列表。"),
                PredefinedRule(title: "Edge 浏览器缓存", path: "\(home)/Library/Caches/com.microsoft.edgemac", category: .browser,
                               subtitle: "微软 Edge 网页浏览临时数据",
                               rationale: "仅为 Edge 网页资源缓存，清理后不影响任何账户设置与收藏夹。"),
                PredefinedRule(title: "Firefox 浏览器缓存", path: "\(home)/Library/Caches/Firefox", category: .browser,
                               subtitle: "火狐浏览器临时网络缓存",
                               rationale: "包含网页图片及离线资源缓存，清理后不影响配置与扩展。"),
                PredefinedRule(title: "Homebrew 安装包下载缓存", path: "\(home)/Library/Caches/Homebrew", category: .package,
                               subtitle: "已安装软件包的离线安装镜像",
                               rationale: "安装完成后留下的离线压缩包与 bottle 镜像，删除后不影响已安装软件的运行。"),
                PredefinedRule(title: "Python pip 依赖包缓存", path: "\(home)/Library/Caches/pip", category: .package,
                               subtitle: "pip 下载的 wheel 与编译缓存",
                               rationale: "pip 下载过的 wheel 离线包。本地已安装的 Python 库不受影响，下次安装新包时按需在线拉取。"),
                PredefinedRule(title: "npm 依赖缓存库", path: "\(home)/.npm/_cacache", category: .package,
                               subtitle: "npm 离线包文件与版本缓存",
                               rationale: "npm 全局离线 tarball 包缓存。本地项目的 node_modules 不受影响。"),
                PredefinedRule(title: "Yarn 包管理器缓存", path: "\(home)/Library/Caches/Yarn", category: .package,
                               subtitle: "Yarn 离线依赖包缓存",
                               rationale: "Yarn 离线下载的包归档，项目依赖已有本地拷贝。"),
                PredefinedRule(title: "CocoaPods 依赖下载缓存", path: "\(home)/Library/Caches/CocoaPods", category: .package,
                               subtitle: "iOS/macOS Pod 离线依赖仓库镜像",
                               rationale: "CocoaPods 下载的 Pod 源码压缩镜像，不影响已有 Xcode 工程。"),
                PredefinedRule(title: "Node-gyp 编译工具缓存", path: "\(home)/Library/Caches/node-gyp", category: .package,
                               subtitle: "Node 本地模块编译 C/C++ 头文件",
                               rationale: "Node.js 本地 C++ 插件编译头文件缓存，下次需要时会自动重新下载。"),
                PredefinedRule(title: "Playwright 测试浏览器内核", path: "\(home)/Library/Caches/ms-playwright", category: .systemTemp,
                               subtitle: "自动化测试工具下载的独立浏览器",
                               rationale: "Playwright 自动下载的独立浏览器内核，与你日常使用的浏览器无关。",
                               costNote: "再次运行 Playwright 测试前需要重新下载（数百 MB 至数 GB）",
                               recommended: false),
                PredefinedRule(title: "Xcode 编译中间产物 (DerivedData)", path: derivedData, category: .developer,
                               subtitle: "Xcode 历史编译产物与索引",
                               rationale: "Xcode 项目的编译索引、符号与中间构建体。删除后 Xcode 会在下次编译时重新生成，也常用于解决诡异的编译错误。",
                               costNote: "下次打开项目需要重新索引并完整编译",
                               recommended: false),
                PredefinedRule(title: "SwiftPM 依赖仓库缓存", path: "\(home)/Library/Caches/org.swift.swiftpm", category: .developer,
                               subtitle: "Swift 依赖源码包与签出缓存",
                               rationale: "Swift Package Manager 的依赖仓库缓存，不影响你的源码。",
                               costNote: "下次构建需要重新拉取依赖（需联网）",
                               recommended: false)
            ]

            for rule in predefinedRules {
                guard fm.fileExists(atPath: rule.path) else { continue }
                let url = URL(fileURLWithPath: rule.path)
                let size = self.calculateDirectorySize(at: url)
                guard size > 1024 * 1024 else { continue } // 过滤小于 1MB 的微小项
                let contentsOnly = rule.path.contains("/Library/Caches/") || rule.path == derivedData
                discovered.append(CleanerItem(
                    title: rule.title,
                    subtitle: rule.subtitle,
                    safetyRationale: rule.rationale,
                    costNote: rule.costNote,
                    category: rule.category,
                    url: url,
                    clearsContentsOnly: contentsOnly,
                    isRecommended: rule.recommended,
                    sizeBytes: size
                ))
            }

            // 2. 扫描开发目录下的构建中间件（.build / __pycache__），向下最多 5 层
            discovered.append(contentsOf: self.scanProjectCaches(home: home))

            // 按体积从大到小排序，并恢复之前的勾选状态
            discovered.sort { $0.sizeBytes > $1.sizeBytes }
            for idx in discovered.indices {
                if let selected = previousSelection[discovered[idx].id] {
                    discovered[idx].isSelected = selected
                }
            }

            let finalItems = discovered
            DispatchQueue.main.async {
                self.items = finalItems
                self.isScanning = false
                self.hasScanned = true
                if !keepStatus {
                    let totalStr = ByteCountFormatter.string(fromByteCount: self.totalBytes, countStyle: .file)
                    self.statusMessage = finalItems.isEmpty ? "未发现超过 1MB 的冗余缓存" : "发现 \(finalItems.count) 项，共 \(totalStr)"
                }
            }
        }
    }

    private func scanProjectCaches(home: String) -> [CleanerItem] {
        let fm = FileManager.default
        let candidateRoots = ["project", "Projects", "Developer", "workspace", "code", "Code", "src", "dev"]
            .map { "\(home)/\($0)" }

        // 不进入这些目录（依赖、虚拟环境、其他构建产物），既加快扫描也避免误报
        let skipNames: Set<String> = [
            "node_modules", "Pods", "DerivedData", "venv", "env", "site-packages",
            "build", "dist", "target", "vendor", "Carthage"
        ]
        let maxDepth = 5

        var results: [CleanerItem] = []
        var visitedRoots = Set<String>()

        for rootPath in candidateRoots {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: rootPath, isDirectory: &isDir), isDir.boolValue else { continue }
            // 大小写不敏感的文件系统上 ~/code 与 ~/Code 是同一个目录
            let resolvedRoot = URL(fileURLWithPath: rootPath).resolvingSymlinksInPath().path.lowercased()
            guard !visitedRoots.contains(resolvedRoot) else { continue }
            visitedRoots.insert(resolvedRoot)

            let rootURL = URL(fileURLWithPath: rootPath)
            let rootComponentCount = rootURL.pathComponents.count
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsPackageDescendants]
            ) else { continue }

            var pycacheByProject: [String: [URL]] = [:]

            while let url = enumerator.nextObject() as? URL {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }

                let name = url.lastPathComponent
                if enumerator.level > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }

                if name == ".build" {
                    enumerator.skipDescendants()
                    let size = calculateDirectorySize(at: url)
                    if size > 1024 * 1024 {
                        let projectName = url.deletingLastPathComponent().lastPathComponent
                        results.append(CleanerItem(
                            title: "\(projectName) · .build",
                            subtitle: "Swift 项目编译产物",
                            safetyRationale: "Swift 编译生成的二进制与中间目标文件，不影响源码，下次编译会重新生成。",
                            costNote: "该项目下次需要完整重新编译",
                            category: .developer,
                            url: url,
                            isRecommended: false,
                            sizeBytes: size
                        ))
                    }
                    continue
                }

                if name == "__pycache__" {
                    enumerator.skipDescendants()
                    let components = url.pathComponents
                    let projectPath: String
                    if components.count > rootComponentCount + 1 {
                        projectPath = NSString.path(withComponents: Array(components.prefix(rootComponentCount + 1)))
                    } else {
                        projectPath = rootPath
                    }
                    pycacheByProject[projectPath, default: []].append(url)
                    continue
                }

                if skipNames.contains(name) || name.hasPrefix(".") {
                    enumerator.skipDescendants()
                }
            }

            for (projectPath, urls) in pycacheByProject {
                let size = urls.reduce(Int64(0)) { $0 + calculateDirectorySize(at: $1) }
                guard size > 1024 * 1024 else { continue }
                let projectURL = URL(fileURLWithPath: projectPath)
                results.append(CleanerItem(
                    id: "pycache:\(projectPath)",
                    title: "\(projectURL.lastPathComponent) · __pycache__",
                    subtitle: "Python 字节码缓存（\(urls.count) 个目录）",
                    safetyRationale: "Python 运行时自动生成的 .pyc 字节码缓存，不影响代码，下次运行会自动重新生成。",
                    category: .developer,
                    url: projectURL,
                    targets: urls,
                    isRecommended: true,
                    sizeBytes: size
                ))
            }
        }
        return results
    }

    // MARK: - 子目录分析
    public func analyzeSubItems(for url: URL) -> [CleanerSubItem] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var subItems: [CleanerSubItem] = []

        for childURL in contents {
            let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let size = calculateDirectorySize(at: childURL)

            if size > 10 * 1024 { // >10KB
                subItems.append(CleanerSubItem(
                    id: childURL.path,
                    name: childURL.lastPathComponent,
                    path: childURL.path,
                    sizeBytes: size,
                    isDirectory: isDir
                ))
            }
        }

        // 如果顶层只有一个子文件夹（例如 Google -> Chrome），自动下钻一层展开更具体的明细
        if subItems.count == 1 && subItems[0].isDirectory {
            let nested = analyzeSubItems(for: URL(fileURLWithPath: subItems[0].path))
            if !nested.isEmpty {
                return nested
            }
        }

        subItems.sort { $0.sizeBytes > $1.sizeBytes }
        return Array(subItems.prefix(15))
    }

    // MARK: - 大小计算（实际占用的磁盘空间）
    private static let sizeKeys: [URLResourceKey] = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]

    private func fileSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: Set(DiskCleanerService.sizeKeys)) else { return 0 }
        if let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize {
            return Int64(size)
        }
        return 0
    }

    private func calculateDirectorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return fileSize(of: url)
        }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: DiskCleanerService.sizeKeys,
            options: []
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(DiskCleanerService.sizeKeys)),
                  values.isDirectory != true else { continue }
            if let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
