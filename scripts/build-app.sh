#!/bin/zsh
# 编译并打包 macClean.app。
# ⚠️ 编译产物一律放在 OneDrive 外面（~/Library/Developer/macClean-build），避免 OneDrive 日志风暴。
set -euo pipefail

PROJ="${0:A:h:h}"
SCRATCH="$HOME/Library/Developer/macClean-build"
APP="$SCRATCH/macClean.app"
DEST="$HOME/Applications/macClean.app"
SIGN_ID="${MACCLEAN_SIGN_ID:-vInput Dev}"   # 固定的自签名证书：重新编译后「完全磁盘访问权限」不会失效

echo "▶ 编译（release）"
swift build -c release --package-path "$PROJ" --scratch-path "$SCRATCH"
BIN="$(swift build -c release --package-path "$PROJ" --scratch-path "$SCRATCH" --show-bin-path)/macClean"

echo "▶ 组装 .app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/macClean"
# 内置一份规则作为后备；运行时优先读项目目录（OneDrive）里的规则
cp "$PROJ/rules.json" "$PROJ/decisions.json" "$APP/Contents/Resources/"
[[ -f "$PROJ/assets/AppIcon.icns" ]] && cp "$PROJ/assets/AppIcon.icns" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.vk.macClean</string>
  <key>CFBundleName</key><string>macClean</string>
  <key>CFBundleDisplayName</key><string>macClean</string>
  <key>CFBundleExecutable</key><string>macClean</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSRequiresAquaSystemAppearance</key><true/>
</dict>
</plist>
PLIST

echo "▶ 签名（$SIGN_ID）"
codesign --force --deep --sign "$SIGN_ID" "$APP"

echo "▶ 安装到 ~/Applications"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "✅ 完成：$DEST"
