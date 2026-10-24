#Requires -Version 7.0
# ==============================================================================
#  让 WinGet 安装的（较新）工具链接管 PATH，替换旧版条目
#
#  用法（PowerShell 7）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\set-toolchain-path.ps1
#
#  本脚本【需要】管理员权限 —— 已在脚本内自动提权，无需手动开管理员终端。
#
#  ⚠️⚠️  强烈警告：本脚本的已知效果是【让 gcc 完全无法编译】  ⚠️⚠️
#  --------------------------------------------------------------------------
#  2026-09-29 实测结论：WinLibs gcc 16.1.0 无法处理非 ASCII 路径。
#
#      16.1.0 + 中文 TEMP + 中文安装路径   -> 失败（汇编阶段）
#      16.1.0 + ASCII TEMP + 中文安装路径  -> 失败（链接阶段，找不到 crt2.o）
#      16.1.0 + 中文 TEMP + ASCII 安装路径 -> 失败（汇编阶段）
#      16.1.0 + ASCII TEMP + ASCII 安装路径 -> 成功
#
#  本机 TEMP 是 C:\Users\<非ASCII>\AppData\Local\Temp，且 WinGet 包也装在
#  含中文的路径下，所以【在当前配置下 gcc 16.1.0 永远无法工作】。
#
#  该改动已于 2026-09-29 用 fix-toolchain-path.ps1 -Mode Revert 回退。
#  因此本脚本现在需要显式加 -IUnderstandTheRisk 才会执行，
#  以免误触再次弄坏编译器。
#
#  另需注意的连带影响
#  WinLibs 包自带 cmake 4.3.2 / ctest / cpack / cppcheck / ctags / doxygen / ninja。
#  放到旧的 index-12 位置后，它们会遮蔽 Strawberry 的版本：
#      cmake  3.29.2  ->  4.3.2
#  CMake 4 取消了对 cmake_minimum_required(VERSION <3.5) 的兼容，
#  老项目会在 configure 阶段直接失败，直到把最低版本要求调高。
#
#  为什么路径用通配符而不是字面量
#  WinGet 包目录位于 C:\Users\<非ASCII用户名>\AppData\Local\Microsoft\WinGet\Packages
#  之下。脚本里绝不写字面中文路径，而是用 $env:LOCALAPPDATA 加通配符查找，
#  这样即使换个用户名也能工作。
#
#  回滚：改动前会把原 Machine PATH 备份到 D:\Backups\；
#        或用 fix-toolchain-path.ps1 自动还原。
# ==============================================================================

param(
    [switch]$IUnderstandTheRisk
)

$ErrorActionPreference = 'Stop'

function Find-FirstPath {
    param([string]$Pattern)
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages')
        'C:\Users\*\AppData\Local\Microsoft\WinGet\Packages'
    )
    foreach ($r in $roots) {
        $hit = Get-Item -Path (Join-Path $r $Pattern) -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

$newGccBin  = Find-FirstPath 'BrechtSanders.WinLibs.MCF.UCRT_*\mingw64\bin'
$newLlvmTgt = Find-FirstPath 'MartinStorsjo.LLVM-MinGW.UCRT_*\llvm-mingw-*-ucrt-x86_64\x86_64-w64-mingw32\bin'

$map = @{}
$map['C:\mingw64\bin']                                            = $newGccBin
$map['C:\llvm-mingw-20251216-ucrt-x86_64\x86_64-w64-mingw32\bin'] = $newLlvmTgt

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host "===== 0. 预检 =====" -ForegroundColor Cyan
Write-Host ("  管理员权限   : $isAdmin")
Write-Host ("  LOCALAPPDATA : $env:LOCALAPPDATA")

# ------------------------------------------------------------------ 风险确认
if (-not $IUnderstandTheRisk) {
    Write-Host ""
    Write-Host "安全闸已触发：本脚本的已知效果是让 gcc 完全无法编译。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  原因：WinLibs gcc 16.1.0 无法处理非 ASCII 路径，而本机 TEMP 与" -ForegroundColor Yellow
    Write-Host "        WinGet 包路径都含中文，因此在当前配置下它永远无法工作。" -ForegroundColor Yellow
    Write-Host "        该改动已于 2026-09-29 回退。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  如果确实要重新执行，加 -IUnderstandTheRisk：" -ForegroundColor Yellow
    Write-Host "    pwsh -File E:\Git\wsl-config\set-toolchain-path.ps1 -IUnderstandTheRisk"
    Write-Host ""
    Write-Host "  回退方式：pwsh -File E:\Git\wsl-config\fix-toolchain-path.ps1"
    Write-Host ""
    Write-Host "未做任何修改。" -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "===== 1. 定位替换目标 =====" -ForegroundColor Cyan
$ok = $true
foreach ($k in @($map.Keys)) {
    $v = $map[$k]
    $e = $false
    if ($v) { $e = Test-Path -LiteralPath $v }
    if (-not $e) { $ok = $false }
    Write-Host ("  存在 [{0}]  {1}" -f $e, $v)
}
if (-not $ok) {
    Write-Host "中止：有替换目标无法定位。未写入任何内容。" -ForegroundColor Red
    exit 1
}

$machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
$entries     = @($machinePath -split ';')

Write-Host ""
Write-Host "===== 2. 计划替换 =====" -ForegroundColor Cyan
$changed    = 0
$newEntries = New-Object System.Collections.ArrayList
foreach ($e in $entries) {
    if ($map.ContainsKey($e)) {
        Write-Host ("  [$e]")
        Write-Host ("     -> $($map[$e])")
        $changed++
        [void]$newEntries.Add($map[$e])
    } else {
        [void]$newEntries.Add($e)
    }
}
Write-Host ("  待替换条目数：$changed")

if ($changed -eq 0) {
    Write-Host "  无需改动（可能已经替换过）" -ForegroundColor Green
    exit 0
}

$newPath = ($newEntries -join ';')

# --- 安全闸：拒绝写入任何可疑内容 -------------------------------------------
if ($newEntries.Count -ne $entries.Count) {
    Write-Host "中止：条目数异常变化。未写入任何内容。" -ForegroundColor Red
    exit 1
}
if ($newPath -match '=====|->|待替换') {
    Write-Host "中止：PATH 中似乎混入了日志文本。未写入任何内容。" -ForegroundColor Red
    exit 1
}
foreach ($k in @($map.Keys)) {
    if ($newPath.Contains($k)) {
        Write-Host "中止：替换后旧条目仍然存在：$k" -ForegroundColor Red
        exit 1
    }
}

# 风险已确认，但写 Machine PATH 仍需管理员；脚本自行提权
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "本脚本需要管理员权限，正在请求提权（请在 UAC 窗口点『是』）..." -ForegroundColor Yellow
    Start-Process -FilePath 'pwsh' -Verb RunAs -Wait -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"",
        '-IUnderstandTheRisk'
    )
    exit
}

Write-Host ""
Write-Host "===== 3. 备份 Machine PATH =====" -ForegroundColor Cyan
$bakDir = 'D:\Backups'
if (-not (Test-Path -LiteralPath $bakDir)) { New-Item -ItemType Directory -Path $bakDir -Force | Out-Null }
$bak = Join-Path $bakDir ("Machine-PATH-backup-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
[System.IO.File]::WriteAllText($bak, $machinePath, [System.Text.Encoding]::UTF8)
Write-Host ("  已备份 -> $bak") -ForegroundColor Green

Write-Host ""
Write-Host "===== 4. 应用 =====" -ForegroundColor Cyan
[Environment]::SetEnvironmentVariable('PATH', $newPath, 'Machine')
Write-Host "  Machine PATH 已更新" -ForegroundColor Green

Write-Host ""
Write-Host "===== 5. 复核 =====" -ForegroundColor Cyan
Write-Host "  当前 shell 仍用旧 PATH，请开新终端查看效果。"
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
$probe    = @($newEntries) + @($userPath -split ';')
foreach ($tool in @('gcc','g++','gdb','cmake','ninja','clang')) {
    $hit = $null
    foreach ($d in $probe) {
        if (-not $d) { continue }
        foreach ($ext in @('.exe','.cmd','.bat')) {
            $cand = Join-Path $d ($tool + $ext)
            if (Test-Path -LiteralPath $cand) { $hit = $cand; break }
        }
        if ($hit) { break }
    }
    if ($hit) {
        Write-Host ("    {0,-7} -> {1}" -f $tool, $hit)
    } else {
        Write-Host ("    {0,-7} -> （未找到）" -f $tool)
    }
}

Write-Host ""
Write-Host "⚠️  请立刻在新终端里验证 gcc 是否还能编译！" -ForegroundColor Yellow
Write-Host "    预期：gcc 16.1.0 会因中文路径而失败。" -ForegroundColor Yellow
Write-Host "    回退：pwsh -File E:\Git\wsl-config\fix-toolchain-path.ps1" -ForegroundColor Yellow
Write-Host ""
Write-Host ("完成。回退方法：从 $bak 还原 Machine PATH") -ForegroundColor Green
