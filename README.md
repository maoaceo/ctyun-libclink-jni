# 天翼云电脑 Clink / QUIC 原生多设备轮询保活中心 (ctyun-libclink-jni)

包含官方 Android / Linux 底层 **`libclink-jni.so`** 核心动态库与 **Web 控制台、手机扫码登录、设备ID管理及实时日志**。

---

## 📦 架构说明：为什么有 `libclink-jni.so` 和 Python Web

1. **`jni/` 目录中的 `libclink-jni.so`**：
   - 提取自天翼云官方客户端（包含 `arm64-v8a` 和 `armeabi-v7a` 双架构）；
   - 官方导出函数包括：`Java_com_iiordanov_bVNC_ClinkCommunicator_clinkCall`、`clinkCallStream` 等；
   - 封装了完整的 **QUIC (RFC 9000) / Clink 串流传输协议与 H.264 解码管线**，专用于 Android 端二次开发或注入调用。
2. **服务器端 Linux x86_64 调度与 Web 面板**：
   - 在 Linux 服务器上无需笨重的 Android 模拟器，而是通过轻量无头环境直接调用官方原生 x86_64 Clink 引擎；
   - 结合 Web 控制台实现 **手机扫码登录、多设备 ID 录入、自动防冲突轮询与日志监控**。

---

## 🌟 核心功能

- 📱 **手机扫码授权**：自动捕获并展示官方最新登录二维码与确认直链；
- 🖥️ **设备 ID 管理**：Web 界面一键增删云电脑数字 ID、设备别名与编码，自带防重复与防互踢检测；
- 🔄 **单实例轻量轮询保活**：
  - 5 台机器轮流串流 35 秒，完整周期仅需 3 分钟；
  - 成功重置官方机房的 **5 分钟（游戏版）/ 10 分钟（普通版）** 闲置自动关机倒计时；
  - 内存仅占 200~300MB，不卡死低配服务器。
- 📜 **实时视讯日志监控**：Web 端实时显示底层 Clink 视讯握手、延时与轮询进度。

---

## 🚀 部署与使用

### 1. 克隆仓库

```bash
git clone https://github.com/maoaceo/ctyun-libclink-jni.git
cd ctyun-libclink-jni
```

### 2. 环境一键配置

```bash
chmod +x setup.sh web_server.py
./setup.sh
```

### 3. 启动 Web 控制中心

```bash
# 后台常驻运行（默认端口 8572）
nohup python3 web_server.py > web.log 2>&1 &
```

在浏览器打开 `http://你的服务器IP:8572` 即可使用！

---

## 📂 项目结构

```text
ctyun-libclink-jni/
├── jni/                               # 官方底层 Clink JNI 原生核心库
│   ├── arm64-v8a/libclink-jni.so      # 64 位 ARM 架构
│   └── armeabi-v7a/libclink-jni.so    # 32 位 ARM 架构
├── web_server.py                      # Web 控制台服务与多设备轮询引擎
├── setup.sh                           # Linux x86_64 官方核心引擎提取脚本
├── config.json                        # 轮询设备列表与保持时间配置
└── README.md
```
