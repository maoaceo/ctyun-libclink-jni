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

### 3. 查看连接状态
```bash
./ctyun.sh status
```

### 4. 实时查看串流日志
```bash
./ctyun.sh log
```

### 5. 停止运行
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
