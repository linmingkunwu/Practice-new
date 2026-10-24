#Requires -Version 7.0
# ==============================================================================
#  清理已确认的卸载残留
#
#  用法（PowerShell 7）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\clean-leftovers.ps1
#
#  本脚本【需要】管理员权限 —— 已在脚本内自动提权，无需手动开管理员终端。
#
#  ---------------------------------------------------------------------------
#  可安全删除（已核实：所属软件确已不在）
#  ---------------------------------------------------------------------------
#   Wise：
#     HKLM\SOFTWARE\WiseCleaner
#     HKLM\SOFTWARE\WOW6432Node\WiseCleaner
#     HKCU\SOFTWARE\WiseCleaner
#     —— 三个 Wise 产品均已卸载并核实清除
#
#   RAS 跟踪残留：
#     HKLM\SOFTWARE\Microsoft\Tracing\Docker Desktop Installer_RASAPI32
#     HKLM\SOFTWARE\Microsoft\Tracing\Docker Desktop Installer_RASMANCS
#     HKLM\SOFTWARE\Microsoft\Tracing\WiseCare365_RASAPI32
#     HKLM\SOFTWARE\Microsoft\Tracing\WiseTray_RASAPI32
#
#   死快捷方式（目标已不存在）：
#     %APPDATA%\Microsoft\Windows\Start Menu\Programs\Docker Desktop.lnk
#
#   .dockerfile 上的悬空 shell 扩展：
#     HKCU\SOFTWARE\Classes\.dockerfile\shellex\{8895b1c6-b41f-4c1c-a562-0d564250836f}
#     —— 该 CLSID 在 HKCU\Classes\CLSID、HKLM\Classes\CLSID 及 WOW6432Node 视图中
#        均未注册，shell 永远无法加载它。只删这个死引用；.dockerfile 根键保留，
#        因为 VS Code 在它的 OpenWithProgids 下注册了 VSCode.dockerfile。
#
#   Java 更新器残留（注意【不是】 JavaSoft\Prefs）：
#     HKCU\SOFTWARE\JavaSoft\DeploymentProperties
#     HKCU\SOFTWARE\JavaSoft\Java Update
#
#  ---------------------------------------------------------------------------
#  刻意不碰
#  ---------------------------------------------------------------------------
#   HKCU\SOFTWARE\JavaSoft\Prefs
#       —— 内含 Prefs\jetbrains 下的 PyCharm 设备 ID 与账号数据。
#          删除会导致 PyCharm 需要重新登录。
#
#   HKCU\SOFTWARE\Classes\VSCode.dockerfile
#       —— AppUserModelID = Microsoft.VisualStudioCode，属于 VS Code。
#
#   C:\Program Files\Java\jre1.8.0_481 与 C:\ProgramData\Oracle\Java\.oracle_jre_usage
#       —— JRE 8 运行时是刻意保留的。
#
#  ---------------------------------------------------------------------------
#  2026-09-30 状态说明
#  ---------------------------------------------------------------------------
#   360（悟空）已于 2026-09-29 从 D:\wukong 卸载，其注册表树（原 1242 个子键）
#   与服务项均已清除，因此本脚本不再需要规避 HKCU\SOFTWARE\360Safe。
#   见 clean-360-leftovers.ps1。
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
$skipped = 0

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
        $script:skipped++
    }
}

Write-Host ""
Write-Host "===== 1. Wise 注册表残留 =====" -ForegroundColor Cyan
Remove-Tree 'HKLM:\SOFTWARE\WiseCleaner'             'HKLM\SOFTWARE\WiseCleaner'
Remove-Tree 'HKLM:\SOFTWARE\WOW6432Node\WiseCleaner' 'HKLM\SOFTWARE\WOW6432Node\WiseCleaner'
Remove-Tree 'HKCU:\SOFTWARE\WiseCleaner'             'HKCU\SOFTWARE\WiseCleaner'

Write-Host ""
Write-Host "===== 2. RAS 跟踪残留 =====" -ForegroundColor Cyan
Remove-Tree 'HKLM:\SOFTWARE\Microsoft\Tracing\Docker Desktop Installer_RASAPI32' 'Tracing\Docker Desktop Installer_RASAPI32'
Remove-Tree 'HKLM:\SOFTWARE\Microsoft\Tracing\Docker Desktop Installer_RASMANCS' 'Tracing\Docker Desktop Installer_RASMANCS'
Remove-Tree 'HKLM:\SOFTWARE\Microsoft\Tracing\WiseCare365_RASAPI32'              'Tracing\WiseCare365_RASAPI32'
Remove-Tree 'HKLM:\SOFTWARE\Microsoft\Tracing\WiseTray_RASAPI32'                 'Tracing\WiseTray_RASAPI32'

Write-Host ""
Write-Host "===== 3. 死掉的 Docker Desktop 快捷方式 =====" -ForegroundColor Cyan
$lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Docker Desktop.lnk'
if (Test-Path -LiteralPath $lnk) {
    try {
        Remove-Item -LiteralPath $lnk -Force -ErrorAction Stop
        Write-Host "  已删除  Docker Desktop.lnk" -ForegroundColor Green
        $removed++
    } catch {
        Write-Host ("  失败    Docker Desktop.lnk -> " + $_.Exception.Message) -ForegroundColor Red
    }
} else {
    Write-Host "  本不存在  Docker Desktop.lnk"
    $skipped++
}

Write-Host ""
Write-Host "===== 4. .dockerfile 上的悬空 shell 扩展 =====" -ForegroundColor Cyan
$shellex = 'HKCU:\SOFTWARE\Classes\.dockerfile\shellex\{8895b1c6-b41f-4c1c-a562-0d564250836f}'
Remove-Tree $shellex 'shellex\{8895b1c6-...}（该 CLSID 未在任何位置注册）'
Write-Host "  保留 HKCU\SOFTWARE\Classes\VSCode.dockerfile（属于 VS Code）"
Write-Host "  保留 HKCU\SOFTWARE\Classes\.dockerfile 根键（VS Code 的 OpenWithProgids）"

Write-Host ""
Write-Host "===== 5. Java 更新器残留（保留 JavaSoft\Prefs）=====" -ForegroundColor Cyan
Remove-Tree 'HKCU:\SOFTWARE\JavaSoft\DeploymentProperties' 'HKCU\SOFTWARE\JavaSoft\DeploymentProperties'
Remove-Tree 'HKCU:\SOFTWARE\JavaSoft\Java Update'          'HKCU\SOFTWARE\JavaSoft\Java Update'

Write-Host ""
Write-Host "===== 6. 校验 =====" -ForegroundColor Cyan
$checks = @(
    @{ N = 'HKLM\SOFTWARE\WiseCleaner';              P = 'HKLM:\SOFTWARE\WiseCleaner';              Keep = $false },
    @{ N = 'HKLM\SOFTWARE\WOW6432Node\WiseCleaner';  P = 'HKLM:\SOFTWARE\WOW6432Node\WiseCleaner';  Keep = $false },
    @{ N = 'HKCU\SOFTWARE\WiseCleaner';              P = 'HKCU:\SOFTWARE\WiseCleaner';              Keep = $false },
    @{ N = 'Tracing\WiseCare365_RASAPI32';           P = 'HKLM:\SOFTWARE\Microsoft\Tracing\WiseCare365_RASAPI32'; Keep = $false },
    @{ N = 'Tracing\WiseTray_RASAPI32';              P = 'HKLM:\SOFTWARE\Microsoft\Tracing\WiseTray_RASAPI32';    Keep = $false },
    @{ N = '【保留】HKCU\SOFTWARE\JavaSoft\Prefs';    P = 'HKCU:\SOFTWARE\JavaSoft\Prefs';           Keep = $true },
    @{ N = '【保留】HKCU\Classes\VSCode.dockerfile';  P = 'HKCU:\SOFTWARE\Classes\VSCode.dockerfile'; Keep = $true },
    @{ N = '【保留】C:\Program Files\Java（JRE 8）';  P = 'C:\Program Files\Java';                   Keep = $true }
)
foreach ($c in $checks) {
    $exists = Test-Path -LiteralPath $c.P
    if ($c.Keep) {
        $color = if ($exists) { 'Green' } else { 'Red' }
        Write-Host ("  {0,-44} 存在？{1}   （应为 True）" -f $c.N, $exists) -ForegroundColor $color
    } else {
        $color = if ($exists) { 'Yellow' } else { 'Green' }
        Write-Host ("  {0,-44} 存在？{1}   （应为 False）" -f $c.N, $exists) -ForegroundColor $color
    }
}
Write-Host ""
Write-Host ("  已删除：$removed 项   本就缺失：$skipped 项") -ForegroundColor Green
Write-Host "完成。" -ForegroundColor Green
