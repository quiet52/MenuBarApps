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

public enum AppSortMode: String, CaseIterable, Identifiable {
    case name = "按名称"
    case memory = "按内存"
    case cpu = "按 CPU"

    public var id: String { rawValue }
}

public final class AppManager: ObservableObject {
    @Published public var selectedTab: NavigationTab = .apps
    @Published public var runningApps: [AppItem] = []
    @Published public var recentApps: [AppItem] = []
    @Published public var searchText: String = ""
    @Published public var selectedCategory: AppCategory = .all
    @Published public var sortMode: AppSortMode {
        didSet { UserDefaults.standard.set(sortMode.rawValue, forKey: Self.sortModeKey) }
    }
    @Published public var ignoredBundleIds: [String] = []
    @Published public var showingIgnoredSheet: Bool = false

    /// 菜单栏角标：当前运行的菜单栏（辅助）应用数量
    @Published public var menuBarAppCount: Int = 0

    // 设置项
    @Published public var launchAtLogin: Bool = LoginItemManager.isEnabled
    @Published public var hotKeyPreset: HotKeyPreset = HotKeyPreset.defaultPreset
    @Published public var hotKeyRegistered: Bool = true

    /// 底部临时提示（如重启被取消、快捷键冲突）
    @Published public var toastMessage: String?

    // 即时动作状态跟踪
    @Published public var openingAppIds: Set<String> = []
    @Published public var restartingAppIds: Set<String> = []
    @Published public var quittingAppIds: Set<String> = []

    private static let sortModeKey = "com.quiet52.MenuBarApps.sortMode"

    private var pollTimer: Timer?
    private var toastWorkItem: DispatchWorkItem?
    private let workQueue = DispatchQueue(label: "com.quiet52.MenuBarApps.refresh", qos: .userInitiated)
    private var isRefreshing = false
    private var needsAnotherRefresh = false
    private var launchedProcesses: [Process] = []

    /// 面板是否正在显示：只有显示时才做完整扫描与定时刷新，隐藏时几乎零开销
    public private(set) var isPanelVisible = false

    public init() {
        let savedSort = UserDefaults.standard.string(forKey: Self.sortModeKey)
        self.sortMode = AppSortMode(rawValue: savedSort ?? "") ?? .name
        setupObservers()
        updateMenuBarCount()
    }

    deinit {
        pollTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - 列表过滤与排序

    private func applyFilters(_ source: [AppItem]) -> [AppItem] {
        var list = source
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
                ($0.pid.map { String($0).hasPrefix(query) } ?? false) ||
                ($0.fullCommandLine?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        return list
    }

    public var filteredRunningApps: [AppItem] {
        let list = applyFilters(runningApps)
        switch sortMode {
        case .name:
            return list
        case .memory:
            return list.sorted { ($0.memoryBytes ?? 0) > ($1.memoryBytes ?? 0) }
        case .cpu:
            return list.sorted { ($0.cpuPercent ?? 0) > ($1.cpuPercent ?? 0) }
        }
    }

    public var filteredRecentApps: [AppItem] {
        return applyFilters(recentApps)
    }

    // MARK: - 面板可见性 / 定时刷新

    public func setPanelVisible(_ visible: Bool) {
        guard visible != isPanelVisible else {
            if visible { refresh() }
            return
        }
        isPanelVisible = visible
        pollTimer?.invalidate()
        pollTimer = nil

        if visible {
            refresh()
            let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
                self?.refresh()
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
        SystemMonitor.shared.setPanelVisible(visible)
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

    @objc private func handleAppLaunched(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.handleWorkspaceChange()
        }
    }

    @objc private func handleAppTerminated(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           FilterRules.shared.isUserFacingApp(app) {
            HistoryStore.shared.recordQuit(app: app)
        }
        DispatchQueue.main.async { [weak self] in
            self?.handleWorkspaceChange()
        }
    }

    private func handleWorkspaceChange() {
        if isPanelVisible {
            refresh()
        } else {
            updateMenuBarCount()
        }
    }

    /// 轻量刷新：只更新菜单栏角标（面板隐藏时使用）
    private func updateMenuBarCount() {
        let ignored = FilterRules.shared.ignoredBundleIds
        let count = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .accessory && FilterRules.shared.isUserFacingApp($0, ignored: ignored)
        }.count
        if count != menuBarAppCount {
            menuBarAppCount = count
        }
    }

    // MARK: - 完整刷新（后台线程）

    private struct GuiAppSnapshot {
        let pid: pid_t
        let bundleId: String
        let name: String
        let bundleURL: URL?
        let isAccessory: Bool
    }

    public func refresh() {
        if isRefreshing {
            needsAnotherRefresh = true
            return
        }
        isRefreshing = true

        // NSRunningApplication 只在主线程读取，转成纯数据后交给后台
        let ignored = FilterRules.shared.ignoredBundleIds
        let guiApps: [GuiAppSnapshot] = NSWorkspace.shared.runningApplications
            .filter { FilterRules.shared.isUserFacingApp($0, ignored: ignored) }
            .map {
                GuiAppSnapshot(
                    pid: $0.processIdentifier,
                    bundleId: $0.bundleIdentifier ?? "",
                    name: $0.localizedName ?? "未命名应用",
                    bundleURL: $0.bundleURL,
                    isAccessory: $0.activationPolicy == .accessory
                )
            }

        workQueue.async { [weak self] in
            let processes = ProcessInspector.snapshot()

            var running: [AppItem] = []
            var runningIds = Set<String>()
            var runningPaths = Set<String>()
            var seenIds = Set<String>()
            var footprintCache: [pid_t: UInt64] = [:]

            func footprint(_ pid: pid_t) -> UInt64 {
                if let cached = footprintCache[pid] { return cached }
                let value = ProcessInspector.memoryFootprint(pid: pid) ?? 0
                footprintCache[pid] = value
                return value
            }

            for app in guiApps {
                let path = app.bundleURL?.path ?? ""

                // 内存 = 主进程 + 位于该 .app 包内的所有 Helper / 渲染进程（Chrome、VS Code 等多进程应用）
                // CPU 与内存口径相同，同样合并所有相关进程
                var memory: UInt64 = 0
                var cpu: Double?
                var processCount = 0
                if !path.isEmpty {
                    let prefix = path.hasSuffix("/") ? path : path + "/"
                    for entry in processes where entry.path.hasPrefix(prefix) {
                        memory += footprint(entry.pid)
                        if let usage = CpuUsageSampler.shared.usage(pid: entry.pid) {
                            cpu = (cpu ?? 0) + usage
                        }
                        processCount += 1
                    }
                }
                if processCount == 0 {
                    memory = footprint(app.pid)
                    cpu = CpuUsageSampler.shared.usage(pid: app.pid)
                    processCount = 1
                }

                // 同一应用多开时 bundleId 相同，追加 PID 保证列表 ID 唯一
                var itemId = app.bundleId.isEmpty ? (path.isEmpty ? "pid_\(app.pid)" : path) : app.bundleId
                if seenIds.contains(itemId) {
                    itemId += "#\(app.pid)"
                }
                seenIds.insert(itemId)

                running.append(AppItem(
                    id: itemId,
                    pid: app.pid,
                    bundleId: app.bundleId,
                    name: app.name,
                    bundleURL: app.bundleURL,
                    isRunning: true,
                    isAccessory: app.isAccessory,
                    memoryBytes: memory > 0 ? memory : nil,
                    cpuPercent: cpu,
                    processCount: processCount
                ))
                runningIds.insert(itemId)
                if !app.bundleId.isEmpty { runningIds.insert(app.bundleId) }
                if !path.isEmpty { runningPaths.insert(path) }
            }

            // 终端 / AI 常驻服务（Ollama、Claude Code 等）
            let cliApps = CliProcessScanner.shared.scanActiveCliServices(in: processes)
            running.append(contentsOf: cliApps)
            for cli in cliApps {
                runningIds.insert(cli.id)
            }

            running.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            let recent = HistoryStore.shared.getRecentQuitApps(
                excludingRunning: runningIds,
                excludingPaths: runningPaths
            )
            let menuBarCount = guiApps.filter { $0.isAccessory }.count
            let finalRunning = running
            let finalRunningIds = runningIds

            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.runningApps != finalRunning { self.runningApps = finalRunning }
                if self.recentApps != recent { self.recentApps = recent }
                if self.menuBarAppCount != menuBarCount { self.menuBarAppCount = menuBarCount }
                let ignoredList = Array(ignored).sorted()
                if self.ignoredBundleIds != ignoredList { self.ignoredBundleIds = ignoredList }
                self.quittingAppIds.formIntersection(finalRunningIds)

                self.isRefreshing = false
                if self.needsAnotherRefresh {
                    self.needsAnotherRefresh = false
                    self.refresh()
                }
            }
        }
    }

    private func refresh(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - 提示

    public func showToast(_ message: String) {
        toastWorkItem?.cancel()
        toastMessage = message
        let work = DispatchWorkItem { [weak self] in
            self?.toastMessage = nil
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    // MARK: - 查找运行中的应用

    private func runningApplication(for item: AppItem) -> NSRunningApplication? {
        if let pid = item.pid, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
            return app
        }
        guard !item.bundleId.isEmpty else { return nil }
        return NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == item.bundleId })
    }

    /// 等待进程真正退出（不依赖 NSRunningApplication 的 KVO 更新，后台线程轮询）
    private static func waitForExit(pid: pid_t, startTime: UInt64?, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !ProcessInspector.isAlive(pid: pid, startTime: startTime) {
                return true
            }
            usleep(100_000)
        }
        return !ProcessInspector.isAlive(pid: pid, startTime: startTime)
    }

    // MARK: - 打开 / 激活

    public func activateApp(_ item: AppItem) {
        openingAppIds.insert(item.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.openingAppIds.remove(item.id)
        }

        if item.isCliProcess {
            let terminals = [
                "com.mitchellh.ghostty", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
                "dev.warp.Warp-GDK", "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm",
                "com.apple.Terminal"
            ]
            let running = NSWorkspace.shared.runningApplications
            for termId in terminals {
                if let termApp = running.first(where: { $0.bundleIdentifier == termId }) {
                    termApp.activate(options: [.activateIgnoringOtherApps])
                    return
                }
            }
            return
        }

        if let app = runningApplication(for: item) {
            app.unhide()
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        // 再发一次「重新打开」事件：没有窗口的菜单栏应用通常会借此弹出主界面/设置窗口
        if let url = item.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.addsToRecentItems = false
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
    }

    // MARK: - 退出

    public func quitApp(_ item: AppItem, force: Bool = false) {
        quittingAppIds.insert(item.id)

        if item.isCliProcess {
            terminateCliProcess(item, force: force)
            return
        }

        HistoryStore.shared.recordQuit(item: item)
        guard let target = runningApplication(for: item) else {
            quittingAppIds.remove(item.id)
            refresh()
            return
        }

        if force {
            target.forceTerminate()
        } else {
            target.terminate()
        }
        refresh(after: 0.4)

        // 应用可能弹出「是否保存」并被用户取消：超时后恢复按钮，避免整行一直卡在「退出中」
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self = self, self.quittingAppIds.contains(item.id) else { return }
            if !target.isTerminated {
                self.quittingAppIds.remove(item.id)
                self.showToast("「\(item.name)」没有退出，可右键选择「强制退出」")
            }
        }
    }

    private func terminateCliProcess(_ item: AppItem, force: Bool) {
        guard let pid = item.pid else { return }
        let startTime = item.processStartTime

        // 发信号前再次确认 PID 仍属于同一个进程
        guard ProcessInspector.isAlive(pid: pid, startTime: startTime) else {
            refresh()
            return
        }

        if force {
            kill(pid, SIGKILL)
            refresh(after: 0.4)
            return
        }

        kill(pid, SIGTERM)
        refresh(after: 0.4)

        let name = item.name
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let exited = AppManager.waitForExit(pid: pid, startTime: startTime, timeout: 3.0)
            if !exited && ProcessInspector.isAlive(pid: pid, startTime: startTime) {
                kill(pid, SIGKILL)
            }
            DispatchQueue.main.async {
                if !exited {
                    self?.showToast("\(name) 未响应 SIGTERM，已强制结束")
                }
                self?.refresh()
            }
        }
    }

    // MARK: - 重启

    public func restartApp(_ item: AppItem) {
        if item.isCliProcess {
            restartCliService(item)
            return
        }
        guard let url = item.bundleURL else { return }
        restartingAppIds.insert(item.id)

        guard let target = runningApplication(for: item) else {
            launchForRestart(item: item, url: url)
            return
        }

        let pid = target.processIdentifier
        let startTime = ProcessInspector.startTime(of: pid)
        target.terminate()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // 大型应用（Chrome、Xcode、Electron）退出可能需要数秒，最多等 20 秒
            let exited = AppManager.waitForExit(pid: pid, startTime: startTime, timeout: 20.0)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if exited {
                    self.launchForRestart(item: item, url: url)
                } else {
                    self.restartingAppIds.remove(item.id)
                    self.showToast("「\(item.name)」未能退出（可能在等待保存），已取消重启")
                    self.refresh()
                }
            }
        }
    }

    private func launchForRestart(item: AppItem, url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            DispatchQueue.main.async {
                self?.restartingAppIds.remove(item.id)
                if error != nil {
                    self?.showToast("「\(item.name)」重新启动失败")
                }
                self?.refresh(after: 0.5)
            }
        }
    }

    /// 目前只有 `ollama serve` 支持重启；其余终端程序（如 Claude Code）依附于终端会话，无法由本工具代为拉起
    private func restartCliService(_ item: AppItem) {
        guard item.canRestart, let pid = item.pid, let execURL = item.bundleURL else {
            showToast("\(item.name) 不支持一键重启，请在终端中重新运行")
            return
        }
        restartingAppIds.insert(item.id)
        let startTime = item.processStartTime

        if ProcessInspector.isAlive(pid: pid, startTime: startTime) {
            kill(pid, SIGTERM)
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if !AppManager.waitForExit(pid: pid, startTime: startTime, timeout: 5.0),
               ProcessInspector.isAlive(pid: pid, startTime: startTime) {
                kill(pid, SIGKILL)
                _ = AppManager.waitForExit(pid: pid, startTime: startTime, timeout: 1.0)
            }

            let proc = Process()
            proc.executableURL = execURL
            proc.arguments = ["serve"]
            proc.standardInput = FileHandle.nullDevice
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            let launched: Bool
            do {
                try proc.run()
                launched = true
            } catch {
                launched = false
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                if launched {
                    self.launchedProcesses.removeAll { !$0.isRunning }
                    self.launchedProcesses.append(proc)
                } else {
                    self.showToast("\(item.name) 重新启动失败")
                }
                self.restartingAppIds.remove(item.id)
                self.refresh(after: 1.0)
            }
        }
    }

    // MARK: - 最近退出 / 其他

    public func relaunchApp(_ item: AppItem) {
        guard let url = item.bundleURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refresh(after: 0.5)
            }
        }
    }

    public func showInFinder(_ item: AppItem) {
        guard let url = item.bundleURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    public func ignoreApp(_ item: AppItem) {
        guard !item.bundleId.isEmpty else { return }
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

    // MARK: - 设置：开机自启 / 快捷键

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
        } catch {
            showToast("设置开机自启失败：请先把应用放到「应用程序」文件夹")
        }
        launchAtLogin = LoginItemManager.isEnabled
        if enabled && LoginItemManager.requiresApproval {
            showToast("请在「系统设置 → 登录项」中允许本应用")
            LoginItemManager.openSystemSettings()
        }
    }

    public func applySavedHotKey() {
        applyHotKey(HotKeyManager.shared.savedPreset, announce: false)
    }

    public func applyHotKey(_ preset: HotKeyPreset, announce: Bool = true) {
        let ok = HotKeyManager.shared.register(preset)
        hotKeyPreset = preset
        hotKeyRegistered = ok
        if !ok {
            showToast("快捷键 \(preset.title) 已被其他应用占用，请换一个")
        } else if announce {
            showToast("快捷键已改为 \(preset.title)")
        }
    }
}
