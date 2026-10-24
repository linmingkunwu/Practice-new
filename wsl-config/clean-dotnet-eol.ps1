#Requires -Version 7.0
# ==============================================================================
#  移除已停止支持（EOL）的 .NET 运行时
#
#  用法（PowerShell 7）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\clean-dotnet-eol.ps1
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\clean-dotnet-eol.ps1 -DryRun
#
#  本脚本【需要】管理员权限 —— 已在脚本内自动提权。
#
#  为什么做这件事
#  ------------------------------------------
#  .NET Core 3.1 于 2022-12 停止支持，6.0 于 2024-11，7.0 于 2025-05，9.0 于 2026-05。
#  已停止支持意味着不再有安全修复。本机同时装着 3.1 / 6.0 / 7.0 / 8.0 / 9.0 / 10.0
#  六个大版本，其中除 8.0（LTS，支持到 2026-11）与 10.0（当前 LTS）外全部 EOL。
#
#  处理范围
#  ------------------------------------------
#  删除：3.1.x / 6.0.x / 7.0.x / 9.0.x 的
#        .NET Runtime、Windows Desktop Runtime、Host、Host FX Resolver
#  保留：8.0.x 与 10.0.x（全部）
#        以及任何 Targeting Pack / SDK / Templates / Manifest
#
#  ⚠️ 风险
#  ------------------------------------------
#  若某个应用被配置为必须在这些特定运行时版本上运行（如 runtimeconfig.json 里
#  写死了 6.0.36），卸载后该应用会启动失败。.NET 的滚动前进机制通常会让
#  6.0.x 的应用自动跑在更高的 6.0.x 上，但大版本之间不通用。
#  如果之后发现某软件打不开，从其安装包重装对应运行时即可恢复。
#
#  卸载策略：只卸 bundle，让安装器自己处理内部 MSI
#  ------------------------------------------
#  .NET 安装器是 WiX Burn 结构，同一版本会注册两个卸载入口：
#      Bundle : "C:\ProgramData\Package Cache\{GUID}\xxx.exe" /uninstall
#      MSI    : MsiExec.exe /X{GUID}
#  单独卸 MSI 会留下孤儿 bundle 条目，所以优先只卸 bundle。
#  对于只有 MSI 条目的（如 3.1.9 的 Host），再单独处理。
#
#  日志：D:\Backups\dotnet-eol-cleanup.log
# ==============================================================================

param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'

$logFile = 'D:\Backups\dotnet-eol-cleanup.log'
$eolPattern = '^(24\.100|48\.144|56\.44|72\.68|3\.1\.9|6\.0\.36|7\.0\.11|9\.0\.17)'
$namePattern = 'Microsoft (\.NET Core Runtime|\.NET Runtime|Windows Desktop Runtime|\.NET Core Host|\.NET Host|\.NET Core Host FX Resolver|\.NET Host FX Resolver)'

function W([string]$m) {
    $ts = Get-Date -Format 'HH:mm:ss'
    "[$ts] $m" | Tee-Object -FilePath $logFile -Append
}

# ---------------------------------------------------------------- 自动提权
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "本脚本需要管理员权限，正在请求提权（请在 UAC 窗口点『是』）..." -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($DryRun) { $argList += '-DryRun' }
    Start-Process -FilePath 'pwsh' -Verb RunAs -Wait -ArgumentList $argList
    exit
}

New-Item -ItemType Directory -Path (Split-Path $logFile -Parent) -Force -ErrorAction SilentlyContinue | Out-Null
"==================== .NET EOL 运行时清理 ====================" | Set-Content $logFile -Encoding UTF8

W ("管理员   : 是")
W ("模式     : " + $(if ($DryRun) { '预演' } else { '实际执行' }))
W ""

# ---------------------------------------------------------------- 前置检查
W "---- 前置检查：是否有 dotnet 进程在运行 ----"
$running = Get-Process -Name 'dotnet' -ErrorAction SilentlyContinue
if ($running) {
    W ("  发现 " + $running.Count + " 个 dotnet 进程，先结束它们以避免文件占用")
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
} else {
    W "  无 dotnet 进程"
}
W ""

# ---------------------------------------------------------------- 记录基线
W "---- 基线 ----"
$dirs = @('C:\Program Files\dotnet', 'C:\Program Files (x86)\dotnet')
foreach ($d in $dirs) {
    if (Test-Path $d) {
        $s = (Get-ChildItem $d -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        W ("  " + $d + "  " + [math]::Round($s/1MB,0) + " MB")
    }
}
$freeBefore = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace
W ("  C 盘可用: " + [math]::Round($freeBefore/1GB,2) + " GB")
W ""

# ---------------------------------------------------------------- 枚举
W "---- 枚举 EOL 卸载入口 ----"
$rows = @()
foreach ($h in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
    Get-ChildItem $h -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($p.DisplayName -and $p.DisplayVersion -and
            $p.DisplayName -match $namePattern -and $p.DisplayVersion -match $eolPattern) {
            $u = if ($p.QuietUninstallString) { $p.QuietUninstallString } else { $p.UninstallString }
            if ($u) {
                $rows += [PSCustomObject]@{
                    Name = $p.DisplayName
                    Ver  = $p.DisplayVersion
                    Kind = $(if ($u -match 'MsiExec') { 'MSI' } else { 'Bundle' })
                    Cmd  = $u
                }
            }
        }
    }
}
$bundles = @($rows | Where-Object Kind -eq 'Bundle' | Sort-Object Name)
$msis    = @($rows | Where-Object Kind -eq 'MSI'    | Sort-Object Name)

W ("  Bundle 类型: " + $bundles.Count + " 项")
foreach ($b in $bundles) { W ("    " + $b.Name.PadRight(58) + " " + $b.Ver) }
W ("  MSI 类型   : " + $msis.Count + " 项")
foreach ($m in $msis) { W ("    " + $m.Name.PadRight(58) + " " + $m.Ver) }
W ""

if ($rows.Count -eq 0) {
    W "没有找到符合条件的 EOL 运行时，无需操作。"
    W "DONE"
    return
}

if ($DryRun) {
    W "预演模式，未执行任何卸载。"
    W "DONE"
    return
}

# ---------------------------------------------------------------- 卸载
W "---- 开始卸载 ----"
$okCount = 0
$failCount = 0

# 先卸 bundle（会连带移除内部 MSI）
foreach ($b in $bundles) {
    W ("  [Bundle] " + $b.Name)
    $exe = $null
    if ($b.Cmd -match '^"([^"]+)"') { $exe = $Matches[1] }
    elseif ($b.Cmd -match '^(\S+\.exe)') { $exe = $Matches[1] }
    if ($exe -and (Test-Path -LiteralPath $exe)) {
        $p = Start-Process -FilePath $exe -ArgumentList '/uninstall', '/quiet', '/norestart' -Wait -PassThru
        W ("    退出码 " + $p.ExitCode + $(if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 1605) { '  -> 成功' } else { '  -> 需检查' }))
        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 1605) { $okCount++ } else { $failCount++ }
    } else {
        W ("    找不到卸载程序: " + $exe + "  -> 跳过")
        $failCount++
    }
    Start-Sleep -Milliseconds 500
}

# 再处理只剩 MSI 条目的
foreach ($m in $msis) {
    $guid = $null
    if ($m.Cmd -match '\{[0-9A-Fa-f\-]+\}') { $guid = $Matches[0] }
    if (-not $guid) { W ("  [MSI] 无法解析 GUID: " + $m.Name); continue }
    W ("  [MSI] " + $m.Name)
    $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList '/X', $guid, '/qn', '/norestart' -Wait -PassThru
    W ("    退出码 " + $p.ExitCode + $(if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 1605) { '  -> 成功' } else { '  -> 需检查' }))
    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 1605) { $okCount++ } else { $failCount++ }
    Start-Sleep -Milliseconds 500
}

W ""
W ("卸载结果: 成功 " + $okCount + " 项，异常 " + $failCount + " 项")

# ---------------------------------------------------------------- 验证
Start-Sleep -Seconds 2
W ""
W "---- 验证 ----"
W "  x64 运行时:"
& dotnet --list-runtimes 2>&1 | ForEach-Object { W ("    " + $_) }
$d86 = 'C:\Program Files (x86)\dotnet\dotnet.exe'
if (Test-Path $d86) {
    W "  x86 运行时:"
    & $d86 --list-runtimes 2>&1 | ForEach-Object { W ("    " + $_) }
}

W ""
W "  目录大小:"
foreach ($d in $dirs) {
    if (Test-Path $d) {
        $s = (Get-ChildItem $d -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        W ("    " + $d.PadRight(36) + " " + [math]::Round($s/1MB,0) + " MB")
    }
}
$freeAfter = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace
W ("  C 盘可用: " + [math]::Round($freeAfter/1GB,2) + " GB")
W ("  本次释放: " + [math]::Round(($freeAfter-$freeBefore)/1MB,0) + " MB")

W ""
W "---- 残留的 EOL 条目 ----"
$remain = @()
foreach ($h in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
    Get-ChildItem $h -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($p.DisplayName -and $p.DisplayVersion -and
            $p.DisplayName -match $namePattern -and $p.DisplayVersion -match $eolPattern) {
            $remain += ($p.DisplayName + "  " + $p.DisplayVersion)
        }
    }
}
if ($remain.Count -eq 0) { W "  无残留 ✓" } else { $remain | Sort-Object -Unique | ForEach-Object { W ("  " + $_) } }

W ""
W "DONE"
