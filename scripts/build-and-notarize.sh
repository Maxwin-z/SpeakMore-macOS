#!/bin/bash
set -euo pipefail

# ============================================================
# SpeakMore Lite - 构建、签名、公证、打包 一键脚本
# 用法: ./scripts/build-and-notarize.sh [版本号]
# 示例: ./scripts/build-and-notarize.sh 0.2.0
# ============================================================

# --- 配置 ---
APP_NAME="SpeakMoreLite"
DISPLAY_NAME="SpeakMore Lite"
SCHEME="SpeakMoreLite"
BUNDLE_ID="cn.byutech.SpeakMoreLite"
TEAM_ID="BS4GBZN537"
SIGN_IDENTITY="Developer ID Application: Shanghai Baiyu Information Technology Company Limited (BS4GBZN537)"
KEYCHAIN_PROFILE="SpeakMoreLite-Notary"

# --- 目录 ---
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
DMG_STAGING="${BUILD_DIR}/dmg-staging"

# --- 版本号 ---
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION=$(grep 'MARKETING_VERSION' "${PROJECT_DIR}/project.yml" | head -1 | sed 's/.*"\(.*\)"/\1/')
    echo "未指定版本号，使用 project.yml 中的版本: ${VERSION}"
fi
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"

echo "============================================"
echo "  ${DISPLAY_NAME} v${VERSION} 构建与公证"
echo "============================================"
echo ""

# --- Step 1: 清理 ---
echo "▶ [1/6] 清理旧构建..."
rm -rf "${ARCHIVE_PATH}" "${EXPORT_DIR}" "${DMG_STAGING}" "${DMG_PATH}"

# --- Step 2: Archive ---
echo "▶ [2/6] Archive 构建..."
xcodebuild archive \
    -project "${PROJECT_DIR}/${APP_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_STYLE="Manual" \
    CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
    OTHER_CODE_SIGN_FLAGS="--options=runtime" \
    MARKETING_VERSION="${VERSION}" \
    -quiet

echo "  ✓ Archive 完成"

# --- Step 3: 导出 App ---
echo "▶ [3/6] 导出 App..."

# 创建 ExportOptions.plist
EXPORT_OPTIONS="${BUILD_DIR}/ExportOptions.plist"
cat > "${EXPORT_OPTIONS}" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    -quiet

APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"
echo "  ✓ 导出完成: ${APP_PATH}"

# --- Step 4: 验证签名 ---
echo "▶ [4/6] 验证代码签名..."
codesign --verify --deep --strict "${APP_PATH}" 2>&1
echo "  ✓ 签名有效"

# 检查 Hardened Runtime
CODESIGN_INFO=$(codesign -dvv "${APP_PATH}" 2>&1)
if echo "${CODESIGN_INFO}" | grep -q "runtime"; then
    echo "  ✓ Hardened Runtime 已启用"
else
    echo "  ✗ 警告: Hardened Runtime 未启用，公证可能失败"
    exit 1
fi

# --- Step 5: 制作并签名 DMG ---
echo "▶ [5/6] 制作 DMG..."
mkdir -p "${DMG_STAGING}"
cp -R "${APP_PATH}" "${DMG_STAGING}/"

# 创建指向 Applications 的符号链接
ln -sf /Applications "${DMG_STAGING}/Applications"

# 创建 DMG
hdiutil create -volname "${DISPLAY_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov -format UDZO \
    "${DMG_PATH}" \
    -quiet

# 签名 DMG
codesign --force --sign "${SIGN_IDENTITY}" "${DMG_PATH}"
echo "  ✓ DMG 创建并签名完成: ${DMG_PATH}"

# --- Step 6: 公证 ---
echo "▶ [6/6] 提交公证（可能需要几分钟）..."
xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${KEYCHAIN_PROFILE}" \
    --wait

# Staple
echo "  附加公证票据..."
xcrun stapler staple "${DMG_PATH}"
echo "  ✓ 公证完成并已 Staple"

# --- 最终验证 ---
echo ""
echo "▶ 最终验证..."
spctl --assess --type open --context context:primary-signature -v "${DMG_PATH}" 2>&1 || true
echo ""
echo "============================================"
echo "  ✅ 完成！"
echo "  输出: ${DMG_PATH}"
echo "  大小: $(du -h "${DMG_PATH}" | cut -f1)"
echo "============================================"
echo ""
echo "可直接上传到 GitHub Releases，用户下载后不会再出现安全警告。"

# 清理临时文件
rm -rf "${DMG_STAGING}" "${EXPORT_OPTIONS}" "${ARCHIVE_PATH}"
