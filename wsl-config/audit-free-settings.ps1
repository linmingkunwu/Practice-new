#Requires -Version 7.0
# ==============================================================================
#  审计「零成本但可能被关掉」的 Windows 使用体验设置
#
#  用法: pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\audit-free-settings.ps1
#
#  收录标准（三项同时满足）
#  ------------------------------------------
#    1. 不耗资源 —— 不会引入持续 CPU/GPU/内存开销
#    2. 提升体验或安全性 —— 关闭它只会让人难受或冒险，没有性能收益
#    3. 容易被"优化工具"或教程误关
#
#  判定标记
#  ------------------------------------------
#    [OFF]  当前关闭 —— 候选恢复项
#    [ON]   当前开启 —— 正常
#    [---]  未设置（走系统默认）—— 需看默认值判断
#    [ ?? ] 无法从注册表判定，需在图形界面确认
# ==============================================================================

function Sec($t) { Write-Host ""; Write-Host "########## $t ##########" -ForegroundColor Cyan }

$result = New-Object System.Collections.ArrayList

function Check {
    param(
        [string]$Group,
        [string]$Name,
        [string]$Path,
        [string]$Prop,
        $OnValue,          # 视为"开启/理想"的值
        [string]$Why,
        [string]$DefaultNote = ''
    )
    $v = $null
    if ($Path) {
        $v = (Get-ItemProperty $Path -Name $Prop -ErrorAction SilentlyContinue).$Prop
    }
    $state = '---'
    $color = 'Gray'
    if ($null -eq $v) {
        $state = '---'
        $color = 'DarkGray'
    } elseif ("$v" -eq "$OnValue") {
        $state = 'ON '
        $color = 'Green'
    } else {
        $state = 'OFF'
        $color = 'Yellow'
    }
    $disp = if ($null -eq $v) { '(未设置)' } else { "$v" }
    Write-Host ("  [{0}] {1,-34} = {2,-12} {3}" -f $state, $Name, $disp, $Why) -ForegroundColor $color
    [void]$result.Add([PSCustomObject]@{
        Group = $Group; Name = $Name; Value = $disp; State = $state
        Path = $Path; Prop = $Prop; Why = $Why; DefaultNote = $DefaultNote
    })
}

$ADV   = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$DESK  = 'HKCU:\Control Panel\Desktop'
$MOUSE = 'HKCU:\Control Panel\Mouse'
$DWM   = 'HKCU:\SOFTWARE\Microsoft\Windows\DWM'
$EXP   = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'

Write-Host "==================== 零成本设置审计 ====================" -ForegroundColor Cyan

# ---------------------------------------------------------------- 文件浏览
Sec "一、文件浏览（Explorer）"
Check -Group '文件浏览' -Name 'HideFileExt'      -Path $ADV -Prop 'HideFileExt'      -OnValue '0' -Why '显示文件扩展名（隐藏时易被 .txt.exe 类文件欺骗）  0=显示'
Check -Group '文件浏览' -Name 'Hidden'           -Path $ADV -Prop 'Hidden'           -OnValue '1' -Why '显示隐藏文件  1=显示 2=不显示'
Check -Group '文件浏览' -Name 'LaunchTo'         -Path $ADV -Prop 'LaunchTo'         -OnValue '1' -Why '打开资源管理器时定位到「此电脑」  1=此电脑 2=快速访问'
Check -Group '文件浏览' -Name 'NavPaneShowAllFolders' -Path $ADV -Prop 'NavPaneShowAllFolders' -OnValue '1' -Why '导航窗格显示所有文件夹'
Check -Group '文件浏览' -Name 'ShowStatusBar'    -Path $ADV -Prop 'ShowStatusBar'    -OnValue '1' -Why '显示状态栏（含选中项大小、可用空间）'
Check -Group '文件浏览' -Name 'ShowFrequent'     -Path $ADV -Prop 'ShowFrequent'     -OnValue '0' -Why '快速访问不显示常用文件夹  0=不显示'
Check -Group '文件浏览' -Name 'ShowRecent'       -Path $ADV -Prop 'ShowRecent'       -OnValue '0' -Why '快速访问不显示最近文件  0=不显示'
Check -Group '文件浏览' -Name 'SeparateProcess'  -Path $ADV -Prop 'SeparateProcess'  -OnValue '1' -Why '在独立进程中打开文件夹窗口（更稳）  1=是'
Check -Group '文件浏览' -Name 'ListviewShadow'   -Path $ADV -Prop 'ListviewShadow'   -OnValue '1' -Why '图标标签阴影'
Check -Group '文件浏览' -Name 'SnapAssist'       -Path $ADV -Prop 'SnapAssist'       -OnValue '1' -Why '拖动窗口到边缘时显示贴靠建议'

# ---------------------------------------------------------------- 鼠标键盘
Sec "二、鼠标与键盘（日常手感，全部零开销）"
Check -Group '鼠标' -Name 'MouseHoverTime'    -Path $MOUSE -Prop 'MouseHoverTime'    -OnValue '100' -Why '菜单悬停弹出延迟(ms)，默认 400 偏迟钝  建议 100~200'
Check -Group '鼠标' -Name 'MouseSensitivity'  -Path $MOUSE -Prop 'MouseSensitivity'  -OnValue '10'  -Why '鼠标灵敏度（10 为默认中位）'
Check -Group '鼠标' -Name 'MouseWheelRouting' -Path $DESK  -Prop 'MouseWheelRouting' -OnValue '2'   -Why '悬停即滚动非活动窗口（强烈推荐）  2=启用 0=禁用'
Check -Group '鼠标' -Name 'MenuShowDelay'     -Path $DESK  -Prop 'MenuShowDelay'     -OnValue '0'   -Why '菜单展开延迟(ms)，0 = 立即'
Check -Group '鼠标' -Name 'DragHeight'        -Path $DESK  -Prop 'DragHeight'        -OnValue '4'   -Why '拖动容差(像素)，越小越精准'
Check -Group '鼠标' -Name 'DragWidth'         -Path $DESK  -Prop 'DragWidth'         -OnValue '4'   -Why '拖动容差(像素)'
Check -Group '鼠标' -Name 'DoubleClickSpeed'  -Path $MOUSE -Prop 'DoubleClickSpeed'  -OnValue '500' -Why '双击速度(ms)，500 为标准'
Check -Group '鼠标' -Name 'SmoothScroll'      -Path $DESK  -Prop 'SmoothScroll'      -OnValue '1'   -Why '列表平滑滚动  1=启用'

# ---------------------------------------------------------------- 多任务与窗口
Sec "三、多任务与窗口"
Check -Group '多任务' -Name 'MultiTaskingAltTabFilter' -Path $ADV -Prop 'MultiTaskingAltTabFilter' -OnValue '0' -Why 'Alt+Tab 仅显示窗口（不含浏览器标签页）'
Check -Group '多任务' -Name 'SnapAssist'        -Path $ADV -Prop 'SnapAssist'        -OnValue '1' -Why '贴靠辅助'
Check -Group '多任务' -Name 'JointResize'       -Path $ADV -Prop 'JointResize'       -OnValue '1' -Why '贴靠后联动调整相邻窗口大小'
Check -Group '多任务' -Name 'EnableSnapBar'     -Path $ADV -Prop 'EnableSnapBar'     -OnValue '1' -Why '悬停最大化按钮显示贴靠布局'
Check -Group '多任务' -Name 'DITest'            -Path $ADV -Prop 'DITest'            -OnValue '1' -Why '（调试项，忽略）'
Check -Group '多任务' -Name 'TaskbarEndTask'    -Path $ADV -Prop 'TaskbarEndTask'    -OnValue '1' -Why '任务栏右键「结束任务」（Win11 22H2+）'
Check -Group '多任务' -Name 'DisallowShaking'   -Path $ADV -Prop 'DisallowShaking'   -OnValue '0' -Why '标题栏拖动抖动最小化其它窗口  0=允许'

# ---------------------------------------------------------------- 任务栏
Sec "四、任务栏与开始菜单"
Check -Group '任务栏' -Name 'TaskbarDa'          -Path $ADV -Prop 'TaskbarDa'          -OnValue '0' -Why '小组件按钮  0=隐藏（省资源）'
Check -Group '任务栏' -Name 'TaskbarMn'          -Path $ADV -Prop 'TaskbarMn'          -OnValue '0' -Why '聊天(Teams)按钮  0=隐藏'
Check -Group '任务栏' -Name 'ShowCopilotButton'  -Path $ADV -Prop 'ShowCopilotButton'  -OnValue '0' -Why 'Copilot 按钮  0=隐藏'
Check -Group '任务栏' -Name 'ShowTaskViewButton' -Path $ADV -Prop 'ShowTaskViewButton' -OnValue '0' -Why '任务视图按钮  0=隐藏（仍可用 Win+Tab）'
Check -Group '任务栏' -Name 'SearchboxTaskbarMode' -Path $ADV -Prop 'SearchboxTaskbarMode' -OnValue '1' -Why '搜索框样式 0=隐藏 1=仅图标 2=搜索框 3=搜索框+标签'
Check -Group '任务栏' -Name 'HideRecommendedSection' -Path $ADV -Prop 'HideRecommendedSection' -OnValue '1' -Why '开始菜单不显示「推荐的项目」（更干净更快）'

# ---------------------------------------------------------------- 通知与焦点
Sec "五、通知、焦点与弹窗（这些默认值常常很烦人）"
Check -Group '通知' -Name 'ForegroundFlashCount' -Path $DESK -Prop 'ForegroundFlashCount' -OnValue '3' -Why '任务栏按钮闪烁次数，默认【7 次】很烦  建议 1~3'
Check -Group '通知' -Name 'ForegroundLockTimeout' -Path $DESK -Prop 'ForegroundLockTimeout' -OnValue '200000' -Why '防止后台程序抢焦点(ms)，默认 200000'
Check -Group '通知' -Name 'AutoEndTasks'        -Path 'HKCU:\Control Panel\Desktop' -Prop 'AutoEndTasks' -OnValue '0' -Why '关机时自动结束无响应程序  0=询问（更安全）'
Check -Group '通知' -Name 'HungAppTimeout'      -Path 'HKCU:\Control Panel\Desktop' -Prop 'HungAppTimeout' -OnValue '5000' -Why '程序无响应判定超时(ms)，5000 为默认'

# ---------------------------------------------------------------- 剪贴板与输入
Sec "六、剪贴板与输入"
Check -Group '剪贴板' -Name 'AllowClipboardHistory'   -Path "$ADV\..\..\..\..\SOFTWARE\Microsoft\Clipboard" -Prop 'EnableClipboardHistory' -OnValue '1' -Why '剪贴板历史 Win+V（完全免费，非常实用）'
Check -Group '剪贴板' -Name 'CloudClipboard'          -Path 'HKCU:\SOFTWARE\Microsoft\Clipboard' -Prop 'CloudClipboardAutomaticUpload' -OnValue '1' -Why '剪贴板云同步（可关，看需求）'

# ---------------------------------------------------------------- 视觉（零成本部分）
Sec "七、视觉与观感（零成本项）"
Check -Group '视觉' -Name 'MinAnimate'          -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Prop 'MinAnimate' -OnValue '1' -Why '窗口动画'
Check -Group '视觉' -Name 'TaskbarAnimations'   -Path $ADV  -Prop 'TaskbarAnimations'  -OnValue '1' -Why '任务栏动画'
Check -Group '视觉' -Name 'ListviewAlphaSelect' -Path $ADV  -Prop 'ListviewAlphaSelect' -OnValue '1' -Why '列表淡入淡出'
Check -Group '视觉' -Name 'EnableTransparency'  -Path $DWM  -Prop 'EnableTransparency'  -OnValue '1' -Why '透明效果'
Check -Group '视觉' -Name 'EnableAeroPeek'      -Path $DWM  -Prop 'EnableAeroPeek'      -OnValue '1' -Why 'Aero Peek 预览'
Check -Group '视觉' -Name 'AppsUseLightTheme'   -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Prop 'AppsUseLightTheme' -OnValue '0' -Why '应用深色模式  0=深色 1=浅色'
Check -Group '视觉' -Name 'SystemUsesLightTheme' -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Prop 'SystemUsesLightTheme' -OnValue '0' -Why '系统深色模式  0=深色 1=浅色'
Check -Group '视觉' -Name 'ShowSecondsInSystemClock' -Path $ADV -Prop 'ShowSecondsInSystemClock' -OnValue '1' -Why '任务栏时钟显示秒（零开销）'

# ---------------------------------------------------------------- 性能相关的默认项
Sec '八、性能相关的默认值（看看有没有被激进改动）'
Check -Group '性能' -Name 'Win32PrioritySeparation' -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Prop 'Win32PrioritySeparation' -OnValue '38' -Why '前台优先级（38=0x26 为 Windows 默认，改成 24 等是遗留优化迷思）'
Check -Group '性能' -Name 'HwSchMode'               -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Prop 'HwSchMode' -OnValue '2' -Why '硬件加速 GPU 计划  2=启用'
Check -Group '性能' -Name 'LargeSystemCache'        -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Prop 'LargeSystemCache' -OnValue '0' -Why '大系统缓存  0=桌面默认（服务器才该设 1）'
Check -Group '性能' -Name 'ClearPageFileAtShutdown' -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Prop 'ClearPageFileAtShutdown' -OnValue '0' -Why '关机清空分页文件  0=不清（1 会拖慢关机且无收益）'
Check -Group '性能' -Name 'DisablePagingExecutive' -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Prop 'DisablePagingExecutive' -OnValue '0' -Why '内核常驻内存  0=默认允许换出'
Check -Group '性能' -Name 'NtfsDisableLastAccessUpdate' -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Prop 'NtfsDisableLastAccessUpdate' -OnValue '0x80000003' -Why 'NTFS 最后访问时间更新策略'

# ---------------------------------------------------------------- 网络相关（浏览体验）
Sec "九、网络与浏览器体验"
Check -Group '网络' -Name 'EnableActiveProbing' -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet' -Prop 'EnableActiveProbing' -OnValue '1' -Why '网络连通性探测  1=开启（关掉会导致"无 Internet"误报）'
Check -Group '网络' -Name 'Tcp1323Opts'         -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Prop 'Tcp1323Opts' -OnValue '1' -Why 'TCP 窗口缩放  1=启用（默认）'
Check -Group '网络' -Name 'TcpAckFrequency'     -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' -Prop 'TcpAckFrequency' -OnValue $null -Why '(接口级，通常不设，忽略)'

# ---------------------------------------------------------------- 生成建议
Write-Host ""
Write-Host "==================== 可捡回的项（关闭但零成本）====================" -ForegroundColor Cyan
$off = @($result | Where-Object { $_.State -eq 'OFF' })
if ($off.Count -eq 0) {
    Write-Host "  没有发现被关闭的零成本项。" -ForegroundColor Green
} else {
    Write-Host ("  共 " + $off.Count + " 项：") -ForegroundColor Yellow
    Write-Host ""
    $grouped = $off | Group-Object Group
    foreach ($g in $grouped) {
        Write-Host ("  [" + $g.Name + "]") -ForegroundColor Yellow
        foreach ($i in $g.Group) {
            Write-Host ("    {0,-36} 当前={1,-10} {2}" -f $i.Name, $i.Value, $i.Why)
        }
        Write-Host ""
    }
}

Write-Host "==================== 全部结果 ====================" -ForegroundColor Cyan
$result | Group-Object Group | ForEach-Object {
    $on = @($_.Group | Where-Object { $_.State -eq 'ON ' }).Count
    $of = @($_.Group | Where-Object { $_.State -eq 'OFF' }).Count
    $un = @($_.Group | Where-Object { $_.State -eq '---' }).Count
    Write-Host ("  {0,-14} 开启 {1,2}   关闭 {2,2}   未设置 {3,2}" -f $_.Name, $on, $of, $un)
}
