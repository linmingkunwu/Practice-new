#Requires -Version 7.0
# ==============================================================================
#  修复被 WinLibs gcc 16.1.0 切换弄坏的工具链 PATH
#
#  用法（PowerShell 7）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\fix-toolchain-path.ps1
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\fix-toolchain-path.ps1 -Mode AsciiToolchain
#
#  本脚本【需要】管理员权限 —— 已在脚本内自动提权，无需手动开管理员终端。
#
#  为什么需要它
#  ------------
#  set-toolchain-path.ps1 把旧版 Machine PATH 条目换成了 WinGet 的 WinLibs 路径。
#  实测结果：gcc 变得完全不可用。
#
#  WinLibs gcc 16.1.0 完全无法处理非 ASCII 路径。实测矩阵：
#
#      16.1.0 + 中文 TEMP + 中文安装路径  -> 失败（汇编阶段）
#      16.1.0 + ASCII TEMP + 中文安装路径 -> 失败（链接阶段，找不到 crt2.o）
#      16.1.0 + 中文 TEMP + ASCII 安装路径 -> 失败（汇编阶段）
#      16.1.0 + ASCII TEMP + ASCII 安装路径 -> 成功
#
#      15.2.0 + 中文 TEMP + ASCII 安装路径 -> 成功（原来的状态）
#
#  本机 TEMP 是 C:\Users\<非ASCII>\AppData\Local\Temp，因此 gcc 16.1.0
#  在默认配置下【永远不可能】工作。
#
#  模式
#  ----
#  Revert（默认，推荐）
#      从最新的 D:\Backups\Machine-PATH-backup-*.txt 还原 Machine PATH。
#      gcc 回到 15.2.0（零改动即可用），cmake 回到 3.29.2。
#      不触碰任何环境变量。这是已知可用状态。
#
#  AsciiToolchain
#      保留 gcc 16.1.0，但把所有路径改成 ASCII：
#         - Machine PATH 条目指向 D:\Toolchains\winlibs-16.1.0\bin
#         - 用户 TEMP/TMP 移到 C:\Temp
#      附带好处：临时文件离开中文用户路径。
#      注意：工具链变成 WinGet 之外的副本，不会被 "winget upgrade" 更新。
#
#      【2026-09-30 现状】D:\Toolchains\winlibs-16.1.0 已于 09-29 删除
#      （当时决定回退），因此该模式现在会直接中止。若要重新启用，
#      需先从 WinGet 包目录复制一份到该 ASCII 路径。
# ==============================================================================

param(
    [ValidateSet('Revert','AsciiToolchain')]
    [string]$Mode = 'Revert'
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- 自动提权
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "本脚本需要管理员权限，正在请求提权（请在 UAC 窗口点『是』）..." -ForegroundColor Yellow
    Start-Process -FilePath 'pwsh' -Verb RunAs -Wait -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"",
        '-Mode', $Mode
    )
    exit
}

Write-Host "===== 0. 预检 =====" -ForegroundColor Cyan
Write-Host ("  模式       : $Mode")
Write-Host "  管理员权限 : 是"

$machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
$stamp       = Get-Date -Format 'yyyyMMdd-HHmmss'

Write-Host ""
Write-Host "===== 1. 备份当前 Machine PATH =====" -ForegroundColor Cyan
$bakDir = 'D:\Backups'
if (-not (Test-Path -LiteralPath $bakDir)) { New-Item -ItemType Directory -Path $bakDir -Force | Out-Null }
$curBak = Join-Path $bakDir ("Machine-PATH-before-fix-{0}.txt" -f $stamp)
[System.IO.File]::WriteAllText($curBak, $machinePath, [System.Text.Encoding]::UTF8)
Write-Host ("  已备份 -> $curBak") -ForegroundColor Green

if ($Mode -eq 'Revert') {

    Write-Host ""
    Write-Host "===== 2. 定位改动前的备份 =====" -ForegroundColor Cyan
    $cand = Get-ChildItem -Path $bakDir -Filter 'Machine-PATH-backup-*.txt' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    if (-not $cand) {
        Write-Host "中止：D:\Backups 下没有 Machine-PATH-backup-*.txt。" -ForegroundColor Red
        exit 1
    }
    $src = $cand[0]
    Write-Host ("  使用 -> $($src.FullName)  ($($src.LastWriteTime))")

    $orig = [System.IO.File]::ReadAllText($src.FullName)
    if ($orig -match 'BrechtSanders|MartinStorsjo') {
        Write-Host "中止：该备份里已经含 WinGet 条目，拒绝写入。" -ForegroundColor Red
        exit 1
    }
    if ($orig -notmatch 'mingw64') {
        Write-Host "中止：该备份不像是旧版 PATH，拒绝写入。" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "===== 3. 还原 =====" -ForegroundColor Cyan
    [Environment]::SetEnvironmentVariable('PATH', $orig, 'Machine')
    Write-Host "  Machine PATH 已还原" -ForegroundColor Green

} else {

    Write-Host ""
    Write-Host "===== 2. 切换到纯 ASCII 工具链 =====" -ForegroundColor Cyan
    $asciiBin  = 'D:\Toolchains\winlibs-16.1.0\bin'
    $asciiTemp = 'C:\Temp'

    if (-not (Test-Path -LiteralPath $asciiBin)) {
        Write-Host "中止：找不到 $asciiBin" -ForegroundColor Red
        Write-Host "      该副本已于 2026-09-29 删除。需先从 WinGet 包目录复制一份过去。" -ForegroundColor Yellow
        exit 1
    }
    if (-not (Test-Path -LiteralPath $asciiTemp)) {
        New-Item -ItemType Directory -Path $asciiTemp -Force | Out-Null
        Write-Host ("  已创建 $asciiTemp")
    }

    $entries = @($machinePath -split ';')
    $new = New-Object System.Collections.ArrayList
    $replaced = 0
    foreach ($e in $entries) {
        if ($e -match 'BrechtSanders\.WinLibs') {
            Write-Host ("  [$e]")
            Write-Host ("     -> $asciiBin")
            [void]$new.Add($asciiBin)
            $replaced++
        } else {
            [void]$new.Add($e)
        }
    }
    if ($replaced -ne 1) {
        Write-Host "中止：预期恰好 1 个 WinLibs 条目，实际找到 $replaced 个。未写入任何内容。" -ForegroundColor Red
        exit 1
    }
    if ($new.Count -ne $entries.Count) {
        Write-Host "中止：条目数不匹配。未写入任何内容。" -ForegroundColor Red
        exit 1
    }

    [Environment]::SetEnvironmentVariable('PATH', ($new -join ';'), 'Machine')
    Write-Host "  Machine PATH 已更新" -ForegroundColor Green

    Write-Host ""
    Write-Host "===== 3. 把用户 TEMP/TMP 移到 ASCII 路径 =====" -ForegroundColor Cyan
    Write-Host ("  原 TEMP = " + [Environment]::GetEnvironmentVariable('TEMP','User'))
    [Environment]::SetEnvironmentVariable('TEMP', $asciiTemp, 'User')
    [Environment]::SetEnvironmentVariable('TMP',  $asciiTemp, 'User')
    Write-Host ("  新 TEMP = $asciiTemp") -ForegroundColor Green
}

Write-Host ""
Write-Host "===== 4. 功能性编译测试 =====" -ForegroundColor Cyan
$m = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
$u = [Environment]::GetEnvironmentVariable('PATH', 'User')
$probePath = @($m -split ';') + @($u -split ';')

$gcc = $null
foreach ($d in $probePath) {
    if (-not $d) { continue }
    $cand = Join-Path $d 'gcc.exe'
    if (Test-Path -LiteralPath $cand) { $gcc = $cand; break }
}
if (-not $gcc) {
    Write-Host "  在新的 PATH 中找不到 gcc.exe" -ForegroundColor Yellow
} else {
    Write-Host ("  gcc -> $gcc")
    Write-Host ("  " + (& $gcc --version 2>&1 | Select-Object -First 1))

    $testDir = 'E:\Git\_pathfix-test'
    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    $cf = Join-Path $testDir 'h.c'
    [System.IO.File]::WriteAllText($cf, "#include <stdio.h>`r`nint main(void){printf(""COMPILE-OK %d.%d.%d\n"",__GNUC__,__GNUC_MINOR__,__GNUC_PATCHLEVEL__);return 0;}`r`n", [System.Text.Encoding]::ASCII)
    $exe = Join-Path $testDir 'h.exe'
    $out = & $gcc $cf -o $exe 2>&1
    if (Test-Path -LiteralPath $exe) {
        Write-Host ("  编译成功 -> " + (& $exe)) -ForegroundColor Green
    } else {
        Write-Host "  编译失败：" -ForegroundColor Red
        $out | Select-Object -First 4 | ForEach-Object { Write-Host ("    " + $_) }
    }
    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "完成。请开一个新终端让改动生效。" -ForegroundColor Green
Write-Host ("修复前的 PATH 备份：$curBak")
