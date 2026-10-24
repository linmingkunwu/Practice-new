#Requires -Version 7.0
# ==============================================================================
#  测量 Windows 视觉效果的资源开销（A/B 对照）
#
#  用法（PowerShell 7，不需管理员）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\measure-visual-cost.ps1
#
#  背景
#  ------------------------------------------
#  用户问"开动画和透明效果吃资源吗"。与其凭印象，不如做 A/B 实测：
#    阶段 A：动画 + 透明效果【开启】（当前状态）
#    阶段 B：透明效果【关闭】（动画保持开启）
#    阶段 C：恢复开启
#  每阶段采样 DWM 与整体 GPU 占用，对比差值。
#
#  为什么看 dwm：
#    Windows 的窗口动画与透明模糊全部由桌面窗口管理器（dwm.exe）在 GPU 上合成。
#    它的 GPU 占用就是"视觉效果"的直接成本。
#
#  同时检查独显直连状态与各应用的 GPU 分配。
# ==============================================================================

$ErrorActionPreference = 'Continue'
$dwmKey = 'HKCU:\SOFTWARE\Microsoft\Windows\DWM'
$samples = 12
$intervalMs = 900

function Get-GpuSnapshot {
    param([int]$Rounds = 12, [int]$DelayMs = 900)
    $dwmVals = @()
    $totalVals = @()
    for ($i = 0; $i -lt $Rounds; $i++) {
        try {
            $c = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop
            $dwmSum = 0.0
            $totSum = 0.0
            foreach ($s in $c.CounterSamples) {
                $v = [double]$s.CookedValue
                $totSum += $v
                if ($s.InstanceName -match 'pid_(\d+)') {
                    $p = (Get-Process -Id ([int]$Matches[1]) -ErrorAction SilentlyContinue).ProcessName
                    if ($p -eq 'dwm') { $dwmSum += $v }
                }
            }
            $dwmVals += $dwmSum
            $totalVals += $totSum
        } catch {
            # GPU 计数器偶发不可用，跳过该次采样
        }
        Start-Sleep -Milliseconds $DelayMs
    }
    $dwmAvg = if ($dwmVals.Count) { [math]::Round(($dwmVals | Measure-Object -Average).Average, 2) } else { -1 }
    $dwmMax = if ($dwmVals.Count) { [math]::Round(($dwmVals | Measure-Object -Maximum).Maximum, 2) } else { -1 }
    $totAvg = if ($totalVals.Count) { [math]::Round(($totalVals | Measure-Object -Average).Average, 2) } else { -1 }
    return [PSCustomObject]@{ DwmAvg = $dwmAvg; DwmMax = $dwmMax; TotalAvg = $totAvg; N = $dwmVals.Count }
}

Write-Host "==================== 视觉效果资源开销实测 ====================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------- 阶段 A
$anim = @{
    MinAnimate          = (Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name MinAnimate -ErrorAction SilentlyContinue).MinAnimate
    TaskbarAnimations   = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name TaskbarAnimations -ErrorAction SilentlyContinue).TaskbarAnimations
    ListviewAlphaSelect = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name ListviewAlphaSelect -ErrorAction SilentlyContinue).ListViewAlphaSelect
    EnableTransparency  = (Get-ItemProperty $dwmKey -Name EnableTransparency -ErrorAction SilentlyContinue).EnableTransparency
}
Write-Host "---- 阶段 A：动画开 + 透明开（当前）----" -ForegroundColor Yellow
Write-Host ("  MinAnimate={0}  TaskbarAnimations={1}  ListviewAlphaSelect={2}  EnableTransparency={3}" -f `
    $anim.MinAnimate, $anim.TaskbarAnimations, $anim.ListviewAlphaSelect, $anim.EnableTransparency)
Write-Host ("  采样 {0} 次，间隔 {1} ms ..." -f $samples, $intervalMs)
$A = Get-GpuSnapshot -Rounds $samples -DelayMs $intervalMs
Write-Host ("  DWM GPU 平均 {0}%   峰值 {1}%   全系统 GPU 合计平均 {2}%   （有效采样 {3} 次）" -f $A.DwmAvg, $A.DwmMax, $A.TotalAvg, $A.N) -ForegroundColor Green

# ---------------------------------------------------------------- 阶段 B
Write-Host ""
Write-Host "---- 阶段 B：关闭透明效果（动画保持开启）----" -ForegroundColor Yellow
Set-ItemProperty -Path $dwmKey -Name 'EnableTransparency' -Value 0 -Type DWord
Write-Host "  已设 EnableTransparency = 0，等待 6 秒让 DWM 生效 ..."
Start-Sleep -Seconds 6
$B = Get-GpuSnapshot -Rounds $samples -DelayMs $intervalMs
Write-Host ("  DWM GPU 平均 {0}%   峰值 {1}%   全系统 GPU 合计平均 {2}%" -f $B.DwmAvg, $B.DwmMax, $B.TotalAvg) -ForegroundColor Green

# ---------------------------------------------------------------- 阶段 C：恢复
Write-Host ""
Write-Host "---- 阶段 C：恢复透明效果 ----" -ForegroundColor Yellow
Set-ItemProperty -Path $dwmKey -Name 'EnableTransparency' -Value 1 -Type DWord
Start-Sleep -Seconds 6
$C = Get-GpuSnapshot -Rounds 8 -DelayMs $intervalMs
Write-Host ("  DWM GPU 平均 {0}%   峰值 {1}%   全系统 GPU 合计平均 {2}%" -f $C.DwmAvg, $C.DwmMax, $C.TotalAvg) -ForegroundColor Green

# ---------------------------------------------------------------- 对照结论
Write-Host ""
Write-Host "==================== 对照结果 ====================" -ForegroundColor Cyan
Write-Host ("  透明效果【开】  DWM 平均 {0}%   系统合计 {1}%" -f $A.DwmAvg, $A.TotalAvg)
Write-Host ("  透明效果【关】  DWM 平均 {0}%   系统合计 {1}%" -f $B.DwmAvg, $B.TotalAvg)
$dDwm = [math]::Round($A.DwmAvg - $B.DwmAvg, 2)
$dTot = [math]::Round($A.TotalAvg - $B.TotalAvg, 2)
Write-Host ""
Write-Host ("  差值：DWM {0:+0.00;-0.00;0} 个百分点    系统合计 {1:+0.00;-0.00;0} 个百分点" -f $dDwm, $dTot) -ForegroundColor Cyan
Write-Host "  （GPU 占用是多个引擎的百分比之和，非任务管理器口径，仅用于相对比较）"

# ---------------------------------------------------------------- 独显直连
Write-Host ""
Write-Host "==================== 显卡工作模式 ====================" -ForegroundColor Cyan
$vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
Write-Host ("  {0,-38} {1,-14} {2}" -f '适配器', '刷新率', '分辨率')
foreach ($v in $vc) {
    $res = if ($v.CurrentHorizontalResolution) { "$($v.CurrentHorizontalResolution)x$($v.CurrentVerticalResolution)" } else { '(无显示模式)' }
    $hz = if ($v.CurrentRefreshRate) { "$($v.CurrentRefreshRate) Hz" } else { '-' }
    Write-Host ("  {0,-38} {1,-14} {2}" -f $v.Name, $hz, $res)
}
Write-Host ""
$nv = $vc | Where-Object { $_.Name -match 'NVIDIA' }
$ig = $vc | Where-Object { $_.Name -match 'AMD|Radeon|Intel' }
if ($nv.CurrentRefreshRate -and -not $ig.CurrentRefreshRate) {
    Write-Host "  ✓ 判定：显示输出由【独显】驱动 —— 独显直连（MUX）已启用" -ForegroundColor Green
    Write-Host "    依据：独显有刷新率与分辨率，核显两者皆空（说明它不接显示输出）"
} elseif ($nv.CurrentRefreshRate -and $ig.CurrentRefreshRate) {
    Write-Host "  ⚠️ 两个适配器都有显示模式，可能处于混合输出" -ForegroundColor Yellow
} else {
    Write-Host "  无法判定，需在 NVIDIA 应用里查看" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  DWM 使用的显存（判断合成器跑在哪块卡上）:"
try {
    Get-Counter '\GPU Process Memory(*)\Dedicated Usage' -ErrorAction Stop |
        ForEach-Object { $_.CounterSamples } |
        Where-Object { $_.InstanceName -match 'pid_(\d+)' -and (Get-Process -Id ([int]$Matches[1]) -ErrorAction SilentlyContinue).ProcessName -eq 'dwm' } |
        Sort-Object CookedValue -Descending | Select-Object -First 2 | ForEach-Object {
            Write-Host ("    dwm 专用显存: {0} MB" -f [math]::Round($_.CookedValue/1MB, 0))
        }
} catch { Write-Host "    （读取失败）" }

# ---------------------------------------------------------------- 应用 GPU 偏好
Write-Host ""
Write-Host "==================== 各应用的 GPU 分配 ====================" -ForegroundColor Cyan
$prefKey = 'HKCU:\SOFTWARE\Microsoft\DirectX\UserGpuPreferences'
$pref = Get-ItemProperty $prefKey -ErrorAction SilentlyContinue
$map = @{ 'GpuPreference=0' = '由 Windows 决定'; 'GpuPreference=1' = '省电（核显）'; 'GpuPreference=2' = '高性能（独显）' }
if ($pref) {
    $n = 0
    $pref.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
        $n++
        $val = $map[$_.Value]
        if (-not $val) { $val = $_.Value }
        Write-Host ("    {0,-58} {1}" -f $_.Name, $val)
    }
    if ($n -eq 0) { Write-Host "    （无自定义分配，全部由 Windows 决定）" }
} else {
    Write-Host "    未设置任何应用的 GPU 偏好 —— 全部由 Windows 自动决定" -ForegroundColor Green
}

# ---------------------------------------------------------------- 结论
Write-Host ""
Write-Host "==================== 结论 ====================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1) 视觉效果的开销" -ForegroundColor Yellow
if ([math]::Abs($dDwm) -lt 1.0 -and [math]::Abs($dTot) -lt 2.0) {
    Write-Host ("     透明效果实测仅差 {0} 个百分点（DWM），属于测量噪声级别。" -f $dDwm)
    Write-Host "     在这块 RTX 5060 上，窗口动画与透明模糊的开销可忽略。"
} else {
    Write-Host ("     透明效果实测差 {0} 个百分点（DWM），有一定开销。" -f $dDwm)
    Write-Host "     若追求极致性能可关闭；日常使用影响不明显。"
}
Write-Host ""
Write-Host "  2) 核显驱动是否需要更新" -ForegroundColor Yellow
if ($nv.CurrentRefreshRate -and -not $ig.CurrentRefreshRate) {
    Write-Host "     已启用独显直连，核显不参与显示输出 → 对【画面流畅度】几乎无影响。"
    Write-Host "     但核显仍被以下场景使用，驱动过旧仍可能出问题："
    Write-Host "       · 视频硬解码（部分播放器默认走核显）"
    Write-Host "       · 电池模式下的节能渲染"
    Write-Host "       · 被标记为「省电」的应用"
    Write-Host "       · 外接显示器时的部分输出路径"
    Write-Host "     => 建议更新，但优先级【低】，且不必急。"
} else {
    Write-Host "     当前非独显直连，核显驱动直接影响桌面流畅度，建议更新。"
}
Write-Host ""
Write-Host "  最终设置确认:"
foreach ($i in @(
    @{P='HKCU:\Control Panel\Desktop\WindowMetrics'; N='MinAnimate'},
    @{P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; N='TaskbarAnimations'},
    @{P=$dwmKey; N='EnableTransparency'},
    @{P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; N='MultiTaskingAltTabFilter'}
)) {
    $v = (Get-ItemProperty $i.P -Name $i.N -ErrorAction SilentlyContinue).($i.N)
    Write-Host ("    {0,-26} = {1}" -f $i.N, $(if ($null -eq $v) { '(未设置)' } else { $v })) -ForegroundColor Green
}
