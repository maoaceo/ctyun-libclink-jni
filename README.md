# 天翼云电脑 Linux 原生多设备轮询保活控制中心 (Docker 版)

基于天翼云官方 Linux 原生视讯串流内核（**Clink / QUIC RFC 9000**）构建的高性能、超轻量无头多设备轮询保活系统。

---

## 🌟 为什么用 Docker 部署最好？

1. **零环境依赖与秒级拉起**：
   - 内部已装齐轻量无头虚拟屏幕 `Xvfb`、XCB、音频驱动及天翼云官方 Linux 原生动态库；
   - 宿主机不需要安装任何依赖库，任何 Linux 服务器（Ubuntu/Debian/CentOS/Alpine）装好 Docker 就能一键跑起来。
2. **多账号多开彻底天然物理隔离**：
   - 每个 Docker 容器就是一个纯净的独立系统，拥有完全隔离的 `HOME` 数据卷与网络端口；
   - **彻底解决多开账号间进程抢占、日志串线和数据库互相污染的问题**！
3. **极低资源开销**：
   - 单容器常驻内存仅约 `150MB`，CPU 占用极低，1核1G VPS 也能轻松多开几个容器。

---

## 🚀 极速部署使用 (Docker CLI / Docker Compose)

### 方式一：Docker 一键单行命令（最快）

#### 启动主账号（端口 8572）：
```bash
docker run -d \
  --name ctyun-acc1 \
  --restart always \
  -p 8572:8572 \
  -v /opt/ctyun/acc1/home:/root \
  -e TZ=Asia/Shanghai \
  lusean23/ctyun-libclink-jni:latest
```

#### 多开第二个账号（只需改个容器名和端口 8573）：
```bash
docker run -d \
  --name ctyun-acc2 \
  --restart always \
  -p 8573:8572 \
  -v /opt/ctyun/acc2/home:/root \
  -e TZ=Asia/Shanghai \
  lusean23/ctyun-libclink-jni:latest
```

---

### 方式二：Docker Compose 统一编排多开（最方便管理）

创建 `docker-compose.yml`：
```yaml
version: '3.8'

services:
  # 账号 1 (端口 8572)
  ctyun-acc1:
    image: lusean23/ctyun-libclink-jni:latest
    container_name: ctyun-acc1
    restart: always
    ports:
      - "8572:8572"
    volumes:
      - ./data/acc1/home:/root
    environment:
      - TZ=Asia/Shanghai

  # 账号 2 (多开实例，端口 8573)
  ctyun-acc2:
    image: lusean23/ctyun-libclink-jni:latest
    container_name: ctyun-acc2
    restart: always
    ports:
      - "8573:8572"
    volumes:
      - ./data/acc2/home:/root
    environment:
      - TZ=Asia/Shanghai
```

启动命令：
```bash
docker compose up -d
```

---

## 📱 使用指南

1. **打开控制面板**：
   - 账号 1 面板：`http://你的服务器IP:8572` (默认密码: `admin`)
   - 账号 2 面板：`http://你的服务器IP:8573` (默认密码: `admin`)
2. **手机微信/App 扫码**：各自面板独立出码，扫码授权成功后自动闭环，进入常驻保活状态；
3. **添加设备与探测**：点击 **【🔍 自动探测】** 或直接粘贴设备编码（`D00...`）；
4. **全天候挂机**：容器将在后台自动循环进行 35 秒视讯串流握手，重置 5 分钟闲置倒计时！
