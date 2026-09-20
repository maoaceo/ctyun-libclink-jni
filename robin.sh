#!/bin/bash
# ==========================================================
# 天翼云电脑 官方无头轮询保活控制脚本 (Round-Robin Controller)
# ==========================================================

PYTHON_BIN="/usr/bin/python3"
ENGINE_SCRIPT="/root/ctyun-headless/round_robin.py"
PID_FILE="/tmp/ctyun_rr_daemon.pid"
LOG_FILE="/tmp/ctyun_round_robin.log"
CONFIG_FILE="/root/ctyun-headless/round_robin_config.json"

case "$1" in
    start)
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "[*] 轮询引擎已经在运行中 (PID: $(cat $PID_FILE))"
            exit 0
        fi
        echo "[*] 正在启动多设备轮询保活守护引擎..."
        nohup $PYTHON_BIN $ENGINE_SCRIPT daemon > "$LOG_FILE" 2>&1 &
        echo $! > "$PID_FILE"
        sleep 2
        echo "[OK] 轮询保活引擎已在后台启动！(PID: $(cat $PID_FILE))"
        echo " - 实时轮询动态: tail -f $LOG_FILE"
        ;;
    stop)
        echo "[*] 停止轮询守护引擎及官方客户端..."
        if [ -f "$PID_FILE" ]; then
            kill -9 $(cat "$PID_FILE") 2>/dev/null || true
            rm -f "$PID_FILE"
        fi
        pkill -f "round_robin.py" 2>/dev/null || true
        pkill -f "clouddesktop-qml" 2>/dev/null || true
        pkill -f "CtyunStart" 2>/dev/null || true
        pkill -f "Xvfb" 2>/dev/null || true
        echo "[OK] 已停止所有轮询与客户端进程。"
        ;;
    status)
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "[RUNNING] 轮询保活引擎正在运行中 (PID: $(cat $PID_FILE))"
            echo "--- 最近 15 行轮询日志 ---"
            tail -n 15 "$LOG_FILE"
        else
            echo "[STOPPED] 轮询保活引擎未运行。"
        fi
        ;;
    log)
        tail -f "$LOG_FILE"
        ;;
    add)
        # 用法: ./robin.sh add <云电脑ID> <机器名称> <设备编码>
        if [ -z "$2" ]; then
            echo "用法: $0 add <云电脑ID> [机器名称] [设备编码]"
            echo "示例: $0 add 23798069 \"游戏版2号\" \"D0026091923798069\""
            exit 1
        fi
        $PYTHON_BIN - << PY
import json
cfg_path = "$CONFIG_FILE"
data = json.load(open(cfg_path))
new_id = "$2"
new_name = "$3" or "天翼云电脑"
new_code = "$4" or new_id

# 检查是否重复
exists = False
for d in data.get("desktops", []):
    if str(d.get("id")) == str(new_id):
        exists = True
        break

if exists:
    print(f"[!] 云电脑 ID [{new_id}] 已经在轮询列表中，无需重复添加！")
else:
    data.setdefault("desktops", []).append({
        "id": str(new_id),
        "name": new_name,
        "code": new_code
    })
    json.dump(data, open(cfg_path, "w"), ensure_ascii=False, indent=2)
    print(f"[OK] 成功添加云电脑: [{new_name}] ({new_code} - ID: {new_id}) 到轮询列表！")
    print(f"     当前共管理 {len(data['desktops'])} 台设备。")
PY
        ;;
    list)
        $PYTHON_BIN - << PY
import json
data = json.load(open("$CONFIG_FILE"))
desks = data.get("desktops", [])
stay = data.get("stay_seconds_per_desktop", 35)
print("=" * 70)
print(f"{'序号':<6} {'云电脑ID':<12} {'机器编码':<25} {'名称'}")
print("-" * 70)
for idx, d in enumerate(desks, 1):
    print(f"{idx:<6} {d.get('id'):<12} {d.get('code'):<25} {d.get('name')}")
print("=" * 70)
total_cycle = len(desks) * (stay + 8)
print(f"每台串流保持: {stay}秒 | 5台完整轮询周期: 约 {total_cycle}秒 (机房关机门槛: 300秒)")
PY
        ;;
    *)
        echo "用法: $0 {start|stop|status|log|add|list}"
        exit 1
        ;;
esac
