#Requires -Version 7.0
# ==============================================================================
#  把 PowerShell 7 从 MSIX 应用包切换为官方 MSI 安装
#
#  用法（PowerShell 7）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\switch-pwsh-to-msi.ps1
#
#  本脚本【需要】管理员权限 —— 已在脚本内自动提权，无需手动开管理员终端。
#
#  为什么切换
#  ----------
#  winget 的 Microsoft.PowerShell 包【本身就是 MSIX 类型】（清单里安装器类型写死为
#  msix，指向 PowerShell-7.6.6.msixbundle），msstore 源里也没有该包。
#  MSIX 版的实际缺点：Windows Terminal 只检测 C:\Program Files\PowerShell\7\pwsh.exe，
#  因此 WT 里【不会出现 PowerShell 7 配置项】。
#
#  MSI 版则提供标准的 C:\Program Files\PowerShell\7 安装位置、系统级 PATH，
#  以及 WT 的自动识别。两者同样可由 winget / Microsoft Update 维护。
#
#  前置条件
#  ----------
#  本脚本假定【当前已有能用的 pwsh】（即 MSIX 版还在），因为它用
#  Start-Process pwsh -Verb RunAs 提权，且自身含中文需要 PS 7 解析。
#  若 MSIX 已被卸载而 MSI 尚未安装，请直接手动执行：
#      msiexec /i "E:\Git\_pwsh-msi\PowerShell-7.6.6-win-x64.msi" /qn /norestart ADD_PATH=1 REGISTER_MANIFEST=1
#
#  安全校验
#  ----------
#  MSI 若来自第三方镜像（gh-proxy 等），安装前必须校验 Authenticode 签名。
#  签名有效且主体为 Microsoft Corporation 即可确认内容未被篡改。
#
#  安装参数说明
#  ----------
#      ADD_PATH=1              把 PowerShell 加入系统 PATH
#      REGISTER_MANIFEST=1     注册 Windows 事件日志清单
#      /qn                     静默安装
#      /norestart              不自动重启
# ==============================================================================

param(
    [string]$MsiPath = 'E:\Git\_pwsh-msi\PowerShell-7.6.6-win-x64.msi'
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- 自动提权
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "本脚本需要管理员权限，正在请求提权（请在 UAC 窗口点『是』）..." -ForegroundColor Yellow
    Start-Process -FilePath 'pwsh' -Verb RunAs -Wait -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"",
        '-MsiPath', "`"$MsiPath`""
    )
    exit
}

Write-Host "===== 0. 预检 =====" -ForegroundColor Cyan
Write-Host "  管理员权限 : 是"
Write-Host "  MSI 路径   : $MsiPath"

# ---------------------------------------------------------------- 1. 校验 MSI
Write-Host ""
Write-Host "===== 1. 校验 MSI 存在性与签名 =====" -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $MsiPath)) {
    Write-Host "  中止：找不到 MSI 文件。" -ForegroundColor Red
    exit 1
}
$fi = Get-Item -LiteralPath $MsiPath
Write-Host ("  大小   : $([math]::Round($fi.Length/1MB,2)) MB")

$sig = Get-AuthenticodeSignature -LiteralPath $MsiPath
Write-Host ("  签名   : $($sig.Status)")
if ($sig.SignerCertificate) { Write-Host ("  签名者 : $($sig.SignerCertificate.Subject)") }
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
    Write-Host "  中止：签名无效或签名者不是 Microsoft Corporation，拒绝安装。" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ 签名校验通过" -ForegroundColor Green

# ---------------------------------------------------------------- 2. 卸 MSIX
Write-Host ""
Write-Host "===== 2. 卸载 MSIX 版 =====" -ForegroundColor Cyan
$pkg = Get-AppxPackage -Name 'Microsoft.PowerShell' -ErrorAction SilentlyContinue
if ($pkg) {
    Write-Host ("  当前：$($pkg.PackageFullName)")

    # 注意：不能无差别 Stop-Process pwsh —— 本脚本自身就跑在 pwsh 里，
    # 提权链上还有一个等待中的父 pwsh 进程。必须排除它们。
    $selfPid   = $PID
    $parentPid = (Get-CimInstance Win32_Process -Filter "ProcessId = $selfPid" -ErrorAction SilentlyContinue).ParentProcessId

    function Stop-OtherPwsh {
        $others = Get-Process pwsh -ErrorAction SilentlyContinue |
                  Where-Object { $_.Id -ne $selfPid -and $_.Id -ne $parentPid }
        if ($others) {
            Write-Host ("  结束其它 pwsh 进程：" + (($others | ForEach-Object { $_.Id }) -join ', ')) -ForegroundColor Yellow
            $others | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        } else {
            Write-Host "  没有其它 pwsh 进程"
        }
    }

    # 第一轮：先直接尝试卸载
    try { Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop } catch {
        Write-Host ("  首次卸载报错：$($_.Exception.Message)") -ForegroundColor Yellow
    }
    Start-Sleep -Seconds 3

    # 若仍存在，结束其它 pwsh 后重试
    if (Get-AppxPackage -Name 'Microsoft.PowerShell' -ErrorAction SilentlyContinue) {
        Write-Host "  仍存在，结束其它 pwsh 进程后重试 ..." -ForegroundColor Yellow
        Stop-OtherPwsh
        try { Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop } catch {
            Write-Host ("  重试仍失败：$($_.Exception.Message)") -ForegroundColor Red
        }
        Start-Sleep -Seconds 3
    }

    $final = Get-AppxPackage -Name 'Microsoft.PowerShell' -ErrorAction SilentlyContinue
    if ($final) {
        Write-Host "  ✗ MSIX 仍然存在：$($final.PackageFullName)" -ForegroundColor Red
        Write-Host "    建议：手动在「设置 > 应用」里卸载 PowerShell，或重启后重跑本脚本。" -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "  ✓ MSIX 已卸载" -ForegroundColor Green
    }
} else {
    Write-Host "  未发现 MSIX 版（可能已切换过）"
}

# ---------------------------------------------------------------- 3. 装 MSI
Write-Host ""
Write-Host "===== 3. 安装 MSI 版 =====" -ForegroundColor Cyan
$args = @('/i', "`"$MsiPath`"", '/qn', '/norestart', 'ADD_PATH=1', 'REGISTER_MANIFEST=1')
Write-Host ("  正在运行：msiexec " + ($args -join ' '))
$p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru
Write-Host ("  msiexec 退出码：$($p.ExitCode)   （0=成功，3010=成功但需重启，1603=致命错误）") -ForegroundColor $(
    if ($p.ExitCode -in @(0,3010)) { 'Green' } else { 'Red' })

# ---------------------------------------------------------------- 4. 验证
Write-Host ""
Write-Host "===== 4. 验证 =====" -ForegroundColor Cyan
$exe = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
Write-Host ("  安装路径 $exe 存在？$(Test-Path -LiteralPath $exe)") -ForegroundColor $(if (Test-Path -LiteralPath $exe) { 'Green' } else { 'Red' })

if (Test-Path -LiteralPath $exe) {
    $v = (Get-Item -LiteralPath $exe).VersionInfo
    Write-Host ("  文件版本 : $($v.FileVersion)")
    Write-Host ("  产品     : $($v.ProductName)")
    Write-Host "  实际运行 :"
    & $exe -NoProfile -Command "Write-Host ('    PSVersion = ' + `$PSVersionTable.PSVersion); Write-Host ('    PSEdition = ' + `$PSVersionTable.PSEdition); Write-Host ('    PSHOME    = ' + `$PSHOME)"
}

Write-Host ""
Write-Host "  --- 系统 PATH 中的 PowerShell 条目 ---"
$m = [Environment]::GetEnvironmentVariable('PATH','Machine')
$u = [Environment]::GetEnvironmentVariable('PATH','User')
foreach ($e in (($m + ';' + $u) -split ';')) {
    if ($e -match 'PowerShell') { Write-Host ("    $e") }
}

Write-Host ""
Write-Host "  --- Windows Terminal 是否能识别（关键）---"
$wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
Write-Host "    WT 动态 profile 依赖 C:\Program Files\PowerShell\7\pwsh.exe 是否存在"
Write-Host ("    该文件现在存在：$(Test-Path -LiteralPath $exe)  →  重启 Windows Terminal 后应出现 PowerShell 7 配置项") -ForegroundColor Green

Write-Host ""
Write-Host "  --- 清理 MSIX 遗留的别名 ---"
$alias = "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe"
if (Test-Path -LiteralPath $alias) {
    Write-Host "    别名仍存在：$alias" -ForegroundColor Yellow
    $t = (Get-Item -LiteralPath $alias -Force -ErrorAction SilentlyContinue).Target
    Write-Host "    （这是 WindowsApps 的应用执行别名，MSIX 卸载后通常会自行消失）"
} else {
    Write-Host "    别名已消失（正常）" -ForegroundColor Green
}

Write-Host ""
Write-Host "===== 5. 收尾 =====" -ForegroundColor Cyan
Write-Host "  · 请【关闭并重开】Windows Terminal，然后检查标签页菜单里是否出现 PowerShell 7"
Write-Host "  · 在【新】终端里验证：pwsh -v"
Write-Host "  · MSI 文件保留在 $MsiPath（约 112 MB），确认无误后可删除"
if ($p.ExitCode -eq 3010) {
    Write-Host "  · msiexec 返回 3010，建议重启一次" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "完成。" -ForegroundColor Green
