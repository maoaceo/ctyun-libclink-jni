@echo off
chcp 65001 >nul
title 天翼云电脑 Web 控制中心启动器

echo ========================================================
echo  正在启动天翼云电脑 Web 轮询保活控制中心 (Windows 版)...
echo ========================================================

where python >nul 2>nul
if %errorlevel% neq 0 (
    echo [X] 未检测到 Python 环境，请先安装 Python 3.8 或以上版本！
    echo     下载地址: https://www.python.org/downloads/
    pause
    exit /b 1
)

start "" http://127.0.0.1:8572
python web_server.py

pause
