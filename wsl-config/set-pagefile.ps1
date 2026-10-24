#Requires -Version 7.0
# ==============================================================================
#  把分页文件迁移到 E 盘
#
#  用法（PowerShell 7）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\set-pagefile.ps1
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\set-pagefile.ps1 -CKeepMB 0
#
#  本脚本【需要】管理员权限 —— 已在脚本内自动提权，无需手动开管理员终端。
#
#  实测硬件拓扑（这是迁移能带来收益的依据）
#      Disk 0 — Samsung SSD 990 EVO Plus 2TB，NVMe  →  E:
#      Disk 1 — CT1000E100SSD8，NVMe                →  C: 和 D:
#
#  C: 与 D: 位于同一块物理盘，两个分页文件争抢同一设备的 I/O；
#  E: 是独立且更快的 NVMe SSD。迁移是把页面文件 I/O 分流到第二个物理设备，
#  不是纯粹的取舍。
#
#  迁移前
#      C:\pagefile.sys  16405 MB  （系统托管）
#      D:\pagefile.sys   5120 MB  （系统托管）
#      E:\pagefile.sys   5120 MB  （系统托管）
#
#  迁移后（默认 -CKeepMB 4096）
#      C:\pagefile.sys   4096 MB  固定    （保留内核崩溃转储能力）
#      E:\pagefile.sys   系统托管
#      D:\pagefile.sys   已移除
#
#  为什么 C 盘留一个小的
#      Windows 只能把内核内存转储写入引导卷上的分页文件。完全移除 C 盘分页文件
#      会失去 BSOD 转储能力。若不介意，用 -CKeepMB 0 再多省 4 GB。
#
#  需要重启生效。旧的分页文件在下次启动时删除。
# ==============================================================================

param(
    [int]$CKeepMB = 4096
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- 自动提权
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "本脚本需要管理员权限，正在请求提权（请在 UAC 窗口点『是』）..." -ForegroundColor Yellow
    Start-Process -FilePath 'pwsh' -Verb RunAs -Wait -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"",
        '-CKeepMB', "$CKeepMB"
    )
    exit
}

Write-Host "===== 0. 预检 =====" -ForegroundColor Cyan
Write-Host "  管理员权限 : 是"
Write-Host ("  C 盘保留   : $CKeepMB MB")

Write-Host ""
Write-Host "===== 1. 当前配置 =====" -ForegroundColor Cyan
$cs = Get-CimInstance -ClassName Win32_ComputerSystem
Write-Host ("  自动管理分页文件 : " + $cs.AutomaticManagedPagefile)
Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue |
    ForEach-Object {
        Write-Host ("    " + $_.Name + "  初始=" + $_.InitialSize + "  最大=" + $_.MaximumSize)
    }
Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction SilentlyContinue |
    ForEach-Object {
        Write-Host ("    实际在用：" + $_.Name + "  已分配=" + $_.AllocatedBaseSize + " MB  峰值=" + $_.PeakUsage + " MB")
    }

Write-Host ""
Write-Host "===== 2. 确认 E 盘空间充足 =====" -ForegroundColor Cyan
$e = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='E:'"
Write-Host ("  E 盘可用 = " + [math]::Round($e.FreeSpace/1GB,1) + " GB")
if ($e.FreeSpace -lt 20GB) {
    Write-Host "中止：E 盘可用空间不足 20 GB。" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "===== 3. 关闭自动管理 =====" -ForegroundColor Cyan
if ($cs.AutomaticManagedPagefile) {
    Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false }
    Write-Host "  已设为 False"
} else {
    Write-Host "  本来就是 False"
}

Write-Host ""
Write-Host "===== 4. 移除现有分页文件条目 =====" -ForegroundColor Cyan
Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue |
    ForEach-Object {
        Write-Host ("  正在移除 " + $_.Name)
        Remove-CimInstance -InputObject $_
    }

Write-Host ""
Write-Host "===== 5. 创建新条目 =====" -ForegroundColor Cyan

# Win32_PageFileSetting 的 InitialSize / MaximumSize 是 uint32。传 PowerShell 的
# [int] 会报"类型不匹配"；而第 4 步已经删除了旧条目，一旦这里失败，
# 机器就会处于【完全没有分页文件配置】的危险状态。所以必须显式转型。
function Add-PageFileEntry {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][uint32]$Initial,
        [Parameter(Mandatory=$true)][uint32]$Maximum
    )
    try {
        New-CimInstance -ClassName Win32_PageFileSetting -Property @{
            Name        = $Path
            InitialSize = $Initial
            MaximumSize = $Maximum
        } -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Host ("    WMI 方式失败（" + $_.Exception.Message + "），改用注册表回退") -ForegroundColor Yellow
        return $false
    }
}

$wmiOk = $true
if ($CKeepMB -gt 0) {
    $u = [uint32]$CKeepMB
    if (Add-PageFileEntry -Path 'C:\pagefile.sys' -Initial $u -Maximum $u) {
        Write-Host ("  已添加 C:\pagefile.sys  固定 " + $CKeepMB + " MB")
    } else { $wmiOk = $false }
} else {
    Write-Host "  按要求跳过 C 盘分页文件（-CKeepMB 0）"
}

# InitialSize/MaximumSize = 0 表示该文件由系统托管
if (Add-PageFileEntry -Path 'E:\pagefile.sys' -Initial ([uint32]0) -Maximum ([uint32]0)) {
    Write-Host "  已添加 E:\pagefile.sys  系统托管"
} else { $wmiOk = $false }

# --- 注册表回退 / 权威校验 ---------------------------------------------------
$mmKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
if (-not $wmiOk) {
    Write-Host "  直接写入注册表 PagingFiles"
    $vals = @()
    if ($CKeepMB -gt 0) { $vals += ('C:\pagefile.sys ' + $CKeepMB + ' ' + $CKeepMB) }
    $vals += 'E:\pagefile.sys 0 0'
    Set-ItemProperty -Path $mmKey -Name 'PagingFiles' -Value ([string[]]$vals) -Type MultiString
    Write-Host ("    PagingFiles = " + ($vals -join ' | '))
}

Write-Host ""
Write-Host "  --- 权威校验：注册表 PagingFiles ---"
$pf = (Get-ItemProperty -Path $mmKey -ErrorAction SilentlyContinue).PagingFiles
if ($pf) { $pf | ForEach-Object { Write-Host ("    " + $_) } }
else { Write-Host "    （为空 —— 这会让机器完全没有分页文件！）" -ForegroundColor Red }

Write-Host ""
Write-Host "===== 6. 复核 =====" -ForegroundColor Cyan
$cs2 = Get-CimInstance -ClassName Win32_ComputerSystem
Write-Host ("  自动管理分页文件 : " + $cs2.AutomaticManagedPagefile)
Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue |
    ForEach-Object {
        $mode = '系统托管'
        if ($_.InitialSize -gt 0) { $mode = '固定 ' + $_.InitialSize + ' MB' }
        Write-Host ("    " + $_.Name + "   " + $mode)
    }

Write-Host ""
Write-Host "===== 7. 后续步骤 =====" -ForegroundColor Cyan
Write-Host "  注册表已更新，【需要重启】才生效。" -ForegroundColor Yellow
Write-Host "  下次启动时 Windows 会删除 D:\pagefile.sys 与 E 盘旧分页文件，"
Write-Host "  调整 C:\pagefile.sys 大小，并在 E 盘创建新的。"
Write-Host ""
if ($CKeepMB -gt 0) {
    Write-Host ("  预计回收：C 盘 " + [math]::Round((16405-$CKeepMB)/1024,1) + " GB，D 盘 5.0 GB")
} else {
    Write-Host "  预计回收：C 盘 16.0 GB，D 盘 5.0 GB"
}
Write-Host ""
Write-Host "完成。" -ForegroundColor Green
