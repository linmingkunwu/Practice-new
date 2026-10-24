#Requires -Version 7.0
# ==============================================================================
#  切换 C:\mingw64 这个 junction 的指向，从而切换默认 gcc 版本
#
#  用法（PowerShell 7）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\switch-mingw-toolchain.ps1
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\switch-mingw-toolchain.ps1 -Revert
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\switch-mingw-toolchain.ps1 -Target 'D:\Toolchains\mingw64'
#
#  本脚本【需要】管理员权限 —— 已在脚本内自动提权（在 C:\ 根目录创建 junction 需要提升）。
#
#  设计要点：为什么改 junction 而不是改 PATH
#  ------------------------------------------
#  Machine PATH 里已有条目 C:\mingw64\bin（索引 12）。C:\mingw64 是一个 junction，
#  指向真实的工具链目录。因此切换版本只需重指 junction：
#
#      · PATH 一个字都不用改        -> 零风险，不会误伤 PATH
#      · 操作可逆                   -> -Revert 一条命令还原
#      · 路径保持纯 ASCII           -> C:\mingw64 永远是 ASCII
#
#  背景（2026-09-30）
#  ------------------------------------------
#  上游问题：WinLibs 系（Brecht Sanders 构建）的 gcc【全系】无法处理含非 ASCII 的
#  TEMP 路径。实测（均在默认中文 TEMP 下）：
#
#      MinGW-Builds 15.2.0                -> C 与 C++ 均成功
#      WinLibs r8 / Strawberry 13.2.0     -> 失败（can't create .o）
#      WinLibs r1 / WinGet 16.1.0         -> 失败（can't create .o）
#
#  改用 MinGW-Builds 的新构建后，gcc 16.2.0 在中文 TEMP 下同样正常，
#  因此【无需修改全局 TEMP】，只升级工具链版本即可。
#
#  变体一致性：新旧都是 x86_64-win32-seh-UCRT（线程模型 win32 / 异常 SEH /
#  运行时 UCRT），因此只变 gcc 版本，二进制依赖不变。
# ==============================================================================

param(
    [string]$Target = 'D:\Toolchains\mingw64-16.2.0\mingw64',
    [switch]$Revert
)

$ErrorActionPreference = 'Stop'

$linkPath     = 'C:\mingw64'
$oldTarget    = 'D:\Toolchains\mingw64'
if ($Revert) { $Target = $oldTarget }

# ---------------------------------------------------------------- 自动提权
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "本脚本需要管理员权限（在 C:\ 根创建 junction），正在请求提权（请在 UAC 窗口点『是』）..." -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Target', "`"$Target`"")
    if ($Revert) { $argList += '-Revert' }
    Start-Process -FilePath 'pwsh' -Verb RunAs -Wait -ArgumentList $argList
    exit
}

Write-Host "===== 0. 预检 =====" -ForegroundColor Cyan
Write-Host "  管理员权限 : 是"
Write-Host "  链接路径   : $linkPath"
Write-Host "  目标路径   : $Target"
if ($Revert) { Write-Host "  模式       : 回退到旧工具链" -ForegroundColor Yellow }

Write-Host ""
Write-Host "===== 1. 校验目标工具链 =====" -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Target)) {
    Write-Host "中止：目标路径不存在：$Target" -ForegroundColor Red
    exit 1
}
$gccNew = Join-Path $Target 'bin\gcc.exe'
if (-not (Test-Path -LiteralPath $gccNew)) {
    Write-Host "中止：目标下找不到 bin\gcc.exe" -ForegroundColor Red
    exit 1
}
$verNew = (& $gccNew --version 2>&1 | Select-Object -First 1)
Write-Host "  新工具链 gcc : $verNew"
Write-Host ("  路径含非ASCII: " + ($Target -match '[^\x00-\x7F]'))
if ($Target -match '[^\x00-\x7F]') {
    Write-Host "  警告：目标路径含非 ASCII 字符，MinGW-Builds 虽然能处理 TEMP 的中文，" -ForegroundColor Yellow
    Write-Host "        但为稳妥起见仍建议用纯 ASCII 路径。" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "===== 2. 记录当前状态（用于回滚）=====" -ForegroundColor Cyan
$cur = Get-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
if ($cur) {
    Write-Host ("  当前类型 : " + $cur.LinkType)
    Write-Host ("  当前目标 : " + ($cur.Target -join ', '))
} else {
    Write-Host "  $linkPath 不存在" -ForegroundColor Yellow
}
$curGcc = Join-Path $linkPath 'bin\gcc.exe'
if (Test-Path -LiteralPath $curGcc) {
    Write-Host ("  当前 gcc : " + ((& $curGcc --version 2>&1) | Select-Object -First 1))
}

Write-Host ""
Write-Host "===== 3. 切换 junction =====" -ForegroundColor Cyan
if ($cur) {
    Write-Host "  删除旧 junction（只删链接，不动目标目录）..."
    # cmd 的 rmdir 对 junction 只移除链接本身，不会递归删除目标内容
    $r = & cmd.exe /c rmdir "$linkPath" 2>&1
    if ($r) { $r | ForEach-Object { Write-Host ("    " + $_) } }
    if (Test-Path -LiteralPath $linkPath) {
        Write-Host "  中止：无法移除旧 junction。" -ForegroundColor Red
        exit 1
    }
    Write-Host "  已移除"
}
$r2 = & cmd.exe /c mklink /J "$linkPath" "$Target" 2>&1
$r2 | ForEach-Object { Write-Host ("  " + $_) }
if (-not (Test-Path -LiteralPath $linkPath)) {
    Write-Host "  中止：junction 创建失败。" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "===== 4. 验证 =====" -ForegroundColor Cyan
$after = Get-Item -LiteralPath $linkPath -Force
Write-Host ("  新目标 : " + ($after.Target -join ', '))
$gccAfter = Join-Path $linkPath 'bin\gcc.exe'
if (Test-Path -LiteralPath $gccAfter) {
    Write-Host ("  gcc    : " + ((& $gccAfter --version 2>&1) | Select-Object -First 1)) -ForegroundColor Green
}

Write-Host ""
Write-Host "  --- 经 C:\mingw64 实际编译测试（中文 TEMP）---"
$testDir = 'E:\Git\_switchverify'
Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
Set-Content (Join-Path $testDir 'v.c') @'
#include <stdio.h>
int main(void){ printf("switch OK gcc %d.%d.%d\n", __GNUC__,__GNUC_MINOR__,__GNUC_PATCHLEVEL__); return 0; }
'@ -Encoding ASCII
$exe = Join-Path $testDir 'v.exe'
$null = & $gccAfter (Join-Path $testDir 'v.c') -o $exe 2>&1
if (Test-Path -LiteralPath $exe) {
    Write-Host ("  ✅ " + (& $exe)) -ForegroundColor Green
} else {
    Write-Host "  ❌ 编译失败" -ForegroundColor Red
}
Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "===== 5. 回滚方式 =====" -ForegroundColor Cyan
Write-Host "  pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\switch-mingw-toolchain.ps1 -Revert"
Write-Host "  （旧工具链仍保留在 $oldTarget）"

Write-Host ""
Write-Host "完成。请开【新终端】让 PATH 缓存刷新。" -ForegroundColor Green
