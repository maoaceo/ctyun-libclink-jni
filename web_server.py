#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
天翼云电脑 Clink 原生多设备轮询与 Web 控制台服务
Web Dashboard with QR Login, Desktop ID Management & Real-Time Clink Logs
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
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BIN_DIR = os.path.join(BASE_DIR, "bin")
if not os.path.exists(BIN_DIR):
    # 兼容直接使用 /root/ctyun-headless 的情况
    BIN_DIR = "/root/ctyun-headless"

APP_BIN = os.path.join(BIN_DIR, "CtyunStart")
CONFIG_FILE = os.path.join(BASE_DIR, "config.json")
LOG_DIR = "/root/.local/share/CtyunClouddeskPublic/Log"
LOG_FILE = os.path.join(BASE_DIR, "robin.log")

# 全局运行状态
STATE = {
    "running": False,
    "current_desktop": None,
    "round": 0,
    "last_seen_time": "",
    "engine_thread": None,
    "should_stop": False,
    "qr_url": "",
    "qr_img_base64": ""
}

DEFAULT_CONFIG = {
    "port": 8572,
    "stay_seconds": 35,
    "switch_gap": 3,
    "desktops": [
        {
            "id": "23798068",
            "name": "天翼云电脑游戏版",
            "code": "D0026091923798068"
        }
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

def append_log(msg):
    ts = time.strftime("[%Y-%m-%d %H:%M:%S]")
    line = f"{ts} {msg}\n"
    print(line, end="")
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass

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
        cur.execute("PRAGMA wal_checkpoint(FULL)")
        conn.close()
        return True
    except Exception as e:
        append_log(f"数据库更新目标云电脑失败: {e}")
        return False

def stop_active_client():
    subprocess.run("pkill -f 'clouddesktop-qml' 2>/dev/null || true", shell=True)
    subprocess.run("pkill -f 'CtyunStart' 2>/dev/null || true", shell=True)
    subprocess.run("pkill -f 'Xvfb' 2>/dev/null || true", shell=True)
    time.sleep(1)

def check_qr_from_logs():
    today_log = f"{LOG_DIR}/{time.strftime('%Y-%m-%d')}.log"
    if os.path.exists(today_log):
        try:
            with open(today_log, "r", encoding="utf-8", errors="ignore") as f:
                c = f.read()
            matches = re.findall(r'https://desk\.ctyun\.cn[^ ]+loginMode=1[^ ]*', c)
            if matches:
                url = matches[-1]
                STATE["qr_url"] = url
                # 生成 base64 图片
                try:
                    import base64
                    png_path = "/tmp/web_qr.png"
                    subprocess.run(f'qrencode -s 6 -o "{png_path}" "{url}"', shell=True)
                    if os.path.exists(png_path):
                        b64 = base64.b64encode(open(png_path, "rb").read()).decode()
                        STATE["qr_img_base64"] = f"data:image/png;base64,{b64}"
                except Exception:
                    pass
        except Exception:
            pass

def round_robin_worker():
    append_log("🚀 官方 Clink / QUIC 原生多设备轮询保活引擎已启动！")
    STATE["running"] = True
    STATE["should_stop"] = False
    
    while not STATE["should_stop"]:
        cfg = load_config()
        desktops = cfg.get("desktops", [])
        if not desktops:
            append_log("⚠️ 当前轮询列表为空，等待添加设备...")
            time.sleep(5)
            continue
            
        stay_sec = int(cfg.get("stay_seconds", 35))
        switch_gap = int(cfg.get("switch_gap", 3))
        STATE["round"] += 1
        round_num = STATE["round"]
        append_log(f"🔄 === 开始第 {round_num} 轮多设备巡检 ({len(desktops)} 台) ===")
        
        for idx, d in enumerate(desktops, 1):
            if STATE["should_stop"]:
                break
                
            d_id = d.get("id")
            d_name = d.get("name", "云电脑")
            d_code = d.get("code", d_id)
            STATE["current_desktop"] = f"[{d_name}] ({d_code})"
            
            append_log(f"[{idx}/{len(desktops)}] 正在连接: [{d_name}] (ID: {d_id} / {d_code})...")
            set_target_desktop_in_db(d_id)
            
            # 启动无头客户端
            stop_active_client()
            cmd = f'nohup xvfb-run -a -s "-screen 0 1024x768x16 -nolisten tcp" "{APP_BIN}" > /tmp/ctyun_runner.log 2>&1 &'
            subprocess.Popen(cmd, shell=True, executable="/bin/bash")
            
            # 等待串流握手
            connected = False
            today_log = f"{LOG_DIR}/{time.strftime('%Y-%m-%d')}.log"
            for _ in range(12):
                if STATE["should_stop"]:
                    break
                time.sleep(1)
                check_qr_from_logs()
                if os.path.exists(today_log):
                    try:
                        out = subprocess.check_output(f"tail -n 25 '{today_log}' || true", shell=True).decode('utf-8', errors='ignore')
                        if "clink连接成功" in out or "收到第一张图" in out or "当前时延" in out:
                            connected = True
                            break
                    except Exception:
                        pass
                        
            if connected:
                append_log(f"  -> 🟢 视讯串流握手就绪！保持官方媒体流 {stay_sec} 秒...")
            else:
                append_log(f"  -> ⏳ 正在保持视讯连接 ({stay_sec} 秒)...")
                
            # 保持阶段
            waited = 0
            while waited < stay_sec and not STATE["should_stop"]:
                time.sleep(1)
                waited += 1
                check_qr_from_logs()
                
            stop_active_client()
            append_log(f"  -> ✨ [{d_name}] 闲置倒计时已重置！准备轮换...")
            time.sleep(switch_gap)
            
    stop_active_client()
    STATE["running"] = False
    STATE["current_desktop"] = None
    append_log("⏹️ 轮询引擎已停止。")

# HTML Web UI 模版 (精美ACG二次元与现代化暗色毛玻璃风格)
HTML_PAGE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>天翼云 Clink 原生多设备轮询保活控制台</title>
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
  padding: 4px 10px;
  border-radius: 20px;
  font-size: 12px;
  font-weight: 600;
}
.badge-online { background: rgba(0,230,118,0.15); color: var(--success); border: 1px solid var(--success); }
.badge-offline { background: rgba(255,82,82,0.15); color: var(--danger); border: 1px solid var(--danger); }

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
.qr-box img { max-width: 180px; border-radius: 8px; border: 2px solid var(--border); }
.qr-box a { color: var(--primary); font-size: 12px; text-decoration: none; word-break: break-all; display: block; margin-top: 8px; }

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
</style>
</head>
<body>
<div class="container">
  <header>
    <div class="title-group">
      <h1>✨ 天翼云 Clink 原生多设备轮询保活</h1>
      <p>官方 Linux 视讯串流内核 (QUIC/Clink) · 纯无头运行 · 5分钟超时防关机</p>
    </div>
    <div>
      <span id="statusBadge" class="badge badge-offline">未连接</span>
    </div>
  </header>

  <div class="grid">
    <!-- 左侧控制面板 -->
    <div class="sidebar">
      <div class="card">
        <div class="card-header">
          <span>🎮 轮询引擎控制</span>
          <span id="roundCounter" style="font-size: 12px; color: var(--text-muted);">第 0 轮</span>
        </div>
        <p id="currDesktopText" style="font-size: 13px; margin-bottom: 16px; color: var(--text-muted);">当前串流设备: 无</p>
        <div style="display: flex; gap: 10px;">
          <button id="btnStart" class="btn btn-primary" onclick="toggleEngine(true)">启动轮询保活</button>
          <button id="btnStop" class="btn btn-danger" onclick="toggleEngine(false)">停止</button>
        </div>
      </div>

      <!-- 手机扫码登录 -->
      <div class="card">
        <div class="card-header">
          <span>📱 手机扫码授权</span>
          <button class="btn btn-primary" style="padding: 4px 10px; font-size: 12px;" onclick="refreshQR()">刷新二维码</button>
        </div>
        <p style="font-size: 12px; color: var(--text-muted);">打开天翼云电脑 App 或微信扫码确认登录：</p>
        <div class="qr-box">
          <div id="qrPlaceholder" style="padding: 30px; font-size: 12px; color: var(--text-muted);">正在获取二维码...</div>
          <img id="qrImg" src="" style="display: none;">
          <a id="qrLink" href="#" target="_blank" style="display: none;">🔗 点击直接打开网页确认</a>
        </div>
      </div>

      <!-- 设备添加表单 -->
      <div class="card">
        <div class="card-header">
          <span>➕ 添加云电脑设备</span>
        </div>
        <div class="form-group">
          <label>云电脑 ID (例如: 23798068)</label>
          <input type="text" id="newId" class="form-control" placeholder="请输入数字ID">
        </div>
        <div class="form-group">
          <label>机器名称备注</label>
          <input type="text" id="newName" class="form-control" placeholder="如: 游戏版1号">
        </div>
        <div class="form-group">
          <label>设备编码 (例如: D0026091923798068)</label>
          <input type="text" id="newCode" class="form-control" placeholder="可选，便于区分">
        </div>
        <button class="btn btn-primary" style="width: 100%; justify-content: center;" onclick="addDesktop()">添加到轮询队列</button>
      </div>
    </div>

    <!-- 右侧设备列表与实时日志 -->
    <div class="main-content">
      <div class="card">
        <div class="card-header">
          <span>🖥️ 轮询设备列表 (<span id="devCount">0</span> 台)</span>
          <span style="font-size: 12px; color: var(--text-muted);">单台保持: 35s | 切换: 3s</span>
        </div>
        <div id="deviceList">
          <!-- 动态渲染 -->
        </div>
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
function fetchStatus() {
  fetch('/api/status').then(r => r.json()).then(data => {
    const badge = document.getElementById('statusBadge');
    if (data.running) {
      badge.className = 'badge badge-online';
      badge.innerText = '● 正在轮询串流保活';
      document.getElementById('currDesktopText').innerHTML = '当前串流: <b style="color: var(--primary);">' + (data.current_desktop || '连接中...') + '</b>';
    } else {
      badge.className = 'badge badge-offline';
      badge.innerText = '○ 已停止';
      document.getElementById('currDesktopText').innerText = '当前串流设备: 无';
    }
    document.getElementById('roundCounter').innerText = '第 ' + data.round + ' 轮';

    // 二维码展示
    if (data.qr_img_base64) {
      document.getElementById('qrPlaceholder').style.display = 'none';
      const img = document.getElementById('qrImg');
      img.src = data.qr_img_base64;
      img.style.display = 'inline-block';
      const link = document.getElementById('qrLink');
      link.href = data.qr_url;
      link.style.display = 'block';
    }

    // 渲染设备列表
    renderDesktops(data.desktops || [], data.current_desktop);
  }).catch(()=>{});
}

function renderDesktops(list, curr) {
  document.getElementById('devCount').innerText = list.length;
  const container = document.getElementById('deviceList');
  if (list.length === 0) {
    container.innerHTML = '<p style="font-size: 13px; color: var(--text-muted); text-align: center; padding: 20px;">暂无云电脑，请在左侧添加</p>';
    return;
  }
  let html = '';
  list.forEach((d, idx) => {
    const isActive = curr && curr.includes(d.id);
    html += `
      <div class="device-item ${isActive ? 'active' : ''}">
        <div class="device-info">
          <h4>${idx + 1}. ${d.name} ${isActive ? '<span style="color: var(--primary); font-size: 11px;">[正在串流]</span>' : ''}</h4>
          <p>ID: ${d.id} · 编码: ${d.code || d.id}</p>
        </div>
        <button class="btn btn-danger" style="padding: 4px 8px; font-size: 12px;" onclick="removeDesktop('${d.id}')">移除</button>
      </div>
    `;
  });
  container.innerHTML = html;
}

function fetchLogs() {
  fetch('/api/logs').then(r => r.text()).then(t => {
    const box = document.getElementById('logTerminal');
    box.innerText = t || '暂无日志输出';
    box.scrollTop = box.scrollHeight;
  }).catch(()=>{});
}

function toggleEngine(start) {
  fetch('/api/engine', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({action: start ? 'start' : 'stop'})
  }).then(() => {
    setTimeout(fetchStatus, 500);
    setTimeout(fetchLogs, 1000);
  });
}

function addDesktop() {
  const id = document.getElementById('newId').value.trim();
  const name = document.getElementById('newName').value.trim() || '天翼云电脑';
  const code = document.getElementById('newCode').value.trim() || id;
  if (!id) { alert('请输入云电脑 ID'); return; }
  fetch('/api/desktops', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({action: 'add', id, name, code})
  }).then(r => r.json()).then(res => {
    if (res.error) alert(res.error);
    document.getElementById('newId').value = '';
    document.getElementById('newName').value = '';
    document.getElementById('newCode').value = '';
    fetchStatus();
  });
}

function removeDesktop(id) {
  if (!confirm('确定移除该云电脑保活吗？')) return;
  fetch('/api/desktops', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({action: 'remove', id})
  }).then(() => fetchStatus());
}

function refreshQR() {
  fetch('/api/qr/refresh', {method: 'POST'}).then(() => {
    setTimeout(fetchStatus, 1500);
  });
}

setInterval(fetchStatus, 3000);
setInterval(fetchLogs, 4000);
fetchStatus();
fetchLogs();
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

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/" or url.path == "/index.html":
            self._send_html(HTML_PAGE)
        elif url.path == "/api/status":
            cfg = load_config()
            check_qr_from_logs()
            data = {
                "running": STATE["running"],
                "current_desktop": STATE["current_desktop"],
                "round": STATE["round"],
                "qr_url": STATE["qr_url"],
                "qr_img_base64": STATE["qr_img_base64"],
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
                    out = subprocess.check_output(f"tail -n 80 '{LOG_FILE}' || true", shell=True).decode('utf-8', errors='ignore')
                    txt = out
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

        if url.path == "/api/engine":
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
                new_id = str(req_data.get("id", "")).strip()
                new_name = str(req_data.get("name", "云电脑")).strip()
                new_code = str(req_data.get("code", new_id)).strip()
                
                # 去重
                if any(str(d.get("id")) == new_id for d in desktops):
                    self._send_json({"error": f"云电脑 ID [{new_id}] 已经在列表中"}, 400)
                    return
                    
                desktops.append({"id": new_id, "name": new_name, "code": new_code})
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

        elif url.path == "/api/qr/refresh":
            check_qr_from_logs()
            self._send_json({"success": True, "qr_url": STATE["qr_url"]})
        else:
            self.send_error(404, "Not Found")

def main():
    port = 8572
    cfg = load_config()
    if "port" in cfg:
        port = int(cfg["port"])
        
    server = HTTPServer(("0.0.0.0", port), RequestHandler)
    append_log(f"🌐 天翼云 Clink 原生多设备控制中心已启动！控制台端口: http://0.0.0.0:{port}")
    
    # 自动在后台启动轮询
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
