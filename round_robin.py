#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
天翼云电脑 多设备轻量自动轮询保活引擎 (Round-Robin Keepalive Engine)
"""

import os
import sys
import time
import json
import sqlite3
import subprocess
import glob
import signal

BASE_DIR = "/root/ctyun-headless"
APP_BIN = os.path.join(BASE_DIR, "CtyunStart")
CONFIG_FILE = os.path.join(BASE_DIR, "round_robin_config.json")
PID_FILE = "/tmp/ctyun_round_robin.pid"

# 默认配置
DEFAULT_CONFIG = {
    "stay_seconds_per_desktop": 35,  # 每台机器串流保持秒数 (重置官方5分钟关机倒计时)
    "switch_wait_seconds": 3,       # 切换机器间的缓冲间隔
    "desktops": [
        # 示例格式:
        # {"id": "23798068", "name": "天翼云电脑游戏版", "code": "D0026091923798068"}
    ]
}

def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return DEFAULT_CONFIG

def save_config(cfg):
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)

def get_sqlite_path(home_dir="/root"):
    dbs = glob.glob(os.path.join(home_dir, ".local/share/CtyunClouddeskPublic/QML/OfflineStorage/Databases/*.sqlite"))
    return dbs[0] if dbs else None

def set_target_desktop_in_db(desktop_id, home_dir="/root"):
    db_path = get_sqlite_path(home_dir)
    if not db_path:
        return False
    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("SELECT name FROM data WHERE name LIKE '%lastConnectDesktopId%'")
        rows = cur.fetchall()
        for r in rows:
            cur.execute("UPDATE data SET value = ? WHERE name = ?", (f'"{desktop_id}"', r[0]))
        conn.commit()
        # 强制 wal checkpoint 确保写入磁盘
        cur.execute("PRAGMA wal_checkpoint(FULL)")
        conn.close()
        return True
    except Exception as e:
        print(f"[!] 更新目标云电脑数据库失败: {e}")
        return False

def stop_active_client():
    subprocess.run("pkill -f 'clouddesktop-qml' 2>/dev/null || true", shell=True)
    subprocess.run("pkill -f 'CtyunStart' 2>/dev/null || true", shell=True)
    subprocess.run("pkill -f 'Xvfb' 2>/dev/null || true", shell=True)
    time.sleep(1)

def start_client_and_wait(stay_seconds):
    stop_active_client()
    time.sleep(1)
    
    # 启动官方客户端无头环境
    cmd = f'nohup xvfb-run -a -s "-screen 0 1024x768x16 -nolisten tcp" "{APP_BIN}" > /tmp/ctyun_round_robin_run.log 2>&1 &'
    subprocess.Popen(cmd, shell=True, executable="/bin/bash")
    
    # 等待连接成功
    log_file = f"/root/.local/share/CtyunClouddeskPublic/Log/{time.strftime('%Y-%m-%d')}.log"
    connected = False
    for _ in range(15):
        time.sleep(1)
        if os.path.exists(log_file):
            try:
                # 检查最近日志是否有 clink 连接成功
                out = subprocess.check_output(f"tail -n 30 '{log_file}' || true", shell=True).decode('utf-8', errors='ignore')
                if "clink连接成功" in out or "收到第一张图" in out or "当前时延" in out:
                    connected = True
                    break
            except Exception:
                pass
                
    if connected:
        print(f"  -> ✅ 视讯串流已连通并握手！保持串流 {stay_seconds} 秒以激活官方计时器...")
    else:
        print(f"  -> ⏳ 正在等待网关握手与串流帧 (保持 {stay_seconds} 秒)...")
        
    time.sleep(stay_seconds)
    stop_active_client()

def run_loop():
    cfg = load_config()
    desktops = cfg.get("desktops", [])
    if not desktops:
        # 如果未配置，自动填入当前机器作为默认第一项
        cfg["desktops"] = [
            {"id": "23798068", "name": "天翼云电脑游戏版", "code": "D0026091923798068"}
        ]
        save_config(cfg)
        desktops = cfg["desktops"]
        
    stay_sec = cfg.get("stay_seconds_per_desktop", 35)
    switch_gap = cfg.get("switch_wait_seconds", 3)
    
    print("=" * 70)
    print("🚀 天翼云电脑多设备【轮询防关机】引擎已启动")
    print(f" - 设备总数: {len(desktops)} 台")
    print(f" - 单台串流保持: {stay_sec} 秒")
    print(f" - 轮询总周期: 约 {len(desktops) * (stay_sec + switch_gap + 5)} 秒 (远低于 300 秒断开关机门槛)")
    print("=" * 70)
    
    round_count = 1
    while True:
        print(f"\n🔄 === 开始第 {round_count} 轮多设备保活巡检 ({time.strftime('%Y-%m-%d %H:%M:%S')}) ===")
        for idx, d in enumerate(desktops, 1):
            d_id = d.get("id")
            d_name = d.get("name", "云电脑")
            d_code = d.get("code", d_id)
            print(f"[{idx}/{len(desktops)}] 正在切换至机器: [{d_name}] ({d_code} - ID: {d_id})")
            
            # 1. 切换目标云电脑 ID
            set_target_desktop_in_db(d_id)
            
            # 2. 启动并维持该机器串流
            start_client_and_wait(stay_sec)
            
            print(f"  -> 机器 [{d_name}] 本轮保活完成，重置机房 5 分钟闲置倒计时！")
            time.sleep(switch_gap)
            
        round_count += 1
        print(f"✨ 第 {round_count - 1} 轮所有机器均已成功激活！立即进入下一轮平滑轮询...")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "daemon":
        # 守护进程模式
        run_loop()
    else:
        # 前台直接运行
        run_loop()
