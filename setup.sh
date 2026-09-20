#!/bin/bash
# ==========================================================
# 天翼云官方客户端依赖合并与全系统环境一键优化脚本
# 完美兼容 Ubuntu 20.04/22.04/24.04 (t64架构) 及 Debian 10/11/12
# ==========================================================
set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${BASE_DIR}/lib"

echo "=========================================================="
echo "🚀 正在优化配置天翼云 Clink 原生视讯运行环境..."
echo "=========================================================="

# 1. 还原分卷核心运行库
echo "[1/3] 检查并还原核心运行库 libQt5WebEngineCore.so.5..."
if [ -f "${LIB_DIR}/libQt5WebEngineCore.so.5.part_aa" ]; then
    if [ ! -f "${LIB_DIR}/libQt5WebEngineCore.so.5" ] || [ $(stat -c%s "${LIB_DIR}/libQt5WebEngineCore.so.5" 2>/dev/null || echo 0) -lt 100000000 ]; then
        cat "${LIB_DIR}"/libQt5WebEngineCore.so.5.part_* > "${LIB_DIR}/libQt5WebEngineCore.so.5"
        echo "[OK] libQt5WebEngineCore.so.5 还原成功！"
    else
        echo "[*] libQt5WebEngineCore.so.5 已就绪，跳过合成。"
    fi
fi

# 2. 赋予所有组件执行权限
echo "[2/3] 配置可执行权限..."
chmod +x "${BASE_DIR}"/CtyunStart \
         "${BASE_DIR}"/clouddesktop-qml \
         "${BASE_DIR}"/crashpad_handler \
         "${BASE_DIR}"/clouddesktop-daemon \
         "${BASE_DIR}"/web_server.py \
         "${BASE_DIR}"/robin.sh \
         "${BASE_DIR}"/runner.sh 2>/dev/null || true

# 3. 智能检测并安装缺失的系统底层图形/音频/XCB库
echo "[3/3] 智能安装轻量虚拟屏幕与底层系统运行库..."
if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || true

    # 智能判断 ALSA 音频库名称 (适配 Ubuntu 24.04 t64 升级)
    ALSA_PKG="libasound2"
    if ! apt-cache show libasound2 >/dev/null 2>&1; then
        ALSA_PKG="libasound2t64"
    fi

    # 全套必需依赖库清单 (Xvfb, 图像, 音频, XCB 显示扩展, 二维码)
    PACKAGES=(
        xvfb
        qrencode
        "${ALSA_PKG}"
        libxi6
        libxcomposite1
        libxfixes3
        libxcursor1
        libxtst6
        libxrandr2
        libxcb-shape0
        libxcb-xinerama0
        libxcb-icccm4
        libxcb-image0
        libxcb-keysyms1
        libxcb-render-util0
        libxcb-render0
        libxcb-xkb1
        libxkbcommon-x11-0
        libxkbcommon0
        libpixman-1-0
        libopus0
        libpulse0
        libnss3
        libnspr4
        libxdamage1
        libxss1
        libxslt1.1
        libv4l-0
        libgudev-1.0-0
    )

    # 过滤出尚未安装的包进行增量安装，极大提升安装速度
    MISSING_PKGS=()
    for pkg in "${PACKAGES[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            MISSING_PKGS+=("$pkg")
        fi
    done

    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        echo " -> 正在自动补充 ${#MISSING_PKGS[@]} 个缺失运行依赖: ${MISSING_PKGS[*]}"
        apt-get install -y -qq "${MISSING_PKGS[@]}" >/dev/null 2>&1 || {
            # 如批量安装遇个别包冲突，自动逐个容错安装
            for p in "${MISSING_PKGS[@]}"; do
                apt-get install -y -qq "$p" >/dev/null 2>&1 || true
            done
        }
    else
        echo " -> 底层图形与运行库均已安装完备。"
    fi
fi

# 4. 运行完整性自检
echo "----------------------------------------------------------"
echo "🔍 正在进行依赖完整性自检..."
MISSING_SO=$(ldd "${BASE_DIR}/clouddesktop-qml" 2>/dev/null | grep "not found" || true)
MISSING_XCB=$(ldd "${BASE_DIR}/plugins/platforms/libqxcb.so" 2>/dev/null | grep "not found" || true)

if [ -z "$MISSING_SO" ] && [ -z "$MISSING_XCB" ]; then
    echo "✅ 自检通过！所有动态链接库 (so) 均已完整匹配，无任何缺失。"
else
    echo "⚠️ 提示: 检测到以下动态库仍缺失，可能影响特定功能:"
    echo "$MISSING_SO"
    echo "$MISSING_XCB"
fi

echo "=========================================================="
echo "🎉 天翼云官方 Clink 原生视讯引擎环境部署与优化完毕！"
echo "   启动命令: nohup python3 web_server.py > web.log 2>&1 &"
echo "=========================================================="
