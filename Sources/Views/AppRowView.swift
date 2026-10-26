import SwiftUI
import AppKit

struct AppRowView: View {
    let item: AppItem
    @ObservedObject var manager: AppManager
    
    // 内存预警阈值（图形应用已合并 Helper 进程，阈值相应放宽）
    private static let warnThreshold: UInt64 = 500 * 1024 * 1024
    private static let dangerThreshold: UInt64 = 1536 * 1024 * 1024
    
    // CPU 预警阈值（百分比，100 = 占满一个核心）
    private static let cpuWarnThreshold: Double = 50

    private var memoryBytes: UInt64 { item.memoryBytes ?? 0 }

    private func resourceColumn(isQuitting: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let mem = item.memoryString {
                Text(mem)
                    .font(.system(size: 10, weight: memoryBytes > Self.warnThreshold ? .medium : .regular, design: .monospaced))
                    .foregroundColor(
                        memoryBytes > Self.dangerThreshold ? .red :
                        (memoryBytes > Self.warnThreshold ? .orange : .secondary)
                    )
                    .help(item.processCount > 1 ? "与活动监视器口径一致，已合并 \(item.processCount) 个相关进程（Helper / 子进程）" : "与活动监视器口径一致的内存占用")
            }

            if let cpu = item.cpuString, !isQuitting {
                Text("CPU \(cpu)")
                    .font(.system(size: 10, weight: (item.cpuPercent ?? 0) > Self.cpuWarnThreshold ? .medium : .regular, design: .monospaced))
                    .foregroundColor((item.cpuPercent ?? 0) > Self.cpuWarnThreshold ? .orange : .secondary)
                    .help("相邻两次刷新之间的平均占用，100% 表示占满一个 CPU 核心；多进程应用为各进程之和")
            }
        }
        .frame(width: 62, alignment: .trailing)
    }
    
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
                    
                    if let cmd = item.commandLine {
                        Text("·")
                        Text(cmd)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(item.fullCommandLine ?? cmd)
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }
            
            Spacer()

            // 资源占用列：内存在上、CPU 在下，固定宽度，不挤压左侧文字
            resourceColumn(isQuitting: isQuitting)

            // 快捷操作按钮 (具有即时点击状态反馈)
            HStack(spacing: 5) {
                if item.isCliProcess {
                    // 1. 重启按钮（仅限可由本工具重新拉起的服务，如 ollama serve）
                    if item.canRestart {
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
                        .help("重启此服务（先结束再重新运行 ollama serve）")
                    }
                    
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
                    .help("终止进程：先发送 SIGTERM，3 秒内未退出则强制结束")
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
                    .help("重启此应用：等待其完全退出后再重新打开（释放内存）")
                    
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
                if item.canRestart {
                    Button(action: { manager.restartApp(item) }) {
                        Label("重启服务", systemImage: "arrow.clockwise")
                    }
                }
                
                Button(action: { manager.quitApp(item) }) {
                    Label("终止进程 (SIGTERM)", systemImage: "xmark.circle")
                }
                
                Button(role: .destructive, action: { manager.quitApp(item, force: true) }) {
                    Label("强制结束 (SIGKILL)", systemImage: "bolt.fill")
                }
                
                Divider()
                
                if let pid = item.pid {
                    Button(action: { manager.copyToPasteboard(String(pid)) }) {
                        Label("复制 PID", systemImage: "number")
                    }
                }
                
                if let cmd = item.fullCommandLine {
                    Button(action: { manager.copyToPasteboard(cmd) }) {
                        Label("复制完整命令行", systemImage: "doc.on.doc")
                    }
                }
                
                Button(action: { manager.showInFinder(item) }) {
                    Label("在访达中显示可执行文件", systemImage: "folder")
                }
            } else {
                Button(action: { manager.activateApp(item) }) {
                    Label("在台前打开 / 激活", systemImage: "macwindow.and.cursorarrow")
                }
                
                Button(action: { manager.restartApp(item) }) {
                    Label("重启应用 (释放内存)", systemImage: "arrow.clockwise")
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

