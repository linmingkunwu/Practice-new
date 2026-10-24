#Requires -Version 7.0
# ==============================================================================
#  移除冗余软件并执行组件清理
#
#  用法（PowerShell 7）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\cleanup-redundant.ps1
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\cleanup-redundant.ps1 -SkipDism
#
#  本脚本【需要】管理员权限 —— 已在脚本内自动提权，无需手动开管理员终端。
#
#  清理内容
#    1. Wise Memory Optimizer / Wise Care 365 / Wise Folder Hider
#       「系统优化」类工具。Wise Memory Optimizer 靠强制 TrimWorkingSet 回收内存，
#       被换出的页面再次访问时会触发硬缺页——通常【降低】而非提升性能。
#       Wise Care 365 则是注册表清理工具。三者还都留下了登录计划任务。
#    2. 上述两个 Wise 计划任务。
#    3. SunJavaUpdateSched 启动项（HKLM WOW6432 Run）。
#    4. Java SE Development Kit 8 Update 201 —— 2019 年的构建，位于 D:\java，
#       而 JAVA_HOME 与 PATH 都指向 Adoptium JDK 21。
#       注意：Java 8 Update 481（JRE）【刻意保留】，老应用可能依赖 JRE 8 运行时。
#
#  刻意不碰的东西
#    AppData\Local\Google   —— 这是 Chrome 的用户资料（书签、密码、Cookie）
#    AppData\Local\NetEase  —— 网易云音乐数据
#    两者当天都还在被写入；删除是破坏性的。它们只有在读【父目录】时间戳时
#    才显得陈旧，这是个已知的误判陷阱。
#
#  第 7 步是对 C:\Windows\WinSxS（约 13 GB）执行 DISM /StartComponentCleanup，
#  可能耗时 10–30 分钟。用 -SkipDism 可跳过。
# ==============================================================================

param(
    [switch]$SkipDism
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- 自动提权
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "本脚本需要管理员权限，正在请求提权（请在 UAC 窗口点『是』）..." -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($SkipDism) { $argList += '-SkipDism' }
    Start-Process -FilePath 'pwsh' -Verb RunAs -Wait -ArgumentList $argList
    exit
}

Write-Host "===== 0. 预检 =====" -ForegroundColor Cyan
Write-Host "  管理员权限 : 是"
Write-Host ("  跳过 DISM  : " + $SkipDism)

# ------------------------------------------------------------------ 1. Wise
Write-Host ""
Write-Host "===== 1. 停止 Wise 进程与服务 =====" -ForegroundColor Cyan
Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match 'Wise|WiseCare|WiseBoot|WiseTurbo|WX' } |
    ForEach-Object {
        Write-Host ("  停止进程：$($_.ProcessName) ($($_.Id))")
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
Get-Service -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'Wise' -or $_.DisplayName -match 'Wise' } |
    ForEach-Object {
        Write-Host ("  停止服务：$($_.Name)")
        Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
    }
Start-Sleep -Seconds 2

Write-Host ""
Write-Host "===== 2. 卸载 Wise 系列 =====" -ForegroundColor Cyan
$wise = @(
    @{ Name = 'Wise Memory Optimizer'; Exe = 'C:\Program Files\Wise\Wise Memory Optimizer\unins000.exe' },
    @{ Name = 'Wise Care 365';         Exe = 'C:\Program Files (x86)\Wise\Wise Care 365\unins000.exe' },
    @{ Name = 'Wise Folder Hider';     Exe = 'C:\Program Files (x86)\Wise\Wise Folder Hider\unins000.exe' }
)
foreach ($w in $wise) {
    if (Test-Path -LiteralPath $w.Exe) {
        Write-Host ("  正在卸载 $($w.Name) ...")
        $p = Start-Process -FilePath $w.Exe -ArgumentList '/SILENT','/NORESTART' -Wait -PassThru
        Write-Host ("    退出码：$($p.ExitCode)")
    } else {
        Write-Host ("  未找到：$($w.Exe)")
    }
}
Start-Sleep -Seconds 3

Write-Host ""
Write-Host "===== 3. 删除 Wise 计划任务 =====" -ForegroundColor Cyan
Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName -match 'Wise' } |
    ForEach-Object {
        Write-Host ("  注销任务：$($_.TaskName)")
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }

Write-Host ""
Write-Host "===== 4. 移除 SunJavaUpdateSched 启动项 =====" -ForegroundColor Cyan
$runKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
$cur = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue).SunJavaUpdateSched
if ($cur) {
    Write-Host ("  当前值：$cur")
    Remove-ItemProperty -Path $runKey -Name 'SunJavaUpdateSched' -Force -ErrorAction SilentlyContinue
    $after = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue).SunJavaUpdateSched
    Write-Host ("  已移除：$(-not $after)") -ForegroundColor Green
} else {
    Write-Host "  （该项本来就不存在）"
}

Write-Host ""
Write-Host "===== 5. 卸载 JDK 8 Update 201（2019 年构建，已被 JDK 21 取代）=====" -ForegroundColor Cyan
$guid = '{64A3A4F4-B792-11D6-A78A-00B0D0180201}'
if (Test-Path 'D:\java\bin\javac.exe') {
    Write-Host "  D:\java 仍存在，正在运行 msiexec ..."
    $p = Start-Process -FilePath 'MsiExec.exe' -ArgumentList "/X$guid", '/qn', '/norestart' -Wait -PassThru
    Write-Host ("  msiexec 退出码：$($p.ExitCode)   （0=成功，1605=未安装，3010=需重启）")
} else {
    Write-Host "  未找到 D:\java\bin\javac.exe，跳过"
}
Write-Host "  保留 Java 8 Update 481 JRE（老应用可能需要 JRE 8 运行时）"

# ------------------------------------------------------------------ 校验
Write-Host ""
Write-Host "===== 6. 校验 =====" -ForegroundColor Cyan
Write-Host "  --- Wise 残留 ---"
foreach ($d in @('C:\Program Files\Wise','C:\Program Files (x86)\Wise')) {
    if (Test-Path -LiteralPath $d) {
        $s = (Get-ChildItem $d -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        Write-Host ("    仍存在：$d  ($([math]::Round($s/1MB,1)) MB)") -ForegroundColor Yellow
    } else {
        Write-Host ("    已清除：$d") -ForegroundColor Green
    }
}
$st = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match 'Wise' }
Write-Host ("    Wise 计划任务剩余：$(if ($st) { $st.TaskName -join ', ' } else { '无' })")
Write-Host ("    SunJavaUpdateSched 剩余：$(if ((Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue).SunJavaUpdateSched) { '是' } else { '否' })")
Write-Host ("    D:\java 剩余：$(Test-Path 'D:\java')")

# ------------------------------------------------------------------ DISM
if (-not $SkipDism) {
    Write-Host ""
    Write-Host "===== 7. DISM 组件清理（可能耗时 10–30 分钟）=====" -ForegroundColor Cyan
    $before = (Get-ChildItem 'C:\Windows\WinSxS' -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    Write-Host ("  WinSxS 清理前：$([math]::Round($before/1GB,2)) GB")
    Write-Host "  正在运行 DISM /Online /Cleanup-Image /StartComponentCleanup ..."
    & dism.exe /Online /Cleanup-Image /StartComponentCleanup /NoRestart
    Write-Host ("  dism 退出码：$LASTEXITCODE")
    $after = (Get-ChildItem 'C:\Windows\WinSxS' -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    Write-Host ("  WinSxS 清理后：$([math]::Round($after/1GB,2)) GB")
    Write-Host ("  回收：$([math]::Round(($before-$after)/1GB,2)) GB")
} else {
    Write-Host ""
    Write-Host "===== 7. 已跳过 DISM（-SkipDism）=====" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "===== 8. 磁盘 =====" -ForegroundColor Cyan
Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
    Where-Object { $_.Used -ne $null } |
    ForEach-Object { Write-Host ("  {0}: 可用 {1} GB" -f $_.Name, [math]::Round($_.Free/1GB,2)) }

Write-Host ""
Write-Host "完成。" -ForegroundColor Green
