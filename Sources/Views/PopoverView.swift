import SwiftUI
import AppKit

public struct PopoverView: View {
    @ObservedObject var manager: AppManager
    
    public init(manager: AppManager) {
        self.manager = manager
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部搜索与刷新
            headerView
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            // 2. 分类切换标签
            categorySelectorView
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            
            Divider()
            
            // 3. 中间可滚动列表 (确保占满剩余可用高度，杜绝 0 高度折叠)
            ScrollView {
                VStack(spacing: 10) {
                    // 正在运行列表
                    runningSection
                    
                    // 最近退出列表
                    if !manager.filteredRecentApps.isEmpty {
                        recentSection
                    }
                    
                    // 空状态
                    if manager.filteredRunningApps.isEmpty && manager.filteredRecentApps.isEmpty {
                        emptyStateView
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // 4. 底部快捷提示与操作
            footerView
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(width: 340, height: 480)
        .sheet(isPresented: $manager.showingIgnoredSheet) {
            IgnoredAppsView(manager: manager)
        }
    }
    
    // MARK: - 搜索栏
    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 13))
            
            TextField("搜索应用名称或 PID...", text: $manager.searchText)
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
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - 分类选择
    private var categorySelectorView: some View {
        HStack(spacing: 6) {
            ForEach(AppCategory.allCases) { category in
                Button(action: {
                    manager.selectedCategory = category
                }) {
                    Text(category.rawValue)
                        .font(.system(size: 11, weight: manager.selectedCategory == category ? .semibold : .regular))
                        .foregroundColor(manager.selectedCategory == category ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
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
        }
    }
    
    // MARK: - 运行中应用分区
    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("正在运行")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text("\(manager.filteredRunningApps.count)")
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
                ForEach(manager.filteredRunningApps) { app in
                    AppRowView(item: app, manager: manager)
                }
            }
        }
    }
    
    // MARK: - 最近退出分区
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("最近退出")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text("\(manager.filteredRecentApps.count)")
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
                ForEach(manager.filteredRecentApps) { app in
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
        HStack {
            Text("快捷键: ⌥⇧A")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.8))
                .help("随时按 Option + Shift + A 呼出此面板")
            
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
            
            Spacer()
            
            Menu {
                Button("全部重新扫描") {
                    manager.refresh()
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
                        Text(bundleId)
                            .font(.system(size: 12))
                            .lineLimit(1)
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
        .frame(width: 320, height: 260)
    }
}
