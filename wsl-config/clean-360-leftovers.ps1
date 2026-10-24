#Requires -Version 7.0
# ==============================================================================
#  清理 360 遗留的注册表与服务项
#
#  用法（PowerShell 7）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\clean-360-leftovers.ps1
#
#  本脚本【需要】管理员权限 —— 已在脚本内自动提权，无需手动开管理员终端。
#
#  背景
#  360（悟空）已从 D:\wukong 卸载。卸载程序移除了自己的 uninst.exe、删除了
#  C:\Windows\System32\drivers 下全部 6 个驱动 .sys、清除了 ProgramData\360safe
#  与 AppData\Roaming\360safe，并把注册表树从 1242 个子键削减到 17 个。
#
#  这里清理的只是【确定无疑的孤儿项】：
#
#      HKLM\SYSTEM\CurrentControlSet\Services\360netmon    Start=4（已禁用）
#      HKLM\SYSTEM\CurrentControlSet\Services\Q360AMPPL    Start=4（已禁用）
#          两者均已禁用，且 ImagePath 指向的文件已从磁盘删除，永远不可能再启动。
#
#      HKLM\SOFTWARE\360Safe\Liveup、...\MsgCenter
#          更新器 / 消息中心配置，更新器程序已不存在。
#
#      HKCU\SOFTWARE\360\360se5、...\360se6
#          360 安全浏览器的配置。已核实该浏览器【并未安装】：
#          无安装目录、无卸载项、全盘无 360se*.exe、无运行进程。
#
#  刻意不动的东西
#      360FsFlt
#          驱动仍驻留内核内存（.sys 已删、服务键已移除，StartMode 显示 Unknown）。
#          这是标准的待重启状态，无法手动卸载，重启即清除。
#          此时去动它周围的东西毫无意义且有风险。
#
#      D:\wukong
#          safemon 下有 8 个 DLL 被 Explorer 作为 shell 扩展加载而锁定，
#          另有注册表 hive 文件 deepscan\spdm.dat 及其事务日志。
#          重启后即可删除。
#
#  注：截至 2026-09-30，上述目标均已清理完毕，本脚本重复运行只会报告"absent"。
# ==============================================================================

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- 自动提权
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "本脚本需要管理员权限，正在请求提权（请在 UAC 窗口点『是』）..." -ForegroundColor Yellow
    Start-Process -FilePath 'pwsh' -Verb RunAs -Wait -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    )
    exit
}

Write-Host "===== 0. 预检 =====" -ForegroundColor Cyan
Write-Host "  管理员权限 : 是"

$removed = 0

function Remove-Tree {
    param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            if (Test-Path -LiteralPath $Path) {
                Write-Host ("  部分删除  " + $Label) -ForegroundColor Yellow
            } else {
                Write-Host ("  已删除    " + $Label) -ForegroundColor Green
                $script:removed++
            }
        } catch {
            Write-Host ("  失败      " + $Label + "  -> " + $_.Exception.Message) -ForegroundColor Red
        }
    } else {
        Write-Host ("  本不存在  " + $Label)
    }
}

Write-Host ""
Write-Host "===== 1. 守卫：360 浏览器是否真的不在 ？=====" -ForegroundColor Cyan
$sePaths = @()
foreach ($root in @('C:\Program Files (x86)','C:\Program Files',"$env:LOCALAPPDATA")) {
    $sePaths += Get-ChildItem $root -Recurse -Depth 3 -Filter '360se*.exe' -Force -ErrorAction SilentlyContinue
}
$seProc = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '360se|360Chrome' }
if ($sePaths.Count -gt 0 -or $seProc) {
    Write-Host "  中止：发现 360 浏览器痕迹，不删除 HKCU\SOFTWARE\360。" -ForegroundColor Red
    $browserGone = $false
} else {
    Write-Host "  已确认：磁盘上无 360se*.exe，无浏览器进程" -ForegroundColor Green
    $browserGone = $true
}

Write-Host ""
Write-Host "===== 2. 移除孤立服务项 =====" -ForegroundColor Cyan
foreach ($svc in @('360netmon','Q360AMPPL')) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
    if (Test-Path -LiteralPath $key) {
        $ip  = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        $img = $ip.ImagePath
        $imgExists = $false
        if ($img) {
            $clean = $img -replace '^\\\?\?\\','' -replace '"',''
            $imgExists = Test-Path -LiteralPath $clean
        }
        Write-Host ("  $svc  Start=$($ip.Start)  镜像文件存在=$imgExists")
        if ($ip.Start -eq 4 -and -not $imgExists) {
            Remove-Tree $key ("Services\" + $svc)
        } else {
            Write-Host ("  已跳过  $svc （未禁用，或镜像文件仍在）") -ForegroundColor Yellow
        }
    } else {
        Write-Host ("  本不存在  Services\$svc")
    }
}

Write-Host ""
Write-Host "===== 3. 移除孤立的 360Safe 更新器键（HKLM）=====" -ForegroundColor Cyan
Remove-Tree 'HKLM:\SOFTWARE\360Safe' 'HKLM\SOFTWARE\360Safe'
Remove-Tree 'HKLM:\SOFTWARE\WOW6432Node\360Safe' 'HKLM\SOFTWARE\WOW6432Node\360Safe'

Write-Host ""
Write-Host "===== 4. 移除孤立的 360 浏览器键（HKCU）=====" -ForegroundColor Cyan
if ($browserGone) {
    Remove-Tree 'HKCU:\SOFTWARE\360' 'HKCU\SOFTWARE\360'
} else {
    Write-Host "  已跳过（存在浏览器痕迹）" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "===== 5. 校验 =====" -ForegroundColor Cyan
$checks = @(
    @{ N = 'HKLM\SYSTEM\...\Services\360netmon';  P = 'HKLM:\SYSTEM\CurrentControlSet\Services\360netmon' },
    @{ N = 'HKLM\SYSTEM\...\Services\Q360AMPPL';  P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Q360AMPPL' },
    @{ N = 'HKLM\SOFTWARE\360Safe';               P = 'HKLM:\SOFTWARE\360Safe' },
    @{ N = 'HKCU\SOFTWARE\360';                   P = 'HKCU:\SOFTWARE\360' },
    @{ N = 'HKCU\SOFTWARE\360Safe';               P = 'HKCU:\SOFTWARE\360Safe' },
    @{ N = 'D:\wukong（需重启才能清空）';           P = 'D:\wukong' }
)
foreach ($c in $checks) {
    $exists = Test-Path -LiteralPath $c.P
    $color = if ($exists) { 'Yellow' } else { 'Green' }
    Write-Host ("  {0,-40} 存在？{1}" -f $c.N, $exists) -ForegroundColor $color
}

Write-Host ""
Write-Host "===== 6. 仍需重启处理的部分 =====" -ForegroundColor Cyan
$drv = Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '360' }
if ($drv) {
    foreach ($d in $drv) {
        Write-Host ("  360 驱动仍驻留内存：$($d.Name)  状态=$($d.State)") -ForegroundColor Yellow
    }
} else {
    Write-Host "  无 360 驱动驻留" -ForegroundColor Green
}
if (Test-Path 'D:\wukong') {
    $f = Get-ChildItem 'D:\wukong' -Recurse -File -Force -ErrorAction SilentlyContinue
    Write-Host ("  D:\wukong 仍有 $($f.Count) 个文件（$([math]::Round(($f | Measure-Object Length -Sum).Sum/1MB,2)) MB），被 Explorer 锁定") -ForegroundColor Yellow
}
$mm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
Write-Host "  分页文件配置（重启后生效）："
((Get-ItemProperty $mm -ErrorAction SilentlyContinue).PagingFiles) | ForEach-Object { Write-Host ("    " + $_) }

Write-Host ""
Write-Host ("  本次删除：$removed 项") -ForegroundColor Green
Write-Host "完成。" -ForegroundColor Green
