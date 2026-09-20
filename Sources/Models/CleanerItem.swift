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

public struct CleanerItem: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let category: CleanerCategory
    public let url: URL
    public var sizeBytes: Int64
    public var isSelected: Bool
    
    public init(
        title: String,
        subtitle: String,
        category: CleanerCategory,
        url: URL,
        sizeBytes: Int64,
        isSelected: Bool = true
    ) {
        self.id = url.path
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.url = url
        self.sizeBytes = sizeBytes
        self.isSelected = isSelected
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
