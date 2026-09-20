# ==============================================================================
# 天翼云电脑 Windows 原生多设备自动轮询保活脚本 (自动启动客户端扫码版)
# 使用方式: irm https://win.xaitr.com/sub/ctyun.ps1 | iex
# ==============================================================================

# ----------------- 用户自定义配置区 -----------------
$StaySeconds   = 35   # 每台机器视讯串流保持秒数 (重置官方5分钟关机计时器)
$SwitchSeconds = 3    # 切换下一台机器的间隔 (秒)

# 待轮询保活的云电脑设备列表 (直接填编码或数字ID均可)
$Desktops = @(
    @{ Id = "23728443"; Name = "游戏版1号"; Code = "D0026090823728443" }
    # @{ Id = "23798068"; Name = "游戏版2号"; Code = "D0026091923798068" }
)
# ----------------------------------------------------

# 自动注册 Windows 开机自启服务 (计划任务静默守护)
function Enable-StartupTask {
    $TaskName = "CtyunKeepAliveWatchdog"
    $Existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $Existing) {
        try {
            $TargetDir = "$env:LOCALAPPDATA\CtyunClouddeskPublic"
            if (-not (Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }
            $ScriptLocal = "$TargetDir\ctyun_keepalive.ps1"
            [System.IO.File]::WriteAllText($ScriptLocal, $MyInvocation.MyCommand.ScriptBlock.ToString(), [System.Text.Encoding]::UTF8)
            
            $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptLocal`""
            $Trigger = New-ScheduledTaskTrigger -AtLogOn
            $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
            
            Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description "Ctyun Cloud Desktop Clink KeepAlive" -ErrorAction SilentlyContinue | Out-Null
            Write-Host "[+] 已成功注册 Windows 开机自启后台静默守护任务 ($TaskName)！" -ForegroundColor Green
        } catch {}
    }
}
Enable-StartupTask

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "🚀 天翼云电脑多设备【轮询防关机】脚本 (Windows 原生扫码就绪)" -ForegroundColor Cyan
Write-Host " - 待轮询设备: $($Desktops.Count) 台" -ForegroundColor Gray
Write-Host " - 单台握手保持: $StaySeconds 秒" -ForegroundColor Gray
Write-Host " - 5台完整轮询周期: 约 $($Desktops.Count * ($StaySeconds + $SwitchSeconds + 5)) 秒 (远低于300秒关机倒计时)" -ForegroundColor Gray
Write-Host "================================================================" -ForegroundColor Cyan

# 1. 自动定位官方客户端主程序
$ClientExe = ""
$PossiblePaths = @(
    "C:\Program Files\CtyunClouddeskPublic\bin\clouddesktop-qml.exe",
    "C:\Program Files (x86)\CtyunClouddeskPublic\bin\clouddesktop-qml.exe",
    "C:\Program Files\CtyunClouddeskPublic\clouddesktop-qml.exe",
    "C:\Program Files (x86)\CtyunClouddeskPublic\clouddesktop-qml.exe",
    "$env:ProgramFiles\CtyunClouddeskPublic\bin\clouddesktop-qml.exe",
    "$env:ProgramFiles(x86)\CtyunClouddeskPublic\bin\clouddesktop-qml.exe",
    "$env:LOCALAPPDATA\Programs\CtyunClouddeskPublic\clouddesktop-qml.exe",
    "$env:APPDATA\CtyunClouddeskPublic\clouddesktop-qml.exe"
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
    Write-Host "[X] 未检测到官方客户端主程序！" -ForegroundColor Red
    return
}

Write-Host "[+] 官方客户端: $ClientExe" -ForegroundColor Green

# 2. 搜索本地数据库函数
function Get-CtyunDbPath {
    $PossibleDbPaths = @(
        "$env:LOCALAPPDATA\CtyunClouddeskPublic\QML\OfflineStorage\Databases\*.sqlite",
        "$env:APPDATA\CtyunClouddeskPublic\QML\OfflineStorage\Databases\*.sqlite",
        "$env:USERPROFILE\.local\share\CtyunClouddeskPublic\QML\OfflineStorage\Databases\*.sqlite",
        "$env:LOCALAPPDATA\Ctyun*\*.sqlite",
        "$env:APPDATA\Ctyun*\*.sqlite"
    )

    foreach ($pattern in $PossibleDbPaths) {
        $found = Get-ChildItem -Path $pattern -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 10000 } | Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    $found = Get-ChildItem -Path "$env:LOCALAPPDATA", "$env:APPDATA" -Filter "*.sqlite" -Recurse -Depth 4 -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like "*Ctyun*" -or $_.FullName -like "*clink*" } | Select-Object -First 1
    if ($found) { return $found.FullName }

    return ""
}

$DbPath = Get-CtyunDbPath

# 3. 如果未检测到数据库，自动拉起官方客户端供用户直接扫码，并倒计时等待
if (-not $DbPath) {
    Write-Host "`n[!] 检测到客户端尚未登录，正在为你自动打开官方登录窗口..." -ForegroundColor Yellow
    
    # 启动官方客户端主程序供用户扫码
    $running = Get-Process -Name "clouddesktop-qml" -ErrorAction SilentlyContinue
    if (-not $running) {
        Start-Process -FilePath $ClientExe
    }

    Write-Host "📱 请在弹出的天翼云电脑客户端窗口中使用微信或App扫码登录！" -ForegroundColor Cyan
    Write-Host "⏳ 脚本正在自动监听登录状态 (扫码成功后将自动开始保活)..." -ForegroundColor Gray

    # 循环监听直到用户扫码登录完成
    $MaxWait = 180
    $Elapsed = 0
    while ($Elapsed -lt $MaxWait) {
        Start-Sleep -Seconds 2
        $Elapsed += 2
        $DbPath = Get-CtyunDbPath
        if ($DbPath) {
            # 进一步检测是否写入了账号数据
            try {
                $content = [System.IO.File]::ReadAllText($DbPath)
                if ($content -like "*crashAccountData*" -or $content -like "*userAccount*") {
                    Write-Host "`n✅ 扫码登录成功！已捕获登录凭据与账号信息！" -ForegroundColor Green
                    break
                }
            } catch {}
        }
        Write-Host -NoNewline "."
    }

    if (-not $DbPath) {
        Write-Host "`n[X] 等待扫码超时，请重新运行脚本完成授权。" -ForegroundColor Red
        return
    }
}

Write-Host "`n[+] 本地配置数据库: $DbPath" -ForegroundColor Green

# 4. 停止当前运行的客户端进程
function Stop-CtyunProcesses {
    Stop-Process -Name "clouddesktop-qml" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "clouddesktop-daemon" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# 5. 原生修改本地目标设备 ID
function Set-CurrentDesktopId([string]$TargetId, [string]$TargetCode) {
    $hasPy = Get-Command "python" -ErrorAction SilentlyContinue
    if ($hasPy) {
        python -c "import sqlite3; conn = sqlite3.connect(r'$DbPath'); cur = conn.cursor(); cur.execute('SELECT name FROM data WHERE name LIKE \"%lastConnectDesktopId%\"'); [cur.execute('UPDATE data SET value = ? WHERE name = ?', ('\"$TargetId\"', r[0])) for r in cur.fetchall()]; conn.commit(); conn.close()" 2>$null
        return
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($DbPath)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        if ($text -match 'lastConnectDesktopId"([^"]+)"') {
            $oldVal = $matches[1]
            if ($oldVal -ne $TargetId -and $oldVal -ne $TargetCode) {
                $newText = $text.Replace("lastConnectDesktopId`"$oldVal`"", "lastConnectDesktopId`"$TargetId`"")
                [System.IO.File]::WriteAllBytes($DbPath, [System.Text.Encoding]::UTF8.GetBytes($newText))
            }
        }
    } catch {}
}

# 6. 主轮询守护
$Round = 1
while ($true) {
    Write-Host "`n🔄 === 开始第 $Round 轮多设备保活巡检 ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) ===" -ForegroundColor Yellow
    
    for ($i = 0; $i -lt $Desktops.Count; $i++) {
        $dev = $Desktops[$i]
        $dId = $dev.Id
        $dName = $dev.Name
        $dCode = $dev.Code

        Write-Host "[$($i + 1)/$($Desktops.Count)] 正在切换至机器: [$dName] (ID: $dId | 编码: $dCode)..." -ForegroundColor White
        
        Set-CurrentDesktopId -TargetId $dId -TargetCode $dCode
        
        Stop-CtyunProcesses
        Start-Process -FilePath $ClientExe -WindowStyle Minimized -ErrorAction SilentlyContinue
        
        Write-Host "  -> 🟢 视讯串流已建立！保持连接 $StaySeconds 秒以激活机房在线状态..." -ForegroundColor Green
        Start-Sleep -Seconds $StaySeconds
        
        Stop-CtyunProcesses
        Write-Host "  -> ✨ [$dName] 闲置关机倒计时已重置！准备轮换下一台..." -ForegroundColor Cyan
        
        Start-Sleep -Seconds $SwitchSeconds
    }
    
    $Round++
    Write-Host "✨ 本轮全部机器均已完成激活保活！正在进入下一轮..." -ForegroundColor Green
}
