#Requires -Version 7.0
# ==============================================================================
#  恢复「零成本但被关掉」的 Windows 设置 + 关机安全值
#
#  用法（PowerShell 7）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\apply-free-settings.ps1
#
#  HwSchMode（硬件加速 GPU 计划）需要管理员权限，已在脚本内自动提权。
#
#  收录标准：不耗资源 + 提升体验 + 容易被误关
#
#  本次改动
#  ------------------------------------------
#    1. ForegroundFlashCount   7 -> 3      任务栏闪烁次数（原厂默认就是 7，太吵）
#    2. EnableClipboardHistory -  -> 1     Win+V 剪贴板历史
#    3. TaskbarEndTask         -  -> 1     任务栏右键「结束任务」
#    4. HwSchMode              -  -> 2     硬件加速 GPU 计划（需管理员 + 重启）
#    5. TaskbarMn              -  -> 0     隐藏任务栏聊天按钮
#    6. ShowCopilotButton      -  -> 0     隐藏 Copilot 按钮
#    7. HideRecommendedSection -  -> 1     开始菜单不显示「推荐的项目」
#    8. AutoEndTasks           1  -> 0     关机时询问而非强杀（原为丢数据风险）
#    9. HungAppTimeout         3000 -> 5000  无响应判定回到默认
#   10. WaitToKillAppTimeout   10000 -> 20000 等待存盘时间回到文档默认
#
#  备份：D:\Backups\free-settings-backup-<时间戳>.reg 与 .txt
# ==============================================================================

$ErrorActionPreference = 'Continue'
$bakDir = 'D:\Backups'
$stamp = '20261001'
$logFile = Join-Path $bakDir 'free-settings-apply.log'

function W([string]$m) {
    Write-Host ("  " + $m)
    $m | Add-Content -LiteralPath $logFile -Encoding UTF8
}
function Sec($t) { Write-Host ""; Write-Host "########## $t ##########" -ForegroundColor Cyan }

New-Item -ItemType Directory -Path $bakDir -Force -ErrorAction SilentlyContinue | Out-Null
"==================== 零成本设置恢复 ====================" | Set-Content -LiteralPath $logFile -Encoding UTF8

Write-Host "==================== 零成本设置恢复 ====================" -ForegroundColor Cyan

# ---------------------------------------------------------------- 备份
Sec "1. 备份"
$regKeys = @(
    @{ K = 'HKCU\Control Panel\Desktop';                                            F = "desktop-before-freesettings-$stamp.reg" },
    @{ K = 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced';       F = "adv-before-freesettings-$stamp.reg" },
    @{ K = 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced';       F = $null },
    @{ K = 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers';                  F = "graphicsdrivers-before-hags-$stamp.reg" }
)
$done = @{}
foreach ($r in $regKeys) {
    if ($r.F -and -not $done.ContainsKey($r.F)) {
        $p = Join-Path $bakDir $r.F
        $null = & reg.exe export $r.K $p /y 2>&1
        if (Test-Path $p) { W ("已备份 " + $r.F) }
        $done[$r.F] = $true
    }
}
# 剪贴板键可能不存在，单独处理
$cbKey = 'HKCU\SOFTWARE\Microsoft\Clipboard'
$cbReg = Join-Path $bakDir "clipboard-before-freesettings-$stamp.reg"
$null = & reg.exe export $cbKey $cbReg /y 2>&1
W ("剪贴板键备份: " + $(if (Test-Path $cbReg) { '成功' } else { '键不存在（属正常，原来是关闭状态）' }))

# 记录改动前的值
$snapshot = Join-Path $bakDir "free-settings-before-$stamp.txt"
$tmp = New-Object System.Collections.ArrayList
[void]$tmp.Add("===== 改动前的值 =====")
$pre = @(
    @{ N = 'ForegroundFlashCount';    P = 'HKCU:\Control Panel\Desktop';              }
    @{ N = 'AutoEndTasks';            P = 'HKCU:\Control Panel\Desktop';              }
    @{ N = 'HungAppTimeout';          P = 'HKCU:\Control Panel\Desktop';              }
    @{ N = 'WaitToKillAppTimeout';    P = 'HKCU:\Control Panel\Desktop';              }
    @{ N = 'TaskbarEndTask';          P = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' }
    @{ N = 'TaskbarMn';               P = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' }
    @{ N = 'ShowCopilotButton';       P = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' }
    @{ N = 'HideRecommendedSection';  P = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' }
    @{ N = 'EnableClipboardHistory';  P = 'HKCU:\SOFTWARE\Microsoft\Clipboard' }
    @{ N = 'HwSchMode';               P = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' }
)
foreach ($p in $pre) {
    $v = (Get-ItemProperty $p.P -Name $p.N -ErrorAction SilentlyContinue).($p.N)
    [void]$tmp.Add(("{0,-28} = {1}" -f $p.N, $(if ($null -eq $v) { '(未设置)' } else { $v })))
}
$tmp | Set-Content -LiteralPath $snapshot -Encoding UTF8
W ("改动前快照: " + (Split-Path $snapshot -Leaf))

# ---------------------------------------------------------------- 非提权改动
Sec "2. 应用改动（用户级）"
$DESK = 'HKCU:\Control Panel\Desktop'
$ADV  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

$userChanges = @(
    @{ N = 'ForegroundFlashCount';   P = $DESK; V = 3;     T = 'DWord'; D = '任务栏闪烁次数 7 -> 3' },
    @{ N = 'TaskbarEndTask';         P = $ADV;  V = 1;     T = 'DWord'; D = '任务栏右键结束任务' },
    @{ N = 'TaskbarMn';              P = $ADV;  V = 0;     T = 'DWord'; D = '隐藏聊天按钮' },
    @{ N = 'ShowCopilotButton';      P = $ADV;  V = 0;     T = 'DWord'; D = '隐藏 Copilot 按钮' },
    @{ N = 'HideRecommendedSection'; P = $ADV;  V = 1;     T = 'DWord'; D = '开始菜单不显示推荐项' },
    @{ N = 'AutoEndTasks';           P = $DESK; V = 0;     T = 'String'; D = '关机时询问，不强杀' },
    @{ N = 'HungAppTimeout';         P = $DESK; V = '5000';  T = 'String'; D = '无响应判定回到默认' },
    @{ N = 'WaitToKillAppTimeout';   P = $DESK; V = '20000'; T = 'String'; D = '等待存盘时间回到默认' }
)
foreach ($c in $userChanges) {
    try {
        $old = (Get-ItemProperty $c.P -Name $c.N -ErrorAction SilentlyContinue).($c.N)
        Set-ItemProperty -Path $c.P -Name $c.N -Value $c.V -Type $c.T -ErrorAction Stop
        $new = (Get-ItemProperty $c.P -Name $c.N -ErrorAction SilentlyContinue).($c.N)
        W ("[{0}] {1,-24} {2,-10} -> {3,-8} {4}" -f $(if ("$new" -eq "$($c.V)") { 'OK' } else { '!!' }), $c.N, $(if ($null -eq $old) { '(未设置)' } else { $old }), $new, $c.D)
    } catch {
        W ("[失败] " + $c.N + "  -> " + $_.Exception.Message)
    }
}

# 剪贴板历史（键可能不存在，需先创建）
Sec "3. 剪贴板历史（需要先建键）"
if (-not (Test-Path 'HKCU:\SOFTWARE\Microsoft\Clipboard')) {
    New-Item -Path 'HKCU:\SOFTWARE\Microsoft\Clipboard' -Force | Out-Null
    W "已创建 HKCU\SOFTWARE\Microsoft\Clipboard"
}
Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Clipboard' -Name 'EnableClipboardHistory' -Value 1 -Type DWord
$chv = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Clipboard' -Name 'EnableClipboardHistory' -ErrorAction SilentlyContinue).EnableClipboardHistory
W ("[{0}] EnableClipboardHistory   (未设置)   -> {1,-8} Win+V 剪贴板历史" -f $(if ($chv -eq 1) { 'OK' } else { '!!' }), $chv)

# ---------------------------------------------------------------- 提权改动
Sec "4. HAGS 硬件加速 GPU 计划（需管理员）"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    try {
        $old = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -ErrorAction SilentlyContinue).HwSchMode
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value 2 -Type DWord -ErrorAction Stop
        $new = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -ErrorAction SilentlyContinue).HwSchMode
        W ("[OK] HwSchMode  {0} -> {1}  硬件加速 GPU 计划（需重启生效）" -f $(if ($null -eq $old) { '(未设置)' } else { $old }), $new)
    } catch {
        W ("[失败] HwSchMode -> " + $_.Exception.Message)
    }
} else {
    W "当前非管理员，准备提权执行 HwSchMode ..."
    $tmpScript = Join-Path $env:TEMP '_hags.ps1'
    $tmpLog = Join-Path $env:TEMP '_hags.log'
    Remove-Item $tmpLog -Force -ErrorAction SilentlyContinue
    $content = @'
$log = Join-Path $env:TEMP '_hags.log'
$old = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -ErrorAction SilentlyContinue).HwSchMode
try {
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value 2 -Type DWord -ErrorAction Stop
    $new = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -ErrorAction SilentlyContinue).HwSchMode
    "OK HwSchMode $old -> $new" | Set-Content -LiteralPath $log -Encoding UTF8
} catch {
    "FAIL " + $_.Exception.Message | Set-Content -LiteralPath $log -Encoding UTF8
}
'@
    [System.IO.File]::WriteAllText($tmpScript, $content, (New-Object System.Text.UTF8Encoding($false)))
    $cmd = Join-Path $env:TEMP '_hags.cmd'
    Set-Content -LiteralPath $cmd -Encoding ASCII -Value @(
        '@echo off',
        'chcp 65001 > nul',
        "pwsh.exe -NoProfile -ExecutionPolicy Bypass -File `"$tmpScript`""
    )
    Start-Process -FilePath $cmd -Verb RunAs -Wait -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    if (Test-Path $tmpLog) {
        W ((Get-Content $tmpLog -Raw -Encoding UTF8).Trim())
    } else {
        W "提权未完成（UAC 可能被取消）"
    }
    Remove-Item $tmpScript, $cmd, $tmpLog -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- 验证
Sec "5. 最终验证"
$verify = @(
    @{ N = 'ForegroundFlashCount';   P = $DESK; Want = '3';      D = '任务栏闪烁 3 次' },
    @{ N = 'EnableClipboardHistory'; P = 'HKCU:\SOFTWARE\Microsoft\Clipboard'; Want = '1'; D = '剪贴板历史' },
    @{ N = 'TaskbarEndTask';         P = $ADV;  Want = '1';      D = '任务栏结束任务' },
    @{ N = 'TaskbarMn';              P = $ADV;  Want = '0';      D = '隐藏聊天按钮' },
    @{ N = 'ShowCopilotButton';      P = $ADV;  Want = '0';      D = '隐藏 Copilot 按钮' },
    @{ N = 'HideRecommendedSection'; P = $ADV;  Want = '1';      D = '开始菜单无推荐项' },
    @{ N = 'AutoEndTasks';           P = $DESK; Want = '0';      D = '关机询问' },
    @{ N = 'HungAppTimeout';         P = $DESK; Want = '5000';   D = '无响应超时' },
    @{ N = 'WaitToKillAppTimeout';   P = $DESK; Want = '20000';  D = '等待存盘' },
    @{ N = 'HwSchMode';              P = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Want = '2'; D = 'HAGS（需重启）' }
)
$okCount = 0
foreach ($v in $verify) {
    $cur = (Get-ItemProperty $v.P -Name $v.N -ErrorAction SilentlyContinue).($v.N)
    $ok = "$cur" -eq $v.Want
    if ($ok) { $okCount++ }
    W ("[{0}] {1,-26} = {2,-10} {3}" -f $(if ($ok) { 'OK' } else { '!!' }), $v.N, $(if ($null -eq $cur) { '(未设置)' } else { $cur }), $v.D)
}
W ""
W ("通过 " + $okCount + " / " + $verify.Count)

Write-Host ""
Write-Host "==================== 完成 ====================" -ForegroundColor Cyan
Write-Host "  撤销方式:" -ForegroundColor Gray
Write-Host ("    快照: " + $snapshot) -ForegroundColor Gray
Write-Host ("    注册表: " + (Join-Path $bakDir "desktop-before-freesettings-$stamp.reg")) -ForegroundColor Gray
Write-Host ("            " + (Join-Path $bakDir "adv-before-freesettings-$stamp.reg")) -ForegroundColor Gray
Write-Host ("            " + (Join-Path $bakDir "graphicsdrivers-before-hags-$stamp.reg")) -ForegroundColor Gray
Write-Host ""
Write-Host "  生效说明:" -ForegroundColor Cyan
Write-Host "    · 剪贴板历史 / 任务栏项：立即生效（Win+V 试试）"
Write-Host "    · 任务栏按钮显隐：可能需要重启 explorer 或重新登录"
Write-Host "    · HAGS：需【重启电脑】"
