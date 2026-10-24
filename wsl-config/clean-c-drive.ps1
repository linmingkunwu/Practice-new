#Requires -Version 7.0
# ==============================================================================
#  C 盘清理 —— 纯缓存与废弃物
#
#  用法（不需管理员）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\clean-c-drive.ps1
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\clean-c-drive.ps1 -DryRun
#
#  清理范围（用户已确认）
#  ------------------------------------------
#    1. .dsh-wallpaper-engine\cache     帧缓存（从 Wallpaper Engine 场景包提取）
#    2. Temp\DiagOutputDir              ETW 诊断跟踪日志（09-29 陈年残留）
#    3. Local\CrashDumps                崩溃转储
#    4. pip 缓存                        pip cache purge
#    5. uv 缓存                         uv cache clean
#
#  ⚠️ 明确【不】清理（用户选择保留回退能力）
#  ------------------------------------------
#    · Temp\dsh-workspace-changes-*     DSH 文件版本追踪数据（19 个 / 7.8 GB）
#    · Wand                             可能含游戏存档
#    · Local\Packages                   Store 应用数据
#    · Local\JetBrains                  IDE 缓存，应在 IDE 内清理
#
#  ⚠️ 注意事项
#  ------------------------------------------
#    · 壁纸插件（dsh-plugin-wallpaper-engine）仍在运行，被占用的文件会跳过。
#      更彻底的做法是在 DSH 里关闭该插件后再清，否则缓存会重新生成。
#    · 释放量以【清理前后可用空间差值】为准，同时用目录级证据交叉验证。
# ==============================================================================

param([switch]$DryRun)

$ErrorActionPreference = 'Continue'
$logDir = 'D:\Backups'
$logFile = Join-Path $logDir 'clean-c-drive.log'
$tmp = $env:TEMP
$profile_ = $env:USERPROFILE

function W([string]$m) {
    Write-Host ("  " + $m)
    $m | Add-Content -LiteralPath $logFile -Encoding UTF8
}
function Sec($t) { Write-Host ""; Write-Host "########## $t ##########" -ForegroundColor Cyan }
function Get-FreeMB {
    return [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1MB, 0)
}
function Get-SizeMB([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return 0 }
    $s = (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    return [math]::Round($s / 1MB, 0)
}

New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue | Out-Null
"==================== C 盘清理 ====================" | Set-Content -LiteralPath $logFile -Encoding UTF8

Write-Host "==================== C 盘清理 ====================" -ForegroundColor Cyan
W ("模式: " + $(if ($DryRun) { '预演' } else { '实际执行' }))

# ---------------------------------------------------------------- 基线
Sec "1. 清理前基线"
$freeBefore = Get-FreeMB
$totalBefore = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
W ("C 盘可用: " + [math]::Round($freeBefore/1024, 2) + " GB  /  " + [math]::Round($totalBefore.Size/1GB, 1) + " GB")
W ("已用率  : " + [math]::Round(100*($totalBefore.Size-$totalBefore.FreeSpace)/$totalBefore.Size, 1) + "%")

$targets = @(
    @{ N = '壁纸插件帧缓存';   P = "$profile_\.dsh-wallpaper-engine\cache";  Method = 'Remove'; KeepIfLocked = $true },
    @{ N = 'DiagOutputDir';    P = "$tmp\DiagOutputDir";                     Method = 'Remove' },
    @{ N = 'CrashDumps';       P = "$env:LOCALAPPDATA\CrashDumps";           Method = 'Remove' },
    @{ N = 'pip 缓存';         P = "$env:LOCALAPPDATA\pip\Cache";            Method = 'PipPurge' },
    @{ N = 'uv 缓存';          P = "$env:LOCALAPPDATA\uv";                   Method = 'UvClean' }
)

Sec "2. 各项清理前的实际大小"
$planTotal = 0
foreach ($t in $targets) {
    $mb = Get-SizeMB $t.P
    $planTotal += $mb
    W ("{0,-22} {1,8} MB   {2}" -f $t.N, $mb, $t.P)
}
W ""
W ("合计计划清理: " + [math]::Round($planTotal/1024, 2) + " GB")

if ($DryRun) {
    W ""
    W "预演模式，未执行任何删除。"
    return
}

# ---------------------------------------------------------------- 执行
Sec "3. 执行清理"
$freed = @{}
foreach ($t in $targets) {
    $before = Get-SizeMB $t.P
    if ($before -eq 0) { W ("[跳过] " + $t.N + " —— 不存在或为空"); continue }

    Write-Host ("  处理 " + $t.N + " ...") -ForegroundColor Yellow
    $locked = 0
    $deleted = 0

    switch ($t.Method) {
        'PipPurge' {
            $o = & python -m pip cache purge 2>&1
            W ("       " + (($o | Select-Object -Last 1) -join ' '))
            $deleted = $before - (Get-SizeMB $t.P)
        }
        'UvClean' {
            $uv = Get-Command uv -ErrorAction SilentlyContinue
            if ($uv) {
                $o = & uv cache clean 2>&1
                W ("       " + (($o | Select-Object -Last 1) -join ' '))
            } else {
                # uv 未在 PATH，直接删缓存目录
                Get-ChildItem -LiteralPath $t.P -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop; $deleted++ }
                    catch { $locked++ }
                }
            }
            $deleted = $before - (Get-SizeMB $t.P)
        }
        default {
            # 逐个子项删除，统计失败数（被占用的文件）
            Get-ChildItem -LiteralPath $t.P -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                    $deleted++
                } catch {
                    $locked++
                }
            }
            $deleted = $before - (Get-SizeMB $t.P)
        }
    }

    $freed[$t.N] = $deleted
    $msg = "[完成] {0,-22} 释放 {1,8} MB" -f $t.N, $deleted
    if ($locked -gt 0) { $msg += ("   （" + $locked + " 项因被占用而跳过）") }
    W $msg
    Start-Sleep -Milliseconds 300
}

# ---------------------------------------------------------------- 验证
Sec "4. 验证"
$freeAfter = Get-FreeMB
W ""
W ("  分项释放:")
$sumFreed = 0
foreach ($k in $freed.Keys) {
    W ("    {0,-22} {1,8} MB" -f $k, $freed[$k])
    $sumFreed += $freed[$k]
}
W ("    {0,-22} {1,8} MB  ≈ {2} GB" -f '分项合计', $sumFreed, [math]::Round($sumFreed/1024, 2))
W ""
W ("  C 盘可用: " + [math]::Round($freeBefore/1024, 2) + " GB  ->  " + [math]::Round($freeAfter/1024, 2) + " GB")
$delta = $freeAfter - $freeBefore
W ("  实测差值: " + $(if ($delta -ge 0) { '+' } else { '' }) + $delta + " MB  ≈ " + [math]::Round($delta/1024, 2) + " GB")
W ""
W "  ⚠️ 分项合计与实测差值可能有出入："
W "     删除期间系统仍在写盘（日志、浏览器缓存等），实测差值会偏小。"
W "     以目录级证据为准。"

Sec "5. 清理后各项状态"
foreach ($t in $targets) {
    $mb = Get-SizeMB $t.P
    W ("{0,-22} 现存 {1,8} MB   {2}" -f $t.N, $mb, $(if ($mb -eq 0) { '已清空 ✓' } else { '仍有残留' }))
}

Sec "6. C 盘现状"
$d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
W ("  总容量: " + [math]::Round($d.Size/1GB, 1) + " GB")
W ("  可用  : " + [math]::Round($d.FreeSpace/1GB, 2) + " GB  (" + [math]::Round(100*$d.FreeSpace/$d.Size, 1) + "%)")

Sec "7. 保留未动的重要数据"
W ("  Temp\dsh-workspace-changes-*  " + (Get-SizeMB "$tmp\dsh-workspace-changes-*") + " MB  （通配符查询不适用，见下方实际值）")
$wcTotal = 0
Get-ChildItem $tmp -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'dsh-workspace-changes-*' } | ForEach-Object {
    $wcTotal += Get-SizeMB $_.FullName
}
W ("  Temp 下 DSH 工作区快照共 " + [math]::Round($wcTotal/1024,2) + " GB —— 按你的选择保留")
W ("  Wand / Packages / JetBrains 缓存 —— 未动")
