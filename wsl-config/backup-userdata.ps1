#Requires -Version 7.0
# ==============================================================================
#  备份不可再生的用户数据到 E 盘
#
#  用法（PowerShell 7）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\backup-userdata.ps1
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\backup-userdata.ps1 -DryRun
#
#  本脚本【不需要】管理员权限（源和目标都在当前用户可访问范围内）。
#
#  为什么目标是 E 盘而不是 D 盘
#  ----------------------------
#      磁盘 0（三星 990 EVO Plus 2TB）  ->  E:
#      磁盘 1（CT1000E100SSD8）         ->  C: 和 D:
#
#  C 盘和 D 盘位于【同一块物理硬盘】。把 C 盘数据备份到 D 盘挡不住硬盘故障——
#  两个分区会一起失效。只有备份到 E 盘才真正跨物理磁盘。
#
#  注意：本地跨盘备份只能防单盘故障，防不住整机丢失/勒索软件/误删。
#        如需异机保护，还需配合云盘或移动硬盘。
#
#  备份范围（约 1.9 GB）
#  ----------------------------
#  只包含【不可再生】的数据。以下内容被刻意排除：
#      Documents\Paradox Interactive   5.4 GB  HOI4 游戏存档
#      Documents\My Games                      游戏配置
#      Documents\BaiduNetdiskTmp               网盘临时文件
#      Desktop\MTool                   1.36 GB 翻译工具本体（可重下）
#      Desktop\Eagle                   281 MB  素材管理程序（可重装）
#      Desktop\Bepinex                 37 MB   游戏模组加载器
#      Desktop\铃兰花圃...\.bobby       65 MB   Bobby 模组区块缓存（自动重建）
#
#  ⚠️ Desktop\重要 里有明文 API 密钥与恢复码。本脚本会备份它，
#     但也请注意：明文存放本身有风险，建议改用密码管理器。
#
#  日志：E:\Backup\_backup-log.txt
# ==============================================================================

param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$root    = 'E:\Backup\UserData'
$logFile = 'E:\Backup\_backup-log.txt'
$stamp   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# 日志目录可能尚不存在（首次运行），必须先建，否则写日志就会失败
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
if (-not $DryRun -and -not (Test-Path -LiteralPath $root)) {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
}

function W([string]$m) { $m | Tee-Object -FilePath $logFile -Append }
# ---------------------------------------------------------------- 源清单
$sources = [ordered]@{
    '重要（密钥/恢复码）' = @{ Src = "$env:USERPROFILE\Desktop\重要";              Dst = 'Desktop\重要' }
    '绘画资料'            = @{ Src = "$env:USERPROFILE\Desktop\绘画资料";           Dst = 'Desktop\绘画资料' }
    '图片'                = @{ Src = "$env:USERPROFILE\Pictures";                  Dst = 'Pictures' }
    '视频录像'            = @{ Src = "$env:USERPROFILE\Videos";                    Dst = 'Videos' }
    '戴森球计划存档'      = @{ Src = "$env:USERPROFILE\Documents\Dyson Sphere Program"; Dst = 'Documents\Dyson Sphere Program' }
    'Saved Games'         = @{ Src = "$env:USERPROFILE\Saved Games";               Dst = 'Saved Games' }
    '文档-其余'           = @{ Src = "$env:USERPROFILE\Documents";                 Dst = 'Documents'; Exclude = @('Paradox Interactive','My Games','BaiduNetdiskTmp','Unicorn','Dyson Sphere Program') }
}

# 我的世界存档：路径含版本目录名，需动态解析
$mcSaves = @()
$mcVer = "$env:APPDATA\.minecraft\versions"
if (Test-Path $mcVer) {
    Get-ChildItem $mcVer -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $s = Join-Path $_.FullName 'saves'
        if (Test-Path $s) { $mcSaves += @{ Ver = $_.Name; Path = $s } }
    }
}

# ---------------------------------------------------------------- 开始
'' | Set-Content $logFile -Encoding UTF8
W "==================== 用户数据备份 ===================="
W "开始时间 : $stamp"
W "目标     : $root"
if ($DryRun) { W "模式     : 预演（不实际写入）" }
W ""

$totalBytes = 0
$totalOK = 0
$totalFail = 0
$results = @()

foreach ($name in $sources.Keys) {
    $item = $sources[$name]
    $src = $item.Src
    $dst = Join-Path $root $item.Dst

    if (-not (Test-Path -LiteralPath $src)) {
        W "跳过：$name —— 源不存在（$src）"
        continue
    }

    # 预估体积时必须扣除排除项，否则数字会严重失真
    # （Documents 排除前 7047 MB，排除 Paradox/My Games 后只有约 100 MB）
    $allFiles = @(Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue)
    if ($item.Exclude) {
        foreach ($e in $item.Exclude) {
            $exPath = (Join-Path $src $e).TrimEnd('\') + '\'
            $allFiles = @($allFiles | Where-Object { -not $_.FullName.StartsWith($exPath, [StringComparison]::OrdinalIgnoreCase) })
        }
    }
    $fileCount = $allFiles.Count
    $size = [double](($allFiles | Measure-Object Length -Sum).Sum)
    if (-not $size) { $size = 0 }

    W "---- $name ----"
    W ("  源  : $src")
    W ("  目标: $dst")
    W ("  内容: $fileCount 个文件 / $([math]::Round($size/1MB,1)) MB")

    if ($DryRun) { W "  [预演] 未执行"; W ""; $totalBytes += $size; continue }

    # robocopy：镜像复制。参数说明见下方注释
    $rcArgs = @(
        $src, $dst,
        '/MIR',            # 镜像（删除目标中源已不存在的文件）
        '/COPY:DAT',       # 数据+属性+时间戳（不含安全描述符，避免权限复制问题）
        '/DCOPY:DAT',      # 目录同样处理
        '/R:2',            # 失败重试 2 次
        '/W:2',            # 重试间隔 2 秒
        '/NP',             # 不显示百分比
        '/NFL',            # 不列出每个文件
        '/NDL',            # 不列出每个目录
        '/XJ',             # 排除 junction（防止递归循环）
        '/NJH', '/NJS'     # 不显示作业摘要/统计（我们自己算）
    )
    if ($item.Exclude) {
        $rcArgs += '/XD'
        foreach ($e in $item.Exclude) { $rcArgs += (Join-Path $src $e) }
    }

    & robocopy.exe @rcArgs | Out-Null
    $code = $LASTEXITCODE

    # robocopy 退出码：0=无变化 1=已复制 2=有多余项 3=1+2 ... 8 以上为错误
    $ok = $code -lt 8
    if ($ok) { $totalOK++ } else { $totalFail++ }
    $results += [PSCustomObject]@{ 项目=$name; 退出码=$code; 结果=$(if ($ok) { '成功' } else { '失败' }) }
    W ("  结果: robocopy 退出码 $code  ->  " + $(if ($ok) { '成功' } else { '失败' }))
    W ""
    $totalBytes += $size
}

# ---------------------------------------------------------------- 我的世界
if ($mcSaves.Count -gt 0 -and -not $DryRun) {
    foreach ($mc in $mcSaves) {
        $dst = Join-Path $root "Minecraft\$($mc.Ver)\saves"
        W "---- 我的世界存档：$($mc.Ver) ----"
        $size = (Get-ChildItem -LiteralPath $mc.Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        W ("  源  : $($mc.Path)")
        W ("  目标: $dst")
        W ("  内容: $([math]::Round($size/1MB,1)) MB")
        & robocopy.exe $mc.Path $dst /MIR /COPY:DAT /DCOPY:DAT /R:2 /W:2 /NP /NFL /NDL /XJ /NJH /NJS | Out-Null
        $code = $LASTEXITCODE
        $ok = $code -lt 8
        if ($ok) { $totalOK++ } else { $totalFail++ }
        $results += [PSCustomObject]@{ 项目="我的世界 ($($mc.Ver))"; 退出码=$code; 结果=$(if ($ok) { '成功' } else { '失败' }) }
        W ("  结果: robocopy 退出码 $code  ->  " + $(if ($ok) { '成功' } else { '失败' }))
        W ""
        $totalBytes += $size
    }
}

# ---------------------------------------------------------------- 汇总
W "==================== 汇总 ===================="
$results | Format-Table -AutoSize | Out-String -Width 80 | ForEach-Object { W $_ }
W ("  成功 $totalOK 项   失败 $totalFail 项")
W ("  源数据合计约 $([math]::Round($totalBytes/1MB,1)) MB")

if (-not $DryRun -and (Test-Path $root)) {
    $actual = (Get-ChildItem $root -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    $cnt = @(Get-ChildItem $root -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    W ("  目标实际占用: $([math]::Round($actual/1MB,1)) MB / $cnt 个文件")
    W ("  位置: $root")
    W ""
    W "  目标盘可用空间:"
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.IsReady -and $d.Name -eq 'E:\') {
            W ("    E: $([math]::Round($d.AvailableFreeSpace/1GB,1)) GB")
        }
    }
}

W ("结束时间 : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
W "DONE"

Write-Host ""
Write-Host "备份完成。日志：$logFile" -ForegroundColor Green
