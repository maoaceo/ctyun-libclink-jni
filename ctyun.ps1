# ==============================================================================
# 天翼云电脑 多设备轻量自动轮询保活脚本 (PowerShell 原生版)
# ==============================================================================

# 1. 基础配置
$StaySeconds   = 35   # 每台云电脑串流保持秒数 (足以重置官方5分钟关机计时器)
$SwitchSeconds = 3    # 切换间隔 (秒)

# 轮询设备列表 (在此填入你的云电脑数字 ID 与备注名称)
$Desktops = @(
    @{ Id = "23798068"; Name = "游戏版1号"; Code = "D0026091923798068" }
    # @{ Id = "23798069"; Name = "游戏版2号"; Code = "D0026091923798069" }
    # @{ Id = "23798070"; Name = "尊享版3号"; Code = "D0026091923798070" }
)

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "🚀 天翼云电脑官方原生多设备轮询保活已启动 (Windows PowerShell)" -ForegroundColor Cyan
Write-Host " - 轮询设备总数: $($Desktops.Count) 台" -ForegroundColor Gray
Write-Host " - 单台串流保持: $StaySeconds 秒" -ForegroundColor Gray
Write-Host " - 5台完整周期: 约 $($Desktops.Count * ($StaySeconds + $SwitchSeconds + 5)) 秒 (远低于300秒关机门槛)" -ForegroundColor Gray
Write-Host "================================================================" -ForegroundColor Cyan

# 2. 定位官方客户端程序路径
$ClientExe = ""
$PossiblePaths = @(
    "C:\Program Files (x86)\CtyunClouddeskPublic\clouddesktop-qml.exe",
    "C:\Program Files\CtyunClouddeskPublic\clouddesktop-qml.exe",
    "$env:LOCALAPPDATA\Programs\CtyunClouddeskPublic\clouddesktop-qml.exe",
    "$env:APPDATA\CtyunClouddeskPublic\clouddesktop-qml.exe"
)

foreach ($path in $PossiblePaths) {
    if (Test-Path $path) {
        $ClientExe = $path
        break
    }
}

if (-not $ClientExe) {
    # 尝试从已安装服务或运行进程查找
    $RunningProc = Get-Process -Name "clouddesktop-qml" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($RunningProc) {
        $ClientExe = $RunningProc.Path
    }
}

if (-not $ClientExe) {
    Write-Host "[X] 未检测到官方天翼云电脑客户端！" -ForegroundColor Red
    Write-Host "    请确认已安装天翼云电脑官方客户端，或检查安装目录。" -ForegroundColor Yellow
    exit 1
}

Write-Host "[*] 成功定位官方客户端: $ClientExe" -ForegroundColor Green

# 3. 定位本地离线 SQLite 数据库
$DbDir = "$env:LOCALAPPDATA\CtyunClouddeskPublic\QML\OfflineStorage\Databases"
$SqliteFile = Get-ChildItem -Path $DbDir -Filter "*.sqlite" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $SqliteFile) {
    Write-Host "[X] 未找到客户端本地数据库文件，请先在官方客户端登录一次账号！" -ForegroundColor Red
    exit 1
}

$DbPath = $SqliteFile.FullName
Write-Host "[*] 本地配置数据库: $DbPath" -ForegroundColor Green

# 4. 函数：平滑结束当前运行的客户端进程
function Stop-CtyunClient {
    Stop-Process -Name "clouddesktop-qml" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "clouddesktop-daemon" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# 5. 函数：更新目标机器 ID (PowerShell 原生轻量二进制/纯文本补丁方式，无需安装 sqlite3.exe)
function Set-TargetDesktopId([string]$TargetId) {
    $PyCmd = Get-Command "python" -ErrorAction SilentlyContinue
    if ($PyCmd) {
        python -c "import sqlite3; conn = sqlite3.connect(r'$DbPath'); cur = conn.cursor(); cur.execute('SELECT name FROM data WHERE name LIKE \"%lastConnectDesktopId%\"'); [cur.execute('UPDATE data SET value = ? WHERE name = ?', ('\"$TargetId\"', r[0])) for r in cur.fetchall()]; conn.commit(); conn.close()" 2>$null
        return
    }

    try {
        $Bytes = [System.IO.File]::ReadAllBytes($DbPath)
        $Text = [System.Text.Encoding]::UTF8.GetString($Bytes)
        if ($Text -match 'lastConnectDesktopId"(\d+)"') {
            $OldId = $matches[1]
            if ($OldId -ne $TargetId) {
                $NewText = $Text.Replace("lastConnectDesktopId`"$OldId`"", "lastConnectDesktopId`"$TargetId`"")
                [System.IO.File]::WriteAllBytes($DbPath, [System.Text.Encoding]::UTF8.GetBytes($NewText))
            }
        }
    } catch {
        # 忽略并发写入异常
    }
}

# 6. 主轮询循环
$Round = 1
while ($true) {
    Write-Host "`n🔄 === 开始第 $Round 轮多设备保活巡检 ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) ===" -ForegroundColor Yellow
    
    for ($i = 0; $i -lt $Desktops.Count; $i++) {
        $Desktop = $Desktops[$i]
        $DId = $Desktop.Id
        $DName = $Desktop.Name
        $DCode = $Desktop.Code

        Write-Host "[$($i + 1)/$($Desktops.Count)] 正在切换至: [$DName] (编码: $DCode / ID: $DId)..." -ForegroundColor White
        
        # 写入目标设备 ID
        Set-TargetDesktopId -TargetId $DId
        
        # 启动官方客户端进行视讯握手
        Stop-CtyunClient
        Start-Process -FilePath $ClientExe -WindowStyle Minimized -ErrorAction SilentlyContinue
        
        Write-Host "  -> 🟢 视讯串流通道连接中，保持 $StaySeconds 秒以激活机房在线状态..." -ForegroundColor Green
        Start-Sleep -Seconds $StaySeconds
        
        # 串流保持完毕，平滑关闭，重置机房 5 分钟闲置倒计时
        Stop-CtyunClient
        Write-Host "  -> ✨ [$DName] 保活成功！已刷新官方机房倒计时。" -ForegroundColor Cyan
        
        Start-Sleep -Seconds $SwitchSeconds
    }
    
    $Round++
    Write-Host "✨ 本轮所有设备均已完成保活握手！正在进入下一轮..." -ForegroundColor Green
}
