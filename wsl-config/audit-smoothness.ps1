#Requires -Version 7.0
# ==============================================================================
#  整体流畅度审计
#
#  用法: pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\audit-smoothness.ps1
#
#  场景：用户反馈"放大缩小页面不流畅"，要求整体排查。
#
#  审计维度
#  ------------------------------------------
#   1. GPU 资源竞争（谁能持续占用 GPU，就是流畅度的敌人）
#   2. 游戏录制/Game DVR（Windows 上最经典的全局卡顿源）
#   3. 硬件加速 GPU 计划（HAGS）
#   4. 叠加层（overlay）—— 注入进程、影响合成
#   5. 刷新率与可变刷新率（VRR）
#   6. 后台进程与内存压力
#   7. 电源与存储
# ==============================================================================

function Sec($t) { Write-Host ""; Write-Host "########## $t ##########" -ForegroundColor Cyan }
function Note($t) { Write-Host ("    · " + $t) -ForegroundColor DarkGray }

Write-Host "==================== 整体流畅度审计 ====================" -ForegroundColor Cyan

# ---------------------------------------------------------------- 1. GPU 竞争
Sec "1. GPU 资源竞争（谁在持续占用 GPU）"
try {
    $samples = @{}
    for ($i = 0; $i -lt 6; $i++) {
        $c = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop
        foreach ($s in $c.CounterSamples) {
            if ($s.InstanceName -match 'pid_(\d+)') {
                $p = (Get-Process -Id ([int]$Matches[1]) -ErrorAction SilentlyContinue).ProcessName
                if ($p) {
                    if (-not $samples.ContainsKey($p)) { $samples[$p] = New-Object System.Collections.ArrayList }
                    [void]$samples[$p].Add([double]$s.CookedValue)
                }
            }
        }
        Start-Sleep -Milliseconds 700
    }
    Write-Host ("  {0,-26} {1,10}   {2}" -f '进程', 'GPU 平均', '说明')
    Write-Host ("  " + ('-' * 66))
    $samples.GetEnumerator() |
        ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Key
                Avg  = [math]::Round(($_.Value | Measure-Object -Average).Average, 2)
                Max  = [math]::Round(($_.Value | Measure-Object -Maximum).Maximum, 2)
            }
        } | Where-Object { $_.Avg -gt 0.3 } | Sort-Object Avg -Descending | ForEach-Object {
            $hint = switch -Regex ($_.Name) {
                'wallpaper'   { '桌面动态壁纸，持续占用' }
                'dwm'         { '桌面合成器，正常' }
                'Nahimic'     { '音频软件，会注入图形管线，常见卡顿源' }
                'NVIDIA'      { 'NVIDIA 叠加层' }
                'Discord'     { 'Discord 叠加层' }
                'mCloud'      { '移动云盘，含渲染进程' }
                'GamePP'      { '游戏加加，含叠加层' }
                'msedge'      { 'Edge 浏览器' }
                'DeepSeek'    { 'DSH（当前应用）' }
                default       { '' }
            }
            Write-Host ("  {0,-26} {1,9}%   {2}" -f $_.Name, $_.Avg, $hint) -ForegroundColor $(if ($_.Avg -ge 3) { 'Yellow' } else { 'Gray' })
        }
} catch { Write-Host "  GPU 计数器读取失败" }

# ---------------------------------------------------------------- 2. Game DVR
Sec "2. 游戏录制 / Game DVR（Windows 最经典的全局卡顿源）"
$gcd = Get-ItemProperty 'HKCU:\System\GameConfigStore' -ErrorAction SilentlyContinue
$gb = Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\GameBar' -ErrorAction SilentlyContinue
$dvr = $gcd.GameDVR_Enabled
Write-Host ("  GameDVR_Enabled              = " + $(if ($null -eq $dvr) { '(未设置 → 默认开启)' } else { $dvr })) -ForegroundColor $(if ($dvr -eq 0) { 'Green' } else { 'Yellow' })
Write-Host ("  GameDVR_FSEBehaviorMode      = " + $gcd.GameDVR_FSEBehaviorMode)
Write-Host ("  GameDVR_HonorUserFSEBehaviorMode = " + $gcd.GameDVR_HonorUserFSEBehaviorMode)
Write-Host ("  AutoGameModeEnabled          = " + $gb.AutoGameModeEnabled)
Write-Host ("  ShowStartupPanel             = " + $gb.ShowStartupPanel)
Write-Host ""
Write-Host "  捕获服务状态（后台录制）："
$cap = Get-Service -Name '*Capture*','*GameDVR*','*Broadcast*' -ErrorAction SilentlyContinue
if ($cap) {
    $cap | Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize
} else { Write-Host "    未找到捕获相关服务" }
Write-Host "  Xbox Game Bar 是否在运行:"
$gbar = Get-Process -Name 'GameBar','GameBarFTServer','XboxGameBarWidgets' -ErrorAction SilentlyContinue
if ($gbar) { $gbar | ForEach-Object { Write-Host ("    " + $_.ProcessName + "  PID " + $_.Id) -ForegroundColor Yellow } }
else { Write-Host "    未运行 ✓" -ForegroundColor Green }
Note "GameDVR 开启时系统会持续做后台录制，是放大缩小/拖窗卡顿的常见原因"

# ---------------------------------------------------------------- 3. HAGS
Sec "3. 硬件加速 GPU 计划（HAGS）"
$hags = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -ErrorAction SilentlyContinue
$hagsVal = $hags.HwSchMode
Write-Host ("  HwSchMode = " + $(if ($null -eq $hagsVal) { '(未设置 → 由系统决定，通常为开)' } else { $hagsVal + "  " + $(if ($hagsVal -eq 2) { '(已启用)' } elseif ($hagsVal -eq 1) { '(已禁用)' } else { '' }) }))
Note "HAGS 让 GPU 自行管理显存与调度，通常对流畅度有小幅改善"

# ---------------------------------------------------------------- 4. 叠加层
Sec "4. 叠加层（overlay）审计"
$overlays = @(
    @{ N='NVIDIA 叠加层';    P='NVIDIA Overlay|nvcontainer|NVIDIA Share' },
    @{ N='Discord 叠加层';   P='Discord' },
    @{ N='Nahimic（音频）'; P='Nahimic' },
    @{ N='GamePP 游戏加加';  P='GamePP|GPP' },
    @{ N='mCloud 移动云盘';  P='mCloud' },
    @{ N='Xbox Game Bar';    P='GameBar' },
    @{ N='Wallpaper Engine'; P='wallpaper' },
    @{ N='Razer Synapse';    P='Razer' },
    @{ N='MSI Afterburner';  P='Afterburner|RTSS' },
    @{ N='GeForce Experience'; P='NVIDIA GeForce' }
)
foreach ($o in $overlays) {
    $p = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match $o.P }
    if ($p) {
        $mem = [math]::Round(($p | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 0)
        Write-Host ("  [运行中] {0,-22} {1} 个进程  {2} MB" -f $o.N, $p.Count, $mem) -ForegroundColor Yellow
    } else {
        Write-Host ("  [未运行] {0}" -f $o.N) -ForegroundColor DarkGray
    }
}
Note "叠加层会注入到渲染进程并参与合成，数量越多越容易造成卡顿"

# ---------------------------------------------------------------- 5. 刷新率与 VRR
Sec "5. 显示与可变刷新率"
$vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.CurrentRefreshRate }
foreach ($v in $vc) {
    Write-Host ("  {0,-40} {1} Hz   {2}x{3}" -f $v.Name, $v.CurrentRefreshRate, $v.CurrentHorizontalResolution, $v.CurrentVerticalResolution) -ForegroundColor Green
}
Write-Host ""
Write-Host "  G-Sync / VRR 状态无法从 WMI 读取，需在 NVIDIA 应用查看："
Write-Host "    设置 > 显示 > G-SYNC 设置"
Note "180Hz 面板若 VRR 未开，画面撕裂感可能被感知为'不流畅'"

# ---------------------------------------------------------------- 6. 后台进程
Sec "6. 后台进程与内存压力"
$os = Get-CimInstance Win32_OperatingSystem
Write-Host ("  内存: {0} GB 可用 / {1} GB  ({2}% 已用)" -f `
    [math]::Round($os.FreePhysicalMemory/1MB,1), [math]::Round($os.TotalVisibleMemorySize/1MB,1), `
    [math]::Round(100*(1-$os.FreePhysicalMemory/$os.TotalVisibleMemorySize),1)) -ForegroundColor $(if ((1-$os.FreePhysicalMemory/$os.TotalVisibleMemorySize) -gt 0.85) { 'Yellow' } else { 'Green' })
Write-Host ""
Write-Host "  内存占用 TOP 12:"
Get-Process -ErrorAction SilentlyContinue | Group-Object ProcessName | ForEach-Object {
    [PSCustomObject]@{ Name = $_.Name; Count = $_.Count; MB = [math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 0) }
} | Sort-Object MB -Descending | Select-Object -First 12 | ForEach-Object {
    Write-Host ("    {0,-26} {1,3} 进程  {2,7} MB" -f $_.Name, $_.Count, $_.MB) -ForegroundColor $(if ($_.MB -gt 800) { 'Yellow' } else { 'Gray' })
}
Write-Host ""
Write-Host ("  进程总数: " + @(Get-Process -ErrorAction SilentlyContinue).Count)
Write-Host ("  页面文件使用: " + [math]::Round(($os.TotalVirtualMemorySize - $os.FreeVirtualMemory)/1MB,1) + " GB")

# ---------------------------------------------------------------- 7. 存储
Sec "7. 存储与分页文件"
Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | ForEach-Object {
    $pct = [math]::Round(100*$_.SizeRemaining/$_.Size, 1)
    Write-Host ("  {0}: 可用 {1} GB / {2} GB  ({3}%)" -f $_.DriveLetter, [math]::Round($_.SizeRemaining/1GB,1), [math]::Round($_.Size/1GB,1), $pct) -ForegroundColor $(if ($pct -lt 10) { 'Yellow' } else { 'Green' })
}
Write-Host ""
Write-Host "  分页文件:"
Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host ("    {0}  当前 {1} MB  峰值 {2} MB" -f $_.Name, $_.CurrentUsage, $_.PeakUsage) -ForegroundColor $(if ($_.PeakUsage -gt $_.AllocatedBaseSize * 0.8) { 'Yellow' } else { 'Green' })
}

# ---------------------------------------------------------------- 8. Electron/Chromium
Sec "8. DSH（Electron）渲染相关"
$dsh = Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue
if ($dsh) {
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $dsh.Id -contains $_.ProcessId }
    $flags = @('--disable-gpu','--disable-gpu-compositing','--disable-gpu-rasterization','--disable-software-rasterizer','--disable-accelerated-2d-canvas','--disable-features','--use-gl=','--use-angle=')
    foreach ($p in $procs) {
        $cl = $p.CommandLine
        $type = if ($cl -match '--type=([a-z-]+)') { $Matches[1] } else { 'main' }
        $hit = @()
        foreach ($fl in $flags) {
            if ($cl -match [regex]::Escape($fl)) {
                $m = [regex]::Match($cl, [regex]::Escape($fl) + '\S*')
                $hit += $m.Value
            }
        }
        if ($hit.Count -gt 0) {
            Write-Host ("  PID {0} ({1}):" -f $p.ProcessId, $type) -ForegroundColor Yellow
            foreach ($h in $hit) { Write-Host ("      " + $h) -ForegroundColor Red }
        }
    }
    Write-Host "  （未列出即无 GPU 限制参数 ✓）" -ForegroundColor Green
    Write-Host ""
    Write-Host "  DSH 进程类型分布:"
    $procs | ForEach-Object {
        if ($_.CommandLine -match '--type=([a-z-]+)') { $Matches[1] } else { 'main' }
    } | Group-Object | ForEach-Object { Write-Host ("    {0,-16} {1}" -f $_.Name, $_.Count) }
} else { Write-Host "  DSH 未运行" }

# ---------------------------------------------------------------- 9. 音频/其它钩子
Sec "9. 可能注入图形管线的软件"
$hooks = @(
    @{ N='Nahimic 服务';   S='NahimicService|Nahimic' },
    @{ N='AMD 相关服务';   S='AMD Crash Defender|AMD External Events|AmdPpkgSvc' },
    @{ N='Razer 服务';     S='Razer' },
    @{ N='Wallpaper Engine 服务'; S='Wallpaper' }
)
foreach ($h in $hooks) {
    $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $h.S -or $_.DisplayName -match $h.S }
    if ($svc) {
        foreach ($s in $svc) {
            Write-Host ("  {0,-26} {1,-10} {2}" -f $s.Name, $s.Status, $s.StartType) -ForegroundColor $(if ($s.Status -eq 'Running') { 'Yellow' } else { 'Gray' })
        }
    }
}
Note "Nahimic 是已知会在部分机器上造成渲染卡顿的软件（它 hook 图形管线做音效追踪）"

# ---------------------------------------------------------------- 10. 自动维护
Sec "10. 后台自动任务（可能周期性抢占资源）"
$tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.State -eq 'Ready' -and $_.TaskPath -notmatch '^\\Microsoft\\(Windows\\)?(?!.*(Defrag|Update))' -and $_.Settings.Enabled
}
Write-Host ("  已启用的计划任务总数: " + @($tasks).Count)
$recent = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Running' }
if ($recent) {
    Write-Host "  正在运行的任务:"
    $recent | ForEach-Object { Write-Host ("    " + $_.TaskName + "   " + $_.TaskPath) -ForegroundColor Yellow }
} else { Write-Host "  当前无任务在运行 ✓" -ForegroundColor Green }

Write-Host ""
Write-Host "==================== 审计完成 ====================" -ForegroundColor Cyan
Write-Host "  下一步：根据上述结果决定具体优化项。" -ForegroundColor Cyan
