import SwiftUI
import AppKit

public struct DiskCleanerView: View {
    @ObservedObject var service: DiskCleanerService
    
    public init(service: DiskCleanerService) {
        self.service = service
    }
    
    public var body: some View {
        if let detailItem = service.activeDetailItem {
            DiskItemDetailView(service: service, item: detailItem)
        } else {
            mainListView
        }
    }
    
    // MARK: - 主列表视图
    private var mainListView: some View {
        VStack(spacing: 0) {
            // 1. 顶部总览大卡片
            overviewHeader
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
            
            Divider()
            
            // 2. 缓存项目可滚动列表
            ScrollView {
                VStack(spacing: 8) {
                    if (service.isScanning || !service.hasScanned) && service.items.isEmpty {
                        scanningView
                    } else if service.items.isEmpty {
                        cleanEmptyView
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(service.items) { item in
                                cacheRowView(for: item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // 3. 底部快捷操作栏
            bottomActionBar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }
    
    // MARK: - 顶部总览卡片
    private var overviewHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 42, height: 42)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("已选择:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text(service.selectedBytesString)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                Text(service.statusMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: {
                service.isConfirmingClean = false
                service.scan()
            }) {
                if service.isScanning {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(service.isScanning || service.isCleaning)
            .help("重新扫描全盘缓存")
        }
    }
    
    // MARK: - 缓存单行卡片
    private func cacheRowView(for item: CleanerItem) -> some View {
        HStack(spacing: 8) {
            // 复选框
            Button(action: {
                service.toggleSelection(for: item.id)
            }) {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isSelected ? .blue : .secondary)
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            
            // 图标
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .quaternaryLabelColor))
                    .frame(width: 28, height: 28)
                
                Image(systemName: item.category.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
            }
            
            // 描述与名称（点击可直接下钻查看明细）
            Button(action: {
                service.openDetail(for: item)
            }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let cost = item.costNote {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                            Text(cost)
                                .font(.system(size: 9))
                                .lineLimit(1)
                        }
                        .foregroundColor(.orange)
                    } else {
                        Text(item.subtitle)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.costNote.map { "\(item.subtitle)\n清理代价：\($0)" } ?? item.subtitle)
            
            Spacer()
            
            // 大小标签
            Text(item.sizeString)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(
                    item.sizeBytes > 500 * 1024 * 1024 ? .orange : .primary
                )
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            
            // 详情下钻小箭头
            Button(action: {
                service.openDetail(for: item)
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)
            }
            .buttonStyle(.plain)
            .help("查看明细与在访达中显示")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.4))
        .cornerRadius(8)
    }
    
    // MARK: - 正在扫描状态
    private var scanningView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .padding(.top, 40)
            
            Text("正在全盘深度排查无用缓存...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 空状态（完全干净）
    private var cleanEmptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundColor(.green.opacity(0.8))
                .padding(.top, 40)
            
            Text("没有发现可清理的缓存")
                .font(.system(size: 13, weight: .medium))
            
            Text("未发现超过 1MB 的冗余大缓存。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 底部清理与全选（两步确认，避免误删）
    private var bottomActionBar: some View {
        let selectedCount = service.selectedItems.count
        return HStack(spacing: 8) {
            if service.isConfirmingClean {
                VStack(alignment: .leading, spacing: 1) {
                    Text("将永久删除 \(selectedCount) 项")
                        .font(.system(size: 11, weight: .semibold))
                    Text("共 \(service.selectedBytesString)，不会进入废纸篓")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("取消") {
                    service.isConfirmingClean = false
                }
                .controlSize(.small)
                
                Button(action: {
                    service.isConfirmingClean = false
                    service.cleanSelected()
                }) {
                    Text("确认清理")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            } else {
                Menu {
                    Button("只选推荐项（无代价）") { service.selectRecommended() }
                    Button("全选") { service.selectAll() }
                    Button("全不选") { service.deselectAll() }
                } label: {
                    Text("选择")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(service.items.isEmpty || service.isCleaning)
                
                Spacer()
                
                Button(action: {
                    service.isConfirmingClean = true
                }) {
                    HStack(spacing: 6) {
                        if service.isCleaning {
                            ProgressView()
                                .controlSize(.mini)
                            Text("清理中...")
                        } else {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                            Text("清理所选 (\(service.selectedBytesString))")
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(service.selectedBytes == 0 || service.isCleaning || service.isScanning)
            }
        }
        .onChange(of: service.selectedBytes) { _ in
            service.isConfirmingClean = false
        }
    }
}
