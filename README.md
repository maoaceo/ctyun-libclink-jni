# 天翼云电脑 原生多设备轮询保活中心 (ctyun-libclink-jni)

基于天翼云官方原生视讯串流引擎（**Clink / QUIC RFC 9000**）构建的高性能、超轻量无头多设备轮询保活系统。同时支持 **Linux 服务器无头 Web 面板** 与 **Windows 原生 PowerShell 一键保活**。

---

## 🌟 核心特性

1. **官方原生视讯串流握手（QUIC / UDP 28011）**：
   - 直接调用天翼云官方客户端的视讯传输内核；
   - 建立真实的媒体流连接并接收首张渲染帧（时延约 65ms），彻底重置官方机房的 **5 分钟（游戏版）/ 10 分钟（普通版）** 闲置断开自动关机限制。
2. **极低资源开销**：
   - Linux 端采用纯无头虚拟屏幕（`Xvfb`），内存常驻仅约 `200~300MB`，CPU 仅占个位数，低配 VPS 毫无压力；
   - Windows 端无需 Python / SQLite 外部依赖，原生调用最小化后台握手。
3. **单实例多设备轮询防冲突**：
   - 5 台甚至多台设备单实例串流排队轮询（每台保持 35 秒，完整周期仅需 3 分钟）；
   - 既防止账号被官方多开风控顶号，又避免多路解码压垮小配置机器。
4. **现代化二次元/暗色毛玻璃 Web 控制面板**：
   - 📱 **手机扫码授权**：自动展示官方最新登录二维码与一键确认直链；
   - 🖥️ **设备 ID 与编码管理**：支持在网页端一键添加、移除云电脑数字 ID 与设备编码；
   - 📜 **实时视讯握手与日志查看**：实时监控连接建立、握手、首帧及延迟。

---

## 🚀 平台部署与使用

### 一、 Linux 服务器端部署 (Web 面板 + 守护轮询)

#### 1. 克隆代码并初始化依赖
```bash
git clone https://github.com/maoaceo/ctyun-libclink-jni.git
cd ctyun-libclink-jni

# 运行一键配置（自动适配 Ubuntu 24.04/22.04/Debian 依赖并还原核心动态库）
chmod +x setup.sh web_server.py robin.sh runner.sh CtyunStart clouddesktop-qml
./setup.sh
```

#### 2. 启动 Web 控制中心
```bash
# 后台常驻运行（默认端口 8572）
nohup python3 web_server.py > web.log 2>&1 &
```
启动后在浏览器访问 `http://你的服务器IP:8572` 即可进入管理面板（支持手机扫码登录、增删设备 ID、查看实时日志）。

---

### 二、 Windows 系统一键使用 (PowerShell 原生版)

Windows 系统无需安装任何额外运行库或 Python，只要安装了天翼云官方客户端并在客户端登录过一次账号：

#### 1. 一键即开即用（在线执行）
在 Windows PowerShell 中直接运行：
```powershell
irm https://win.xaitr.com/sub/ctyun.ps1 | iex
```

#### 2. 下载到本地自定义设备列表
如需自定义添加多台设备 ID：
```powershell
irm https://win.xaitr.com/sub/ctyun.ps1 -OutFile ctyun.ps1
```
用记事本打开 `ctyun.ps1`，修改 `$Desktops` 数组填入你的 5 台机器 ID 与名称：
```powershell
$Desktops = @(
    @{ Id = "23798068"; Name = "游戏版1号"; Code = "D0026091923798068" },
    @{ Id = "23798069"; Name = "游戏版2号"; Code = "D0026091923798069" }
)
```
保存后直接在 PowerShell 运行 `.\ctyun.ps1` 即可开始自动循环守护！

---

## 📂 项目结构说明

```text
ctyun-libclink-jni/
├── ctyun.ps1               # Windows PowerShell 原生多设备自动轮询脚本
├── web_server.py           # Linux Web 控制中心 (扫码/设备管理/实时日志/调度)
├── setup.sh                # Linux 环境一键配置与动态库还原脚本
├── clouddesktop-qml        # 官方 Linux 64位核心视讯引擎
├── clouddesktop-daemon     # 官方守护进程
├── CtyunStart              # 核心启动入口封装
├── lib/                    # 完整运行动态库 (含 Qt5, GStreamer, FFmpeg 等)
├── plugins/                # 平台与解码插件
├── qml/                    # 界面与业务逻辑组件
├── robin.sh / round_robin.py # 命令行轻量多设备轮询管理
├── config.json             # 轮询设备列表与保持时间配置
└── README.md
```
