#!/bin/bash
# ==========================================================
# 天翼云官方客户端依赖合并与环境初始化
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

echo "[2/2] 检查安装轻量虚拟屏幕依赖 (Xvfb, XCB, 音频库)..."
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq xvfb qrencode libasound2 libpixman-1-0 libopus0 libpulse0 libnss3 libnspr4 libxdamage1 libxss1 libxslt1.1 libv4l-0 libgudev-1.0-0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-render0 libxcb-xkb1 libxkbcommon-x11-0 libxkbcommon0
fi

echo "=========================================================="
echo "✅ 天翼云所有运行组件与环境已准备完成！"
echo "=========================================================="
