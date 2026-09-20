#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
天翼云电脑 Clink 原生多设备轮询与 Web 安全控制台服务 (全平台独立直通免客户端版)
Web Dashboard with Dual Direct-API QR Generator & Native Clink Engine
"""

import os
import sys
import time
import json
import sqlite3
import subprocess
import glob
import re
import threading
import hashlib
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse

IS_WINDOWS = sys.platform.startswith("win")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(BASE_DIR, "config.json")

# 检查命令行是否指定独立配置文件 (多开实例支持)
INSTANCE_NAME = "default"
if len(sys.argv) > 1 and sys.argv[1].endswith(".json"):
    CONFIG_FILE = os.path.abspath(sys.argv[1])
    inst_dir = os.path.dirname(CONFIG_FILE)
    INSTANCE_NAME = os.path.basename(inst_dir)
    LOG_FILE = os.path.join(inst_dir, "robin.log")
else:
    LOG_FILE = os.path.join(BASE_DIR, "robin.log")

if IS_WINDOWS:
    LOG_DIR = os.path.expandvars(r"%LOCALAPPDATA%\CtyunClouddeskPublic\Log")
    APP_BIN = ""
    possible_win_paths = [
        r"C:\Program Files\CtyunClouddeskPublic\bin\clouddesktop-qml.exe",
        r"C:\Program Files (x86)\CtyunClouddeskPublic\bin\clouddesktop-qml.exe",
        r"C:\Program Files\CtyunClouddeskPublic\clouddesktop-qml.exe",
        r"C:\Program Files (x86)\CtyunClouddeskPublic\clouddesktop-qml.exe",
        os.path.expandvars(r"%ProgramFiles%\CtyunClouddeskPublic\bin\clouddesktop-qml.exe"),
        os.path.expandvars(r"%ProgramFiles(x86)%\CtyunClouddeskPublic\bin\clouddesktop-qml.exe"),
        os.path.expandvars(r"%LOCALAPPDATA%\Programs\CtyunClouddeskPublic\clouddesktop-qml.exe"),
        os.path.expandvars(r"%APPDATA%\CtyunClouddeskPublic\clouddesktop-qml.exe")
    ]
    for p in possible_win_paths:
        if os.path.exists(p):
            APP_BIN = p
            break
else:
    LOG_DIR = os.path.expanduser("~/.local/share/CtyunClouddeskPublic/Log")
    APP_BIN = os.path.join(BASE_DIR, "CtyunStart")

STATE = {
    "logged_in": False,
    "user_account": "",
    "running": False,
    "current_desktop": None,
    "round": 0,
    "last_seen_time": "",
    "engine_thread": None,
    "should_stop": False,
    "qr_url": "",
    "qr_img_base64": "",
    "qr_id": "",
    "qr_time": 0
}

DEFAULT_CONFIG = {
    "port": 8572,
    "admin_password": "admin",
    "stay_seconds": 35,
    "switch_gap": 3,
    "desktops": []
}

AUTH_TOKENS = set()

def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                cfg = json.load(f)
                if "admin_password" not in cfg:
                    cfg["admin_password"] = "admin"
                return cfg
        except Exception:
            pass
    return DEFAULT_CONFIG

def save_config(cfg):
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)

def append_log(msg):
    ts = time.strftime("[%Y-%m-%d %H:%M:%S]")
    line = f"{ts} {msg}\n"
    print(line, end="")
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass

def get_sqlite_path():
    if IS_WINDOWS:
        search_dirs = [
            os.path.expandvars(r"%LOCALAPPDATA%\CtyunClouddeskPublic\QML\OfflineStorage\Databases"),
            os.path.expandvars(r"%APPDATA%\CtyunClouddeskPublic\QML\OfflineStorage\Databases"),
            os.path.expandvars(r"%USERPROFILE%\.local\share\CtyunClouddeskPublic\QML\OfflineStorage\Databases")
        ]
        for sdir in search_dirs:
            if os.path.exists(sdir):
                dbs = glob.glob(os.path.join(sdir, "*.sqlite"))
                if dbs:
                    return dbs[0]
        dbs = glob.glob(os.path.expandvars(r"%LOCALAPPDATA%\Ctyun*\*.sqlite"))
        if dbs:
            return dbs[0]
        return None
    else:
        home_dir = os.path.expanduser("~")
        dbs = glob.glob(os.path.join(home_dir, ".local/share/CtyunClouddeskPublic/QML/OfflineStorage/Databases/*.sqlite"))
        return dbs[0] if dbs else None

def check_login_status():
    db_path = get_sqlite_path()
    if not db_path or not os.path.exists(db_path):
        STATE["logged_in"] = False
        STATE["user_account"] = ""
        return False
    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("SELECT value FROM data WHERE name = 'crashAccountData'")
        row = cur.fetchone()
        conn.close()
        if row and row[0]:
            acc_info = json.loads(row[0])
            acc = acc_info.get("userAccount") or acc_info.get("email") or "已登录"
            STATE["logged_in"] = True
            STATE["user_account"] = acc
            return True
    except Exception:
        pass
    STATE["logged_in"] = False
    STATE["user_account"] = ""
    return False

def discover_desktops_from_db():
    """仅从当前最新一次登录成功后官方机房返回的 pageDesktop 中提取真实机器，绝不混入历史遗留机器"""
    today_log = os.path.join(LOG_DIR, f"{time.strftime('%Y-%m-%d')}.log")
    desktops = []
    seen = set()
    if os.path.exists(today_log):
        try:
            with open(today_log, "r", encoding="utf-8", errors="ignore") as f:
                lines = f.readlines()
            for line in reversed(lines):
                if "api/desktop/client/pageDesktop" in line or "首页加载桌面列表" in line:
                    matches = re.findall(r'"objId":"(\d+)".*?"objName":"([^"]+)"', line)
                    for did, dname in matches:
                        if did not in seen:
                            seen.add(did)
                            desktops.append({
                                "id": did,
                                "code": f"D00...{did}",
                                "name": f"{dname} ({did})"
                            })
                    if desktops:
                        break
        except Exception:
            pass
    return desktops

def parse_code_or_id(input_str):
    s = str(input_str).strip()
    if not s:
        return "", ""
    m_code = re.search(r'(D\d{14,16})', s, re.I)
    if m_code:
        full_code = m_code.group(1)
        return full_code[-8:], full_code
    m_num = re.search(r'\b(\d{7,10})\b', s)
    if m_num:
        return m_num.group(1), f"D...{m_num.group(1)}"
    return s, s

def set_target_desktop_in_db(desktop_id, desktop_code=""):
    db_path = get_sqlite_path()
    if not db_path:
        return False
    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("SELECT name FROM data WHERE name LIKE '%lastConnectDesktopId%'")
        rows = cur.fetchall()
        real_num_id = desktop_id[-8:] if len(desktop_id) >= 8 and desktop_id[-8:].isdigit() else desktop_id
        for r in rows:
            cur.execute("UPDATE data SET value = ? WHERE name = ?", (f'"{real_num_id}"', r[0]))
        conn.commit()
        cur.execute("PRAGMA wal_checkpoint(FULL)")
        conn.close()
        return True
    except Exception as e:
        append_log(f"数据库更新目标云电脑失败: {e}")
        return False

def stop_active_client():
    if IS_WINDOWS:
        subprocess.run('taskkill /F /IM clouddesktop-qml.exe /T >nul 2>&1', shell=True)
        subprocess.run('taskkill /F /IM clouddesktop-daemon.exe /T >nul 2>&1', shell=True)
    else:
        subprocess.run("pkill -f 'clouddesktop-qml' 2>/dev/null || true", shell=True)
        subprocess.run("pkill -f 'CtyunStart' 2>/dev/null || true", shell=True)
        subprocess.run("pkill -f 'Xvfb' 2>/dev/null || true", shell=True)
    time.sleep(1)

def force_generate_new_qr():
    if check_login_status():
        return
    stop_active_client()
    time.sleep(1)
    
    today_log = os.path.join(LOG_DIR, f"{time.strftime('%Y-%m-%d')}.log")
    try:
        if os.path.exists(today_log):
            os.remove(today_log)
    except Exception:
        pass

    if not IS_WINDOWS:
        cmd = f'nohup xvfb-run -a -s "-screen 0 1024x768x16 -nolisten tcp" "{APP_BIN}" > /tmp/ctyun_login.log 2>&1 &'
        subprocess.Popen(cmd, shell=True, executable="/bin/bash")
        for _ in range(12):
            time.sleep(1)
            check_qr_from_logs()
            if STATE["qr_url"]:
                break

def check_qr_from_logs():
    if STATE["logged_in"]:
        return
    today_log = os.path.join(LOG_DIR, f"{time.strftime('%Y-%m-%d')}.log")
    if os.path.exists(today_log):
        try:
            with open(today_log, "r", encoding="utf-8", errors="ignore") as f:
                lines = f.readlines()
            for line in reversed(lines):
                if "登录二维码地址" in line or "login-confirm" in line:
                    matches = re.findall(r'https://desk\.ctyun\.cn[^ "\'\r\n]+', line)
                    if matches:
                        url = matches[0].strip()
                        if url != STATE["qr_url"]:
                            STATE["qr_url"] = url
                            STATE["qr_time"] = time.time()
                            append_log("📱 成功捕获官方原生客户端最新登录二维码！")
                        break
        except Exception:
            pass

def round_robin_worker():
    append_log(f"🚀 官方 Clink / QUIC 原生多设备轮询引擎已就绪！(运行平台: {'Windows' if IS_WINDOWS else 'Linux'})")
    STATE["running"] = True
    STATE["should_stop"] = False
    
    while not STATE["should_stop"]:
        if not check_login_status():
            STATE["current_desktop"] = "⚠️ 等待手机扫码登录"
            check_qr_from_logs()
            time.sleep(3)
            continue
        else:
            STATE["qr_url"] = ""
            STATE["qr_img_base64"] = ""

        cfg = load_config()
        desktops = cfg.get("desktops", [])
        
        if not desktops:
            discovered = discover_desktops_from_db()
            if discovered:
                cfg["desktops"] = discovered
                save_config(cfg)
                desktops = discovered
                append_log(f"🔍 自动从账号中检索到 {len(discovered)} 台云电脑，已载入轮询列表！")

        if not desktops:
            STATE["current_desktop"] = "⚠️ 登录成功！输入编码（如 D00...）添加设备"
            time.sleep(3)
            continue
            
        stay_sec = int(cfg.get("stay_seconds", 35))
        switch_gap = int(cfg.get("switch_gap", 3))
        STATE["round"] += 1
        round_num = STATE["round"]
        append_log(f"🔄 === 开始第 {round_num} 轮多设备巡检 (共 {len(desktops)} 台) ===")
        
        for idx, d in enumerate(desktops, 1):
            if STATE["should_stop"]:
                break
                
            d_id = d.get("id")
            d_name = d.get("name", "云电脑")
            d_code = d.get("code", d_id)
            STATE["current_desktop"] = f"[{d_name}] ({d_code})"
            
            append_log(f"[{idx}/{len(desktops)}] 正在连接: [{d_name}] (编码: {d_code} / ID: {d_id})...")
            set_target_desktop_in_db(d_id, d_code)
            
            stop_active_client()
            if IS_WINDOWS:
                if APP_BIN and os.path.exists(APP_BIN):
                    subprocess.Popen(f'powershell.exe -NoProfile -Command "Start-Process -FilePath \'{APP_BIN}\' -WindowStyle Minimized"', shell=True)
            else:
                cmd = f'nohup xvfb-run -a -s "-screen 0 1024x768x16 -nolisten tcp" "{APP_BIN}" > /tmp/ctyun_runner.log 2>&1 &'
                subprocess.Popen(cmd, shell=True, executable="/bin/bash")
            
            connected = False
            today_log = os.path.join(LOG_DIR, f"{time.strftime('%Y-%m-%d')}.log")
            for _ in range(12):
                if STATE["should_stop"]:
                    break
                time.sleep(1)
                if os.path.exists(today_log):
                    try:
                        with open(today_log, "r", encoding="utf-8", errors="ignore") as lf:
                            out = "".join(lf.readlines()[-30:])
                        if "clink连接成功" in out or "收到第一张图" in out or "当前时延" in out:
                            connected = True
                            break
                    except Exception:
                        pass
                        
            if connected:
                append_log(f"  -> 🟢 视讯串流握手就绪！保持官方媒体流 {stay_sec} 秒...")
            else:
                append_log(f"  -> ⏳ 正在保持视讯连接 ({stay_sec} 秒)...")
                
            waited = 0
            while waited < stay_sec and not STATE["should_stop"]:
                time.sleep(1)
                waited += 1
                
            stop_active_client()
            append_log(f"  -> ✨ [{d_name}] 闲置倒计时已重置！准备轮换...")
            time.sleep(switch_gap)
            
    stop_active_client()
    STATE["running"] = False
    STATE["current_desktop"] = None
    append_log("⏹️ 轮询引擎已停止。")

# HTML Web UI 模版 (内置客户端原生 JS 二维码生成引擎 qrcode.min.js 兜底，绝无依赖丢失)
HTML_PAGE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>天翼云 Clink 原生多设备轮询保活控制台</title>
<!-- 内置轻量 QRCode.js 引擎 -->
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<style>
:root {
  --primary: #ff7597;
  --primary-hover: #ff547d;
  --bg: #0f111a;
  --card-bg: rgba(26, 29, 45, 0.85);
  --border: rgba(255, 117, 151, 0.2);
  --text: #e6e8f0;
  --text-muted: #8c93b0;
  --success: #00e676;
  --warn: #ffab00;
  --danger: #ff5252;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  background: radial-gradient(circle at 10% 20%, #1a162b 0%, #0d0e17 90%);
  color: var(--text);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "PingFang SC", "Microsoft YaHei", sans-serif;
  min-height: 100vh;
  padding: 24px;
}
.container { max-width: 1200px; margin: 0 auto; }
header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding-bottom: 20px;
  border-bottom: 1px solid var(--border);
  margin-bottom: 24px;
}
.title-group h1 { font-size: 24px; font-weight: 700; color: #fff; display: flex; align-items: center; gap: 10px; }
.title-group p { font-size: 13px; color: var(--text-muted); margin-top: 4px; }
.badge {
  padding: 5px 12px;
  border-radius: 20px;
  font-size: 12px;
  font-weight: 600;
  display: inline-block;
}
.badge-online { background: rgba(0,230,118,0.15); color: var(--success); border: 1px solid var(--success); }
.badge-offline { background: rgba(255,82,82,0.15); color: var(--danger); border: 1px solid var(--danger); }
.badge-warn { background: rgba(255,171,0,0.15); color: var(--warn); border: 1px solid var(--warn); }

.grid { display: grid; grid-template-columns: 360px 1fr; gap: 24px; }
@media (max-width: 900px) { .grid { grid-template-columns: 1fr; } }

.card {
  background: var(--card-bg);
  backdrop-filter: blur(16px);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 20px;
  box-shadow: 0 8px 32px rgba(0,0,0,0.37);
  margin-bottom: 24px;
}
.card-header {
  font-size: 16px;
  font-weight: 600;
  margin-bottom: 16px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  color: var(--primary);
}
.btn {
  padding: 8px 16px;
  border-radius: 8px;
  border: none;
  cursor: pointer;
  font-size: 14px;
  font-weight: 600;
  transition: all 0.2s;
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.btn-primary { background: linear-gradient(135deg, #ff7597, #ff547d); color: #fff; }
.btn-primary:hover { opacity: 0.9; transform: translateY(-1px); }
.btn-danger { background: rgba(255,82,82,0.2); color: var(--danger); border: 1px solid var(--danger); }
.btn-danger:hover { background: var(--danger); color: #fff; }

.qr-box {
  text-align: center;
  padding: 16px;
  background: rgba(0,0,0,0.3);
  border-radius: 12px;
  margin-top: 10px;
}
#qrCanvasContainer {
  display: inline-block;
  background: #fff;
  padding: 10px;
  border-radius: 10px;
  box-shadow: 0 4px 16px rgba(0,0,0,0.4);
}
.qr-box a { color: var(--primary); font-size: 12px; text-decoration: none; word-break: break-all; display: block; margin-top: 12px; }

.account-box {
  padding: 16px;
  background: rgba(0, 230, 118, 0.08);
  border: 1px solid rgba(0, 230, 118, 0.3);
  border-radius: 12px;
  text-align: center;
}
.account-box h3 { color: var(--success); font-size: 15px; margin-bottom: 6px; }
.account-box p { font-size: 12px; color: var(--text-muted); font-family: monospace; }

.device-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  background: rgba(255,255,255,0.03);
  border: 1px solid rgba(255,255,255,0.06);
  padding: 12px 16px;
  border-radius: 10px;
  margin-bottom: 10px;
  transition: all 0.2s;
}
.device-item.active { border-color: var(--primary); background: rgba(255,117,151,0.08); }
.device-info h4 { font-size: 14px; font-weight: 600; color: #fff; }
.device-info p { font-size: 12px; color: var(--text-muted); font-family: monospace; margin-top: 2px; }

.form-group { margin-bottom: 12px; }
.form-group label { font-size: 12px; color: var(--text-muted); display: block; margin-bottom: 4px; }
.form-control {
  width: 100%;
  padding: 8px 12px;
  background: rgba(0,0,0,0.4);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 8px;
  color: #fff;
  font-size: 13px;
}
.form-control:focus { outline: none; border-color: var(--primary); }

.log-terminal {
  background: #08090e;
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 12px;
  padding: 16px;
  font-family: "JetBrains Mono", Consolas, Menlo, monospace;
  font-size: 12px;
  color: #98c379;
  height: 480px;
  overflow-y: auto;
  white-space: pre-wrap;
  word-break: break-all;
  line-height: 1.6;
}

#authModal {
  position: fixed; top: 0; left: 0; width: 100%; height: 100%;
  background: rgba(8, 9, 14, 0.85); backdrop-filter: blur(12px);
  display: flex; align-items: center; justify-content: center; z-index: 9999;
}
.login-card {
  width: 360px; background: var(--card-bg); border: 1px solid var(--border);
  border-radius: 16px; padding: 28px; box-shadow: 0 12px 40px rgba(0,0,0,0.6);
  text-align: center;
}
</style>
</head>
<body>

<div id="authModal" style="display: none;">
  <div class="login-card">
    <h2 style="color: var(--primary); font-size: 20px; margin-bottom: 8px;">🔐 管理访问验证</h2>
    <p style="font-size: 12px; color: var(--text-muted); margin-bottom: 20px;">本控制面板受密码保护，请输入访问密码：</p>
    <div class="form-group" style="text-align: left;">
      <input type="password" id="adminPwd" class="form-control" placeholder="默认密码: admin" onkeydown="if(event.keyCode===13)verifyLogin()">
    </div>
    <button class="btn btn-primary" style="width: 100%; justify-content: center; margin-top: 8px;" onclick="verifyLogin()">进入控制中心</button>
    <p id="pwdErr" style="color: var(--danger); font-size: 12px; margin-top: 10px; display: none;">密码错误，请重新输入</p>
  </div>
</div>

<div class="container">
  <header>
    <div class="title-group">
      <h1>✨ 天翼云 Clink 原生多设备轮询保活</h1>
      <p id="platNotice">官方原生视讯串流内核 (QUIC/Clink) · 纯无头运行 · 5分钟超时防关机</p>
    </div>
    <div style="display: flex; gap: 10px; align-items: center;">
      <span id="loginBadge" class="badge badge-warn">检查登录状态中...</span>
      <span id="statusBadge" class="badge badge-offline">未连接</span>
      <button class="btn btn-danger" style="padding: 4px 10px; font-size: 12px;" onclick="logout()">锁定退出</button>
    </div>
  </header>

  <div class="grid">
    <div class="sidebar">
      <div class="card" id="authSection">
        <div class="card-header">
          <span>📱 账号授权状态</span>
          <button id="btnRefreshQR" class="btn btn-primary" style="padding: 4px 10px; font-size: 12px;" onclick="refreshQR(true)">🔄 刷新二维码</button>
        </div>
        
        <div id="qrContainer">
          <p style="font-size: 12px; color: var(--text-muted); margin-bottom: 10px;">使用天翼云电脑 App 或微信扫码确认登录：</p>
          <div class="qr-box">
            <div id="qrPlaceholder" style="padding: 30px; font-size: 12px; color: var(--text-muted);">正在生成最新官方二维码...</div>
            <div id="qrCanvasContainer" style="display: none;"></div>
            <a id="qrLink" href="#" target="_blank" style="display: none;">🔗 手机直接打开网页授权</a>
          </div>
        </div>

        <div id="loggedContainer" class="account-box" style="display: none;">
          <h3>✅ 账号已授权就绪</h3>
          <p id="loggedAccountText" style="margin-top: 4px; color: #fff;"></p>
          <p style="margin-top: 6px; font-size: 11px; color: var(--text-muted);">Token 已安全持久化，无需再次扫码</p>
          <button class="btn btn-danger" style="margin-top: 12px; font-size: 11px; padding: 4px 10px;" onclick="reloginAccount()">更换/重新登录</button>
        </div>
      </div>

      <div class="card">
        <div class="card-header">
          <span>🎮 轮询保活控制</span>
          <span id="roundCounter" style="font-size: 12px; color: var(--text-muted);">第 0 轮</span>
        </div>
        <p id="currDesktopText" style="font-size: 13px; margin-bottom: 16px; color: var(--text-muted);">当前串流设备: 无</p>
        <div style="display: flex; gap: 10px;">
          <button id="btnStart" class="btn btn-primary" onclick="toggleEngine(true)">启动轮询</button>
          <button id="btnStop" class="btn btn-danger" onclick="toggleEngine(false)">停止</button>
        </div>
      </div>

      <div class="card">
        <div class="card-header">
          <span>➕ 添加云电脑设备</span>
          <button class="btn btn-primary" style="padding: 2px 8px; font-size: 11px;" onclick="autoScanDesktops()">🔍 自动探测</button>
        </div>
        <div class="form-group">
          <label>云电脑编码 或 数字ID</label>
          <input type="text" id="newInput" class="form-control" placeholder="直接粘贴编码如: D0026090823728443">
        </div>
        <div class="form-group">
          <label>机器备注名称 (选填)</label>
          <input type="text" id="newName" class="form-control" placeholder="如: 游戏版1号 (默认自动命名)">
        </div>
        <button class="btn btn-primary" style="width: 100%; justify-content: center;" onclick="addDesktop()">添加到轮询队列</button>
      </div>

      <div class="card">
        <div class="card-header">
          <span>🔑 安全设置 (修改Web密码)</span>
        </div>
        <div class="form-group">
          <label>新访问密码</label>
          <input type="password" id="changeNewPwd" class="form-control" placeholder="设置新密码">
        </div>
        <button class="btn btn-primary" style="width: 100%; justify-content: center;" onclick="changePassword()">保存新密码</button>
      </div>
    </div>

    <div class="main-content">
      <div class="card">
        <div class="card-header">
          <span>🖥️ 轮询设备列表 (<span id="devCount">0</span> 台)</span>
          <span style="font-size: 12px; color: var(--text-muted);">单台保持: 35s | 切换: 3s</span>
        </div>
        <div id="deviceList"></div>
      </div>

      <div class="card" style="margin-bottom: 0;">
        <div class="card-header">
          <span>📜 实时视讯握手与保活日志</span>
          <button class="btn btn-primary" style="padding: 4px 10px; font-size: 12px;" onclick="fetchLogs()">刷新日志</button>
        </div>
        <div id="logTerminal" class="log-terminal">正在加载日志...</div>
      </div>
    </div>
  </div>
</div>

<script>
let authToken = localStorage.getItem('ctyun_auth_token') || '';
let lastRenderedQr = '';

function getHeaders() {
  return {
    'Content-Type': 'application/json',
    'X-Auth-Token': authToken
  };
}

function verifyLogin() {
  const pwd = document.getElementById('adminPwd').value;
  fetch('/api/auth/login', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({password: pwd})
  }).then(r => r.json()).then(res => {
    if (res.success && res.token) {
      authToken = res.token;
      localStorage.setItem('ctyun_auth_token', authToken);
      document.getElementById('authModal').style.display = 'none';
      document.getElementById('pwdErr').style.display = 'none';
      fetchStatus();
      fetchLogs();
    } else {
      document.getElementById('pwdErr').style.display = 'block';
    }
  });
}

function logout() {
  localStorage.removeItem('ctyun_auth_token');
  authToken = '';
  document.getElementById('authModal').style.display = 'flex';
}

function checkAuth(r) {
  if (r.status === 401) {
    document.getElementById('authModal').style.display = 'flex';
    return null;
  }
  return r;
}

function renderQrInBrowser(url) {
  if (!url || url === lastRenderedQr) return;
  lastRenderedQr = url;
  const container = document.getElementById('qrCanvasContainer');
  container.innerHTML = '';
  
  if (typeof QRCode !== 'undefined') {
    new QRCode(container, {
      text: url,
      width: 180,
      height: 180,
      colorDark: '#000000',
      colorLight: '#ffffff',
      correctLevel: QRCode.CorrectLevel.M
    });
    container.style.display = 'inline-block';
    document.getElementById('qrPlaceholder').style.display = 'none';
  } else {
    // 降级使用图片 API
    const img = document.createElement('img');
    img.src = 'https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=' + encodeURIComponent(url);
    img.style.maxWidth = '180px';
    container.appendChild(img);
    container.style.display = 'inline-block';
    document.getElementById('qrPlaceholder').style.display = 'none';
  }
}

function fetchStatus() {
  fetch('/api/status', {headers: getHeaders()})
    .then(r => checkAuth(r))
    .then(r => r ? r.json() : null)
    .then(data => {
      if (!data) return;
      document.getElementById('authModal').style.display = 'none';

      const lBadge = document.getElementById('loginBadge');
      const qrContainer = document.getElementById('qrContainer');
      const loggedContainer = document.getElementById('loggedContainer');
      const btnRefresh = document.getElementById('btnRefreshQR');

      if (data.logged_in) {
        lBadge.className = 'badge badge-online';
        lBadge.innerText = '● 账号已登录: ' + data.user_account;
        qrContainer.style.display = 'none';
        btnRefresh.style.display = 'none';
        loggedContainer.style.display = 'block';
        document.getElementById('loggedAccountText').innerText = '当前账号: ' + data.user_account;
      } else {
        lBadge.className = 'badge badge-warn';
        lBadge.innerText = '▲ 未登录，请先微信/App扫码';
        qrContainer.style.display = 'block';
        btnRefresh.style.display = 'inline-flex';
        loggedContainer.style.display = 'none';

        if (data.qr_url) {
          renderQrInBrowser(data.qr_url);
          const link = document.getElementById('qrLink');
          link.href = data.qr_url;
          link.style.display = 'block';
        }
      }

      const badge = document.getElementById('statusBadge');
      if (data.running) {
        badge.className = 'badge badge-online';
        badge.innerText = '● 正在轮询保活';
        document.getElementById('currDesktopText').innerHTML = '当前串流: <b style="color: var(--primary);">' + (data.current_desktop || '连接中...') + '</b>';
      } else {
        badge.className = 'badge badge-offline';
        badge.innerText = '○ 已停止';
        document.getElementById('currDesktopText').innerText = '当前串流设备: 无';
      }
      document.getElementById('roundCounter').innerText = '第 ' + data.round + ' 轮';

      renderDesktops(data.desktops || [], data.current_desktop);
    }).catch(()=>{});
}

function renderDesktops(list, curr) {
  document.getElementById('devCount').innerText = list.length;
  const container = document.getElementById('deviceList');
  if (list.length === 0) {
    container.innerHTML = '<p style="font-size: 13px; color: var(--text-muted); text-align: center; padding: 20px;">暂无云电脑，请在左侧输入编码添加或点击自动探测</p>';
    return;
  }
  let html = '';
  list.forEach((d, idx) => {
    const isActive = curr && curr.includes(d.id);
    html += `
      <div class="device-item ${isActive ? 'active' : ''}">
        <div class="device-info">
          <h4>${idx + 1}. ${d.name} ${isActive ? '<span style="color: var(--primary); font-size: 11px;">[正在串流]</span>' : ''}</h4>
          <p>编码: ${d.code} · ID: ${d.id}</p>
        </div>
        <button class="btn btn-danger" style="padding: 4px 8px; font-size: 12px;" onclick="removeDesktop('${d.id}')">移除</button>
      </div>
    `;
  });
  container.innerHTML = html;
}

function fetchLogs() {
  fetch('/api/logs', {headers: getHeaders()})
    .then(r => checkAuth(r))
    .then(r => r ? r.text() : null)
    .then(t => {
      if (t === null) return;
      const box = document.getElementById('logTerminal');
      box.innerText = t || '暂无日志输出';
      box.scrollTop = box.scrollHeight;
    }).catch(()=>{});
}

function toggleEngine(start) {
  fetch('/api/engine', {
    method: 'POST',
    headers: getHeaders(),
    body: JSON.stringify({action: start ? 'start' : 'stop'})
  }).then(() => {
    setTimeout(fetchStatus, 500);
    setTimeout(fetchLogs, 1000);
  });
}

function addDesktop() {
  const inputVal = document.getElementById('newInput').value.trim();
  const name = document.getElementById('newName').value.trim();
  if (!inputVal) { alert('请输入云电脑设备编码或数字ID'); return; }
  fetch('/api/desktops', {
    method: 'POST',
    headers: getHeaders(),
    body: JSON.stringify({action: 'add', input: inputVal, name})
  }).then(r => r.json()).then(res => {
    if (res.error) alert(res.error);
    document.getElementById('newInput').value = '';
    document.getElementById('newName').value = '';
    fetchStatus();
  });
}

function autoScanDesktops() {
  fetch('/api/desktops/scan', {method: 'POST', headers: getHeaders()}).then(r => r.json()).then(res => {
    if (res.success) {
      alert('探测完成！已载入 ' + res.count + ' 台设备');
      fetchStatus();
    } else {
      alert('探测失败: ' + (res.error || '未找到设备'));
    }
  });
}

function removeDesktop(id) {
  if (!confirm('确定移除该云电脑保活吗？')) return;
  fetch('/api/desktops', {
    method: 'POST',
    headers: getHeaders(),
    body: JSON.stringify({action: 'remove', id})
  }).then(() => fetchStatus());
}

function refreshQR(manual) {
  lastRenderedQr = '';
  if (manual) {
    document.getElementById('qrPlaceholder').style.display = 'block';
    document.getElementById('qrPlaceholder').innerText = '正在向官方网关重新申请崭新二维码...';
    document.getElementById('qrCanvasContainer').style.display = 'none';
    document.getElementById('qrLink').style.display = 'none';
  }
  fetch('/api/qr/refresh', {method: 'POST', headers: getHeaders()}).then(r => r.json()).then(res => {
    setTimeout(fetchStatus, 500);
  });
}

function reloginAccount() {
  if (!confirm('确定注销当前账号并重新扫码吗？')) return;
  fetch('/api/auth/clear_login', {method: 'POST', headers: getHeaders()}).then(() => {
    fetchStatus();
  });
}

function changePassword() {
  const newPwd = document.getElementById('changeNewPwd').value.trim();
  if (!newPwd) { alert('请输入新密码'); return; }
  fetch('/api/auth/change_password', {
    method: 'POST',
    headers: getHeaders(),
    body: JSON.stringify({new_password: newPwd})
  }).then(r => r.json()).then(res => {
    if (res.success) {
      alert('密码修改成功！请重新登录。');
      logout();
    } else {
      alert('修改失败: ' + (res.error || '未知错误'));
    }
  });
}

if (!authToken) {
  document.getElementById('authModal').style.display = 'flex';
} else {
  fetchStatus();
  fetchLogs();
}

setInterval(() => { if (authToken) fetchStatus(); }, 2500);
setInterval(() => { if (authToken) fetchLogs(); }, 3000);
</script>
</body>
</html>
"""

class RequestHandler(BaseHTTPRequestHandler):
    def _send_json(self, data, code=200):
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode("utf-8"))

    def _send_html(self, html):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(html.encode("utf-8"))

    def _is_authenticated(self):
        token = self.headers.get("X-Auth-Token", "")
        return token in AUTH_TOKENS

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/" or url.path == "/index.html":
            self._send_html(HTML_PAGE)
            return

        if not self._is_authenticated():
            self._send_json({"error": "未登录或登录已过期", "need_auth": True}, 401)
            return

        if url.path == "/api/status":
            cfg = load_config()
            check_login_status()
            check_qr_from_logs()
            data = {
                "logged_in": STATE["logged_in"],
                "user_account": STATE["user_account"],
                "running": STATE["running"],
                "current_desktop": STATE["current_desktop"],
                "round": STATE["round"],
                "qr_url": STATE["qr_url"] if not STATE["logged_in"] else "",
                "desktops": cfg.get("desktops", []),
                "stay_seconds": cfg.get("stay_seconds", 35)
            }
            self._send_json(data)
        elif url.path == "/api/logs":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            txt = ""
            if os.path.exists(LOG_FILE):
                try:
                    with open(LOG_FILE, "r", encoding="utf-8", errors="ignore") as lf:
                        lines = lf.readlines()
                    txt = "".join(lines[-80:])
                except Exception:
                    pass
            self.wfile.write(txt.encode("utf-8"))
        else:
            self.send_error(404, "Not Found")

    def do_POST(self):
        url = urlparse(self.path)
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length).decode('utf-8') if length > 0 else ""
        try:
            req_data = json.loads(body) if body else {}
        except Exception:
            req_data = {}

        if url.path == "/api/auth/login":
            cfg = load_config()
            pwd = req_data.get("password", "")
            expected = cfg.get("admin_password", "admin")
            if pwd == expected:
                token = hashlib.sha256(f"{pwd}:{time.time()}:{os.urandom(8)}".encode()).hexdigest()
                AUTH_TOKENS.add(token)
                self._send_json({"success": True, "token": token})
            else:
                self._send_json({"error": "密码错误"}, 403)
            return

        if not self._is_authenticated():
            self._send_json({"error": "未登录或登录已过期", "need_auth": True}, 401)
            return

        if url.path == "/api/auth/change_password":
            new_pwd = req_data.get("new_password", "").strip()
            if not new_pwd:
                self._send_json({"error": "新密码不能为空"}, 400)
                return
            cfg = load_config()
            cfg["admin_password"] = new_pwd
            save_config(cfg)
            AUTH_TOKENS.clear()
            self._send_json({"success": True, "message": "密码修改成功"})

        elif url.path == "/api/auth/clear_login":
            db_path = get_sqlite_path()
            if db_path and os.path.exists(db_path):
                try:
                    conn = sqlite3.connect(db_path)
                    cur = conn.cursor()
                    cur.execute("DELETE FROM data WHERE name = 'crashAccountData'")
                    conn.commit()
                    conn.close()
                except Exception:
                    pass
            STATE["logged_in"] = False
            STATE["user_account"] = ""
            force_generate_new_qr()
            self._send_json({"success": True, "message": "已重置登录状态"})

        elif url.path == "/api/engine":
            action = req_data.get("action")
            if action == "start":
                if not STATE["running"]:
                    t = threading.Thread(target=round_robin_worker, daemon=True)
                    t.start()
                    STATE["engine_thread"] = t
                self._send_json({"success": True, "message": "启动指令已下发"})
            elif action == "stop":
                STATE["should_stop"] = True
                stop_active_client()
                self._send_json({"success": True, "message": "停止指令已下发"})
            else:
                self._send_json({"error": "未知指令"}, 400)

        elif url.path == "/api/desktops":
            action = req_data.get("action")
            cfg = load_config()
            desktops = cfg.get("desktops", [])
            
            if action == "add":
                raw_input = str(req_data.get("input", req_data.get("id", ""))).strip()
                parsed_id, parsed_code = parse_code_or_id(raw_input)
                
                if not parsed_id:
                    self._send_json({"error": "请输入有效的云电脑编码或ID"}, 400)
                    return

                name = str(req_data.get("name", "")).strip()
                if not name:
                    name = f"云电脑 {parsed_id}"
                
                if any(str(d.get("id")) == parsed_id or str(d.get("code")) == parsed_code for d in desktops):
                    self._send_json({"error": f"设备 [{parsed_code}] 已经在列表中"}, 400)
                    return
                    
                desktops.append({"id": parsed_id, "name": name, "code": parsed_code})
                cfg["desktops"] = desktops
                save_config(cfg)
                self._send_json({"success": True, "desktops": desktops})
                
            elif action == "remove":
                target_id = str(req_data.get("id", "")).strip()
                cfg["desktops"] = [d for d in desktops if str(d.get("id")) != target_id]
                save_config(cfg)
                self._send_json({"success": True, "desktops": cfg["desktops"]})
            else:
                self._send_json({"error": "未知设备操作"}, 400)

        elif url.path == "/api/desktops/scan":
            discovered = discover_desktops_from_db()
            cfg = load_config()
            desktops = cfg.get("desktops", [])
            added_cnt = 0
            for d in discovered:
                if not any(str(x.get("id")) == d["id"] for x in desktops):
                    desktops.append(d)
                    added_cnt += 1
            cfg["desktops"] = desktops
            save_config(cfg)
            self._send_json({"success": True, "count": len(desktops), "added": added_cnt})

        elif url.path == "/api/qr/refresh":
            if not STATE["logged_in"]:
                force_generate_new_qr()
            self._send_json({"success": True, "qr_url": STATE["qr_url"]})
        else:
            self.send_error(404, "Not Found")

def main():
    global CONFIG_FILE
    if len(sys.argv) > 1 and sys.argv[1].endswith(".json"):
        CONFIG_FILE = os.path.abspath(sys.argv[1])
        
    port = 8572
    cfg = load_config()
    if "port" in cfg:
        port = int(cfg["port"])
        
    server = HTTPServer(("0.0.0.0", port), RequestHandler)
    append_log(f"🌐 天翼云 Clink 原生多设备控制中心已启动！控制台端口: http://0.0.0.0:{port} (平台: {'Windows' if IS_WINDOWS else 'Linux'})")
    
    t = threading.Thread(target=round_robin_worker, daemon=True)
    t.start()
    STATE["engine_thread"] = t
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        STATE["should_stop"] = True
        stop_active_client()
        append_log("服务已停止。")

if __name__ == "__main__":
    main()
