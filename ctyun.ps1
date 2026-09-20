# ==============================================================================
# 天翼云电脑 Windows 原生多设备自动轮询保活脚本 (动态参数与全自动探测版)
# 使用方式: 
#   1. 自动探测账号内所有设备: irm https://win.xaitr.com/sub/ctyun.ps1 | iex
#   2. 指定设备编码/ID:        irm https://win.xaitr.com/sub/ctyun.ps1 | iex -args "D00xxxxxx"
# ==============================================================================

param(
    [string]$DeviceInput = "", # 可传入设备编码如 D0026090823728443 或多个逗号分隔
    [int]$StaySeconds = 35,     # 单台保持秒数
    [int]$SwitchSeconds = 3     # 切换间隔秒数
)

# 自动注册 Windows 开机自启服务 (计划任务静默守护)
function Enable-StartupTask {
    $TaskName = "CtyunKeepAliveWatchdog"
    $Existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $Existing) {
        try {
            $TargetDir = "$env:LOCALAPPDATA\CtyunClouddeskPublic"
            if (-not (Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }
            $ScriptLocal = "$TargetDir\ctyun_keepalive.ps1"
            
            # 保存通用脚本本体
            $WebClient = New-Object System.Net.WebClient
            $WebClient.Encoding = [System.Text.Encoding]::UTF8
            $ScriptContent = $WebClient.DownloadString("https://win.xaitr.com/sub/ctyun.ps1")
            [System.IO.File]::WriteAllText($ScriptLocal, $ScriptContent, [System.Text.Encoding]::UTF8)
            
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
Write-Host "🚀 天翼云电脑多设备【轮询防关机】脚本 (Windows 原生)" -ForegroundColor Cyan
Write-Host " - 单台握手保持: $StaySeconds 秒" -ForegroundColor Gray
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
    Write-Host "[X] 未检测到官方客户端主程序，请先安装官方天翼云电脑客户端！" -ForegroundColor Red
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

# 3. 未登录自动拉起客户端扫码
if (-not $DbPath) {
    Write-Host "`n[!] 检测到客户端尚未登录，正在为你自动打开官方登录窗口..." -ForegroundColor Yellow
    $running = Get-Process -Name "clouddesktop-qml" -ErrorAction SilentlyContinue
    if (-not $running) { Start-Process -FilePath $ClientExe }

    Write-Host "📱 请在弹出的客户端窗口中使用微信或App扫码登录！" -ForegroundColor Cyan
    Write-Host "⏳ 脚本正在自动监听登录状态 (扫码成功后将自动开始)..." -ForegroundColor Gray

    $MaxWait = 180
    $Elapsed = 0
    while ($Elapsed -lt $MaxWait) {
        Start-Sleep -Seconds 2
        $Elapsed += 2
        $DbPath = Get-CtyunDbPath
        if ($DbPath) {
            try {
                $content = [System.IO.File]::ReadAllText($DbPath)
                if ($content -like "*crashAccountData*" -or $content -like "*userAccount*") {
                    Write-Host "`n✅ 扫码登录成功！已捕获登录凭据！" -ForegroundColor Green
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

# 4. 动态解析/自动探测待保活的云电脑列表
$Desktops = @()

# 解析辅助函数: 从编码 D00... 提取数字ID
function Parse-DeviceInfo([string]$raw) {
    $s = $raw.Trim()
    if ($s.Length -ge 14 -and $s -match '(\d{7,10})$') {
        return @{ Id = $matches[1]; Code = $s; Name = "云电脑 ($($matches[1]))" }
    }
    return @{ Id = $s; Code = $s; Name = "云电脑 ($s)" }
}

# 逻辑 A: 若运行命令传入了参数 (例如 -args "D00xxxxxx,D00yyyyyy")
if ($DeviceInput) {
    $parts = $DeviceInput -split ','
    foreach ($p in $parts) {
        if ($p.Trim()) {
            $Desktops += (Parse-DeviceInfo $p.Trim())
        }
    }
}

# 逻辑 B: 若未传参数，自动从当前登录的账号数据库中探测发现名下所有设备
if ($Desktops.Count -eq 0) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($DbPath)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        
        # 正则扫描 objId (数字ID) 与 D00 (编码)
        $matchesId = [regex]::Matches($text, '"objId":"(\d+)"')
        foreach ($m in $matchesId) {
            $did = $m.Groups[1].Value
            if (-not ($Desktops | Where-Object { $_.Id -eq $did })) {
                $Desktops += (Parse-DeviceInfo $did)
            }
        }

        # 扫描 lastConnectDesktopId 兜底
        if ($text -match 'lastConnectDesktopId"([^"]+)"') {
            $lastId = $matches[1]
            if (-not ($Desktops | Where-Object { $_.Id -eq $lastId -or $_.Code -eq $lastId })) {
                $Desktops += (Parse-DeviceInfo $lastId)
            }
        }
    } catch {}
}

if ($Desktops.Count -eq 0) {
    Write-Host "[!] 暂未探测到云电脑设备，请直接带参数传入，例如:" -ForegroundColor Yellow
    Write-Host "    irm https://win.xaitr.com/sub/ctyun.ps1 | iex -args `"你的设备编码D00xxxx`"" -ForegroundColor Cyan
    return
}

Write-Host "🔍 成功载入 $($Desktops.Count) 台待保活云电脑:" -ForegroundColor Cyan
foreach ($d in $Desktops) {
    Write-Host " -> 设备: $($d.Code) (ID: $($d.Id))" -ForegroundColor White
}

# 5. 停止客户端进程
function Stop-CtyunProcesses {
    Stop-Process -Name "clouddesktop-qml" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "clouddesktop-daemon" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# 6. 原生修改本地目标设备 ID
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

# 7. 主轮询守护
$Round = 1
while ($true) {
    Write-Host "`n🔄 === 开始第 $Round 轮多设备保活巡检 ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) ===" -ForegroundColor Yellow
    
    for ($i = 0; $i -lt $Desktops.Count; $i++) {
        $dev = $Desktops[$i]
        $dId = $dev.Id
        $dName = $dev.Name
        $dCode = $dev.Code

        Write-Host "[$($i + 1)/$($Desktops.Count)] 正在切换至机器: [$dCode] (ID: $dId)..." -ForegroundColor White
        
        Set-CurrentDesktopId -TargetId $dId -TargetCode $dCode
        
        Stop-CtyunProcesses
        Start-Process -FilePath $ClientExe -WindowStyle Minimized -ErrorAction SilentlyContinue
        
        Write-Host "  -> 🟢 视讯串流通道连接中，保持 $StaySeconds 秒以激活机房在线状态..." -ForegroundColor Green
        Start-Sleep -Seconds $StaySeconds
        
        Stop-CtyunProcesses
        Write-Host "  -> ✨ [$dCode] 闲置倒计时已重置！准备轮换下一台..." -ForegroundColor Cyan
        
        Start-Sleep -Seconds $SwitchSeconds
    }
    
    $Round++
    Write-Host "✨ 本轮全部机器均已完成激活保活！正在进入下一轮..." -ForegroundColor Green
}
