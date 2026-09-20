#!/bin/bash
# ==========================================================
# 天翼云官方客户端依赖合并与环境初始化 (兼容 Debian/Ubuntu 新老版本)
# ==========================================================
set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${BASE_DIR}/lib"

echo "[1/2] 正在还原核心动态库 libQt5WebEngineCore.so.5..."
if [ -f "${LIB_DIR}/libQt5WebEngineCore.so.5.part_aa" ]; then
    cat "${LIB_DIR}"/libQt5WebEngineCore.so.5.part_* > "${LIB_DIR}/libQt5WebEngineCore.so.5"
    echo "[OK] libQt5WebEngineCore.so.5 还原就绪！"
fi

chmod +x "${BASE_DIR}"/CtyunStart "${BASE_DIR}"/clouddesktop-qml "${BASE_DIR}"/crashpad_handler "${BASE_DIR}"/clouddesktop-daemon 2>/dev/null || true

echo "[2/2] 检查并自动适配安装系统虚拟屏幕与运行依赖..."
if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || true
    
    # 智能识别 libasound2 或 libasound2t64 (Ubuntu 24.04 / Debian 13)
    ALSA_PKG="libasound2"
    if ! apt-cache show libasound2 >/dev/null 2>&1; then
        ALSA_PKG="libasound2t64"
    fi
    
    # 逐项兼容安装核心包，单项失败不阻断整体流程
    PACKAGES="xvfb qrencode ${ALSA_PKG} libpixman-1-0 libopus0 libpulse0 libnss3 libnspr4 libxdamage1 libxss1 libxslt1.1 libv4l-0 libgudev-1.0-0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-render0 libxcb-xkb1 libxkbcommon-x11-0 libxkbcommon0"
    
    for pkg in $PACKAGES; do
        apt-get install -y -qq "$pkg" >/dev/null 2>&1 || true
    done
fi

echo "=========================================================="
echo "✅ 天翼云所有运行组件与依赖环境已准备完成！"
echo "=========================================================="
