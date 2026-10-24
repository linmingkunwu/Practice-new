#Requires -Version 7.0
# ==============================================================================
#  第二轮「零成本但被关掉」审计
#
#  用法: pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\audit-free-settings2.ps1
#
#  与第一轮（audit-free-settings.ps1）的分工
#  ------------------------------------------
#    第一轮：任务栏、动画、鼠标、关机、通知闪烁、HAGS
#    本轮  ：资源管理器深层项、系统提示与推荐、广告推送、DNS over HTTPS、
#            浏览器效率、Win11 右键菜单、输入法、电源细节
#
#  ⚠️ 本轮严格遵守上一轮的教训
#  ------------------------------------------
#    凡标注「理想值」的项，必须能说出依据：
#      · 原厂默认（Windows 开箱状态）
#      · Microsoft 文档
#      · 明确的资源收益
#    不能凭"感觉应该开着"下判断。无法确定依据的项一律标 [ ?? ] 不做建议。
# ==============================================================================

function Sec($t) { Write-Host ""; Write-Host "########## $t ##########" -ForegroundColor Cyan }

$rows = New-Object System.Collections.ArrayList

function Probe {
    param(
        [string]$Group,
        [string]$Name,
        [string]$Path,
        [string]$Prop,
        [object]$Now,          # 直接给出当前值（用于特殊查询）；必须是 object，
                               # 若声明为 [string]，$null 会被强制转成 ""，
                               # 导致 `$null -eq $v` 判定失效、永远读不到注册表
        [string]$Ideal,        # 理想值；空串表示不作建议
        [string]$Basis,        # 依据
        [string]$Why
    )
    $v = $Now
    if ($null -eq $v -and $Path) {
        $v = (Get-ItemProperty $Path -Name $Prop -ErrorAction SilentlyContinue).$Prop
    }
    $disp = if ($null -eq $v) { '(未设置)' } else { "$v" }
    $state = '---'
    $color = 'DarkGray'
    if ($Ideal -ne '') {
        if ("$v" -eq "$Ideal") { $state = 'ON '; $color = 'Green' }
        else { $state = 'OFF'; $color = 'Yellow' }
    } else {
        $state = ' ?? '
        $color = 'DarkGray'
    }
    Write-Host ("  [{0}] {1,-34} = {2,-14} {3}" -f $state, $Name, $disp, $Why) -ForegroundColor $color
    if ($Basis) { Write-Host ("          依据: " + $Basis) -ForegroundColor DarkGray }
    [void]$rows.Add([PSCustomObject]@{ Group=$Group; Name=$Name; Value=$disp; State=$state; Ideal=$Ideal; Why=$Why; Path=$Path; Prop=$Prop })
}

$ADV  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$EXP  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'

Write-Host "==================== 第二轮零成本审计 ====================" -ForegroundColor Cyan

# ---------------------------------------------------------------- 1. 系统提示与广告
Sec "一、系统提示、推荐与广告（关掉只有好处）"
Probe -Group '广告与提示' -Name 'SoftLandingEnabled' -Path "$EXP\Advanced" -Prop 'SoftLandingEnabled' -Ideal '0' -Basis 'Windows 开箱默认为 1；关掉减少"Windows 提示"弹窗' -Why 'Windows 提示与建议  0=关'
Probe -Group '广告与提示' -Name 'SubscribedContent-338389Enabled' -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Prop 'SubscribedContent-338389Enabled' -Ideal '0' -Basis '开箱默认为 1；这是"获取使用 Windows 的建议"推送' -Why '使用建议推送'
Probe -Group '广告与提示' -Name 'SubscribedContent-338388Enabled' -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Prop 'SubscribedContent-338388Enabled' -Ideal '0' -Basis '开箱默认为 1；开始菜单应用推荐' -Why '开始菜单推荐应用'
Probe -Group '广告与提示' -Name 'SubscribedContent-310093Enabled' -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Prop 'SubscribedContent-310093Enabled' -Ideal '0' -Basis '开箱默认为 1；Windows 欢迎体验' -Why 'Windows 欢迎体验'
Probe -Group '广告与提示' -Name 'SystemPaneSuggestionsEnabled' -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Prop 'SystemPaneSuggestionsEnabled' -Ideal '0' -Basis '开箱默认为 1；设置界面的建议卡片' -Why '设置里的建议'
Probe -Group '广告与提示' -Name 'SilentInstalledAppsEnabled' -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Prop 'SilentInstalledAppsEnabled' -Ideal '0' -Basis '开箱默认为 1；会静默安装推广应用' -Why '静默安装推广应用  0=禁止'
Probe -Group '广告与提示' -Name 'IsDynamicSearchBoxEnabled' -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings' -Prop 'IsDynamicSearchBoxEnabled' -Ideal '0' -Basis '搜索框的"搜索亮点"插图，纯装饰' -Why '搜索框亮点  0=关'

# ---------------------------------------------------------------- 2. 资源管理器深层
Sec "二、资源管理器深层设置"
Probe -Group '资源管理器' -Name 'ShowSyncProviderNotifications' -Path $ADV -Prop 'ShowSyncProviderNotifications' -Ideal '0' -Basis '开箱默认为 1；OneDrive 会在资源管理器里弹推广通知' -Why 'OneDrive 同步推广通知  0=关'
Probe -Group '资源管理器' -Name 'ShowCloudFilesInQuickAccess' -Path $ADV -Prop 'ShowCloudFilesInQuickAccess' -Ideal '0' -Basis '开箱默认为 1；云盘文件混入快速访问' -Why '快速访问显示云文件'
Probe -Group '资源管理器' -Name 'UseCompactMode' -Path $ADV -Prop 'UseCompactMode' -Ideal '' -Basis '纯外观偏好，无对错' -Why '紧凑模式（密集列表）'
Probe -Group '资源管理器' -Name 'AutoCheckSelect' -Path $ADV -Prop 'AutoCheckSelect' -Ideal '' -Basis '偏好项' -Why '鼠标悬停时显示复选框'
Probe -Group '资源管理器' -Name 'ShowTypeOverlay' -Path $ADV -Prop 'ShowTypeOverlay' -Ideal '' -Basis '偏好项' -Why '图标角落显示类型角标'
Probe -Group '资源管理器' -Name 'FaultTolerantHeap' -Path $ADV -Prop 'FaultTolerantHeap' -Ideal '' -Basis '调试用，不建议动' -Why '容错堆（调试项）'
Probe -Group '资源管理器' -Name 'ShowTabs' -Path $ADV -Prop 'ShowTabs' -Ideal '1' -Basis 'Win11 22H2+ 的资源管理器标签页；关掉会少一个大功能' -Why '资源管理器标签页'
Probe -Group '资源管理器' -Name 'EnableBalloonTips' -Path $ADV -Prop 'EnableBalloonTips' -Ideal '' -Basis '偏好项' -Why '气泡提示'

# ---------------------------------------------------------------- 3. Win11 右键菜单
Sec "三、Win11 经典右键菜单（改动最大的体验项）"
$clsKey = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
$clsExists = Test-Path $clsKey
$clsVal = if ($clsExists) { (Get-ItemProperty $clsKey -Name '(default)' -ErrorAction SilentlyContinue).'(default)' } else { $null }
Write-Host ("  CLSID 键是否存在         : " + $clsExists)
Write-Host ("  InprocServer32 默认值    : " + $(if ($null -eq $clsVal) { '(键不存在)' } elseif ($clsVal -eq '') { '(空字符串 = 经典菜单已启用)' } else { $clsVal }))
Write-Host ""
Write-Host "  说明:" -ForegroundColor DarkGray
Write-Host "    Windows 11 的新右键菜单默认把常用项折叠进「显示更多选项」。" -ForegroundColor DarkGray
Write-Host "    把该 CLSID 的 InprocServer32 设为空字符串，可恢复完整的经典菜单。" -ForegroundColor DarkGray
Write-Host "    零开销（只是换用旧菜单的渲染路径），且随时可删键还原。" -ForegroundColor DarkGray
if ($clsExists -and $clsVal -eq '') {
    Write-Host "    => 当前【经典菜单已启用】" -ForegroundColor Green
} else {
    Write-Host "    => 当前【使用 Win11 默认菜单】" -ForegroundColor Yellow
}

# ---------------------------------------------------------------- 4. DNS over HTTPS
Sec "四、DNS over HTTPS（免费提升隐私与抗污染）"
Write-Host "  系统级 DoH 状态:"
$doh = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Name 'EnableAutoDoh' -ErrorAction SilentlyContinue
Write-Host ("    EnableAutoDoh = " + $(if ($null -eq $doh.EnableAutoDoh) { '(未设置 → 默认 2 = 自动)' } else { $doh.EnableAutoDoh }))
Write-Host ""
Write-Host "  各网卡当前的 DNS 服务器与 DoH 模板:"
$ifaces = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses }
foreach ($i in $ifaces) {
    Write-Host ("    " + $i.InterfaceAlias.PadRight(20) + " DNS: " + ($i.ServerAddresses -join ', '))
    try {
        $dohSrv = Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue | Where-Object { $i.ServerAddresses -contains $_.ServerAddress }
        if ($dohSrv) {
            foreach ($d in $dohSrv) {
                Write-Host ("      DoH: " + $d.ServerAddress + "  自动升级=" + $d.AutoUpgrade + "  允许降级=" + $d.AllowFallbackToPlaintext) -ForegroundColor $(if ($d.AutoUpgrade) { 'Green' } else { 'Yellow' })
            }
        }
    } catch {}
}
Write-Host ""
Write-Host "  已知支持 DoH 的服务器（Win11 内置模板）:"
try {
    Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue | Select-Object -First 8 | ForEach-Object {
        Write-Host ("    {0,-22} 自动升级={1}" -f $_.ServerAddress, $_.AutoUpgrade) -ForegroundColor DarkGray
    }
} catch { Write-Host "    （无法查询）" }
Write-Host ""
Write-Host "  ⚠️ 你当前用的是路由器 DNS（192.168.1.1 / 192.168.3.1），" -ForegroundColor DarkGray
Write-Host "     它们不支持 DoH。要启用需先指定支持 DoH 的上游（如阿里/腾讯 DNS）。" -ForegroundColor DarkGray
Write-Host '     这是【要改动 DNS 服务器】的操作，不属于纯开关类，故不自动建议。' -ForegroundColor DarkGray

# ---------------------------------------------------------------- 5. 浏览器效率
Sec "五、浏览器效率设置（Edge 单进程最高占 1460 MB）"
$edgePref = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Preferences"
$chromePref = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Preferences"
foreach ($b in @(@{N='Edge'; P=$edgePref}, @{N='Chrome'; P=$chromePref})) {
    if (Test-Path $b.P) {
        Write-Host ("  [" + $b.N + "]")
        try {
            $j = Get-Content $b.P -Raw -Encoding UTF8 | ConvertFrom-Json
            $keys = @(
                @{ P='browser.efficiency_mode';      D='效率模式' },
                @{ P='browser.sleeping_tabs.enabled';D='休眠标签页' },
                @{ P='browser.startup_boost_enabled';D='启动加速' },
                @{ P='hardware_acceleration_mode.enabled'; D='硬件加速' },
                @{ P='background_mode.enabled';      D='关闭窗口后仍后台运行' },
                @{ P='browser.prefetch_preload';     D='预加载页面' }
            )
            foreach ($k in $keys) {
                $node = $j
                $ok = $true
                foreach ($seg in ($k.P -split '\.')) {
                    if ($node -and ($node.PSObject.Properties.Name -contains $seg)) { $node = $node.$seg } else { $ok = $false; break }
                }
                $val = if ($ok) { $node } else { '(未设置)' }
                Write-Host ("    {0,-36} = {1,-12} {2}" -f $k.P, $val, $k.D) -ForegroundColor Gray
            }
        } catch { Write-Host ("    读取失败: " + $_.Exception.Message) }
    }
}
Write-Host ""
Write-Host "  ⚠️ 这些在浏览器设置界面里改更可靠（注册表/偏好文件的键名随版本变化）。" -ForegroundColor DarkGray

# ---------------------------------------------------------------- 6. 电源细节
Sec "六、电源与电池（零成本的可用性项）"
Write-Host "  电源模式（Win11 滑块）:"
$overlay = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' -Name 'ActiveOverlayAcPowerScheme' -ErrorAction SilentlyContinue
Write-Host ("    ActiveOverlayAcPowerScheme = " + $(if ($overlay.ActiveOverlayAcPowerScheme) { $overlay.ActiveOverlayAcPowerScheme } else { '(未设置)' }))
Write-Host "      961cc777-2547-4f9d-8174-7d86181b8a7a = 最佳能效"
Write-Host "      00000000-0000-0000-0000-000000000000 = 平衡"
Write-Host "      ded574b5-45a0-4f42-8737-46345c09c238 = 最佳性能"
Write-Host ""
Write-Host "  快速启动（HiberbootEnabled）:"
$hb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
Write-Host ("    HiberbootEnabled = " + $(if ($null -eq $hb) { '(未设置)' } else { $hb }) + "   (1=开 0=关)")
Write-Host "    ⚠️ 这是【有取舍】的项：" -ForegroundColor Yellow
Write-Host "       开着 → 开机更快，但关机不是真关机，驱动/更新可能出怪问题"
Write-Host "       关掉 → 开机慢几秒，但状态干净、问题更少"
Write-Host "       属取舍而非'零成本'，故不自动建议。"
Write-Host ""
Write-Host "  电池:"
$bs = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -EA SilentlyContinue
if ($bs) {
    Write-Host ("    当前电量 = " + $bs.RemainingCapacity + " mWh   接AC=" + $bs.PowerOnline)
}
$saver = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\EnergySaver' -Name 'EnergySaverPolicy' -ErrorAction SilentlyContinue)
Write-Host "    节能模式相关键:"
Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\EnergySaver' -EA SilentlyContinue |
    Select-Object * -ExcludeProperty PS* | Format-List

# ---------------------------------------------------------------- 7. 开始菜单与最近项
Sec "七、开始菜单与最近使用项"
Probe -Group '开始菜单' -Name 'Start_TrackDocs' -Path $ADV -Prop 'Start_TrackDocs' -Ideal '' -Basis '偏好：关掉后开始菜单不记录最近打开的文件（隐私 vs 便利）' -Why '记录最近打开的文件'
Probe -Group '开始菜单' -Name 'Start_TrackProgs' -Path $ADV -Prop 'Start_TrackProgs' -Ideal '' -Basis '偏好项' -Why '记录最常用程序'
Probe -Group '开始菜单' -Name 'Start_IrisRecommendations' -Path $ADV -Prop 'Start_IrisRecommendations' -Ideal '0' -Basis '开始菜单的"为你推荐"推广内容' -Why '开始菜单推荐内容'
Probe -Group '开始菜单' -Name 'ShowRecentList' -Path "$EXP\Advanced" -Prop 'ShowRecentList' -Ideal '' -Basis '偏好项' -Why '跳转列表显示最近项'
Probe -Group '开始菜单' -Name 'ShowFrequentList' -Path "$EXP\Advanced" -Prop 'ShowFrequentList' -Ideal '' -Basis '偏好项' -Why '跳转列表显示常用项'

# ---------------------------------------------------------------- 8. 无障碍与输入
Sec "八、输入与无障碍（有些默认关闭但很有用）"
Probe -Group '输入' -Name 'ShowTextSuggestions' -Path 'HKCU:\SOFTWARE\Microsoft\Input\Settings' -Prop 'EnableHwkbTextPrediction' -Ideal '' -Basis '物理键盘文字建议，偏好项' -Why '键盘输入建议'
Probe -Group '输入' -Name 'MultilingualTextPrediction' -Path 'HKCU:\SOFTWARE\Microsoft\Input\Settings' -Prop 'MultilingualEnabled' -Ideal '' -Basis '偏好项' -Why '多语言输入建议'
$ime = Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\InputMethod\Settings\CHS' -EA SilentlyContinue
Write-Host "  中文输入法设置:"
if ($ime) {
    $ime.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | Select-Object -First 8 | ForEach-Object {
        Write-Host ("    {0,-36} = {1}" -f $_.Name, $_.Value) -ForegroundColor DarkGray
    }
} else { Write-Host "    （键不存在）" }

# ---------------------------------------------------------------- 汇总
Write-Host ""
Write-Host "==================== 建议恢复的项（有明确依据）====================" -ForegroundColor Cyan
$off = @($rows | Where-Object { $_.State -eq 'OFF' })
if ($off.Count -eq 0) {
    Write-Host "  无" -ForegroundColor Green
} else {
    $off | Group-Object Group | ForEach-Object {
        Write-Host ("  [" + $_.Name + "]") -ForegroundColor Yellow
        foreach ($i in $_.Group) {
            Write-Host ("    {0,-34} 当前={1,-12} 建议={2}" -f $i.Name, $i.Value, $i.Ideal)
            Write-Host ("      " + $i.Why) -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
Write-Host "==================== 不作建议的项（偏好或取舍）====================" -ForegroundColor Cyan
$unknown = @($rows | Where-Object { $_.State -eq ' ?? ' })
if ($unknown.Count -eq 0) { Write-Host "  无" } else {
    $unknown | ForEach-Object { Write-Host ("    {0,-34} = {1}" -f $_.Name, $_.Value) -ForegroundColor DarkGray }
}

Write-Host ""
Write-Host "==================== 统计 ====================" -ForegroundColor Cyan
$rows | Group-Object Group | ForEach-Object {
    $on = @($_.Group | Where-Object { $_.State -eq 'ON ' }).Count
    $of = @($_.Group | Where-Object { $_.State -eq 'OFF' }).Count
    $un = @($_.Group | Where-Object { $_.State -eq ' ?? ' }).Count
    Write-Host ("  {0,-14} 已ok {1,2}   建议改 {2,2}   偏好项 {3,2}" -f $_.Name, $on, $of, $un)
}
