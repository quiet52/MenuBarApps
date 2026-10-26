import Foundation

public enum CleanerCategory: String, CaseIterable, Identifiable {
    case browser = "浏览器缓存"
    case developer = "开发编译缓存"
    case package = "包管理器与下载"
    case systemTemp = "临时工件与更新"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .browser: return "globe"
        case .developer: return "hammer.fill"
        case .package: return "shippingbox.fill"
        case .systemTemp: return "trash.fill"
        }
    }
}

public struct CleanerSubItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public let isDirectory: Bool

    public init(id: String, name: String, path: String, sizeBytes: Int64, isDirectory: Bool) {
        self.id = id
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
    }

    public var sizeString: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

public struct CleanerItem: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let safetyRationale: String
    /// 清理的代价（如需要重新编译、重新下载）。为 nil 表示几乎没有代价
    public let costNote: String?
    public let category: CleanerCategory
    /// 展示用路径（单目录时即清理目标）
    public let url: URL
    /// 实际要清理的目录（例如同一项目下的多个 __pycache__）
    public let targets: [URL]
    /// true：只清空目录内的内容，保留目录本身（系统 / 应用缓存根目录）
    public let clearsContentsOnly: Bool
    /// 是否默认勾选（无代价的缓存才默认勾选）
    public let isRecommended: Bool
    public var sizeBytes: Int64
    public var isSelected: Bool

    public init(
        id: String? = nil,
        title: String,
        subtitle: String,
        safetyRationale: String = "该目录仅包含临时生成的缓存，清理后软件会自动重建，不影响账号数据与正常使用。",
        costNote: String? = nil,
        category: CleanerCategory,
        url: URL,
        targets: [URL]? = nil,
        clearsContentsOnly: Bool = false,
        isRecommended: Bool = true,
        sizeBytes: Int64,
        isSelected: Bool? = nil
    ) {
        self.id = id ?? url.path
        self.title = title
        self.subtitle = subtitle
        self.safetyRationale = safetyRationale
        self.costNote = costNote
        self.category = category
        self.url = url
        self.targets = targets ?? [url]
        self.clearsContentsOnly = clearsContentsOnly
        self.isRecommended = isRecommended
        self.sizeBytes = sizeBytes
        self.isSelected = isSelected ?? isRecommended
    }

    public var sizeString: String {
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(sizeBytes)
        hasher.combine(isSelected)
    }

    public static func == (lhs: CleanerItem, rhs: CleanerItem) -> Bool {
        return lhs.id == rhs.id &&
               lhs.sizeBytes == rhs.sizeBytes &&
               lhs.isSelected == rhs.isSelected
    }
}
