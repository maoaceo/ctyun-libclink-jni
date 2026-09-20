FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV HOME=/root

WORKDIR /app

# 安装底层轻量虚拟屏幕、XCB 与视讯依赖
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        python3 \
        xvfb \
        qrencode \
        libasound2 \
        libxi6 \
        libxcomposite1 \
        libxfixes3 \
        libxcursor1 \
        libxtst6 \
        libxrandr2 \
        libxcb-shape0 \
        libxcb-xinerama0 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-render-util0 \
        libxcb-render0 \
        libxcb-xkb1 \
        libxkbcommon-x11-0 \
        libxkbcommon0 \
        libpixman-1-0 \
        libopus0 \
        libpulse0 \
        libnss3 \
        libnspr4 \
        libxdamage1 \
        libxss1 \
        libxslt1.1 \
        libv4l-0 \
        libgudev-1.0-0 \
        curl \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# 复制当前完整运行组件与动态库
COPY . /app/

# 合成分卷大库并赋予执行权限
RUN if [ -f /app/lib/libQt5WebEngineCore.so.5.part_aa ]; then \
        cat /app/lib/libQt5WebEngineCore.so.5.part_* > /app/lib/libQt5WebEngineCore.so.5 && \
        rm -f /app/lib/libQt5WebEngineCore.so.5.part_*; \
    fi && \
    chmod +x /app/CtyunStart /app/clouddesktop-qml /app/crashpad_handler /app/clouddesktop-daemon /app/setup.sh /app/web_server.py 2>/dev/null || true

EXPOSE 8572

ENTRYPOINT ["python3", "/app/web_server.py"]
