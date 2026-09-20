#!/bin/bash
# ==========================================================
# 天翼云电脑 Linux 原生无头持久保活脚本 (第一版原生极简架构)
# ==========================================================

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BIN="$BASE_DIR/CtyunStart"
LOG_DIR="$HOME/.local/share/CtyunClouddeskPublic/Log"
PID_FILE="/tmp/ctyun_keeper.pid"

case "$1" in
    start)
        if pgrep -f "clouddesktop-qml" >/dev/null 2>&1; then
            echo "[*] 官方客户端已经在运行中 (PID: $(pgrep -f clouddesktop-qml | tr '\n' ' '))"
            exit 0
        fi
        echo "[*] 正在拉起天翼云官方底层串流引擎..."
        nohup xvfb-run -a -s "-screen 0 1024x768x16 -nolisten tcp" "$APP_BIN" > /tmp/ctyun_app.log 2>&1 &
        echo $! > "$PID_FILE"
        sleep 3
        if pgrep -f "clouddesktop-qml" >/dev/null 2>&1; then
            echo "[OK] 客户端已成功拉起并进入后台持续连接！"
            echo " - 运行状态: $0 status"
            echo " - 查看二维码: $0 qr"
            echo " - 实时连接日志: $0 log"
        else
            echo "[!] 启动失败，请检查依赖或查看 /tmp/ctyun_app.log"
        fi
        ;;
    rotate)
        # 后台启动两台设备的自动开机与 20 秒真实视讯串流保活
        pkill -9 -f "boot_and_rotate.py" 2>/dev/null || true
        nohup python3 -u "$BASE_DIR/robin.py" > "$LOG_DIR/../robin.log" 2>&1 &
        echo "[OK] 自动唤醒与 20 秒真视讯轮询保活已在后台启动！"
        echo " - 查看实时保活动态: $0 log-rotate"
        ;;
    log-rotate)
        tail -f "$LOG_DIR/../robin.log"
        ;;
    stop)
        echo "[*] 正在停止天翼云官方客户端..."
        pkill -9 -f "clouddesktop-qml" 2>/dev/null || true
        pkill -9 -f "CtyunStart" 2>/dev/null || true
        pkill -9 -f "Xvfb" 2>/dev/null || true
        rm -f "$PID_FILE"
        echo "[OK] 已全部停止。"
        ;;
    status)
        PID=$(pgrep -f "clouddesktop-qml" | head -n1)
        if [ -n "$PID" ]; then
            echo "[RUNNING] 天翼云客户端正在运行中 (PID: $PID)"
            MEM=$(ps -o rss= -p "$PID" 2>/dev/null | awk '{printf "%.1f MB", $1/1024}')
            echo " - 内存占用: $MEM"
            TODAY_LOG="$LOG_DIR/$(date +%Y-%m-%d).log"
            if [ -f "$TODAY_LOG" ]; then
                echo "--- 最新连接动态 ---"
                tail -n 10 "$TODAY_LOG" | grep -E 'connectMaster|clink连接成功|收到第一张图|当前时延|tokenLogin' || tail -n 5 "$TODAY_LOG"
            fi
        else
            echo "[STOPPED] 客户端未运行。"
        fi
        ;;
    scan)
        TODAY_LOG="$LOG_DIR/$(date +%Y-%m-%d).log"
        if [ ! -f "$TODAY_LOG" ]; then
            echo "[!] 暂无今日日志，请先 ./ctyun.sh start 启动一次"
            exit 1
        fi
        python3 - << 'PY'
import json, re, os, glob

today = os.path.expanduser("~/.local/share/CtyunClouddeskPublic/Log/" + os.popen("date +%Y-%m-%d").read().strip() + ".log")
found = False
if os.path.exists(today):
    with open(today, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()
    for line in reversed(lines):
        if "pageDesktop" in line and "desktopList" in line:
            m = re.search(r'\"desktopList\":(\[.*?\]),\"preemptionDesktopList\"', line)
            if m:
                try:
                    dlist = json.loads(m.group(1))
                    print("=" * 70)
                    print(f"{'序号':<6} {'云电脑ID':<12} {'机器编码':<22} {'状态':<10} {'名称'}")
                    print("-" * 70)
                    for idx, d in enumerate(dlist, 1):
                        status = d.get('useStatusText', '未知')
                        print(f"{idx:<6} {d.get('objId'):<12} {d.get('desktopCode'):<22} {status:<10} {d.get('objName')}")
                    print("=" * 70)
                    print(f"[OK] 成功从官方接口解析到 {len(dlist)} 台设备！")
                    found = True
                    break
                except Exception:
                    pass
if not found:
    print("[!] 尚未获取到设备列表，请确保已通过 ./ctyun.sh qr 扫码登录！")
PY
        ;;
    qr)
        TODAY_LOG="$LOG_DIR/$(date +%Y-%m-%d).log"
        if [ ! -f "$TODAY_LOG" ]; then
            echo "[!] 暂未找到今天的客户端日志，请先执行: $0 start"
            exit 1
        fi
        QR_URL=$(grep -o 'https://desk.ctyun.cn[^ "]\{1,\}' "$TODAY_LOG" | grep -E 'login-confirm|qrCode' | tail -n 1)
        if [ -n "$QR_URL" ]; then
            echo "=========================================================="
            echo "📱 天翼云电脑官方登录二维码 (终端直接扫码):"
            echo "=========================================================="
            if command -v qrencode >/dev/null 2>&1; then
                qrencode -t ANSIUTF8 "$QR_URL"
            else
                python3 -c "
import urllib.parse
print('提示: 安装 qrencode 可在终端直接显示字符二维码 (apt install -y qrencode)')
"
            fi
            echo "=========================================================="
            echo "🌐 二维码网页直链 (也可复制到浏览器打开):"
            echo "$QR_URL"
            echo "=========================================================="
        else
            echo "[*] 未在最新日志中匹配到二维码，可能已经处于登录状态，或请尝试: $0 restart"
        fi
        ;;
    log)
        TODAY_LOG="$LOG_DIR/$(date +%Y-%m-%d).log"
        if [ -f "$TODAY_LOG" ]; then
            tail -f "$TODAY_LOG"
        else
            echo "[!] 日志文件尚不存在: $TODAY_LOG"
        fi
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status|scan|qr|log|rotate|log-rotate}"
        exit 1
        ;;
esac
