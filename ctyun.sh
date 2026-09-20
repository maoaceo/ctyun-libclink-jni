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
    qr)
        TODAY_LOG="$LOG_DIR/$(date +%Y-%m-%d).log"
        if [ ! -f "$TODAY_LOG" ]; then
            echo "[!] 暂未找到今天的客户端日志，请先执行: $0 start"
            exit 1
        fi
        QR_URL=$(grep -o 'https://desk.ctyun.cn[^ "]\{1,\}' "$TODAY_LOG" | grep -E 'login-confirm|qrCode' | tail -n 1)
        if [ -n "$QR_URL" ]; then
            echo "=========================================================="
            echo "📱 天翼云电脑官方登录二维码直链:"
            echo "$QR_URL"
            echo "=========================================================="
            echo "在浏览器打开上述链接，或使用手机微信/App扫描即可登录！"
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
        echo "用法: $0 {start|stop|restart|status|qr|log}"
        exit 1
        ;;
esac
