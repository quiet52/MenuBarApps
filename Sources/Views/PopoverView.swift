import SwiftUI
import AppKit

public struct PopoverView: View {
    @ObservedObject var manager: AppManager
    @ObservedObject var cleanerService = DiskCleanerService.shared

    public init(manager: AppManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶部一级功能导航 (应用管理 vs 磁盘清理)
            topNavTabBar
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider()

            // 内容区域根据 Tab 动态切换
            if manager.selectedTab == .apps {
                appsManagementView
            } else {
                DiskCleanerView(service: cleanerService)
            }
        }
        .frame(width: PanelLayout.width, height: PanelLayout.height)
        .sheet(isPresented: $manager.showingIgnoredSheet) {
            IgnoredAppsView(manager: manager)
        }
        .onAppear {
            if manager.selectedTab == .cleaner {
                cleanerService.scanIfNeeded()
            }
        }
    }

    // MARK: - 顶部双标签切换栏
    private var topNavTabBar: some View {
        HStack(spacing: 4) {
            ForEach(NavigationTab.allCases) { tab in
                Button(action: {
                    manager.selectedTab = tab
                    if tab == .cleaner {
                        cleanerService.scanIfNeeded()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 11))
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: manager.selectedTab == tab ? .semibold : .regular))
                    }
                    .foregroundColor(manager.selectedTab == tab ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        manager.selectedTab == tab ?
                        Color(nsColor: .controlBackgroundColor) :
                        Color.clear
                    )
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.6))
        .cornerRadius(8)
    }

    // MARK: - 应用管理主视图
    private var appsManagementView: some View {
        VStack(spacing: 0) {
            // 1. 搜索与刷新
            headerView
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)

            // 2. 分类切换标签 + 排序
            categorySelectorView
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

            Divider()

            // 3. 运行列表
            ScrollView {
                VStack(spacing: 10) {
                    runningSection

                    if !manager.filteredRecentApps.isEmpty {
                        recentSection
                    }

                    if manager.filteredRunningApps.isEmpty && manager.filteredRecentApps.isEmpty {
                        emptyStateView
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // 4. 底部状态与设置
            footerView
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
    }

    // MARK: - 搜索栏
    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 13))

            TextField("搜索名称、PID 或命令行...", text: $manager.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !manager.searchText.isEmpty {
                Button(action: {
                    manager.searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }

            Button(action: {
                manager.refresh()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("立即刷新应用列表")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - 分类选择与排序
    private var categorySelectorView: some View {
        HStack(spacing: 6) {
            ForEach(AppCategory.allCases) { category in
                Button(action: {
                    manager.selectedCategory = category
                }) {
                    Text(category.rawValue)
                        .font(.system(size: 11, weight: manager.selectedCategory == category ? .semibold : .regular))
                        .foregroundColor(manager.selectedCategory == category ? .primary : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            manager.selectedCategory == category ?
                            Color(nsColor: .selectedControlColor).opacity(0.18) :
                            Color(nsColor: .controlBackgroundColor).opacity(0.5)
                        )
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            Spacer()

            Menu {
                Picker("排序", selection: $manager.sortMode) {
                    ForEach(AppSortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 9))
                    Text(manager.sortMode.rawValue)
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("切换排序方式")
        }
    }

    // MARK: - 运行中应用分区
    private var runningSection: some View {
        let apps = manager.filteredRunningApps
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("正在运行")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                Text("\(apps.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color(nsColor: .quaternaryLabelColor))
                    .cornerRadius(4)

                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            LazyVStack(spacing: 2) {
                ForEach(apps) { app in
                    AppRowView(item: app, manager: manager)
                }
            }
        }
    }

    // MARK: - 最近退出分区
    private var recentSection: some View {
        let apps = manager.filteredRecentApps
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("最近退出")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                Text("\(apps.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color(nsColor: .quaternaryLabelColor))
                    .cornerRadius(4)

                Spacer()

                Button(action: {
                    manager.clearRecentHistory()
                }) {
                    Text("清空")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)

            LazyVStack(spacing: 2) {
                ForEach(apps) { app in
                    RecentRowView(item: app, manager: manager)
                }
            }
        }
    }

    // MARK: - 空状态
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.top, 40)

            Text(manager.searchText.isEmpty ? "暂无运行中的应用" : "未搜索到匹配的应用")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Button("刷新列表") {
                manager.refresh()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 底部快捷栏
    private var footerView: some View {
        HStack(spacing: 8) {
            if let toast = manager.toastMessage {
                Text(toast)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                    .lineLimit(2)
                    .transition(.opacity)
            } else {
                Text(manager.hotKeyRegistered ? "快捷键: \(manager.hotKeyPreset.title)" : "快捷键 \(manager.hotKeyPreset.title) 不可用")
                    .font(.system(size: 10))
                    .foregroundColor(manager.hotKeyRegistered ? Color.secondary.opacity(0.8) : Color.orange)
                    .help("随时按此快捷键呼出面板，可在右侧菜单中更换")

                if !manager.ignoredBundleIds.isEmpty {
                    Button(action: {
                        manager.showingIgnoredSheet = true
                    }) {
                        Text("已忽略 (\(manager.ignoredBundleIds.count))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Menu {
                Button("立即刷新") {
                    manager.refresh()
                }

                Divider()

                Toggle("开机自动启动", isOn: Binding(
                    get: { manager.launchAtLogin },
                    set: { manager.setLaunchAtLogin($0) }
                ))

                Picker("全局快捷键", selection: Binding(
                    get: { manager.hotKeyPreset.id },
                    set: { manager.applyHotKey(HotKeyPreset.preset(withId: $0)) }
                )) {
                    ForEach(HotKeyPreset.all) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                }

                Divider()

                Button("退出 菜单栏应用管家") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
        .animation(.easeInOut(duration: 0.2), value: manager.toastMessage)
    }
}

// MARK: - 已忽略列表管理
struct IgnoredAppsView: View {
    @ObservedObject var manager: AppManager

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("已忽略的应用")
                    .font(.headline)
                Spacer()
                Button("完成") {
                    manager.showingIgnoredSheet = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 8)

            if manager.ignoredBundleIds.isEmpty {
                Text("暂无忽略的应用")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                List(manager.ignoredBundleIds, id: \.self) { bundleId in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(FilterRules.shared.displayName(for: bundleId))
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(bundleId)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("取消忽略") {
                            manager.unignoreApp(bundleId)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340, height: 280)
    }
}
