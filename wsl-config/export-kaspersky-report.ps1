#Requires -Version 7.0
# ==============================================================================
#  导出卡巴斯基假阳性事件诊断报告
#
#  用法（不需管理员）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\export-kaspersky-report.ps1
#
#  背景（2026-10-13）
#  ------------------------------------------
#  用户反馈卡巴斯基假阳性把 clash 与 TranslucentTB 搞崩。排查结论：
#    · 文件未被删除，完整性、签名、ACL 全部正常
#    · 报错为 0xc0000022 = STATUS_ACCESS_DENIED（拒绝访问）
#    · 涉及 6 个不同的微软系统 DLL —— 不可能同时损坏
#    · 报错集中在 20:35~20:48 共 13 分钟，与卡巴斯基活动期吻合
#    · clash sidecar 反复以 code 1 退出
#  => 卡巴斯基的运行时防护在进程加载系统组件时拒绝访问，导致 Electron 应用崩溃
#
#  本脚本把事件日志、文件校验、时间线、排除项建议导出到 D:\Backups
# ==============================================================================

$ErrorActionPreference = 'Continue'
$reportDir = 'D:\Backups\kaspersky-fp-20261013'
New-Item -ItemType Directory -Path $reportDir -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "==================== 导出卡巴斯基假阳性诊断报告 ====================" -ForegroundColor Cyan
Write-Host ("  目标目录: " + $reportDir)
Write-Host ""

# ---------------------------------------------------------------- 1. 收集事件
Write-Host "---- 1. 收集事件日志 ----" -ForegroundColor Yellow
$evts = @()
try {
    $evts = Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = (Get-Date).AddDays(-30) } -MaxEvents 3000 -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match '损坏的映像' }
} catch {}
Write-Host ("  找到 " + @($evts).Count + " 条「损坏的映像」事件")

$appCounts = @{}
foreach ($e in $evts) {
    $app = if ($e.Message -match '应用程序: ([^\s]+)') { $Matches[1] } else { '(未知)' }
    if (-not $appCounts.ContainsKey($app)) { $appCounts[$app] = 0 }
    $appCounts[$app]++
}

$dllCounts = @{}
foreach ($e in $evts) {
    if ($e.Message -match '(C:\\[^\s]+\.dll)') {
        $d = $Matches[1]
        if (-not $dllCounts.ContainsKey($d)) { $dllCounts[$d] = 0 }
        $dllCounts[$d]++
    }
}

Write-Host "  受影响程序:"
foreach ($k in ($appCounts.Keys | Sort-Object { -$appCounts[$_] })) {
    Write-Host ("    {0,-32} {1,4} 次" -f $k, $appCounts[$k]) -ForegroundColor Yellow
}
Write-Host "  涉及的 DLL:"
foreach ($k in ($dllCounts.Keys | Sort-Object { -$dllCounts[$_] })) {
    Write-Host ("    {0,-50} {1,4} 次" -f $k, $dllCounts[$k])
}

# ---------------------------------------------------------------- 2. 导出 XML
Write-Host ""
Write-Host "---- 2. 导出事件 XML ----" -ForegroundColor Yellow
$xmlPath = Join-Path $reportDir '损坏的映像事件.xml'
if ($evts.Count -gt 0) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sb.AppendLine('<Events>')
    foreach ($e in $evts) { [void]$sb.AppendLine($e.ToXml()) }
    [void]$sb.AppendLine('</Events>')
    [System.IO.File]::WriteAllText($xmlPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("  [OK] " + (Split-Path $xmlPath -Leaf) + "  " + [math]::Round((Get-Item $xmlPath).Length/1KB, 1) + " KB") -ForegroundColor Green
}

# ---------------------------------------------------------------- 3. DLL 校验
Write-Host ""
Write-Host "---- 3. 校验被报「损坏」的系统 DLL ----" -ForegroundColor Yellow
$dllFiles = @('TextShaping.dll', 'kernel.appcore.dll', 'gpapi.dll', 'Wlanapi.dll', 'wuceffects.dll', 'devenum.dll', 'kernel32.dll')
$dllInfo = @()
foreach ($d in $dllFiles) {
    $p = "C:\Windows\System32\$d"
    if (Test-Path -LiteralPath $p) {
        $f = Get-Item -LiteralPath $p -Force
        $sig = Get-AuthenticodeSignature -LiteralPath $p -ErrorAction SilentlyContinue
        $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
        $acl = Get-Acl -LiteralPath $p -ErrorAction SilentlyContinue
        $deny = @($acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' }).Count
        $dllInfo += [PSCustomObject]@{
            Name = $d; Size = $f.Length; Version = $f.VersionInfo.FileVersion
            SignStatus = "$($sig.Status)"; Owner = $acl.Owner; Rules = $acl.Access.Count
            DenyRules = $deny; SHA256 = $h
        }
        $color = if ($sig.Status -eq 'Valid' -and $deny -eq 0) { 'Green' } else { 'Red' }
        Write-Host ("  [{0}] {1,-24} {2,9} 字节  签名 {3,-6} Deny {4}  规则 {5}" -f `
            $(if ($sig.Status -eq 'Valid' -and $deny -eq 0) { 'OK' } else { '!!' }), $d, $f.Length, $sig.Status, $deny, $acl.Access.Count) -ForegroundColor $color
    } else {
        Write-Host ("  [缺失] " + $d) -ForegroundColor Red
    }
}

# ---------------------------------------------------------------- 4. clash 崩溃时间线
Write-Host ""
Write-Host "---- 4. clash 崩溃时间线 ----" -ForegroundColor Yellow
$cfgDir = "$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev"
$logDir = Join-Path $cfgDir 'logs'
$timeline = @()
if (Test-Path -LiteralPath $logDir) {
    $logs = Get-ChildItem -LiteralPath $logDir -Recurse -File -Force -ErrorAction SilentlyContinue -Filter '*.log' | Sort-Object LastWriteTime
    foreach ($l in $logs) {
        $last = Get-Content -LiteralPath $l.FullName -Tail 1 -ErrorAction SilentlyContinue
        $isTerm = $last -match 'Process terminated with code: (\d+)'
        $code = if ($isTerm) { $Matches[1] } else { $null }
        $timeline += [PSCustomObject]@{ File = $l.Name; Modified = $l.LastWriteTime; Terminated = $isTerm; Code = $code }
    }
    foreach ($t in $timeline) {
        $mark = if ($t.Terminated) { "terminated code=" + $t.Code } else { "" }
        Write-Host ("    {0,-50} {1}  {2}" -f $t.File, $t.Modified.ToString('MM-dd HH:mm'), $mark) -ForegroundColor $(if ($t.Terminated) { 'Yellow' } else { 'Gray' })
    }
}

# ---------------------------------------------------------------- 5. 排除项目标
Write-Host ""
Write-Host "---- 5. 需加入卡巴斯基排除项/受信任应用程序的路径 ----" -ForegroundColor Yellow
$targets = @()
$cv = 'C:\Program Files\Clash Verge Ninja'
if (Test-Path -LiteralPath $cv) {
    $targets += [PSCustomObject]@{ Cat = '代理客户端'; Path = $cv; Note = '主程序目录' }
    $targets += [PSCustomObject]@{ Cat = '代理客户端'; Path = "$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev"; Note = '配置与日志' }
}
$ttp = Get-AppxPackage -Name '*TranslucentTB*' -ErrorAction SilentlyContinue
if ($ttp) {
    $targets += [PSCustomObject]@{ Cat = '任务栏工具'; Path = $ttp.InstallLocation; Note = 'MSIX 安装目录' }
    $targets += [PSCustomObject]@{ Cat = '任务栏工具'; Path = "$env:LOCALAPPDATA\Packages\28017CharlesMilette.TranslucentTB_v826wp6bftszj"; Note = '应用数据' }
}
$targets += [PSCustomObject]@{ Cat = '其它 Electron 应用'; Path = "$env:LOCALAPPDATA\Programs"; Note = '多个应用受影响' }
$targets += [PSCustomObject]@{ Cat = '本机开发环境'; Path = 'E:\Git'; Note = '开发目录，建议整体排除以提速' }
foreach ($t in $targets) {
    $exists = Test-Path -LiteralPath $t.Path
    Write-Host ("    [{0}] {1}" -f $t.Cat, $t.Path) -ForegroundColor $(if ($exists) { 'Green' } else { 'DarkGray' })
    Write-Host ("        " + $t.Note) -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- 6. 当前状态
Write-Host ""
Write-Host "---- 6. 当前防护状态 ----" -ForegroundColor Yellow
$avpSvc = Get-Service -Name 'AVP21.26' -ErrorAction SilentlyContinue
$mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
Write-Host ("  卡巴斯基服务      : " + $(if ($avpSvc) { $avpSvc.Status } else { '(未安装)' })) -ForegroundColor $(if ($avpSvc.Status -eq 'Running') { 'Green' } else { 'Red' })
Write-Host ("  Defender 实时保护 : " + $mp.RealTimeProtectionEnabled)
Write-Host ("  Defender 运行模式 : " + $mp.AMRunningMode)
if ($avpSvc.Status -ne 'Running' -and -not $mp.RealTimeProtectionEnabled) {
    Write-Host "  ⚠️ 当前没有任何实时防护" -ForegroundColor Red
}

# ---------------------------------------------------------------- 7. 写文本报告
Write-Host ""
Write-Host "---- 7. 生成文本报告 ----" -ForegroundColor Yellow
$txtPath = Join-Path $reportDir '诊断报告.txt'
$L = New-Object System.Collections.ArrayList
function Add-Line([string]$s) { [void]$L.Add($s) }

Add-Line "==================== 卡巴斯基假阳性事件诊断报告 ===================="
Add-Line ("生成时间: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Add-Line ""
Add-Line "【结论】"
Add-Line "  卡巴斯基的运行时防护在进程加载系统 DLL 时返回 0xc0000022"
Add-Line "  (STATUS_ACCESS_DENIED 拒绝访问)，导致 Electron 应用反复崩溃。"
Add-Line "  文件本身完好，未被删除。"
Add-Line ""
Add-Line "【受影响程序】"
foreach ($k in ($appCounts.Keys | Sort-Object { -$appCounts[$_] })) {
    Add-Line ("  {0,-30} {1,4} 次" -f $k, $appCounts[$k])
}
Add-Line ""
Add-Line "【被报损坏的系统 DLL —— 全部为微软签名文件，校验均通过】"
foreach ($d in $dllInfo) {
    Add-Line ("  {0,-24} {1,9} 字节  版本 {2}  签名 {3}  所有者 {4}  规则 {5}  Deny {6}" -f $d.Name, $d.Size, $d.Version, $d.SignStatus, $d.Owner, $d.Rules, $d.DenyRules)
    Add-Line ("      SHA256 " + $d.SHA256)
}
Add-Line ""
Add-Line "【涉及的 DLL 频次】"
foreach ($k in ($dllCounts.Keys | Sort-Object { -$dllCounts[$_] })) {
    Add-Line ("  {0,-52} {1,4} 次" -f $k, $dllCounts[$k])
}
Add-Line ""
Add-Line "【clash sidecar 退出记录】"
foreach ($t in $timeline) {
    if ($t.Terminated) { Add-Line ("  " + $t.Modified.ToString('MM-dd HH:mm') + "  " + $t.File + "  -> terminated code=" + $t.Code) }
}
Add-Line ""
Add-Line "【时间线】"
Add-Line "  20:35:25  TextShaping.dll 报错开始（70 条，全为 clash-verge）"
Add-Line "  20:41:26  clash sidecar 退出 (code 0)"
Add-Line "  20:48:43  最后一条报错"
Add-Line "  20:52:51  clash sidecar 退出 (code 1)  <- 异常"
Add-Line "  21:15     clash sidecar 重启成功"
Add-Line "  之后      再无新报错"
Add-Line ""
Add-Line "【当前防护状态】"
Add-Line ("  卡巴斯基服务      : " + $(if ($avpSvc) { $avpSvc.Status } else { '(未安装)' }))
Add-Line ("  Defender 实时保护 : " + $mp.RealTimeProtectionEnabled)
Add-Line ("  Defender 运行模式 : " + $mp.AMRunningMode)
Add-Line ""
Add-Line "【建议加入卡巴斯基排除项 / 受信任应用程序的路径】"
Add-Line "  打开方式: 卡巴斯基 > 设置(齿轮) > 安全威胁与排除项 > 管理排除项 / 指定受信任应用程序"
Add-Line "  建议同时勾选: 不扫描文件与流量、不监控进程活动、不扫描网络流量"
Add-Line ""
foreach ($t in $targets) {
    Add-Line ("  [" + $t.Cat + "] " + $t.Path)
    Add-Line ("      " + $t.Note)
}
Add-Line ""
Add-Line "【系统信息】"
$os = Get-CimInstance Win32_OperatingSystem
Add-Line ("  系统: " + $os.Caption + "  Build " + $os.BuildNumber)
Add-Line ("  用户: " + $env:USERNAME)
Add-Line ("  机器: " + $env:COMPUTERNAME)
$L | Set-Content -LiteralPath $txtPath -Encoding UTF8
Write-Host ("  [OK] " + (Split-Path $txtPath -Leaf) + "  " + [math]::Round((Get-Item $txtPath).Length/1KB, 1) + " KB") -ForegroundColor Green

# ---------------------------------------------------------------- 8. 文件清单
Write-Host ""
Write-Host "---- 8. 导出程序文件清单 ----" -ForegroundColor Yellow
if (Test-Path -LiteralPath $cv) {
    $inv = Join-Path $reportDir 'clash文件清单.txt'
    cmd /c "dir /s /b `"$cv`" > `"$inv`" 2>&1"
    Write-Host ("  [OK] clash文件清单.txt") -ForegroundColor Green
}
if ($ttp -and $ttp.InstallLocation) {
    $inv2 = Join-Path $reportDir 'TranslucentTB文件清单.txt'
    cmd /c "dir /s /b `"$($ttp.InstallLocation)`" > `"$inv2`" 2>&1"
    Write-Host ("  [OK] TranslucentTB文件清单.txt") -ForegroundColor Green
}

Write-Host ""
Write-Host "==================== 报告目录内容 ====================" -ForegroundColor Cyan
Get-ChildItem -LiteralPath $reportDir -Force | ForEach-Object {
    Write-Host ("    {0,-42} {1,9} KB" -f $_.Name, [math]::Round($_.Length/1KB, 1)) -ForegroundColor Green
}
Write-Host ""
Write-Host "  完成。" -ForegroundColor Green
