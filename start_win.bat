@echo off
title Ctyun KeepAlive Launcher
cd /d "%~dp0"

where python >nul 2>nul
if %errorlevel% equ 0 (
    echo [*] Starting Web Console with Python...
    start "" http://127.0.0.1:8572
    python web_server.py
    pause
    exit /b
)

where py >nul 2>nul
if %errorlevel% equ 0 (
    echo [*] Starting Web Console with Python...
    start "" http://127.0.0.1:8572
    py web_server.py
    pause
    exit /b
)

echo [!] Python not detected. Running native Windows KeepAlive directly...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ctyun.ps1"
pause
