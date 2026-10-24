#Requires -Version 7.0
# ==============================================================================
#  WSL 配置回滚脚本
#
#  用法（PowerShell 7）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\rollback.ps1
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\rollback.ps1 20260915-210456
#
#  不带参数运行时，列出所有可用的备份时间戳。
#
#  本脚本【不需要】管理员权限。
#
#  为什么强制 PowerShell 7：
#      Windows PowerShell 5.1 会把无 BOM 的 UTF-8 脚本按 GBK 解码，
#      本文件含中文，在 5.1 下会直接解析失败（详见 README 第七节）。
#      #Requires -Version 7.0 会在 5.1 下立刻报错，而不是产生乱码后行为诡异。
# ==============================================================================

param([string]$Stamp)

$profileDir = [Environment]::GetFolderPath('UserProfile')
$distros    = @('Debian', 'Ubuntu-24.04', 'Arch', 'FedoraLinux-44')

if (-not $Stamp) {
    Write-Host "用法：rollback.ps1 <时间戳>" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "全局备份（位于 $profileDir）："
    $global:bak = Get-ChildItem "$profileDir\.wslconfig.bak*" -ErrorAction SilentlyContinue
    if ($bak) { $bak | ForEach-Object { Write-Host ("  " + $_.Name) } }
    else { Write-Host "  （无）" }

    Write-Host ""
    Write-Host "各发行版内的备份："
    foreach ($d in $distros) {
        Write-Host ("  [$d]")
        $hits = & wsl.exe -d $d -u root -- ls -1 /etc/ 2>$null | Select-String 'wsl.conf.bak'
        if ($hits) { $hits | ForEach-Object { Write-Host ("    $_") } }
        else { Write-Host "    （无）" }
    }
    exit 0
}

Write-Host "===== 还原全局 .wslconfig =====" -ForegroundColor Cyan
$bak = "$profileDir\.wslconfig.bak-$Stamp"
if (Test-Path $bak) {
    Copy-Item $bak (Join-Path $profileDir '.wslconfig') -Force
    Write-Host ("  已从 $bak 还原") -ForegroundColor Green
} else {
    Write-Host ("  未找到：$bak") -ForegroundColor Red
}

Write-Host ""
Write-Host "===== 还原各发行版 /etc/wsl.conf =====" -ForegroundColor Cyan
foreach ($d in $distros) {
    & wsl.exe -d $d -u root -- cp "/etc/wsl.conf.bak-$Stamp" /etc/wsl.conf 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("  [$d] 已还原") -ForegroundColor Green
    } else {
        Write-Host ("  [$d] 未找到 /etc/wsl.conf.bak-$Stamp") -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "===== wsl --shutdown =====" -ForegroundColor Cyan
& wsl.exe --shutdown
Start-Sleep -Seconds 3
Write-Host "  已关闭全部发行版" -ForegroundColor Green
