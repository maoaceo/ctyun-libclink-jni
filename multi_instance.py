#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
天翼云电脑 多账号/多实例独立多开启动与管理工具
Multi-Account Isolation Launcher for Ctyun Headless
"""

import os
import sys
import time
import json
import subprocess
import shutil

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
INSTANCES_DIR = os.path.join(BASE_DIR, "instances")

def show_help():
    print("=" * 65)
    print("✨ 天翼云电脑 多账号/多实例独立多开管理工具")
    print("=" * 65)
    print("用法:")
    print("  python3 multi_instance.py create <实例名称> <端口号>")
    print("  python3 multi_instance.py list")
    print("  python3 multi_instance.py start <实例名称>")
    print("  python3 multi_instance.py stop <实例名称>")
    print("  python3 multi_instance.py remove <实例名称>")
    print("\n示例:")
    print("  python3 multi_instance.py create acc2 8573")
    print("  python3 multi_instance.py create acc3 8574")
    print("=" * 65)

def create_instance(name, port):
    target_dir = os.path.join(INSTANCES_DIR, name)
    if os.path.exists(target_dir):
        print(f"[!] 实例【{name}】已存在，路径: {target_dir}")
        return

    os.makedirs(target_dir, exist_ok=True)
    home_dir = os.path.join(target_dir, "home")
    os.makedirs(home_dir, exist_ok=True)

    # 独立配置文件
    cfg = {
        "port": int(port),
        "admin_password": "admin",
        "stay_seconds": 35,
        "switch_gap": 3,
        "desktops": []
    }
    with open(os.path.join(target_dir, "config.json"), "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)

    # 启动脚本
    runner_sh = f"""#!/bin/bash
export HOME="{home_dir}"
cd "{BASE_DIR}"
exec /usr/bin/python3 "{os.path.join(BASE_DIR, 'web_server.py')}" "{os.path.join(target_dir, 'config.json')}"
"""
    runner_path = os.path.join(target_dir, "run.sh")
    with open(runner_path, "w", encoding="utf-8") as f:
        f.write(runner_sh)
    os.chmod(runner_path, 0o755)

    print(f"✅ 实例【{name}】创建成功！")
    print(f" - 专属独立数据目录: {home_dir}")
    print(f" - 专属 Web 控制端口: http://0.0.0.0:{port} (密码: admin)")
    print(f" - 启动该实例命令: python3 multi_instance.py start {name}")

def list_instances():
    if not os.path.exists(INSTANCES_DIR):
        print("[*] 暂无多开实例，默认主实例运行在端口 8572。")
        return
    items = [d for d in os.listdir(INSTANCES_DIR) if os.path.isdir(os.path.join(INSTANCES_DIR, d))]
    if not items:
        print("[*] 暂无多开实例，默认主实例运行在端口 8572。")
        return

    print("=" * 65)
    print(f"{'实例名称':<12} {'Web 端口':<10} {'运行状态':<12} {'数据目录'}")
    print("-" * 65)
    for name in items:
        cfg_file = os.path.join(INSTANCES_DIR, name, "config.json")
        port = "未知"
        if os.path.exists(cfg_file):
            try:
                cfg = json.load(open(cfg_file))
                port = str(cfg.get("port", "未知"))
            except Exception:
                pass
        status = "已停止"
        out = subprocess.check_output(f"ps aux | grep 'instances/{name}' | grep -v grep || true", shell=True).strip()
        if out:
            status = "🟢 运行中"
        print(f"{name:<12} {port:<10} {status:<12} {os.path.join(INSTANCES_DIR, name)}")
    print("=" * 65)

def start_instance(name):
    target_dir = os.path.join(INSTANCES_DIR, name)
    runner = os.path.join(target_dir, "run.sh")
    log_file = os.path.join(target_dir, "instance.log")
    if not os.path.exists(runner):
        print(f"[X] 未找到实例【{name}】")
        return

    out = subprocess.check_output(f"ps aux | grep 'instances/{name}' | grep -v grep || true", shell=True).strip()
    if out:
        print(f"[*] 实例【{name}】已经在运行中！")
        return

    cfg = json.load(open(os.path.join(target_dir, "config.json")))
    port = cfg.get("port", 8573)

    cmd = f'nohup /bin/bash "{runner}" > "{log_file}" 2>&1 &'
    subprocess.Popen(cmd, shell=True, executable="/bin/bash")
    time.sleep(2)
    print(f"🚀 实例【{name}】已成功在后台启动！")
    print(f"👉 浏览器打开专属管理面板: http://你的服务器IP:{port} (密码: admin)")

def stop_instance(name):
    print(f"[*] 正在停止实例【{name}】...")
    subprocess.run(f"pkill -f 'instances/{name}' 2>/dev/null || true", shell=True)
    print(f"[OK] 实例【{name}】已停止。")

def remove_instance(name):
    target_dir = os.path.join(INSTANCES_DIR, name)
    if not os.path.exists(target_dir):
        print(f"[X] 未找到实例【{name}】")
        return
    stop_instance(name)
    shutil.rmtree(target_dir, ignore_errors=True)
    print(f"[OK] 实例【{name}】及其所有数据目录已彻底删除。")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        show_help()
        sys.exit(0)

    act = sys.argv[1].lower()
    if act == "create" and len(sys.argv) >= 4:
        create_instance(sys.argv[2], sys.argv[3])
    elif act == "list":
        list_instances()
    elif act == "start" and len(sys.argv) >= 3:
        start_instance(sys.argv[2])
    elif act == "stop" and len(sys.argv) >= 3:
        stop_instance(sys.argv[2])
    elif act == "remove" and len(sys.argv) >= 3:
        remove_instance(sys.argv[2])
    else:
        show_help()
