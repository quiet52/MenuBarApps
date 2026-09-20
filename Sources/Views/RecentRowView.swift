import SwiftUI
import AppKit

struct RecentRowView: View {
    let item: AppItem
    @ObservedObject var manager: AppManager
    
    private var timeString: String {
        guard let quitAt = item.quitAt else { return "最近退出" }
        let interval = Date().timeIntervalSince(quitAt)
        if interval < 60 {
            return "刚刚退出"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins) 分钟前退出"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) 小时前退出"
        } else {
            let days = Int(interval / 86400)
            return "\(days) 天前退出"
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // 图标
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .opacity(0.85)
                .cornerRadius(6)
            
            // 名称和退出时间
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(timeString)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            
            Spacer()
            
            // 重新启动按钮
            Button(action: {
                manager.relaunchApp(item)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                    Text("启动")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("重新启动该应用")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: { manager.relaunchApp(item) }) {
                Label("重新启动应用", systemImage: "arrow.clockwise")
            }
            
            Button(action: { manager.showInFinder(item) }) {
                Label("在访达中显示", systemImage: "folder")
            }
            
            Divider()
            
            Button(role: .destructive, action: { manager.removeFromRecent(item.bundleId) }) {
                Label("从历史记录中移除", systemImage: "trash")
            }
        }
    }
}
