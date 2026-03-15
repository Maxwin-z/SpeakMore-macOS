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
TARGET="SpeakMoreLite"
BUNDLE_ID="cn.byutech.SpeakMoreLite"
TEAM_ID="BS4GBZN537"
SIGN_IDENTITY="Developer ID Application: Shanghai Baiyu Information Technology Company Limited (BS4GBZN537)"
KEYCHAIN_PROFILE="SpeakMoreLite-Notary"

# --- 目录 ---
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
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
rm -rf "${DMG_STAGING}" "${DMG_PATH}"

# --- Step 2: 构建 Release ---
echo "▶ [2/6] 构建 Release..."
xcodebuild build \
    -project "${PROJECT_DIR}/${APP_NAME}.xcodeproj" \
    -target "${TARGET}" \
    -configuration Release \
    SYMROOT="${BUILD_DIR}" \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    MARKETING_VERSION="${VERSION}" \
    -quiet

APP_PATH="${BUILD_DIR}/Release/${APP_NAME}.app"
echo "  ✓ 构建完成: ${APP_PATH}"

# --- Step 3: 签名（Developer ID + Hardened Runtime）---
echo "▶ [3/6] 代码签名..."

# 对 App 内所有可执行文件和框架递归签名
codesign --force --deep --options runtime \
    --entitlements "${PROJECT_DIR}/${APP_NAME}.entitlements" \
    --sign "${SIGN_IDENTITY}" \
    "${APP_PATH}"

echo "  ✓ 签名完成"

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
rm -rf "${DMG_STAGING}"
