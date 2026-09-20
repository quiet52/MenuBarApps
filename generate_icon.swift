import AppKit

func generateAppIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    
    // 背景圆角矩形 (macOS squircle 规范: 约 22.5% 圆角)
    let inset = size * 0.08
    let iconRect = rect.insetBy(dx: inset, dy: inset)
    let cornerRadius = iconRect.width * 0.225
    let path = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)
    
    // 阴影
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.03)
    shadow.shadowBlurRadius = size * 0.06
    shadow.set()
    
    // 背景渐变色: 优雅的深蓝-深青渐变 (Deep Indigo to Ocean Cyan)
    let gradient = NSGradient(
        colors: [
            NSColor(red: 0.12, green: 0.18, blue: 0.32, alpha: 1.0),
            NSColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1.0)
        ]
    )
    gradient?.draw(in: path, angle: -45)
    
    // 取消阴影避免内部元素受影响
    NSShadow().set()
    
    // 边缘高光边框
    NSColor.white.withAlphaComponent(0.15).setStroke()
    path.lineWidth = size * 0.015
    path.stroke()
    
    // 内部绘制: 菜单栏 + 应用窗口层叠图形
    let innerW = iconRect.width * 0.68
    let innerH = iconRect.height * 0.52
    let innerX = iconRect.midX - innerW / 2
    let innerY = iconRect.midY - innerH / 2
    
    // 1. 模拟顶部菜单栏小条
    let barH = innerH * 0.22
    let barRect = NSRect(x: innerX, y: innerY + innerH - barH, width: innerW, height: barH)
    let barPath = NSBezierPath(roundedRect: barRect, xRadius: barH * 0.35, yRadius: barH * 0.35)
    NSColor.white.withAlphaComponent(0.22).setFill()
    barPath.fill()
    
    // 菜单栏上的小圆点状态灯
    let dotRadius = barH * 0.22
    let dotY = barRect.midY - dotRadius
    let dot1 = NSBezierPath(ovalIn: NSRect(x: barRect.maxX - barH * 0.8, y: dotY, width: dotRadius * 2, height: dotRadius * 2))
    NSColor(red: 0.3, green: 0.85, blue: 0.45, alpha: 0.9).setFill()
    dot1.fill()
    
    let dot2 = NSBezierPath(ovalIn: NSRect(x: barRect.maxX - barH * 1.5, y: dotY, width: dotRadius * 2, height: dotRadius * 2))
    NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.9).setFill()
    dot2.fill()
    
    // 2. 模拟下方展开的应用卡片网格
    let cardGap = innerW * 0.06
    let cardW = (innerW - cardGap) / 2
    let cardH = innerH - barH - innerH * 0.12
    let cardY = innerY
    
    // 左卡片 (主面板)
    let leftCardRect = NSRect(x: innerX, y: cardY, width: cardW, height: cardH)
    let leftCardPath = NSBezierPath(roundedRect: leftCardRect, xRadius: 6 * (size / 128), yRadius: 6 * (size / 128))
    let cardGrad = NSGradient(
        colors: [
            NSColor(red: 0.25, green: 0.45, blue: 0.85, alpha: 0.85),
            NSColor(red: 0.15, green: 0.30, blue: 0.70, alpha: 0.85)
        ]
    )
    cardGrad?.draw(in: leftCardPath, angle: -60)
    
    // 右卡片
    let rightCardRect = NSRect(x: innerX + cardW + cardGap, y: cardY, width: cardW, height: cardH)
    let rightCardPath = NSBezierPath(roundedRect: rightCardRect, xRadius: 6 * (size / 128), yRadius: 6 * (size / 128))
    let rightGrad = NSGradient(
        colors: [
            NSColor(red: 0.18, green: 0.25, blue: 0.40, alpha: 0.7),
            NSColor(red: 0.12, green: 0.16, blue: 0.28, alpha: 0.7)
        ]
    )
    rightGrad?.draw(in: rightCardPath, angle: -60)
    
    img.unlockFocus()
    return img
}

let iconsetDir = "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconsetDir)
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, s) in sizes {
    let img = generateAppIcon(size: s)
    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        let path = "\(iconsetDir)/\(name)"
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

print("Iconset generated successfully")
