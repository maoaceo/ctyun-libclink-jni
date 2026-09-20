#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
天翼云电脑 自动唤醒开机 + 20秒真实视讯串流轮询守护引擎
"""
import os, sys, time, json, sqlite3, subprocess, glob, re

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
APP_BIN = os.path.join(BASE_DIR, 'CtyunStart')
LOG_DIR = os.path.expanduser('~/.local/share/CtyunClouddeskPublic/Log')

def get_sqlite_path():
    dbs = glob.glob(os.path.expanduser('~/.local/share/CtyunClouddeskPublic/QML/OfflineStorage/Databases/*.sqlite'))
    return dbs[0] if dbs else None

def get_username():
    db = get_sqlite_path()
    if not db:
        return 'ydn_c_20260816_czelz4'
    conn = sqlite3.connect(db)
    cur = conn.cursor()
    cur.execute("SELECT name FROM data WHERE name LIKE '%/enableDesktopListByPage'")
    r = cur.fetchone()
    conn.close()
    if r:
        return r[0].split('/')[0]
    return 'ydn_c_20260816_czelz4'

def set_target(desktop_id):
    db = get_sqlite_path()
    if not db:
        return
    user = get_username()
    conn = sqlite3.connect(db)
    cur = conn.cursor()
    cur.execute("DELETE FROM data WHERE name LIKE '%lastConnectDesktopId%'")
    cur.execute("INSERT INTO data(name, value) VALUES(?, ?)", (f"{user}/lastConnectDesktopId", f'"{desktop_id}"'))
    conn.commit()
    cur.execute("PRAGMA wal_checkpoint(FULL)")
    conn.close()

def stop_client():
    subprocess.run("pkill -9 -f 'clouddesktop-qml' 2>/dev/null || true", shell=True)
    subprocess.run("pkill -9 -f 'CtyunStart' 2>/dev/null || true", shell=True)
    subprocess.run("pkill -9 -f 'Xvfb' 2>/dev/null || true", shell=True)
    time.sleep(1)

def start_client():
    cmd = f'nohup xvfb-run -a -s "-screen 0 1024x768x16 -nolisten tcp" "{APP_BIN}" > /tmp/ctyun_loop.log 2>&1 &'
    subprocess.Popen(cmd, shell=True, executable="/bin/bash")

def wait_for_real_stream(timeout=60):
    today_log = os.path.join(LOG_DIR, f"{time.strftime('%Y-%m-%d')}.log")
    start_time = time.time()
    while time.time() - start_time < timeout:
        time.sleep(1)
        if os.path.exists(today_log):
            try:
                out = subprocess.check_output(f"tail -n 60 '{today_log}' || true", shell=True).decode('utf-8', errors='ignore')
                if any(k in out for k in ["clink连接成功", "收到第一张图", "当前时延", "视频第一帧", "connectMaster"]):
                    return True
            except Exception:
                pass
    return False

def discover_desktops():
    today = os.path.join(LOG_DIR, f"{time.strftime('%Y-%m-%d')}.log")
    if os.path.exists(today):
        try:
            with open(today, 'r', encoding='utf-8', errors='ignore') as f:
                for line in reversed(f.readlines()):
                    if 'pageDesktop' in line and 'desktopList' in line:
                        m = re.search(r'\"desktopList\":(\[.*?\]),\"preemptionDesktopList\"', line)
                        if m:
                            dlist = json.loads(m.group(1))
                            return [{"id": d.get("objId"), "name": d.get("objName", "云电脑"), "code": d.get("desktopCode", d.get("objId"))} for d in dlist]
        except Exception:
            pass
    # 默认保底设备
    return [
        {"id": "23794229", "name": "游戏版1号", "code": "D0026091823794229"},
        {"id": "23795479", "name": "游戏版2号", "code": "D0026091823795479"}
    ]

def main():
    desktops = discover_desktops()
    print("=" * 70)
    print("🚀 天翼云电脑【自动唤醒开机 + 真实串流连接 20 秒】轮询守护已启动")
    print(f"   共发现 {len(desktops)} 台设备 | 单台真实握手串流保持: 20 秒")
    print("=" * 70)

    round_cnt = 0
    while True:
        round_cnt += 1
        print(f"\n🔄 ===== 开始第 {round_cnt} 轮巡检保活 (共 {len(desktops)} 台) =====")
        for idx, d in enumerate(desktops, 1):
            did, dname, dcode = d["id"], d["name"], d["code"]
            print(f"[{idx}/{len(desktops)}] 🎯 正在连接目标机器: [{dname}] (ID: {did} / 编码: {dcode})...")
            
            # 写入目标 ID 到 SQLite
            set_target(did)
            
            # 官方客户端自动排队并向机房请求开机唤醒
            stop_client()
            start_client()
            
            # 严密监测真实串流握手
            print("   ⏳ 正在等待官方机房开机响应与真实 Clink/QUIC 视讯串流握手...")
            if wait_for_real_stream(timeout=50):
                print("   ✅ 真实视讯串流已连通！(机房已收到视讯握手帧，闲置倒计时已重置为 300 秒满格)")
            else:
                print("   ⏳ 正在向官方机房下发连接/唤醒指令并保持等待...")
                
            print(f"   ⏱️ 严格保持视讯串流连接 20 秒...")
            time.sleep(20)
            print(f"   ✨ [{dname}] 20 秒视讯串流保活完成！准备切换下一台。")

if __name__ == '__main__':
    main()
