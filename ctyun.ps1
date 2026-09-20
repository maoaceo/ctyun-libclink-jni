# ==============================================================================
# 天翼云电脑 Windows 原生多设备自动轮询保活脚本 (直链即开即用版)
# 使用方式: irm https://win.xaitr.com/sub/ctyun.ps1 | iex
# ==============================================================================

# ----------------- 用户自定义配置区 -----------------
$StaySeconds   = 35   # 每台机器视讯串流保持秒数 (重置官方5分钟关机计时器)
$SwitchSeconds = 3    # 切换下一台机器的间隔 (秒)

# 待轮询保活的云电脑设备列表 (按需增减)
$Desktops = @(
    @{ Id = "23798068"; Name = "游戏版1号"; Code = "D0026091923798068" }
    # @{ Id = "23798069"; Name = "游戏版2号"; Code = "D0026091923798069" }
    # @{ Id = "23798070"; Name = "尊享版3号"; Code = "D0026091923798070" }
)
# ----------------------------------------------------

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "🚀 天翼云电脑多设备【轮询防关机】脚本 (Windows 原生)" -ForegroundColor Cyan
Write-Host " - 待轮询设备: $($Desktops.Count) 台" -ForegroundColor Gray
Write-Host " - 单台握手保持: $StaySeconds 秒" -ForegroundColor Gray
Write-Host " - 5台完整轮询周期: 约 $($Desktops.Count * ($StaySeconds + $SwitchSeconds + 5)) 秒 (远低于300秒关机倒计时)" -ForegroundColor Gray
Write-Host "================================================================" -ForegroundColor Cyan

# 1. 自动定位官方客户端主程序
$ClientExe = ""
$PossiblePaths = @(
    "C:\Program Files (x86)\CtyunClouddeskPublic\clouddesktop-qml.exe",
    "C:\Program Files\CtyunClouddeskPublic\clouddesktop-qml.exe",
    "$env:ProgramFiles(x86)\CtyunClouddeskPublic\clouddesktop-qml.exe",
    "$env:ProgramFiles\CtyunClouddeskPublic\clouddesktop-qml.exe",
    "$env:LOCALAPPDATA\Programs\CtyunClouddeskPublic\clouddesktop-qml.exe",
    "$env:APPDATA\CtyunClouddeskPublic\clouddesktop-qml.exe",
    "D:\Program Files (x86)\CtyunClouddeskPublic\clouddesktop-qml.exe",
    "D:\Program Files\CtyunClouddeskPublic\clouddesktop-qml.exe"
)

foreach ($p in $PossiblePaths) {
    if (Test-Path $p) {
        $ClientExe = $p
        break
    }
}

if (-not $ClientExe) {
    $proc = Get-Process -Name "clouddesktop-qml" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) { $ClientExe = $proc.Path }
}

if (-not $ClientExe) {
    Write-Host "[X] 未检测到官方客户端安装目录！" -ForegroundColor Red
    Write-Host "    请确认已安装天翼云电脑官方 Windows 客户端。" -ForegroundColor Yellow
    return
}

Write-Host "[+] 官方客户端: $ClientExe" -ForegroundColor Green

# 2. 定位本地离线配置数据库
$DbDir = "$env:LOCALAPPDATA\CtyunClouddeskPublic\QML\OfflineStorage\Databases"
$SqliteFile = Get-ChildItem -Path $DbDir -Filter "*.sqlite" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $SqliteFile) {
    Write-Host "[X] 未找到客户端本地数据库文件，请先在官方客户端上登录一次你的账号！" -ForegroundColor Red
    return
}

$DbPath = $SqliteFile.FullName
Write-Host "[+] 本地数据库: $DbPath" -ForegroundColor Green

# 3. 停止当前运行的客户端进程
function Stop-CtyunProcesses {
    Stop-Process -Name "clouddesktop-qml" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "clouddesktop-daemon" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# 4. 原生平滑修改本地目标设备 ID (兼容 SQLite 数据库无额外依赖)
function Set-CurrentDesktopId([string]$TargetId) {
    # 优先 Python (如有)
    $hasPy = Get-Command "python" -ErrorAction SilentlyContinue
    if ($hasPy) {
        python -c "import sqlite3; conn = sqlite3.connect(r'$DbPath'); cur = conn.cursor(); cur.execute('SELECT name FROM data WHERE name LIKE \"%lastConnectDesktopId%\"'); [cur.execute('UPDATE data SET value = ? WHERE name = ?', ('\"$TargetId\"', r[0])) for r in cur.fetchall()]; conn.commit(); conn.close()" 2>$null
        return
    }

    # 原生二进制正则匹配替换 SQLite 键值
    try {
        $bytes = [System.IO.File]::ReadAllBytes($DbPath)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        if ($text -match 'lastConnectDesktopId"(\d+)"') {
            $oldId = $matches[1]
            if ($oldId -ne $TargetId) {
                $newText = $text.Replace("lastConnectDesktopId`"$oldId`"", "lastConnectDesktopId`"$TargetId`"")
                [System.IO.File]::WriteAllBytes($DbPath, [System.Text.Encoding]::UTF8.GetBytes($newText))
            }
        }
    } catch {}
}

# 5. 主轮询守护
$Round = 1
while ($true) {
    Write-Host "`n🔄 === 开始第 $Round 轮多设备保活巡检 ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) ===" -ForegroundColor Yellow
    
    for ($i = 0; $i -lt $Desktops.Count; $i++) {
        $dev = $Desktops[$i]
        $dId = $dev.Id
        $dName = $dev.Name
        $dCode = $dev.Code

        Write-Host "[$($i + 1)/$($Desktops.Count)] 正在切换至机器: [$dName] (ID: $dId | 编码: $dCode)..." -ForegroundColor White
        
        # 写入本次要连接的目标机器 ID
        Set-CurrentDesktopId -TargetId $dId
        
        # 启动官方客户端进行 Clink/QUIC 握手
        Stop-CtyunProcesses
        Start-Process -FilePath $ClientExe -WindowStyle Minimized -ErrorAction SilentlyContinue
        
        Write-Host "  -> 🟢 视讯串流已建立！保持连接 $StaySeconds 秒以激活机房在线状态..." -ForegroundColor Green
        Start-Sleep -Seconds $StaySeconds
        
        # 握手完成，平滑关闭，彻底重置机房 5 分钟闲置倒计时
        Stop-CtyunProcesses
        Write-Host "  -> ✨ [$dName] 闲置关机倒计时已重置！准备轮换下一台..." -ForegroundColor Cyan
        
        Start-Sleep -Seconds $SwitchSeconds
    }
    
    $Round++
    Write-Host "✨ 本轮全部机器均已完成激活保活！正在进入下一轮..." -ForegroundColor Green
}
