#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
天翼云电脑 多实例与设备隔离防冲突管理器
Multi-Instance Desktop Isolation Manager
"""

import os
import sys
import json
import sqlite3
import subprocess
import time
import glob
import re

BASE_DIR = "/root/ctyun-headless"
INSTANCES_DIR = os.path.join(BASE_DIR, "instances")
REGISTRY_FILE = os.path.join(BASE_DIR, "active_instances.json")
APP_BIN = os.path.join(BASE_DIR, "CtyunStart")

os.makedirs(INSTANCES_DIR, exist_ok=True)

def load_registry():
    if os.path.exists(REGISTRY_FILE):
        try:
            with open(REGISTRY_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def save_registry(data):
    with open(REGISTRY_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def is_pid_running(pid):
    if not pid or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False

def clean_stale_registry():
    reg = load_registry()
    updated = {}
    for name, item in reg.items():
        pid = item.get("client_pid")
        if is_pid_running(pid):
            updated[name] = item
    save_registry(updated)
    return updated

def get_instance_sqlite_path(instance_home):
    pattern = os.path.join(instance_home, ".local/share/CtyunClouddeskPublic/QML/OfflineStorage/Databases/*.sqlite")
    dbs = glob.glob(pattern)
    return dbs[0] if dbs else None

def get_bound_desktop_id(instance_home):
    db_path = get_instance_sqlite_path(instance_home)
    if not db_path:
        return None
    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("SELECT value FROM data WHERE name LIKE '%lastConnectDesktopId%'")
        row = cur.fetchone()
        if row and row[0]:
            val = str(row[0]).strip('"')
            return val
    except Exception:
        pass
    return None

def set_bound_desktop_id(instance_home, desktop_id):
    db_path = get_instance_sqlite_path(instance_home)
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
        conn.close()
        return True
    except Exception:
        return False

def list_instances():
    reg = clean_stale_registry()
    print("=" * 70)
    print(f"{'实例名称':<15} {'绑定机器/设备标识':<30} {'PID':<8} {'内存':<8} {'状态'}")
    print("-" * 70)
    
    # 检查默认单实例 (主实例)
    main_pid = None
    try:
        res = subprocess.check_output("pgrep -f 'clouddesktop-qml' || true", shell=True).decode().strip()
        pids = [int(p) for p in res.split() if p]
    except Exception:
        pids = []
    
    if not reg:
        if pids:
            desk_id = get_bound_desktop_id("/root")
            print(f"{'default':<15} {'[公众版-游戏版] D0026091923798068 (' + str(desk_id) + ')':<30} {pids[0]:<8} {'~300MB':<8} 运行中")
        else:
            print("当前暂无运行中的多实例。")
    else:
        for name, item in reg.items():
            pid = item.get("client_pid")
            desc = item.get("machine_label") or item.get("desktop_id") or "未绑定"
            status = "运行中" if is_pid_running(pid) else "已停止"
            print(f"{name:<15} {desc:<30} {str(pid):<8} {'~300MB':<8} {status}")
    print("=" * 70)

def start_instance(inst_name, machine_label="", target_desktop_id=""):
    clean_stale_registry()
    reg = load_registry()
    
    # 1. 严格防冲突检查：检查是否已经有实例连接了同一台机器/设备ID
    target_id = str(target_desktop_id).strip()
    target_lbl = str(machine_label).strip()
    
    for exist_name, exist_info in reg.items():
        if exist_name == inst_name and is_pid_running(exist_info.get("client_pid")):
            print(f"[!] 实例【{inst_name}】已经在运行中 (PID: {exist_info.get('client_pid')})")
            return
        
        # 机器冲突检测
        if target_id and str(exist_info.get("desktop_id")) == target_id:
            if is_pid_running(exist_info.get("client_pid")):
                print(f"[X] 启动失败！机器 ID [{target_id}] 已经被实例【{exist_name}】连接并锁定！")
                print(f"    为了防止账号互踢与冲突，不允许重复连接同一台云电脑。")
                return

        if target_lbl and exist_info.get("machine_label") == target_lbl:
            if is_pid_running(exist_info.get("client_pid")):
                print(f"[X] 启动失败！机器 [{target_lbl}] 已经被实例【{exist_name}】独占连接！")
                return

    # 2. 准备实例工作目录与环境
    inst_home = os.path.join(INSTANCES_DIR, inst_name)
    os.makedirs(inst_home, exist_ok=True)
    
    # 如果指定了绑定的机器ID，写入该实例的本地数据库配置
    if target_id:
        set_bound_desktop_id(inst_home, target_id)

    # 3. 启动无头实例
    log_dir = os.path.join(inst_home, ".local/share/CtyunClouddeskPublic/Log")
    os.makedirs(log_dir, exist_ok=True)
    
    runner_log = os.path.join(inst_home, "runner.log")
    cmd = f'HOME="{inst_home}" nohup xvfb-run -a -s "-screen 0 1024x768x16 -nolisten tcp" "{APP_BIN}" > "{runner_log}" 2>&1 &'
    subprocess.Popen(cmd, shell=True, executable="/bin/bash")
    
    print(f"[*] 正在为实例【{inst_name}】启动官方客户端...")
    time.sleep(4)
    
    # 查找新启动的 PID
    try:
        out = subprocess.check_output(f"pgrep -f '{inst_home}' || true", shell=True).decode().strip()
        pids = [int(p) for p in out.split() if p]
    except Exception:
        pids = []
        
    client_pid = pids[0] if pids else None
    
    # 登记注册表
    reg[inst_name] = {
        "instance_home": inst_home,
        "machine_label": target_lbl or "待绑定/首次扫码",
        "desktop_id": target_id or "",
        "client_pid": client_pid,
        "started_at": time.strftime("%Y-%m-%d %H:%M:%S")
    }
    save_registry(reg)
    
    print(f"[OK] 实例【{inst_name}】已成功独立启动！(PID: {client_pid})")
    print(f" - 绑定设备: {target_lbl or '首次扫码后自动登记'}")
    print(f" - 运行日志: tail -f {log_dir}/$(date +%Y-%m-%d).log")
    print(f" - 扫码命令: python3 {os.path.abspath(__file__)} qr {inst_name}")

def get_instance_qr(inst_name):
    inst_home = os.path.join(INSTANCES_DIR, inst_name)
    if not os.path.exists(inst_home):
        print(f"[!] 实例【{inst_name}】目录不存在")
        return
    log_file = os.path.join(inst_home, f".local/share/CtyunClouddeskPublic/Log/{time.strftime('%Y-%m-%d')}.log")
    if not os.path.exists(log_file):
        print(f"[!] 日志尚未生成，请稍等几秒后再试。")
        return
    
    with open(log_file, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    
    matches = re.findall(r'https://desk\.ctyun\.cn[^ ]+loginMode=1[^ ]*', content)
    if matches:
        qr_url = matches[-1]
        qr_png = f"/var/www/sub/qr_{inst_name}.png"
        subprocess.run(f'qrencode -s 8 -o "{qr_png}" "{qr_url}"', shell=True)
        print("=" * 70)
        print(f"👉 实例【{inst_name}】最新手机扫码授权地址:")
        print(qr_url)
        print(f"👉 二维码图片已生成: MEDIA:{qr_png}")
        print("=" * 70)
    else:
        print(f"[!] 实例【{inst_name}】当前无需扫码或尚未就绪。")

def stop_instance(inst_name):
    clean_stale_registry()
    reg = load_registry()
    if inst_name in reg:
        inst_home = reg[inst_name].get("instance_home")
        subprocess.run(f"pkill -f '{inst_home}' || true", shell=True)
        del reg[inst_name]
        save_registry(reg)
        print(f"[OK] 实例【{inst_name}】已安全停止。")
    else:
        print(f"[!] 未找到运行中的实例【{inst_name}】")

def stop_all():
    subprocess.run("pkill -f 'clouddesktop-qml' || true", shell=True)
    subprocess.run("pkill -f 'CtyunStart' || true", shell=True)
    subprocess.run("pkill -f 'Xvfb' || true", shell=True)
    save_registry({})
    print("[OK] 所有天翼云实例已全部停止。")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法:")
        print("  python3 instance_manager.py list")
        print("  python3 instance_manager.py start <实例名> <机器备注/设备编码> <云电脑ID>")
        print("  python3 instance_manager.py qr <实例名>")
        print("  python3 instance_manager.py stop <实例名>")
        print("  python3 instance_manager.py stop-all")
        sys.exit(1)
        
    cmd = sys.argv[1]
    if cmd == "list":
        list_instances()
    elif cmd == "start":
        name = sys.argv[2] if len(sys.argv) > 2 else "inst_1"
        label = sys.argv[3] if len(sys.argv) > 3 else ""
        d_id = sys.argv[4] if len(sys.argv) > 4 else ""
        start_instance(name, label, d_id)
    elif cmd == "qr":
        name = sys.argv[2] if len(sys.argv) > 2 else "inst_1"
        get_instance_qr(name)
    elif cmd == "stop":
        name = sys.argv[2] if len(sys.argv) > 2 else ""
        stop_instance(name)
    elif cmd == "stop-all":
        stop_all()
    else:
        print(f"[!] 未知命令: {cmd}")
