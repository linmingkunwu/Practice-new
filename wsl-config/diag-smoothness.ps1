#Requires -Version 7.0
# ==============================================================================
#  诊断 UI 流畅度相关设置
#
#  用法: pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\diag-smoothness.ps1
#
#  排查四类原因：
#    1. 显示器刷新率（游戏本若跑在 60Hz 会明显不流畅）
#    2. Windows 动画开关（被"优化工具"关掉后切换会显得生硬）
#    3. Electron 应用的 GPU 加速（DSH 这类应用关掉 GPU 会卡）
#    4. 显卡驱动与混合显卡工作模式
# ==============================================================================

function Sec($t) { Write-Host ""; Write-Host "########## $t ##########" -ForegroundColor Cyan }

Sec "1. 显示器与刷新率"
$vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
foreach ($v in $vc) {
    Write-Host ("  [" + $v.Name + "]")
    if ($v.CurrentRefreshRate) {
        $mark = if ($v.CurrentRefreshRate -ge 100) { '✓ 高刷已启用' } elseif ($v.CurrentRefreshRate -ge 60) { '普通' } else { '异常' }
        Write-Host ("    刷新率  : {0} Hz  (最大 {1} Hz)   {2}" -f $v.CurrentRefreshRate, $v.MaxRefreshRate, $mark) -ForegroundColor $(if ($v.CurrentRefreshRate -ge 100) { 'Green' } else { 'Yellow' })
    }
    if ($v.CurrentHorizontalResolution) {
        Write-Host ("    分辨率  : {0} x {1}" -f $v.CurrentHorizontalResolution, $v.CurrentVerticalResolution)
    }
    Write-Host ("    驱动    : {0}   ({1})" -f $v.DriverVersion, $v.DriverDate)
}

Write-Host ""
Write-Host "  混合显卡（笔记本常见）:"
$nv = $vc | Where-Object { $_.Name -match 'NVIDIA' }
$amd = $vc | Where-Object { $_.Name -match 'AMD|Radeon' }
Write-Host ("    独显: " + $(if ($nv) { $nv.Name } else { '无' }))
Write-Host ("    核显: " + $(if ($amd) { $amd.Name } else { '无' }))
Write-Host "    → 桌面渲染通常由核显负责；若核显驱动老旧可能影响流畅度"
if ($amd) { Write-Host ("    核显驱动日期: " + $amd.DriverDate + "   （独显是 " + $nv.DriverDate + "）") }

Sec "2. Windows 动画开关（逐个列出）"
$checks = @(
    @{ P='HKCU:\Control Panel\Desktop\WindowMetrics'; N='MinAnimate';            D='窗口最小化/最大化动画'; Good=1 },
    @{ P='HKCU:\Control Panel\Desktop';               N='MinAnimate';            D='（同上，另一处）';       Good=1 },
    @{ P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; N='TaskbarAnimations';   D='任务栏动画';    Good=1 },
    @{ P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; N='ListviewAlphaSelect'; D='列表淡入淡出';  Good=1 },
    @{ P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; N='ListviewShadow';      D='列表阴影';      Good=1 },
    @{ P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; N='IconsOnly';           D='仅显示图标(关缩略图)'; Good=0 },
    @{ P='HKCU:\SOFTWARE\Microsoft\Windows\DWM';      N='EnableTransparency';    D='透明效果';       Good=1 },
    @{ P='HKCU:\SOFTWARE\Microsoft\Windows\DWM';      N='EnableAeroPeek';        D='Aero Peek';      Good=1 },
    @{ P='HKCU:\SOFTWARE\Microsoft\Windows\DWM';      N='AlwaysHibernateThumbnails'; D='缩略图常驻内存'; Good=0 },
    @{ P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; N='VisualFXSetting'; D='0=系统决定 1=最佳外观 2=最佳性能 3=自定义'; Good=1 }
)
Write-Host ("  {0,-32} {1,-10} {2}" -f '设置项', '当前值', '说明')
Write-Host ("  " + ('-' * 78))
foreach ($c in $checks) {
    $v = (Get-ItemProperty $c.P -Name $c.N -ErrorAction SilentlyContinue).($c.N)
    $disp = if ($null -eq $v) { '(未设置)' } else { $v }
    $isGood = if ($null -eq $v) { $null } else { $v -eq $c.Good }
    $color = if ($null -eq $isGood) { 'Gray' } elseif ($isGood) { 'Green' } else { 'Yellow' }
    Write-Host ("  {0,-32} {1,-10} {2}" -f $c.N, $disp, $c.D) -ForegroundColor $color
}

Write-Host ""
Write-Host "  各项动画的独立开关（VisualEffects 子键）:"
$subKeys = @('AnimateControlsInWindows','AnimateMinMax','ComboBoxAnimation','CursorShadow','DropShadow','ListBoxSmoothScrolling','MenuAnimation','MenuFade','SelectionFade','Shadows','TaskbarAnimations','ThemeAnimation','TooltipAnimation','TooltipFade')
$anyFound = $false
foreach ($k in $subKeys) {
    $p = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\$k"
    if (Test-Path $p) {
        $anyFound = $true
        $dv = (Get-ItemProperty $p -ErrorAction SilentlyContinue).DefaultValue
        Write-Host ("    {0,-28} DefaultValue={1}  {2}" -f $k, $dv, $(if ($dv -eq 1) { '启用' } elseif ($dv -eq 0) { '禁用' } else { '' })) -ForegroundColor $(if ($dv -eq 0) { 'Yellow' } else { 'Green' })
    }
}
if (-not $anyFound) { Write-Host "    （全部未单独配置，跟随 VisualFXSetting）" }

Sec "3. 辅助功能中的动画总开关"
$acc = Get-ItemProperty 'HKCU:\Control Panel\Accessibility' -ErrorAction SilentlyContinue
Write-Host ("  Accessibility\Animation = " + $(if ($acc.Animation) { $acc.Animation } else { '(未设置)' }))
Write-Host "    1 = 关闭所有不必要的动画（会覆盖上面的所有动画设置）"
Write-Host ""
Write-Host ("  UserPreferencesMask = " + (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name UserPreferencesMask -ErrorAction SilentlyContinue).UserPreferencesMask)

Sec "4. DSH（Electron）的 GPU 加速状态"
$dsh = Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue
if (-not $dsh) { Write-Host "  DSH 未运行" } else {
    Write-Host ("  进程数: " + $dsh.Count)
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $dsh.Id -contains $_.ProcessId }
    Write-Host ""
    foreach ($p in $procs) {
        $cl = $p.CommandLine
        $type = if ($cl -match '--type=([a-z-]+)') { $Matches[1] } else { 'main' }
        Write-Host ("  PID {0}  类型={1}" -f $p.ProcessId, $type) -ForegroundColor Yellow
        # GPU 相关开关
        $flags = @()
        if ($cl -match '--disable-gpu\b')        { $flags += '--disable-gpu  ← 禁用 GPU！' }
        if ($cl -match '--disable-gpu-compositing') { $flags += '--disable-gpu-compositing  ← 禁用 GPU 合成' }
        if ($cl -match '--disable-software-rasterizer') { $flags += '--disable-software-rasterizer' }
        if ($cl -match '--in-process-gpu')       { $flags += '--in-process-gpu' }
        if ($cl -match '--use-gl=(\S+)')         { $flags += ('--use-gl=' + $Matches[1]) }
        if ($cl -match '--use-angle=(\S+)')      { $flags += ('--use-angle=' + $Matches[1]) }
        if ($cl -match '--enable-gpu')           { $flags += '--enable-gpu' }
        if ($cl -match '--disable-gpu-sandbox')  { $flags += '--disable-gpu-sandbox' }
        if ($flags.Count -gt 0) {
            foreach ($f in $flags) { Write-Host ("      " + $f) -ForegroundColor $(if ($f -match 'disable-gpu\b|disable-gpu-compositing') { 'Red' } else { 'Gray' }) }
        } else {
            Write-Host "      （无 GPU 相关开关）" -ForegroundColor Green
        }
    }
    Write-Host ""
    Write-Host "  显卡使用情况（DSH 进程是否真的在用 GPU）:"
    $gpuCounters = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction SilentlyContinue |
                   Where-Object { $dsh.Id -contains ($_.Name -split '_pid_')[-1] -as [int] }
    if ($gpuCounters) {
        Write-Host ("    有 " + @($gpuCounters).Count + " 个 GPU 引擎实例绑定到 DSH")
        $gpuCounters | Select-Object -First 5 | ForEach-Object { Write-Host ("      " + $_.Name) }
    } else {
        Write-Host "    未发现 DSH 的 GPU 引擎实例（可能未在用硬件加速）" -ForegroundColor Yellow
    }
}

Sec "5. 电源计划（对 UI 流畅度的影响）"
Write-Host ("  当前计划: " + (((& powercfg.exe /getactivescheme 2>&1) -join ' ') -replace '.*\((.+)\)', '$1'))
$q = & powercfg.exe /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 2>&1
$ac = ($q | Select-String '当前交流电源设置索引|Current AC' | ForEach-Object { $_.ToString().Trim() })
if ($ac) {
    $v = [Convert]::ToInt32((($ac -split ':')[-1].Trim()).Replace('0x', ''), 16)
    Write-Host ("  最小处理器状态 AC = " + $v + "%")
}
Write-Host "  说明：此项影响 CPU 频率下限，对桌面 UI 流畅度影响很小（桌面几乎不占 CPU）"

Sec "6. 诊断结论"
Write-Host ""
$minAnimate = (Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name MinAnimate -ErrorAction SilentlyContinue).MinAnimate
$taskbarAnim = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name TaskbarAnimations -ErrorAction SilentlyContinue).TaskbarAnimations
if ($minAnimate -eq 0 -or $taskbarAnim -eq 0) {
    Write-Host "  ⚠️ 检测到动画效果被关闭：" -ForegroundColor Yellow
    if ($minAnimate -eq 0) { Write-Host "     MinAnimate = 0（窗口最小化/最大化无动画）" }
    if ($taskbarAnim -eq 0) { Write-Host "     TaskbarAnimations = 0（任务栏无动画）" }
    Write-Host ""
    Write-Host "  → 这是【切换显得生硬】的典型原因。这类设置通常来自"
    Write-Host "    「系统优化工具」或「游戏加速教程」，它们为了压低极小的性能开销"
    Write-Host "    而关掉了视觉过渡，代价是操作反馈变突兀。"
    Write-Host ""
    Write-Host "  恢复方式（二选一）："
    Write-Host "    A. 图形界面：设置 > 系统 > 关于 > 高级系统设置 > 性能设置 >"
    Write-Host "       选「调整为最佳外观」"
    Write-Host "    B. 脚本：见 set-smoothness.ps1"
} else {
    Write-Host "  ✓ 动画效果未被关闭" -ForegroundColor Green
}
