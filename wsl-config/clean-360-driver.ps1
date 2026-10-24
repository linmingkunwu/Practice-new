#Requires -Version 7.0
# ==============================================================================
#  清理最后残留的 360 驱动文件
#
#  用法（PowerShell 7）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\clean-360-driver.ps1
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\clean-360-driver.ps1 -EPagefileMB 16384
#
#  本脚本【需要】管理员权限 —— 已在脚本内自动提权，无需手动开管理员终端。
#
#  背景
#  重启后 360 已彻底清除：内存中无驱动、D:\wukong 已空、注册表 0 个子键、
#  无服务引用。但有一个文件残留：
#
#      C:\Windows\System32\drivers\360AvFlt.sys   98.2 KB
#      版本信息：产品="360杀毒"  公司=360.cn  版本=1.1.0.1078
#
#  注意这是【360杀毒】的驱动，与已卸载的「悟空」是不同的产品。
#  无任何服务引用、也不在待删列表中，属于纯孤儿文件。
#  独占打开被拒（通常是 ACL 拒绝写入），因此先取得所有权再删除。
#
#  可选参数 -EPagefileMB
#  E 盘分页文件当前是「系统托管」，Windows 按物理内存 31.2 GB 分配了 36864 MB，
#  而实测峰值仅约 1.2 GB。传 -EPagefileMB 可改为固定大小并回收差额。
#  注意 2026-09-29 的决定是【保持系统托管不变】，此参数仅在日后 E 盘吃紧时使用。
# ==============================================================================

param(
    [int]$EPagefileMB = 0
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- 自动提权
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "本脚本需要管理员权限，正在请求提权（请在 UAC 窗口点『是』）..." -ForegroundColor Yellow
    Start-Process -FilePath 'pwsh' -Verb RunAs -Wait -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"",
        '-EPagefileMB', "$EPagefileMB"
    )
    exit
}

Write-Host "===== 0. 预检 =====" -ForegroundColor Cyan
Write-Host "  管理员权限 : 是"
if ($EPagefileMB -gt 0) {
    Write-Host ("  E 盘分页文件目标 : 固定 $EPagefileMB MB")
} else {
    Write-Host "  E 盘分页文件     : 保持不变"
}

# ------------------------------------------------------------------ 1. 驱动文件
Write-Host ""
Write-Host "===== 1. 孤儿驱动 360AvFlt.sys =====" -ForegroundColor Cyan
$drv = 'C:\Windows\System32\drivers\360AvFlt.sys'
if (Test-Path -LiteralPath $drv) {
    $i = Get-Item -LiteralPath $drv -Force
    Write-Host ("  存在：$($i.Length) 字节，修改于 $($i.LastWriteTime)")
    Write-Host ("  版本：$($i.VersionInfo.ProductName) / $($i.VersionInfo.CompanyName) / $($i.VersionInfo.FileVersion)")

    $holder = Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue |
              Where-Object { $_.PathName -match '360AvFlt' }
    if ($holder) {
        foreach ($h in $holder) { Write-Host ("  警告：仍被驱动对象引用 $($h.Name)  状态=$($h.State)") -ForegroundColor Yellow }
    } else {
        Write-Host "  无驱动对象引用它"
    }

    # 取得所有权 → 授权 → 删除
    Write-Host "  正在取得所有权 ..."
    & takeown.exe /F $drv /A 2>&1 | ForEach-Object { Write-Host ("    " + $_) }
    Write-Host "  正在授权 ..."
    & icacls.exe $drv /grant "*S-1-5-32-544:F" 2>&1 | ForEach-Object { Write-Host ("    " + $_) }

    Remove-Item -LiteralPath $drv -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $drv) {
        Write-Host "  仍存在 —— 已排入下次重启时删除" -ForegroundColor Yellow
        $smKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
        $cur = @((Get-ItemProperty -Path $smKey -ErrorAction SilentlyContinue).PendingFileRenameOperations)
        $cur += "\??\$drv"
        $cur += ''
        Set-ItemProperty -Path $smKey -Name 'PendingFileRenameOperations' -Value ([string[]]$cur) -Type MultiString
        Write-Host "  已加入 PendingFileRenameOperations"
    } else {
        Write-Host "  已删除" -ForegroundColor Green
    }
} else {
    Write-Host "  本就不存在（已清理过）" -ForegroundColor Green
}

# ------------------------------------------------------------------ 2. 分页文件
Write-Host ""
Write-Host "===== 2. 分页文件 =====" -ForegroundColor Cyan
$mm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
Write-Host "  当前 PagingFiles："
((Get-ItemProperty -Path $mm -ErrorAction SilentlyContinue).PagingFiles) | ForEach-Object { Write-Host ("    " + $_) }
Write-Host "  实际分配："
Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host ("    $($_.Name)  $($_.AllocatedBaseSize) MB   峰值 $($_.PeakUsage) MB") }

if ($EPagefileMB -gt 0) {
    Write-Host ""
    Write-Host ("  正在把 E:\pagefile.sys 设为固定 $EPagefileMB MB")
    $vals = @('C:\pagefile.sys 4096 4096', ('E:\pagefile.sys ' + $EPagefileMB + ' ' + $EPagefileMB))
    Set-ItemProperty -Path $mm -Name 'PagingFiles' -Value ([string[]]$vals) -Type MultiString
    Write-Host "  新的 PagingFiles："
    ((Get-ItemProperty -Path $mm -ErrorAction SilentlyContinue).PagingFiles) | ForEach-Object { Write-Host ("    " + $_) }
    Write-Host ""
    Write-Host "  【需要重启】生效，同时会在启动时释放 E 盘的差额空间。" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "  未改动。如需改为固定大小，重跑并加 -EPagefileMB <数值>，例如："
    Write-Host "    pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\clean-360-driver.ps1 -EPagefileMB 16384"
}

Write-Host ""
Write-Host "完成。" -ForegroundColor Green
