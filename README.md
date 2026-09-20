# 天翼云电脑 Linux 原生无头持久保活脚本 (第一版原生极简版)

基于天翼云官方 Linux 原生视讯内核（**Clink / RFC 9000 QUIC**）构建的原生保活脚本。

彻底杜绝闲置超时自动关机，不依赖复杂的 Web 框架，开箱即用，极简纯净。

---

## 🚀 快速使用命令

进入目录赋予权限：
```bash
cd /root/ctyun-libclink-jni
chmod +x setup.sh ctyun.sh CtyunStart clouddesktop-qml
./setup.sh
```

### 1. 启动持久连接
```bash
./ctyun.sh start
```

### 2. 获取登录二维码
```bash
./ctyun.sh qr
```
> 输出官方直链二维码地址，手机直接打开或扫码即可完成授权。

### 3. 自动扫描名下所有云电脑
```bash
./ctyun.sh scan
```
> 直接从官方接口解析返回当前账号下所有设备列表、8位纯数字 ID、设备编码（`D00...`）以及当前的开关机状态（`已关机` / `运行中`）。

### 4. 远程电源控制 (官方签名开机/唤醒/关机)
```bash
# 触发开机 (对齐 ctyun-dashboard Triple Link 双重信令链路)
./ctyun.sh boot 23794229 poweron

# 触发唤醒
./ctyun.sh boot 23794229 awake

# 触发关机 / 重启
./ctyun.sh boot 23794229 shutdown
./ctyun.sh boot 23794229 reboot
```

### 5. 查看连接状态
```bash
./ctyun.sh status
```

### 6. 实时查看串流日志
```bash
./ctyun.sh log
```

### 7. 停止运行
```bash
./ctyun.sh stop
```

---

## 🌟 开机自启与后台常驻 (systemd)

如需服务器重启后全自动拉起连接，可配置 systemd：

```bash
cat << 'EOF' > /etc/systemd/system/ctyun-keepalive.service
[Unit]
Description=Ctyun Clink Native KeepAlive Service
After=network.target

[Service]
Type=forking
User=root
WorkingDirectory=/root/ctyun-libclink-jni
ExecStart=/root/ctyun-libclink-jni/ctyun.sh start
ExecStop=/root/ctyun-libclink-jni/ctyun.sh stop
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ctyun-keepalive
systemctl start ctyun-keepalive
```
