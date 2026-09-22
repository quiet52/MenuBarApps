import SwiftUI
import AppKit

struct AppRowView: View {
    let item: AppItem
    @ObservedObject var manager: AppManager
    
    var body: some View {
        let isOpening = manager.openingAppIds.contains(item.id)
        let isRestarting = manager.restartingAppIds.contains(item.id)
        let isQuitting = manager.quittingAppIds.contains(item.id)
        
        HStack(spacing: 10) {
            // 应用图标 (退出时变暗)
            if item.isCliProcess {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: item.name.lowercased().contains("ollama") ? "sparkles" : "terminal.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.purple)
                }
                .opacity(isQuitting ? 0.4 : 1.0)
            } else {
                Image(nsImage: item.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)
                    .opacity(isQuitting ? 0.4 : 1.0)
            }
            
            // 应用信息与标签
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isQuitting ? .secondary : .primary)
                        .lineLimit(1)
                    
                    // 类型标记
                    let tagTitle = isQuitting ? "正在退出" : (item.isCliProcess ? "AI/服务" : (item.isAccessory ? "菜单栏" : "窗口"))
                    let tagColor: Color = isQuitting ? .red : (item.isCliProcess ? .purple : (item.isAccessory ? .orange : .blue))
                    
                    Text(tagTitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(tagColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(tagColor.opacity(0.12))
                        .cornerRadius(3)
                }
                
                // PID 与 实时内存占用显示
                HStack(spacing: 4) {
                    if let pid = item.pid {
                        Text("PID: \(pid)")
                    }
                    
                    if let mem = item.memoryString {
                        Text("·")
                        Text(mem)
                            .font(.system(size: 10, weight: (item.memoryBytes ?? 0) > 200 * 1024 * 1024 ? .medium : .regular))
                            .foregroundColor(
                                (item.memoryBytes ?? 0) > 500 * 1024 * 1024 ? .red :
                                ((item.memoryBytes ?? 0) > 200 * 1024 * 1024 ? .orange : .secondary)
                            )
                    }
                    
                    if let cmd = item.commandLine {
                        Text("·")
                        Text(cmd)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 快捷操作按钮 (具有即时点击状态反馈)
            HStack(spacing: 5) {
                if item.isCliProcess {
                    // 1. 重启按钮 (针对已知服务)
                    Button(action: {
                        manager.restartApp(item)
                    }) {
                        if isRestarting {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isQuitting || isRestarting)
                    .help("一键重启此服务")
                    
                    // 2. 终止按钮
                    Button(action: {
                        manager.quitApp(item)
                    }) {
                        Text(isQuitting ? "终止中..." : "终止")
                            .font(.system(size: 11))
                            .foregroundColor(isQuitting ? .secondary : .red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isQuitting || isRestarting)
                    .help("终止此后台/AI服务进程 (kill -15)")
                } else {
                    // 1. 打开按钮 (点击后变为“已唤起 ✓”)
                    Button(action: {
                        manager.activateApp(item)
                    }) {
                        Text(isOpening ? "已唤起 ✓" : "打开")
                            .font(.system(size: 11, weight: isOpening ? .semibold : .regular))
                            .foregroundColor(isOpening ? .blue : .primary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isQuitting || isRestarting)
                    .help("在台前激活并显示应用窗口")
                    
                    // 2. 重启按钮 (点击后立刻变为转圈 Loading)
                    Button(action: {
                        manager.restartApp(item)
                    }) {
                        if isRestarting {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isQuitting || isRestarting)
                    .help("一键重启此应用（快速释放内存）")
                    
                    // 3. 退出按钮 (点击后变为“退出中...”)
                    Button(action: {
                        manager.quitApp(item)
                    }) {
                        Text(isQuitting ? "退出中..." : "退出")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isQuitting || isRestarting)
                    .help("正常退出此应用")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .opacity(isQuitting ? 0.45 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isQuitting)
        .animation(.easeInOut(duration: 0.2), value: isOpening)
        .onTapGesture(count: 2) {
            manager.activateApp(item)
        }
        .contextMenu {
            if item.isCliProcess {
                Button(action: { manager.restartApp(item) }) {
                    Label("🔄 重启服务", systemImage: "arrow.clockwise")
                }
                
                Button(action: { manager.quitApp(item) }) {
                    Label("终止进程 (SIGTERM)", systemImage: "xmark.circle")
                }
                
                Button(role: .destructive, action: { manager.quitApp(item, force: true) }) {
                    Label("强制杀掉 (SIGKILL)", systemImage: "bolt.fill")
                }
            } else {
                Button(action: { manager.activateApp(item) }) {
                    Label("在台前打开 / 激活", systemImage: "macwindow.and.cursorarrow")
                }
                
                Button(action: { manager.restartApp(item) }) {
                    Label("🔄 重启应用 (释放内存)", systemImage: "arrow.clockwise")
                }
                
                Divider()
                
                Button(action: { manager.quitApp(item) }) {
                    Label("正常退出", systemImage: "xmark.circle")
                }
                
                Button(role: .destructive, action: { manager.quitApp(item, force: true) }) {
                    Label("强制退出", systemImage: "bolt.fill")
                }
                
                Divider()
                
                Button(action: { manager.showInFinder(item) }) {
                    Label("在访达中显示", systemImage: "folder")
                }
                
                Button(action: { manager.ignoreApp(item) }) {
                    Label("忽略此应用 (不在列表显示)", systemImage: "eye.slash")
                }
            }
        }
    }
}

