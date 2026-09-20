#!/bin/bash
# ==========================================================
# 天翼云 Clink 原生客户端一键下载与环境初始化脚本
# ==========================================================
set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${BASE_DIR}/bin"
CORE_DEB="https://desk.ctyun.cn/desktop/software/clientsoftware/download/7996be544023a0e2432281e1363f9fe2"

echo "=========================================================="
echo "正在准备天翼云官方 Linux 原生视讯引擎 (Clink / QUIC)..."
echo "=========================================================="

mkdir -p "${BIN_DIR}"

if [ ! -f "${BIN_DIR}/clouddesktop-qml" ]; then
    echo "[1/3] 下载官方 Linux x86_64 原生客户端包 (175MB)..."
    TMP_DEB="/tmp/ctyun_client.deb"
    curl -L --progress-bar -o "${TMP_DEB}" "${CORE_DEB}"
    
    echo "[2/3] 解包核心视讯引擎与原生库..."
    TMP_EXTRACT="/tmp/ctyun_extract_$$"
    mkdir -p "${TMP_EXTRACT}"
    dpkg-deb -x "${TMP_DEB}" "${TMP_EXTRACT}"
    
    cp -r "${TMP_EXTRACT}/opt/ctg/CtyunClouddeskPublic"/* "${BIN_DIR}/"
    rm -rf "${TMP_EXTRACT}" "${TMP_DEB}"
    echo "[OK] 官方核心引擎提取完成！"
else
    echo "[*] 官方原生引擎已存在: ${BIN_DIR}/clouddesktop-qml"
fi

echo "[3/3] 安装轻量 Xvfb 虚拟屏幕及 XCB 运行依赖..."
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq xvfb qrencode libasound2 libpixman-1-0 libopus0 libpulse0 libnss3 libnspr4 libxdamage1 libxss1 libxslt1.1 libv4l-0 libgudev-1.0-0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-render0 libxcb-xkb1 libxkbcommon-x11-0 libxkbcommon0
fi

echo "=========================================================="
echo "环境部署就绪！"
echo "=========================================================="
