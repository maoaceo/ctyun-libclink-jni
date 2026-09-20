# 天翼云电脑 Linux 原生无头持久保活控制中心

基于天翼云官方 Linux 原生视讯串流内核（**Clink / RFC 9000 QUIC**）构建的高性能、超轻量常驻保活系统。

彻底解决天翼云电脑（游戏版 5 分钟 / 普通版 10 分钟）闲置超时自动关机的问题。

---

## 🌟 核心特性

1. **真实视讯串流（彻底杜绝关机）**：
   - 区别于仅调用网页 HTTP API 假在线，本项目直接拉起官方原生客户端并建立真实的 QUIC/UDP 28011 视讯通道，向机房网关上报活跃。
2. **持久在线模式（不再 35 秒轮询断开）**：
   - 连接成功后持续保持视讯连接，绝不主动退出重连，网络波动或进程异常时自动恢复。
3. **Web 可视化控制台**：
   - 现代化磨砂玻璃暗黑风 UI。
   - 官方直链扫码登录、授权状态实时感知。
   - 设备自动扫描（精准动态解析机房最新分配的 8 位数字 ID 与设备编码）。
   - 实时滚动日志监控与安全密码防护（默认密码：`admin`）。
4. **原生极轻量占用**：
   - 无头 Xvfb 虚拟屏幕驱动，无需安装桌面环境（GNOME/KDE），单实例仅占约 200MB~300MB 内存。

---

## 🚀 快速开始 (Linux 服务器一键部署)

### 1. 克隆仓库与初始化环境
```bash
git clone https://github.com/maoaceo/ctyun-libclink-jni.git
cd ctyun-libclink-jni
chmod +x setup.sh web_server.py CtyunStart clouddesktop-qml
./setup.sh
```
> `setup.sh` 会自动安装无头虚拟屏幕 `Xvfb`、XCB、音频驱动，并自动解压组装还原大体积核心动态库。

### 2. 启动 Web 控制中心
```bash
python3 web_server.py
```
若需后台常驻运行：
```bash
nohup python3 web_server.py > web.log 2>&1 &
```

打开浏览器访问：`http://你的服务器IP:8572`（默认访问密码：`admin`）。

---

## 📱 使用步骤

1. **扫码登录**：打开控制台，使用天翼云电脑手机 App / 微信扫码，授权成功后界面自动显示绿色已登录。
2. **扫描设备**：点击页面中的 **【🔍 自动探测】**，系统会自动读取机房返回的设备编码（如 `D002609...`）并绑定到保活任务。
3. **保持运行**：设备添加后，系统会自动拉起底层串流核心并打印 `✅ 真实 Clink 视讯串流已连通`，随后一直保持连接，安心挂机！

---

## 👥 多账号 / 多设备多开指南

为保证连接稳定性，建议**一个实例保持连接一台云电脑**。如果拥有多个云电脑或账号，推荐使用多实例隔离运行：

```bash
# 账号 1 (默认端口 8572)
python3 web_server.py

# 账号 2 (多开实例，指定端口 8573 与独立数据目录)
python3 multi_instance.py start acc2 8573

# 账号 3 (多开实例，指定端口 8574)
python3 multi_instance.py start acc3 8574
```

每个实例拥有完全隔离的 Session、配置与日志，分别访问对应端口即可独立扫码与保活。

---

## ⚙️ 配置文件说明 (`config.json`)

```json
{
  "port": 8572,
  "admin_password": "admin",
  "keepalive_mode": "continuous",
  "desktops": [
    {
      "id": "23794229",
      "code": "D0026091823794229",
      "name": "天翼云电脑游戏版"
    }
  ]
}
```
- `keepalive_mode`：保活模式，默认为 `continuous`（持久在线保持，不主动断开）。

---

## 📋 常用管理命令

```bash
# 查看实时保活日志
tail -f robin.log

# 检查当前客户端运行状态
ps aux | grep clouddesktop-qml

# 停止保活服务
pkill -f web_server.py && pkill -f clouddesktop-qml
```
