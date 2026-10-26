#!/bin/bash
set -e

# 版本号只在这里维护一处
VERSION="1.5.0"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="MenuBarApps"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
ZIP_NAME="$PROJECT_DIR/$APP_NAME-v$VERSION.zip"
# 可通过环境变量指定稳定的签名证书（如 "Apple Development: xxx"），
# 这样重新编译后系统不会把它当成新应用（登录项等授权不会失效）。默认使用临时签名。
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

echo "🔨 正在编译 $APP_NAME v$VERSION (Release 模式)..."
cd "$PROJECT_DIR"
swift build -c release

echo "📦 正在打包为 macOS 应用包 ($APP_NAME.app)..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制可执行文件
BIN_PATH=$(swift build -c release --show-bin-path)/$APP_NAME
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 复制高清 App 图标
if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# 创建 Info.plist
cat << PLIST > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.quiet52.MenuBarApps</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>菜单栏应用管家</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "🔏 进行签名 ($SIGN_IDENTITY)..."
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

echo "🗜️ 正在生成便于分享的 Zip 压缩包..."
rm -f "$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_NAME"

echo "🚀 同步更新到 /Applications/ 目录..."
WAS_RUNNING=0
if pgrep -x "$APP_NAME" > /dev/null; then
    WAS_RUNNING=1
    pkill -x "$APP_NAME" || true
    sleep 1
fi
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"

if [ "$WAS_RUNNING" = "1" ]; then
    open "/Applications/$APP_NAME.app"
fi

echo "✅ 打包完成！"
echo "  - 应用程序: $APP_BUNDLE"
echo "  - 安装目录: /Applications/$APP_NAME.app"
echo "  - 分享压缩包: $ZIP_NAME"
