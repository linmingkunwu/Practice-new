#Requires -Version 7.0
# ==============================================================================
#  WSL 配置应用脚本
#
#  用法（PowerShell 7）：
#      pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\apply.ps1
#
#  做四件事：
#      1. 备份并替换全局   C:\Users\<你>\.wslconfig
#      2. 备份并替换四个发行版的 /etc/wsl.conf
#      3. wsl --shutdown
#      4. （稀疏 VHD 步骤已废弃，见第 6 步说明）
#
#  回滚：pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\rollback.ps1 <时间戳>
#
#  本脚本【不需要】管理员权限。
# ==============================================================================

$src        = 'E:\Git\wsl-config'
$stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$profileDir = [Environment]::GetFolderPath('UserProfile')

$distros = [ordered]@{
    'Debian'         = 'debian'
    'Ubuntu-24.04'   = 'ubuntu'
    'Arch'           = 'arch'
    'FedoraLinux-44' = 'fedora'
}

Write-Host "===== 0. 预检：发行版内能否看到 /mnt/e =====" -ForegroundColor Cyan
& wsl.exe -d Debian -u root -- ls /mnt/e/Git/wsl-config
if ($LASTEXITCODE -ne 0) {
    Write-Host "中止：无法从 WSL 内访问 /mnt/e/Git/wsl-config。未做任何修改。" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "===== 1. 现有备份（首次运行应为空）=====" -ForegroundColor Cyan
$existing = Get-ChildItem "$profileDir\.wslconfig.bak-*" -ErrorAction SilentlyContinue
if ($existing) { $existing | ForEach-Object { Write-Host ("  发现：" + $_.Name) } }
else { Write-Host "  （无）" }
foreach ($d in $distros.Keys) {
    $b = & wsl.exe -d $d -u root -- ls -1 /etc/ 2>$null | Select-String 'wsl.conf.bak'
    if ($b) { foreach ($line in $b) { Write-Host "  [$d] /etc/$line" } }
}

Write-Host ""
Write-Host "===== 2. 应用全局 .wslconfig =====" -ForegroundColor Cyan
$dst = Join-Path $profileDir '.wslconfig'
Copy-Item $dst "$dst.bak-$stamp" -Force
Write-Host "  已备份 -> $dst.bak-$stamp"
Copy-Item (Join-Path $src '.wslconfig') $dst -Force
Write-Host "  已写入 $dst" -ForegroundColor Green

Write-Host ""
Write-Host "===== 3. 应用各发行版 /etc/wsl.conf =====" -ForegroundColor Cyan
foreach ($d in $distros.Keys) {
    $name = $distros[$d]
    & wsl.exe -d $d -u root -- cp /etc/wsl.conf "/etc/wsl.conf.bak-$stamp" 2>&1 | Out-Null
    & wsl.exe -d $d -u root -- cp "/mnt/e/Git/wsl-config/$name.wsl.conf" /etc/wsl.conf 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [$d] 复制失败，已跳过" -ForegroundColor Red
        continue
    }
    & wsl.exe -d $d -u root -- sed -i 's/\r$//' /etc/wsl.conf 2>&1 | Out-Null
    Write-Host "  [$d] 已应用（原文件备份为 /etc/wsl.conf.bak-$stamp）" -ForegroundColor Green
}

Write-Host ""
Write-Host "===== 4. 校验写入结果 =====" -ForegroundColor Cyan
foreach ($d in $distros.Keys) {
    Write-Host "--- $d ---" -ForegroundColor Yellow
    & wsl.exe -d $d -u root -- cat /etc/wsl.conf
}

Write-Host ""
Write-Host "===== 5. wsl --shutdown =====" -ForegroundColor Cyan
& wsl.exe --shutdown
Start-Sleep -Seconds 3
Write-Host "  已关闭全部发行版"

Write-Host ""
Write-Host "===== 6. 稀疏 VHD：已跳过（当前 WSL 版本不支持）=====" -ForegroundColor Cyan
Write-Host "  WSL 2.7.13 已全局禁用稀疏 VHD，实测报错原文："
Write-Host "    「由于潜在的数据损坏，目前已禁用稀疏 VHD 支持。」"
Write-Host "    / 错误代码 Wsl/Service/E_INVALIDARG"
Write-Host "  因此 'sparseVhd=true' 与 '--set-sparse true' 在这台机器上都是空操作。"
Write-Host "  【不要】加 --allow-unsafe：报错原文明确写了「潜在的数据损坏」。"
Write-Host "  要回收 vhdx 空间，请在 wsl --shutdown 后手动压缩："
Write-Host "    diskpart"
Write-Host '      select vdisk file="E:\WSL\<发行版>\ext4.vhdx"'
Write-Host "      attach vdisk readonly"
Write-Host "      compact vdisk"
Write-Host "      detach vdisk"
Write-Host "      exit"

Write-Host ""
Write-Host "===== 7. 最终状态 =====" -ForegroundColor Cyan
& wsl.exe -l -v
[System.IO.DriveInfo]::GetDrives() |
    Where-Object { $_.IsReady -and $_.TotalSize -gt 0 } |
    Select-Object Name,
        @{n='总GB';  e={[math]::Round($_.TotalSize/1GB,1)}},
        @{n='可用GB'; e={[math]::Round($_.AvailableFreeSpace/1GB,1)}},
        @{n='可用%';  e={[math]::Round(100*$_.AvailableFreeSpace/$_.TotalSize,1)}} |
    Format-Table -AutoSize

Write-Host ""
Write-Host "完成。时间戳 = $stamp" -ForegroundColor Green
