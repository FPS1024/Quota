#!/bin/bash

# ============================================================
#  iOS IPA 打包脚本 (TrollStore 免签版)
#  使用方式: 将此脚本放在 Xcode 项目根目录下运行
#  作者: Kaysarjan @fps10243@gmail.com
# ============================================================

set -e

# ── 颜色输出 ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[✔]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[✘]${NC}    $1"; exit 1; }
log_step()    { echo -e "\n${BOLD}${CYAN}▶ $1${NC}"; }

# ── 欢迎横幅 ────────────────────────────────────────────────
echo -e "${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║      iOS IPA 打包脚本 (TrollStore)        ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ── Step 1: 确定项目目录 ─────────────────────────────────────
log_step "Step 1/7 · 确定项目目录"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
log_info "项目根目录: ${PROJECT_DIR}"

# ── Step 2: 查找 Xcode ──────────────────────────────────────
log_step "Step 2/7 · 查找 Xcode"

XCODE_PATH=""

# 优先查找用户级 Applications
USER_XCODE=$(find ~/Applications -maxdepth 2 -name "Xcode*.app" 2>/dev/null | head -1)
if [ -n "$USER_XCODE" ]; then
    XCODE_PATH="$USER_XCODE"
    log_success "找到用户级 Xcode: $XCODE_PATH"
fi

# 其次查找系统级 Applications
if [ -z "$XCODE_PATH" ]; then
    SYS_XCODE=$(find /Applications -maxdepth 2 -name "Xcode*.app" 2>/dev/null | head -1)
    if [ -n "$SYS_XCODE" ]; then
        XCODE_PATH="$SYS_XCODE"
        log_success "找到系统级 Xcode: $XCODE_PATH"
    fi
fi

[ -z "$XCODE_PATH" ] && log_error "未找到 Xcode，请确认已安装 Xcode"

# 设置 xcode-select 指向找到的 Xcode
XCODE_DEVELOPER="${XCODE_PATH}/Contents/Developer"
log_info "设置 xcode-select → $XCODE_DEVELOPER"
sudo xcode-select --switch "$XCODE_DEVELOPER" 2>/dev/null || \
    log_warn "xcode-select 切换失败（可能需要密码），将继续尝试..."

XCODEBUILD="${XCODE_DEVELOPER}/usr/bin/xcodebuild"
[ ! -f "$XCODEBUILD" ] && log_error "在 $XCODEBUILD 找不到 xcodebuild"
log_success "xcodebuild 路径: $XCODEBUILD"

# ── Step 3: 查找 .xcodeproj / .xcworkspace & 选择 Scheme ────
log_step "Step 3/7 · 查找项目文件并选择 Scheme"

# 优先使用 .xcworkspace（CocoaPods 项目）
WORKSPACE=$(find "$PROJECT_DIR" -maxdepth 2 -name "*.xcworkspace" \
    ! -path "*/xcodeproj/*" 2>/dev/null | head -1)
XCPROJECT=$(find "$PROJECT_DIR" -maxdepth 2 -name "*.xcodeproj" 2>/dev/null | head -1)

if [ -n "$WORKSPACE" ]; then
    BUILD_FLAG="-workspace"
    BUILD_TARGET="$WORKSPACE"
    log_success "检测到 Workspace: $(basename "$WORKSPACE")"
elif [ -n "$XCPROJECT" ]; then
    BUILD_FLAG="-project"
    BUILD_TARGET="$XCPROJECT"
    log_success "检测到 Project: $(basename "$XCPROJECT")"
else
    log_error "在 $PROJECT_DIR 中未找到 .xcworkspace 或 .xcodeproj"
fi

# 列出所有 Scheme
log_info "正在列出可用 Scheme..."
SCHEMES=$("$XCODEBUILD" $BUILD_FLAG "$BUILD_TARGET" -list 2>/dev/null \
    | awk '/Schemes:/,/^$/' | grep -v "Schemes:" | sed 's/^[[:space:]]*//' | grep -v '^$')

if [ -z "$SCHEMES" ]; then
    log_error "未能获取 Scheme 列表，请检查项目是否正常"
fi

echo ""
echo -e "${BOLD}请选择 Scheme:${NC}"
IFS=$'\n' read -rd '' -a SCHEME_ARRAY <<< "$SCHEMES" || true
for i in "${!SCHEME_ARRAY[@]}"; do
    echo "  $((i+1))) ${SCHEME_ARRAY[$i]}"
done
echo ""
read -rp "输入编号 [1-${#SCHEME_ARRAY[@]}]: " SCHEME_CHOICE

# 验证输入
if ! [[ "$SCHEME_CHOICE" =~ ^[0-9]+$ ]] || \
   [ "$SCHEME_CHOICE" -lt 1 ] || \
   [ "$SCHEME_CHOICE" -gt "${#SCHEME_ARRAY[@]}" ]; then
    log_error "无效的选择: $SCHEME_CHOICE"
fi

SELECTED_SCHEME="${SCHEME_ARRAY[$((SCHEME_CHOICE-1))]}"
log_success "已选择 Scheme: ${SELECTED_SCHEME}"

# ── Step 4: 选择 Configuration ──────────────────────────────
log_step "Step 4/7 · 选择编译配置"
echo ""
echo -e "${BOLD}请选择编译配置:${NC}"
echo "  1) Debug"
echo "  2) Release"
echo ""
read -rp "输入编号 [1-2]: " CONFIG_CHOICE

case "$CONFIG_CHOICE" in
    1) CONFIGURATION="Debug"  ;;
    2) CONFIGURATION="Release" ;;
    *) log_error "无效的选择: $CONFIG_CHOICE" ;;
esac
log_success "已选择配置: ${CONFIGURATION}"

# ── Step 5: 编译 ─────────────────────────────────────────────
log_step "Step 5/7 · 开始编译 (arch: arm64)"

# Xcode DerivedData 默认路径
DERIVED_DATA_PATH="${XCODE_DEVELOPER}/../../../DerivedData"
DERIVED_DATA_PATH=$(eval echo "$DERIVED_DATA_PATH")   # 展开 ~

# 也可用自定义路径避免权限问题
BUILD_DIR="${PROJECT_DIR}/build_output"
mkdir -p "$BUILD_DIR"

log_info "DerivedData 输出目录: ${BUILD_DIR}"
log_info "正在编译，请稍候..."

"$XCODEBUILD" \
    $BUILD_FLAG "$BUILD_TARGET" \
    -scheme "$SELECTED_SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk iphoneos \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CONFIGURATION_BUILD_DIR="${BUILD_DIR}" \
    clean build 2>&1 | tee "${PROJECT_DIR}/build.log" | \
    grep -E "^(=|Build|error:|warning:|CompileC|Ld |CodeSign|Touch )" || true

log_success "编译完成！详细日志已保存至 build.log"

# ── Step 6: 查找 .app 并打包成 IPA ──────────────────────────
log_step "Step 6/7 · 查找 .app 文件并打包为 IPA"

APP_PATH=$(find "$BUILD_DIR" -maxdepth 3 -name "*.app" 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    # 回退：在 DerivedData 中查找
    log_warn "在 build_output 中未找到 .app，正在搜索 DerivedData..."
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "*.app" \
        -path "*/${CONFIGURATION}-iphoneos/*" 2>/dev/null \
        | grep -v ".xctest" | head -1)
fi

[ -z "$APP_PATH" ] && log_error "未找到编译产物 .app，请检查 build.log"

APP_NAME=$(basename "$APP_PATH" .app)
log_success "找到 .app: $APP_PATH"
log_info "App 名称: ${APP_NAME}"

# 创建 Payload 目录
PAYLOAD_DIR="${PROJECT_DIR}/Payload"
IPA_PATH="${PROJECT_DIR}/${APP_NAME}.ipa"

log_info "创建 Payload 目录..."
rm -rf "$PAYLOAD_DIR"
mkdir -p "$PAYLOAD_DIR"

log_info "拷贝 .app 到 Payload..."
cp -r "$APP_PATH" "${PAYLOAD_DIR}/"

log_info "压缩为 .ipa..."
cd "$PROJECT_DIR"
zip -r "${APP_NAME}.ipa" "Payload" -x "*.DS_Store" 2>/dev/null
cd - > /dev/null

# 清理临时文件
rm -rf "$PAYLOAD_DIR"

[ ! -f "$IPA_PATH" ] && log_error "IPA 生成失败，请检查日志"

# ── Step 7: 完成 ─────────────────────────────────────────────
log_step "Step 7/7 · 打包完成"

IPA_SIZE=$(du -sh "$IPA_PATH" | cut -f1)
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗"
echo -e "║           🎉  打包成功！                  ║"
echo -e "╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}App 名称:${NC}    ${APP_NAME}"
echo -e "  ${BOLD}配置:${NC}        ${CONFIGURATION}"
echo -e "  ${BOLD}Scheme:${NC}      ${SELECTED_SCHEME}"
echo -e "  ${BOLD}IPA 路径:${NC}    ${IPA_PATH}"
echo -e "  ${BOLD}文件大小:${NC}    ${IPA_SIZE}"
echo ""
echo -e "  ${CYAN}→ 使用 TrollStore 安装 IPA 即可完成部署${NC}"
echo ""

# 可选：直接在 Finder 中显示 IPA
open -R "$IPA_PATH" 2>/dev/null || true
