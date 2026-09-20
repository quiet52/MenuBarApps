import SwiftUI
import AppKit

public struct DiskCleanerView: View {
    @ObservedObject var service: DiskCleanerService
    
    public init(service: DiskCleanerService) {
        self.service = service
    }
    
    public var body: some View {
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
                    if service.isScanning && service.items.isEmpty {
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
                    Text("可安全释放:")
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
        HStack(spacing: 10) {
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
            
            // 描述
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(item.subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 大小标签
            Text(item.sizeString)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(
                    item.sizeBytes > 500 * 1024 * 1024 ? .orange : .primary
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
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
            
            Text("你的 Mac 极其干净！")
                .font(.system(size: 13, weight: .medium))
            
            Text("未发现超过 1MB 的冗余大缓存。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 底部清理与全选
    private var bottomActionBar: some View {
        HStack {
            // 全选与反选
            Button(action: {
                if service.items.allSatisfy({ $0.isSelected }) {
                    service.deselectAll()
                } else {
                    service.selectAll()
                }
            }) {
                Text(service.items.allSatisfy({ $0.isSelected }) ? "取消全选" : "全选")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(service.items.isEmpty || service.isCleaning)
            
            Spacer()
            
            // 一键清理按钮
            Button(action: {
                service.cleanSelected()
            }) {
                HStack(spacing: 6) {
                    if service.isCleaning {
                        ProgressView()
                            .controlSize(.mini)
                        Text("清理中...")
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("一键清理 (\(service.selectedBytesString))")
                    }
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(service.selectedBytes == 0 || service.isCleaning || service.isScanning)
        }
    }
}
