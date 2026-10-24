#Requires -Version 7.0
# ==============================================================================
#  第二轮「零成本设置」应用 —— 关闭推广应用与系统提示
#
#  用法（不需管理员）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\apply-free-settings2.ps1
#
#  本次改动（5 项，全部为用户级、零开销、可还原）
#  ------------------------------------------
#    1. SilentInstalledAppsEnabled       1  -> 0   禁止静默安装推广应用  ← 唯一有实际影响的一项
#    2. SoftLandingEnabled                  -> 0   关闭「Windows 提示与建议」弹窗
#    3. SubscribedContent-310093Enabled     -> 0   关闭「Windows 欢迎体验」
#    4. ShowSyncProviderNotifications       -> 0   关闭资源管理器里的 OneDrive 推广通知
#    5. ShowCloudFilesInQuickAccess         -> 0   快速访问不混入云盘文件
#
#  ⚠️ 未包含项（用户选择不做）
#  ------------------------------------------
#    · 经典右键菜单（CLSID 86ca1aa0-...）—— 属偏好项，用户保留 Win11 默认菜单
#
#  备份：D:\Backups\contentdelivery-before-20261001.reg 等
# ==============================================================================

$ErrorActionPreference = 'Continue'
$bakDir = 'D:\Backups'
$stamp = '20261001'
$logFile = Join-Path $bakDir 'free-settings2-apply.log'

function W([string]$m) {
    Write-Host ("  " + $m)
    $m | Add-Content -LiteralPath $logFile -Encoding UTF8
}
function Sec($t) { Write-Host ""; Write-Host "########## $t ##########" -ForegroundColor Cyan }

New-Item -ItemType Directory -Path $bakDir -Force -ErrorAction SilentlyContinue | Out-Null
"==================== 第二轮零成本设置应用 ====================" | Set-Content -LiteralPath $logFile -Encoding UTF8

$CDM = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$ADV = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

Write-Host "==================== 第二轮零成本设置应用 ====================" -ForegroundColor Cyan

# ---------------------------------------------------------------- 备份
Sec "1. 备份"
$regTargets = @(
    @{ K = 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; F = "contentdelivery-before-$stamp.reg" },
    @{ K = 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced';      F = "adv2-before-$stamp.reg" }
)
foreach ($t in $regTargets) {
    $p = Join-Path $bakDir $t.F
    $null = & reg.exe export $t.K $p /y 2>&1
    W ("已备份 " + $t.F + "  " + $(if (Test-Path $p) { '(' + [math]::Round((Get-Item $p).Length/1KB,1) + ' KB)' } else { '(失败)' }))
}

# 改动前快照
$snap = Join-Path $bakDir "free-settings2-before-$stamp.txt"
$lines = New-Object System.Collections.ArrayList
[void]$lines.Add("===== 第二轮改动前的值 =====")
$targets = @(
    @{ N = 'SilentInstalledAppsEnabled';     P = $CDM },
    @{ N = 'SoftLandingEnabled';             P = $ADV },
    @{ N = 'SubscribedContent-310093Enabled';P = $CDM },
    @{ N = 'ShowSyncProviderNotifications';  P = $ADV },
    @{ N = 'ShowCloudFilesInQuickAccess';    P = $ADV }
)
foreach ($t in $targets) {
    $v = (Get-ItemProperty $t.P -Name $t.N -ErrorAction SilentlyContinue).($t.N)
    [void]$lines.Add(("{0,-34} = {1}" -f $t.N, $(if ($null -eq $v) { '(未设置)' } else { $v })))
}
$lines | Set-Content -LiteralPath $snap -Encoding UTF8
W ("改动前快照: " + (Split-Path $snap -Leaf))

# ---------------------------------------------------------------- 应用
Sec "2. 应用改动"
$changes = @(
    @{ N = 'SilentInstalledAppsEnabled';      P = $CDM; D = '禁止静默安装推广应用' },
    @{ N = 'SoftLandingEnabled';              P = $ADV; D = '关闭 Windows 提示与建议' },
    @{ N = 'SubscribedContent-310093Enabled'; P = $CDM; D = '关闭 Windows 欢迎体验' },
    @{ N = 'ShowSyncProviderNotifications';   P = $ADV; D = '关闭 OneDrive 推广通知' },
    @{ N = 'ShowCloudFilesInQuickAccess';     P = $ADV; D = '快速访问不显示云文件' }
)
foreach ($c in $changes) {
    try {
        $old = (Get-ItemProperty $c.P -Name $c.N -ErrorAction SilentlyContinue).($c.N)
        if (-not (Test-Path $c.P)) { New-Item -Path $c.P -Force | Out-Null }
        Set-ItemProperty -Path $c.P -Name $c.N -Value 0 -Type DWord -ErrorAction Stop
        $new = (Get-ItemProperty $c.P -Name $c.N -ErrorAction SilentlyContinue).($c.N)
        W ("[{0}] {1,-34} {2,-10} -> {3,-4} {4}" -f $(if ($new -eq 0) { 'OK' } else { '!!' }), $c.N, $(if ($null -eq $old) { '(未设置)' } else { $old }), $new, $c.D)
    } catch {
        W ("[失败] " + $c.N + "  -> " + $_.Exception.Message)
    }
}

# ---------------------------------------------------------------- 验证
Sec "3. 最终验证"
$ok = 0
foreach ($c in $changes) {
    $v = (Get-ItemProperty $c.P -Name $c.N -ErrorAction SilentlyContinue).($c.N)
    $good = $v -eq 0
    if ($good) { $ok++ }
    W ("[{0}] {1,-34} = {2,-6} {3}" -f $(if ($good) { 'OK' } else { '!!' }), $c.N, $v, $c.D)
}
W ""
W ("通过 " + $ok + " / " + $changes.Count)

# ---------------------------------------------------------------- 顺带确认已ok的项
Sec "4. 顺带确认此前已正确的广告相关项"
$already = @(
    @{ N = 'SubscribedContent-338389Enabled'; P = $CDM },
    @{ N = 'SubscribedContent-338388Enabled'; P = $CDM },
    @{ N = 'SystemPaneSuggestionsEnabled';    P = $CDM },
    @{ N = 'IsDynamicSearchBoxEnabled';       P = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings' }
)
foreach ($a in $already) {
    $v = (Get-ItemProperty $a.P -Name $a.N -ErrorAction SilentlyContinue).($a.N)
    W ("[{0}] {1,-34} = {2}" -f $(if ($v -eq 0) { 'OK' } else { '??' }), $a.N, $(if ($null -eq $v) { '(未设置)' } else { $v }))
}

Write-Host ""
Write-Host "==================== 完成 ====================" -ForegroundColor Cyan
Write-Host "  撤销方式:" -ForegroundColor Gray
Write-Host ("    reg import " + (Join-Path $bakDir "contentdelivery-before-$stamp.reg")) -ForegroundColor Gray
Write-Host ("    reg import " + (Join-Path $bakDir "adv2-before-$stamp.reg")) -ForegroundColor Gray
Write-Host ""
Write-Host "  生效说明: 这些项在下次触发系统提示/推荐时体现，无需重启。" -ForegroundColor Cyan
Write-Host "            已安装的推广 App 不会因此被卸载（如需要请手动卸载）。" -ForegroundColor Cyan
