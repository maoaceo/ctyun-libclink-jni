# 天翼云电脑 Linux 原生多设备轮询保活中心

基于天翼云官方 Linux 原生视讯串流引擎（**Clink / QUIC RFC 9000**）构建的高性能、超轻量无头多设备轮询保活系统。

---

## 🌟 核心特性

1. **官方原生视讯串流握手（QUIC / UDP 28011）**：
   - 直接运行官方 Linux x86_64 核心视讯进程 `clouddesktop-qml`；
   - 建立真实媒体通道并接收渲染帧，彻底破解游戏版 **5 分钟**、普通版 **10 分钟** 的闲置自动关机限制。
2. **极轻量、超低服务器配置要求**：
   - 采用纯无头虚拟屏幕（`Xvfb`），内存常驻仅约 `200~300MB`，CPU 占用极低；
   - 无需运行任何庞大桌面环境或 Windows 虚拟机。
3. **多设备防冲突平滑轮询**：
   - 支持同一账号名下多台（如 5 台）云电脑单实例排队轮流握手（每台保持 35 秒，完整周期仅需 3 分钟）；
   - 既防止账号被官方多开风控顶号，又避免多路解码压垮小配置服务器。
4. **现代化二次元/暗色毛玻璃 Web 控制面板**：
   - 📱 **手机扫码授权**：自动展示官方最新登录二维码与一键确认直链；
   - 🖥️ **设备 ID 与编码管理**：支持在网页端一键添加、移除云电脑数字 ID 与设备编码；
   - 📜 **实时视讯握手与日志查看**：实时监控连接建立、握手、首帧及延迟（约 65ms）。

---

## 🚀 快速部署与使用

### 1. 克隆代码

```bash
git clone https://github.com/maoaceo/ctyun-libclink-jni.git
cd ctyun-libclink-jni
```

### 2. 一键配置运行环境

```bash
chmod +x setup.sh web_server.py robin.sh runner.sh CtyunStart clouddesktop-qml
./setup.sh
```

### 3. 启动 Web 控制中心

```bash
# 后台常驻运行（默认端口 8572）
nohup python3 web_server.py > web.log 2>&1 &
```

启动后在浏览器访问 `http://你的服务器IP:8572` 即可进入管理面板！

---

## 📂 项目结构

```text
ctyun-libclink-jni/
├── clouddesktop-qml        # 官方 64 位核心视讯引擎
├── clouddesktop-daemon     # 守护进程
├── CtyunStart              # 启动入口封装
├── lib/                    # 完整运行动态库 (含 GStreamer, Qt5, FFmpeg 等)
├── plugins/                # 平台与音频解码插件
├── qml/                    # 核心 QML 模块
├── web_server.py           # Web 控制台与多设备轮询调度引擎
├── setup.sh                # 一键依赖安装与运行库初始化脚本
├── robin.sh / round_robin.py # 命令行多设备轮询管理
├── config.json             # 设备列表与轮询时间配置
└── README.md
```
