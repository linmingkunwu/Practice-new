#Requires -Version 7.0
# ==============================================================================
#  清理失效的 GPU 偏好注册表条目
#
#  用法（不需管理员）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\clean-gpu-prefs.ps1
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\clean-gpu-prefs.ps1 -DryRun
#
#  背景
#  ------------------------------------------
#  HKCU\SOFTWARE\Microsoft\DirectX\UserGpuPreferences 记录每个应用的显卡偏好
#  （省电 / 高性能 / 由 Windows 决定）。每次在「设置 > 显示 > 显卡」里为某个
#  程序选一次，就会写入一条；程序卸载后条目不会自动消失，于是逐年堆积。
#  本机有 145 条路径型条目，其中约 110 条指向已不存在的文件。
#
#  ⚠️ 判定必须用 -LiteralPath
#  ------------------------------------------
#  游戏路径常含 [ ]（如 E:\ABC\1\[PC]骑士与三从者-PC\Game.exe），
#  而 Test-Path 会把它们当作通配符，从而误判为"不存在"。
#  本脚本一律使用 Test-Path -LiteralPath。
#
#  只删除路径型且文件确实不存在的条目；
#  全局设置（DirectXUserGlobalSettings 等非路径键）与有效条目一律保留。
#
#  日志：D:\Backups\gpu-prefs-cleanup.log
# ==============================================================================

param([switch]$DryRun)

$ErrorActionPreference = 'Continue'
$key = 'HKCU:\SOFTWARE\Microsoft\DirectX\UserGpuPreferences'
$backupDir = 'D:\Backups'
$logFile = Join-Path $backupDir 'gpu-prefs-cleanup.log'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$regBackup = Join-Path $backupDir "GPU-preferences-before-cleanup-$stamp.reg"

function W([string]$m) {
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host ("  " + $m)
    "[$ts] $m" | Add-Content -LiteralPath $logFile -Encoding UTF8
}

New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction SilentlyContinue | Out-Null
"==================== GPU 偏好条目清理 ====================" | Set-Content -LiteralPath $logFile -Encoding UTF8

Write-Host "==================== GPU 偏好条目清理 ====================" -ForegroundColor Cyan
W ("模式: " + $(if ($DryRun) { '预演' } else { '实际执行' }))
W ""

if (-not (Test-Path $key)) {
    W "注册表键不存在，无需处理。"
    return
}

# ---------------------------------------------------------------- 备份
W "---- 1. 导出注册表备份 ----"
$r = & reg.exe export 'HKCU\SOFTWARE\Microsoft\DirectX\UserGpuPreferences' $regBackup /y 2>&1
if (Test-Path $regBackup) {
    W ("  已备份 -> " + $regBackup + "  (" + [math]::Round((Get-Item $regBackup).Length/1KB, 1) + " KB)")
} else {
    W "  ⚠️ 备份失败，中止操作"
    return
}

# ---------------------------------------------------------------- 分类
W ""
W "---- 2. 分类 ----"
$all = Get-ItemProperty $key -ErrorAction SilentlyContinue
$props = @($all.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' })
$pathLike = @($props | Where-Object { $_.Name -match '^[A-Za-z]:\\' })
$globalLike = @($props | Where-Object { $_.Name -notmatch '^[A-Za-z]:\\' })

W ("  条目总数    : " + $props.Count)
W ("  路径型      : " + $pathLike.Count)
W ("  全局/非路径 : " + $globalLike.Count + "   （一律保留）")
foreach ($g in $globalLike) { W ("      " + $g.Name) }

$exist = New-Object System.Collections.ArrayList
$missing = New-Object System.Collections.ArrayList
foreach ($p in $pathLike) {
    if (Test-Path -LiteralPath $p.Name -ErrorAction SilentlyContinue) {
        [void]$exist.Add($p.Name)
    } else {
        [void]$missing.Add($p.Name)
    }
}
W ""
W ("  路径存在    : " + $exist.Count + "   （保留）")
W ("  路径已失效  : " + $missing.Count + "   （待删）")

# ---------------------------------------------------------------- 列出待删
W ""
W "---- 3. 待删除条目 ----"
foreach ($m in ($missing | Sort-Object)) { W ("  [删] " + $m) }

if ($DryRun) {
    W ""
    W "预演模式，未做任何修改。"
    W "DONE"
    return
}

if ($missing.Count -eq 0) {
    W ""
    W "没有需要删除的条目。"
    W "DONE"
    return
}

# ---------------------------------------------------------------- 执行删除
W ""
W "---- 4. 执行删除 ----"
$ok = 0
$fail = 0
foreach ($m in $missing) {
    try {
        Remove-ItemProperty -Path $key -Name $m -ErrorAction Stop
        $ok++
    } catch {
        $fail++
        W ("  删除失败: " + $m + "  -> " + $_.Exception.Message)
    }
}
W ("  成功 " + $ok + " 条，失败 " + $fail + " 条")

# ---------------------------------------------------------------- 验证
W ""
W "---- 5. 验证 ----"
$after = Get-ItemProperty $key -ErrorAction SilentlyContinue
$afterProps = @($after.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' })
$afterPath = @($afterProps | Where-Object { $_.Name -match '^[A-Za-z]:\\' })
$afterMissing = @($afterPath | Where-Object { -not (Test-Path -LiteralPath $_.Name -ErrorAction SilentlyContinue) })

W ("  条目总数    : " + $props.Count + "  ->  " + $afterProps.Count)
W ("  其中路径型  : " + $pathLike.Count + "  ->  " + $afterPath.Count)
W ("  仍失效      : " + $afterMissing.Count + $(if ($afterMissing.Count -eq 0) { "  ✓" } else { "" }))

W ""
W "  保留的有效条目（正在玩的游戏等）:"
foreach ($e in ($afterPath | Sort-Object Name)) { W ("  [留] " + $e.Name) }

W ""
W "  撤销方式:"
W ("    reg import " + $regBackup)
W ""
W "DONE"
