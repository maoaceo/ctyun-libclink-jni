# 天翼云电脑 Linux 原生多设备轮询保活控制中心 (ctyun-libclink-jni)

基于天翼云官方 Linux 原生视讯串流内核（**Clink / QUIC RFC 9000**）构建的高性能、超轻量无头多设备轮询保活系统。

---

## 🌟 核心特性与优势

1. **官方底层真实视讯串流握手（QUIC / UDP 28011）**：
   - 绝非模拟网页端无效的 HTTP `reportOnline`，而是直接调用天翼云官方 Linux 客户端视讯内核 `clouddesktop-qml`；
   - 建立真实的媒体通道并接收首张渲染帧（时延约 65ms），彻底粉碎游戏版 **5 分钟**、普通版 **10 分钟** 的闲置自动关机倒计时。
2. **极轻量、超低服务器配置要求**：
   - 采用纯无头虚拟显示（`Xvfb`），内存常驻仅约 `150~250MB`，CPU 占用个位数，低配 1核1G VPS 毫无压力；
   - 无需安装笨重的桌面环境或虚拟机。
3. **单实例多设备轮询防冲突**：
   - 5 台甚至多台设备单实例串流排队轮询（每台握手保持 35 秒，完整周期仅需 3 分钟）；
   - 既防止账号被官方多开风控顶号，又避免多路视频解码压垮服务器。
4. **现代化二次元/暗色毛玻璃 Web 控制面板**：
   - 🔐 **全接口安全密码防护**：访问默认受密码保护（默认密码 `admin`，支持自定义修改与一键锁定退出）；
   - 📱 **官方原生客户端扫码登录**：严格由官方视讯引擎生成专属二维码，微信/App扫码后 100% 立即闭环完成授权；
   - 🔍 **精准实时自动探测**：自动穿透官方实时解密接口，精准识别名下真实存在的全部云电脑，杜绝历史过期假设备；
   - 🖥️ **设备编码直接识别**：支持直接粘贴天翼云电脑编码（如 `D0026090823728443`），底层自动提取绑定真实的 8 位机房数字 ID；
   - 📜 **实时视讯握手与日志查看**：实时观察连接建立、串流握手、首帧时标与重置倒计时。
5. **多账号独立多开隔离 (`multi_instance.py`)**：
   - 支持单台服务器独立多开多个天翼账号，每个账号独立数据目录与独立端口，零冲突、不顶号。

---

## 🚀 快速部署与使用 (Ubuntu / Debian)

### 1. 克隆仓库

```bash
git clone https://github.com/maoaceo/ctyun-libclink-jni.git
cd ctyun-libclink-jni
```

### 2. 一键环境依赖初始化

```bash
chmod +x setup.sh web_server.py robin.sh runner.sh CtyunStart clouddesktop-qml
./setup.sh
```
> `setup.sh` 自动兼容 Ubuntu 24.04/22.04/20.04（智能识别 `t64` 音频库）及 Debian 10/11/12，增量补齐 XCB 与虚拟屏幕依赖，并自带完整性自检。

### 3. 启动 Web 控制中心

直接前台运行调试：
```bash
python3 web_server.py
```

或后台常驻运行：
```bash
nohup python3 web_server.py > web.log 2>&1 &
```

---

## 🔄 配置开机自启系统守护 (Systemd)

为了保证服务器重启后自动恢复挂机保活，直接注册为系统守护服务：

```bash
cat << 'EOF' > /etc/systemd/system/ctyun-keepalive.service
[Unit]
Description=Ctyun Headless Clink KeepAlive Web Console
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/ctyun-libclink-jni
ExecStart=/usr/bin/python3 /root/ctyun-libclink-jni/web_server.py
Restart=always
RestartSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ctyun-keepalive
systemctl restart ctyun-keepalive
```

---

## 📱 使用指南

1. **打开控制面板**：在浏览器访问 `http://你的服务器IP:8572`；
2. **输入访问密码**：输入默认密码 `admin` 解锁控制台；
3. **手机扫码授权**：在左侧“账号授权状态”中，使用天翼云电脑 App 或微信扫描二维码确认登录；
4. **添加云电脑**：
   - **方式一（最推荐）**：点击 **“🔍 自动探测”**，系统会自动读取当前账号名下最新持有的真实云电脑并排队保活；
   - **方式二**：在输入框直接粘贴你的设备编码（例如 `D0026090823728443`），点击“添加到轮询队列”；
5. **挂机保活**：系统将 24 小时全天候在名下设备间平滑轮流串流握手，各机器永久保持在线！

---

## 👥 多账号多开指引 (`multi_instance.py`)

如有名下多个天翼云账号需在同一服务器上独立保活：

```bash
# 1. 为第二个账号创建专属实例（指定端口 8573）
python3 multi_instance.py create acc2 8573

# 2. 启动该多开实例
python3 multi_instance.py start acc2

# 3. 浏览器打开第二个账号专属控制面板
# http://你的服务器IP:8573 (密码: admin)
```

---

## 📂 项目结构

```text
ctyun-libclink-jni/
├── web_server.py           # Web 控制中心与多设备轮询调度引擎
├── multi_instance.py       # 多账号环境隔离与多开管理工具
├── setup.sh                # 全系统环境智能优化与运行库还原脚本
├── clouddesktop-qml        # 官方 Linux 64位核心视讯引擎
├── clouddesktop-daemon     # 官方守护进程
├── CtyunStart              # 原生启动与运行库环境加载封装
├── lib/                    # 完整运行动态库 (Qt5, GStreamer, FFmpeg 等)
├── plugins/                # 平台与音频解码插件
├── qml/                    # 官方核心界面与业务逻辑组件
├── config.json             # 轮询设备列表与端口/密码配置
└── README.md
```
