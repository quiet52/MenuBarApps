import AppKit
import SwiftUI
import Combine
import Darwin

public enum NavigationTab: String, CaseIterable, Identifiable {
    case apps = "应用管理"
    case cleaner = "磁盘清理"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .apps: return "app.dashed"
        case .cleaner: return "sparkles"
        }
    }
}

public enum AppCategory: String, CaseIterable, Identifiable {
    case all = "全部"
    case accessory = "菜单栏"
    case regular = "窗口应用"
    case cli = "终端/AI"
    
    public var id: String { rawValue }
}

public final class AppManager: ObservableObject {
    @Published public var selectedTab: NavigationTab = .apps
    @Published public var runningApps: [AppItem] = []
    @Published public var recentApps: [AppItem] = []
    @Published public var searchText: String = ""
    @Published public var selectedCategory: AppCategory = .all
    @Published public var ignoredBundleIds: [String] = []
    @Published public var showingIgnoredSheet: Bool = false
    
    // 即时动作状态跟踪 (方案 3: Loading / 状态响应动效)
    @Published public var openingAppIds: Set<String> = []
    @Published public var restartingAppIds: Set<String> = []
    @Published public var quittingAppIds: Set<String> = []
    
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    
    public init() {
        setupObservers()
        refresh()
        startTimer()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    public static func getMemoryUsage(pid: pid_t) -> UInt64? {
        var taskInfo = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size)
        if result == size {
            return taskInfo.pti_resident_size
        }
        return nil
    }
    
    public var filteredRunningApps: [AppItem] {
        var list = runningApps
        
        switch selectedCategory {
        case .all:
            break
        case .accessory:
            list = list.filter { $0.isAccessory && !$0.isCliProcess }
        case .regular:
            list = list.filter { !$0.isAccessory && !$0.isCliProcess }
        case .cli:
            list = list.filter { $0.isCliProcess }
        }
        
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.bundleId.localizedCaseInsensitiveContains(query) ||
                ($0.commandLine?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        return list
    }
    
    public var filteredRecentApps: [AppItem] {
        var list = recentApps
        switch selectedCategory {
        case .all:
            break
        case .accessory:
            list = list.filter { $0.isAccessory && !$0.isCliProcess }
        case .regular:
            list = list.filter { !$0.isAccessory && !$0.isCliProcess }
        case .cli:
            list = list.filter { $0.isCliProcess }
        }
        
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.bundleId.localizedCaseInsensitiveContains(query) ||
                ($0.commandLine?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        return list
    }
    
    private func setupObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(
            self,
            selector: #selector(handleAppLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleAppTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }
    
    @objc private func handleAppLaunched(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }
    
    @objc private func handleAppTerminated(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            if FilterRules.shared.isUserFacingApp(app) {
                HistoryStore.shared.recordQuit(app: app)
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }
    
    public func refresh() {
        let workspace = NSWorkspace.shared
        let allApps = workspace.runningApplications
        
        var running: [AppItem] = []
        var runningIds = Set<String>()
        var runningPaths = Set<String>()
        
        for app in allApps {
            if FilterRules.shared.isUserFacingApp(app) {
                let name = app.localizedName ?? "未命名应用"
                let bundleId = app.bundleIdentifier ?? ""
                let path = app.bundleURL?.path ?? ""
                let isAccessory = (app.activationPolicy == .accessory)
                let mem = AppManager.getMemoryUsage(pid: app.processIdentifier)
                
                let item = AppItem(
                    pid: app.processIdentifier,
                    bundleId: bundleId,
                    name: name,
                    bundleURL: app.bundleURL,
                    isRunning: true,
                    isAccessory: isAccessory,
                    memoryBytes: mem
                )
                running.append(item)
                if !bundleId.isEmpty {
                    runningIds.insert(bundleId)
                }
                if !path.isEmpty {
                    runningPaths.insert(path)
                }
            }
        }
        
        // 扫描并整合终端 / AI 常驻服务 (Ollama, Claude Code, Kimi Code 等)
        let cliApps = CliProcessScanner.shared.scanActiveCliServices()
        running.append(contentsOf: cliApps)
        for cli in cliApps {
            runningIds.insert(cli.id)
            if let path = cli.bundleURL?.path {
                runningPaths.insert(path)
            }
        }
        
        running.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        
        let recent = HistoryStore.shared.getRecentQuitApps(
            excludingRunning: runningIds,
            excludingPaths: runningPaths
        )
        
        self.runningApps = running
        self.recentApps = recent
        self.ignoredBundleIds = Array(FilterRules.shared.ignoredBundleIds)
        self.quittingAppIds.formIntersection(runningIds)
    }
    
    public func activateApp(_ item: AppItem) {
        openingAppIds.insert(item.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.openingAppIds.remove(item.id)
        }
        
        if item.isCliProcess {
            let terms = ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-GDK", "com.mitchellh.ghostty"]
            for termId in terms {
                if let termApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == termId }) {
                    termApp.activate(options: [.activateIgnoringOtherApps])
                    break
                }
            }
            return
        }
        
        if let pid = item.pid,
           let app = NSRunningApplication(processIdentifier: pid) {
            app.unhide()
            app.activate(options: [.activateIgnoringOtherApps])
        } else if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == item.bundleId }) {
            app.unhide()
            app.activate(options: [.activateIgnoringOtherApps])
        }
        
        if let url = item.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.addsToRecentItems = false
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
        
        if !item.bundleId.isEmpty {
            let script = "tell application id \"\(item.bundleId)\" to activate"
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
        }
    }
    
    public func quitApp(_ item: AppItem, force: Bool = false) {
        quittingAppIds.insert(item.id)
        HistoryStore.shared.recordQuit(item: item)
        
        if item.isCliProcess, let pid = item.pid {
            if force {
                kill(pid, SIGKILL)
            } else {
                kill(pid, SIGTERM)
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
                    if kill(pid, 0) == 0 {
                        kill(pid, SIGKILL)
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.refresh()
            }
            return
        }
        
        var targetApp: NSRunningApplication?
        if let pid = item.pid {
            targetApp = NSRunningApplication(processIdentifier: pid)
        }
        if targetApp == nil {
            targetApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == item.bundleId })
        }
        
        if let targetApp = targetApp {
            if force {
                targetApp.forceTerminate()
            } else {
                targetApp.terminate()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refresh()
        }
    }
    
    public func restartApp(_ item: AppItem) {
        restartingAppIds.insert(item.id)
        HistoryStore.shared.recordQuit(item: item)
        
        if item.isCliProcess, let pid = item.pid {
            let execURL = item.bundleURL
            let isOllama = item.name.lowercased().contains("ollama")
            kill(pid, SIGTERM)
            
            DispatchQueue.global().async { [weak self] in
                for _ in 0..<15 {
                    if kill(pid, 0) != 0 { break }
                    usleep(100_000)
                }
                
                if isOllama, let execURL = execURL {
                    let proc = Process()
                    proc.executableURL = execURL
                    proc.arguments = ["serve"]
                    try? proc.run()
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self?.restartingAppIds.remove(item.id)
                    self?.refresh()
                }
            }
            return
        }
        
        guard let url = item.bundleURL else { return }
        
        var targetApp: NSRunningApplication?
        if let pid = item.pid {
            targetApp = NSRunningApplication(processIdentifier: pid)
        }
        if targetApp == nil {
            targetApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == item.bundleId })
        }
        targetApp?.terminate()
        
        DispatchQueue.global().async { [weak self] in
            if let targetApp = targetApp {
                for _ in 0..<15 {
                    if targetApp.isTerminated { break }
                    usleep(100_000)
                }
            } else {
                usleep(300_000)
            }
            
            DispatchQueue.main.async {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                config.addsToRecentItems = false
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self?.restartingAppIds.remove(item.id)
                        self?.refresh()
                    }
                }
            }
        }
    }
    
    public func relaunchApp(_ item: AppItem) {
        guard let url = item.bundleURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.refresh()
            }
        }
    }
    
    public func showInFinder(_ item: AppItem) {
        guard let url = item.bundleURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    public func ignoreApp(_ item: AppItem) {
        FilterRules.shared.ignore(bundleId: item.bundleId)
        refresh()
    }
    
    public func unignoreApp(_ bundleId: String) {
        FilterRules.shared.unignore(bundleId: bundleId)
        refresh()
    }
    
    public func clearRecentHistory() {
        HistoryStore.shared.clear()
        refresh()
    }
    
    public func removeFromRecent(_ bundleId: String) {
        HistoryStore.shared.remove(bundleId: bundleId)
        refresh()
    }
}
