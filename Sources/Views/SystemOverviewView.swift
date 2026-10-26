import SwiftUI

public struct SystemOverviewView: View {
    @ObservedObject var monitor: SystemMonitor

    public init(monitor: SystemMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                monitor.isExpanded.toggle()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: monitor.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("系统概览")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    if !monitor.isExpanded {
                        Text(collapsedSummary)
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
                .foregroundColor(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if monitor.isExpanded {
                VStack(spacing: 6) {
                    metricRow(title: "CPU", value: percentText(monitor.cpuUsage), fraction: monitor.cpuUsage)
                    metricRow(title: "内存", value: memoryText, fraction: memoryFraction)
                    metricRow(title: "GPU", value: percentText(monitor.gpuUsage), fraction: monitor.gpuUsage)
                    metricRow(title: "下载", value: rateText(monitor.downloadBytesPerSec), fraction: nil)
                    metricRow(title: "上传", value: rateText(monitor.uploadBytesPerSec), fraction: nil)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - 单行指标

    private func metricRow(title: String, value: String, fraction: Double?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 34, alignment: .leading)

            if let fraction {
                usageBar(fraction)
            } else {
                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 128, alignment: .trailing)
        }
    }

    private func usageBar(_ fraction: Double) -> some View {
        let clamped = min(max(fraction, 0), 1)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .quaternaryLabelColor))
                Capsule()
                    .fill(clamped > 0.85 ? Color.orange : Color.accentColor)
                    .frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: 5)
    }

    // MARK: - 文本格式化

    private var collapsedSummary: String {
        "CPU \(percentText(monitor.cpuUsage))  内存 \(percentText(memoryFraction))"
    }

    private var memoryFraction: Double? {
        guard let used = monitor.memoryUsedBytes, monitor.memoryTotalBytes > 0 else { return nil }
        return Double(used) / Double(monitor.memoryTotalBytes)
    }

    private var memoryText: String {
        guard let used = monitor.memoryUsedBytes else { return "—" }
        return "\(byteText(Int64(used))) / \(byteText(Int64(monitor.memoryTotalBytes)))"
    }

    private func percentText(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    private func rateText(_ bytesPerSec: Double?) -> String {
        guard let bytesPerSec else { return "—" }
        return "\(byteText(Int64(bytesPerSec)))/s"
    }

    private func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }
}
