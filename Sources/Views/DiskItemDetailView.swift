import SwiftUI
import AppKit

public struct DiskItemDetailView: View {
    @ObservedObject var service: DiskCleanerService
    let item: CleanerItem
    
    public init(service: DiskCleanerService, item: CleanerItem) {
        self.service = service
        self.item = item
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部导航与访达快捷键
            topNavBar
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)
            
            Divider()
            
            // 2. 中间可滚动详情区域
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // 物理绝对路径展示卡片
                    pathInfoCard
                    
                    // 100% 安全说明卡片
                    safetyExplanationCard
                    
                    // 占用体积最大的具体子项
                    subItemsSection
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // 3. 底部单项清理栏
            bottomActionBar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }
    
    // MARK: - 顶部导航
    private var topNavBar: some View {
        HStack(spacing: 8) {
            Button(action: {
                service.closeDetail()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("返回")
                        .font(.system(size: 12))
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text(item.title)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
            
            Spacer()
            
            Button(action: {
                service.revealInFinder(url: item.url)
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11))
                    Text("在访达中显示")
                        .font(.system(size: 11))
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .help("在访达中定位并打开此文件夹")
        }
    }
    
    // MARK: - 路径信息卡片
    private var pathInfoCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("实际物理路径:")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            
            HStack {
                Text(item.url.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Spacer()
                
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.url.path, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("复制完整物理路径")
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        }
    }
    
    // MARK: - 安全保障卡片
    private var safetyExplanationCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 3) {
                Text("安全说明 (为什么 100% 可清理)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(item.safetyRationale)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.green.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(8)
    }
    
    // MARK: - 子项目明细
    private var subItemsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("📦 体积排查明细 (Top \(service.currentDetailSubItems.count))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if service.isLoadingSubItems {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.top, 4)
            
            if service.isLoadingSubItems && service.currentDetailSubItems.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在排查子项目大小...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else if service.currentDetailSubItems.isEmpty {
                HStack {
                    Spacer()
                    Text("该目录内暂无超过 10KB 的子项目")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                VStack(spacing: 5) {
                    ForEach(service.currentDetailSubItems) { subItem in
                        subItemRow(for: subItem)
                    }
                }
            }
        }
    }
    
    // MARK: - 单个子项目行
    private func subItemRow(for subItem: CleanerSubItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: subItem.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 11))
                .foregroundColor(subItem.isDirectory ? .blue.opacity(0.8) : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(subItem.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(subItem.sizeString)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            
            Button(action: {
                service.revealInFinder(url: URL(fileURLWithPath: subItem.path))
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("在访达中定位此项")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
        .cornerRadius(6)
    }
    
    // MARK: - 底部单项清理
    private var bottomActionBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("占用体积")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(item.sizeString)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            Button(action: {
                service.cleanSingleItem(item)
            }) {
                HStack(spacing: 5) {
                    if service.isCleaning {
                        ProgressView()
                            .controlSize(.mini)
                        Text("清理中...")
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("仅清理此项 (\(item.sizeString))")
                    }
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(service.isCleaning)
        }
    }
}
