# WSL 配置调整记录

主机：Windows 11 Build 26200.9445 / 31.2 GB 内存 / 24 逻辑核心
WSL：2.7.13.0，内核 6.18.33.2-2，WSLg 1.0.73.2
发行版：Debian（默认）、Ubuntu-24.04、Arch、FedoraLinux-44，全部位于 `E:\WSL\`

---

## 一、改了什么

### 全局 `C:\Users\琳珉琨珸\.wslconfig`

原有的三项网络设置**原样保留**（`networkingMode=mirrored` / `dnsTunneling` / `autoProxy`），新增：

| 项 | 值 | 理由 |
|---|---|---|
| `memory` | `16GB` | 四个发行版共享同一个虚拟机，显式写死防止行为漂移 |
| `processors` | `16` | 原为吃满 24 核，留 8 核给 Windows |
| `swap` + `swapFile` | `4GB` → `E:\WSL\swap.vhdx` | 原在 `C:\...\Temp`，而 C 盘紧张 |
| `autoMemoryReclaim` | `gradual` | 页缓存归还 Windows |
| `hostAddressLoopback` | `true` | mirrored 下访问宿主其它 IP |

### 各发行版 `/etc/wsl.conf`

`[boot] systemd=true` 保留，新增默认用户、挂载选项、interop、hostname：

- `[user] default=linminkunwu` —— 四个发行版统一
- `[automount] options="metadata,umask=22,fmask=11"` —— 让 `/mnt/e` 支持 Linux 权限位
- `[interop] appendWindowsPath=false` —— **影响日常使用，见下方"注意"**
- `[network] hostname=<发行版名>` —— 四个发行版可区分

---

## 二、注意：`appendWindowsPath=false` 会改变你的使用习惯

这条会从 Linux 的 `PATH` 里移除整条 Windows 路径。带来的好处是四个发行版不再出现
`python` / `node` / `git` / `docker` 命令来源不明，shell 启动也更快。

代价：**无法再用短名调用 Windows 程序**。以下写法失效：

```
code .            # 需要改用发行版内自装的 code
explorer.exe .
clip.exe
```

仍然可用的是完整路径调用：`/mnt/c/Windows/explorer.exe`。

改回默认只需把 `appendWindowsPath` 改成 `true`，然后 `wsl --terminate <发行版>`。

---

## 三、修正：稀疏 VHD 在当前版本不可用

原计划用 `sparseVhd=true` 和 `wsl --manage <发行版> --set-sparse true` 回收 vhdx 空间，
**实测两者都不生效**。WSL 返回的原文：

```
由于潜在的数据损坏，目前已禁用稀疏 VHD 支持。
要强制发行版使用稀疏 VHD，请运行:
wsl.exe --manage <DistributionName> --set-sparse true --allow-unsafe
错误代码: Wsl/Service/E_INVALIDARG
```

即 WSL 已**全局禁用**稀疏 VHD。`sparseVhd=true` 是空操作，已从 `.wslconfig` 移除。

**不要使用 `--allow-unsafe`** —— 官方提示原文明确写着「潜在的数据损坏」。

`fsutil sparse queryflag` 确认四个 vhdx 当前均非稀疏，且体积未变。

回收 vhdx 空间的替代方案（手动）：

```powershell
wsl --shutdown
# 用 diskpart 逐个压缩，或直接用 Hyper-V 的 Optimize-VHD
diskpart
  select vdisk file="E:\WSL\Ubuntu\ext4.vhdx"
  attach vdisk readonly
  compact vdisk
  detach vdisk
  exit
```

---

## 四、刻意没有做的事

- **`firewall=true`**：已写在 `.wslconfig` 里但保持注释状态。mirrored + 系统代理 +
  Docker Desktop 本身已是上游已知的问题组合，再叠一层 Hyper-V 防火墙会让排障变复杂。
  需要时取消注释即可。
- **`--allow-unsafe`**：见上。
- **删除 docker-desktop**：这是需要你决策的架构选择，没有代你执行。

---

## 五、验证结果

| 检查项 | Debian | Ubuntu-24.04 | Arch | FedoraLinux-44 |
|---|---|---|---|---|
| 启动 / systemd | running | running | running | running |
| `nproc` | 16 | 16 | 16 | 16 |
| 内核主机名 | debian | ubuntu | arch | fedora |
| 默认用户 | linminkunwu | linminkunwu | linminkunwu | linminkunwu |
| `PATH` 含 Windows 路径 | 否 | 否 | 否 | 否 |
| `/mnt/e` 挂载参数 | metadata 生效 | metadata 生效 | metadata 生效 | metadata 生效 |
| `systemctl --failed` | 无 | 无 | 无 | `user@0.service` |

内存总数 15 GiB（对应 `memory=16GB`），swap 4.0 GiB。

### 属于噪音、无需处理的项

- **`user@0.service` 失败**（仅 Fedora 可见）：WSL 会尝试为 root 启动 systemd 用户会话，
  systemd 对 UID 0 的用户管理器处理不正常。与本次改动无关，且不影响使用。
- **`wsl: Failed to start the systemd user session`**：同上，同一个成因。
- **`misc dxg: dxgkio_query_adapter_info: Ioctl failed: -22`**：WSLg / Direct3D 常规噪音。
- **Arch / Fedora 上 `hostname` 命令不存在**：这两个发行版默认没装 `inetutils`。
  只是查询工具缺失，内核主机名是正确的。需要的话 `pacman -S inetutils` / `dnf install hostname`。

---

## 六、尚未解决 / 待你决定

### 1. 磁盘空间

```
C:  230 GB 总  →  剩 12.2 GB ( 5.3%)
D:  701 GB 总  →  剩 17.2 GB ( 2.4%)
E: 1863 GB 总  →  剩 51.3 GB ( 2.8%)
```

四个 vhdx 合计仅 11.9 GB，且体积未变，所以 E 盘从 15.6 GB 变成 51.3 GB
**不是本次 WSL 改动带来的**，是同期别的东西释放了空间。C 盘和 D 盘依然很紧张。

Docker Desktop 的镜像数据盘在 `%LOCALAPPDATA%\Docker\wsl\main`，即 **C 盘**。

### 2. Docker Desktop 与 mirrored 网络的冲突

当前组合：`networkingMode=mirrored` + `autoProxy=true` + Docker Desktop
（`HostNetworkingEnabled: true`，手动代理指向 `http://127.0.0.1:7897`）。

这是上游已知的问题组合，参见：

- <https://github.com/docker/for-win/issues/14691>
- <https://forums.docker.com/t/docker-desktop-4-40-4-41-cannot-pull-any-images-when-wsl2-networkingmode-mirrored-and-the-system-proxy-is-enabled/148344>
- <https://forums.docker.com/t/host-networking-not-working-on-docker-desktop-in-wsl2-with-mirrored-mode/147994>
- <https://github.com/microsoft/WSL/issues/13210>

三条路：保 mirrored 并调整 Docker 网络设置 / 退回 NAT / 改在 Ubuntu-24.04 里装原生
docker-ce 并弃用 Docker Desktop。最后一条同时缓解 C 盘压力。

### 3. 一处不一致

默认发行版是 **Debian**，但 `EnableIntegrationWithDefaultWslDistro: true` 配合
`IntegratedWslDistros: ["Ubuntu-24.04"]`，意味着 Docker CLI 会同时注入这两个发行版。

---

## 七、文件说明

| 文件 | 作用 |
|---|---|
| `.wslconfig` | 全局配置的来源副本，目标为 `C:\Users\琳珉琨珸\.wslconfig` |
| `debian.wsl.conf` | Debian 的 `/etc/wsl.conf` 来源副本 |
| `ubuntu.wsl.conf` | Ubuntu-24.04 的 |
| `arch.wsl.conf` | Arch 的 |
| `fedora.wsl.conf` | FedoraLinux-44 的 |
| `apply.ps1` | 应用 WSL 配置（**不需要**管理员） |
| `rollback.ps1` | 回滚 WSL 配置（**不需要**管理员） |
| `cleanup-redundant.ps1` | 卸载 Wise 三件套 + JDK 8、可选 DISM 组件清理 |
| `clean-leftovers.ps1` | 清理 Wise / Docker / Java 的卸载残留 |
| `clean-360-leftovers.ps1` | 清理 360 遗留的注册表与服务项 |
| `clean-360-driver.ps1` | 删除 360 孤儿驱动；可选调整 E 盘分页文件 |
| `set-pagefile.ps1` | 把分页文件迁移到 E 盘 |
| `set-toolchain-path.ps1` | 切换工具链 PATH（**危险，见下**） |
| `fix-toolchain-path.ps1` | 回退上述切换（`-Mode Revert` / `-Mode AsciiToolchain`） |
| `switch-pwsh-to-msi.ps1` | 把 PowerShell 7 从 MSIX 切换为官方 MSI（一次性，已完成） |

**除 `apply.ps1` 与 `rollback.ps1` 外，其余脚本都会在需要时自动提权**
（`Start-Process pwsh -Verb RunAs`，会弹 UAC），无需手动开管理员终端。

### 关于脚本编码（2026-09-30 已解决）

**问题（2026-09-29）**：这台机器当时**没有安装 PowerShell 7**，`pwsh` 根本不存在；
实际执行脚本的一直是 **Windows PowerShell 5.1**。
**PS 5.1 会把无 BOM 的 UTF-8 脚本文件按 ANSI/GBK 解码**，脚本里的中文
字面量因此变成乱码，进而破坏字符串边界与解析。

第一次执行 `apply.ps1` 失败即由此产生——当时我误判为"调用方 stdout 解码问题"，
真正的成因就是 PS 5.1 的脚本编码。同一天我又踩了第二次：把
`C:\Users\琳珉琨珸\...` 硬编码进 `set-toolchain-path.ps1` 后，dry-run 立刻报路径不存在，
用户名显示为 `鐞崇弶鐞ㄧ徃`。第三次是命令行正则里写了中文
（`'360|悟空|安全卫士|...'`），同样被破坏——**不只脚本文件，命令行参数也一样**。

**解决（2026-09-30）**：安装 **PowerShell 7.6.6**
（`winget install --id Microsoft.PowerShell --exact`，MSIX 应用包方式）。

同一个无 BOM 的 UTF-8 测试脚本，两种宿主的表现：

| 宿主 | 结果 |
|---|---|
| PowerShell 5.1 | ❌ 乱码 + 级联 ParseError（`The string is missing the terminator`） |
| **PowerShell 7.6.6** | ✅ 中文、中文路径、中文正则、中文文件名**全部正常** |

其它改善：控制台/输出编码从 GBK 变为 **UTF-8**；`PSEdition=Core`；
启动耗时 **1229ms → 365ms**（约 3.4 倍）。

**现行约定（2026-09-30 全面改造后）**：

本目录 9 个脚本已全部改造为 PowerShell 7 专用：

| 约定 | 说明 |
|---|---|
| **`#Requires -Version 7.0`** | 每个脚本首行都有。在 5.1 下会**立刻明确报错**（`ScriptRequiresUnmatchedPSVersion`），而不是产生乱码后行为诡异 |
| **中文注释与输出** | 已全部恢复中文。PS 7 的控制台/输出编码是 UTF-8，不再有 GBK 问题 |
| **自动提权** | 需要管理员的 6 个脚本内建 `Start-Process pwsh -Verb RunAs`，运行时弹 UAC，**无需手动开管理员终端，也不再需要外部 .cmd 启动器** |
| **路径写法** | 仍不写死中文用户名，用 `$env:LOCALAPPDATA` 或通配符 `C:\Users\*\...`（不是为了避编码，而是为了让脚本换用户名也能用） |
| **危险操作加闸** | `set-toolchain-path.ps1` 已知会让 gcc 无法编译，因此必须显式传 `-IUnderstandTheRisk` 才会执行 |

> 验证：10 个脚本在 PS 7 下 `Parser::ParseFile` 全部 **OK**；
> `#Requires` 在 5.1 下的拒绝行为已实测确认。

### 安装方式：MSIX → MSI（2026-09-30 切换）

最初用 `winget install --id Microsoft.PowerShell` 安装，得到的是 **MSIX 应用包**——
因为 winget 清单里该包的安装器类型**写死为 `msix`**（指向 `.msixbundle`），
msstore 源里也没有它。MSIX 版有一个实际缺点：

> **Windows Terminal 只检测 `C:\Program Files\PowerShell\7\pwsh.exe`**，
> 而 MSIX 版装在 `C:\Program Files\WindowsApps\...` 下，因此 WT 的 profile 列表里
> **不会出现 PowerShell 7**（本机 11 个 profile 中确实没有）。

改用官方 **MSI** 后：标准安装路径、系统级 PATH、WT 自动识别。
脚本：`switch-pwsh-to-msi.ps1`（一次性，已完成）。

| | MSIX（原） | MSI（现） |
|---|---|---|
| 安装位置 | `C:\Program Files\WindowsApps\...` | **`C:\Program Files\PowerShell\7`** |
| PATH 来源 | 用户 PATH 里的 WindowsApps 别名 | **系统 PATH** |
| WT 识别 | ❌ 不识别 | ✅ 识别 |
| 维护 | winget / Store | winget / Microsoft Update |

**提权方式仍然有效**：换成标准路径后，`Start-Process pwsh -Verb RunAs` 经 PATH 解析
与用绝对路径**两种方式都实测成功**（`isAdmin=True`、`PSHOME=C:\Program Files\PowerShell\7`、
中文正常），因此 6 个脚本无需改动。

> **踩坑记录：卸载 MSIX 时会杀死自己**
> 首次执行时，`.cmd` 启动器里的 `pwsh.exe` 经 PATH 解析到的**正是 MSIX 包内的可执行文件**。
> `Remove-AppxPackage` 删除该包等于删除正在运行的程序，脚本被自身卸载操作杀死
> （日志停在卸载那一刻，退出码 1）。
> 但**卸载本身是成功的**，结果是"MSIX 已删、MSI 未装"的中间状态。
>
> 正确做法：**用一个不依赖 PowerShell 7 的载体执行卸载**——
> 最终用 `.cmd` + `powershell.exe`（5.1）直接调用 `msiexec` 完成安装。
> 教训：**自更新类脚本不能用即将被自己删除的运行时来执行。**

> **镜像下载与签名校验**
> GitHub 直连下载 112 MB 的 MSI 只有 6.4 KB/s（预计 263 分钟）。改用
> `gh-proxy.com` 代理后达 1767 KB/s（65 秒完成）。
> **使用第三方代理下载可执行文件必须校验 Authenticode 签名**——
> 实测签名状态 `Valid`、签名主体 `CN=Microsoft Corporation`、文件头 `D0CF11E0`（真 MSI），
> 据此确认代理未篡改内容。SHA256 留档：
> `958838FF55091E1C8705D89EFED0CC7E8245A3A6EF6C0CCFAE20015227108AD8`

---

## 八、2026-09-29 复查与后续处理

14 天后复查：四个发行版 `/etc/wsl.conf` 与本目录源文件 **MD5 逐一吻合**，`.wslconfig`
源与目标 SHA256 一致——**零漂移**。Arch/Fedora 的 `systemd=degraded` 经交替 A/B 实验
证明是 WSL 反复冷启动下的 spawn 竞态（`user@1000.service` / `Device or resource busy`），
与配置无关，对应上游 microsoft/WSL#40593 与 #10205。

### 磁盘清理（C: 10.63 GB → 47.73 GB）

| 项目 | 释放 | 说明 |
|---|---|---|
| `um-react!<GUID>` WebView2 数据 | 17.37 GB | 孤儿数据，程序未安装、9.5 个月未触碰 |
| `.dsh-wallpaper-engine\cache\frames` | 7.21 GB | 壁纸引擎帧缓存；`config.json` / `uploads` / `overrides` 全部保留 —— **见下方更正：此缓存当晚即自动重建** |
| Docker Desktop 卸载 | 5.91 GB | 含 `docker-desktop` 发行版移除 |
| NVIDIA `ota-artifacts` 驱动包 | 3.78 GB | 15 个月前的旧驱动安装包 |
| `SquirrelTemp` | 1.24 GB | 安装器临时目录 |
| `C:\llvm-mingw-*` / `mingw64` / `DiskGenius_WinPE` | 1.83 GB | 移至 `D:\Toolchains` 并建立 junction |

### 工具链迁移（junction 方式）

`C:\mingw64\bin` 与 `C:\llvm-mingw-...\bin` **本来就在系统 PATH 中**，直接移动会导致
编译工具链全废。处理方式：移动到 `D:\Toolchains\` 后在原路径建立目录联接。

```
C:\mingw64                          -> D:\Toolchains\mingw64                          (Junction)
C:\llvm-mingw-20251216-ucrt-x86_64  -> D:\Toolchains\llvm-mingw-20251216-ucrt-x86_64  (Junction)
C:\DiskGenius_WinPE                 -> D:\Toolchains\DiskGenius_WinPE                 (Junction)
```

PATH 项、快捷方式、脚本全部无感，`Get-Command gcc` 仍解析到 `C:\mingw64\bin\gcc.exe`。

### 弃用 Docker Desktop，改用 Ubuntu-24.04 原生 docker-ce

**这一改动同时解决了三件事**：C 盘占用、mirrored 网络冲突、WSL 被自动拉起。

| 项 | 状态 |
|---|---|
| docker-ce | 29.8.1 |
| containerd.io | 2.3.6 |
| docker-buildx-plugin | 0.37.1 |
| docker-compose-plugin | v5.5.1 |
| `/usr/bin/docker` | 归属 `docker-ce-cli`（不再是 Docker Desktop 软链） |
| `systemctl is-enabled docker` | enabled |
| 普通用户免 sudo | `linminkunwu` 已在 `docker` 组 |

守护进程代理（systemd drop-in，因为服务不继承 shell 环境变量）：

```ini
# /etc/systemd/system/docker.service.d/proxy.conf
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:7897"
Environment="HTTPS_PROXY=http://127.0.0.1:7897"
Environment="NO_PROXY=localhost,127.0.0.1,::1,*.local"
```

**镜像加速的必要性**：clash 把 `registry-1.docker.io` 与
`production.cloudflare.docker.com` 分流为直连，而这两个域名在此网络不可达
（Windows 侧走同一代理也同样失败，`auth.docker.io` 却返回 200）。
故 `/etc/docker/daemon.json` 配置为：

```json
{ "registry-mirrors": ["https://docker.m.daocloud.io", "https://docker.1ms.run"] }
```

若以后调整 clash 规则让上述域名走代理，可删掉该文件恢复官方源。
Docker Desktop 卸载后 `wsl --shutdown` 不再被自动拉起，第九节的回滚不受影响。

### 两处未能处理（需要管理员权限）

| 项目 | 大小 | 原因 | 处理方式 |
|---|---|---|---|
| `C:\llvm-mingw-20251216-ucrt-x86_64.zip` | 0.17 GB | 拒绝访问，`avp`/`avpui`（Kaspersky）持有句柄；当前会话非管理员 | 管理员 PowerShell 执行 `Remove-Item`，或重启后重试 |
| `C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\grd` | 3.56 GB | 12 个 NVIDIA 进程占用，强删有破坏显卡驱动会话的风险 | 管理员 PowerShell 中先停 NVIDIA 相关服务再删 |

D 盘副本已校验与 C 盘原文件 **180742129 字节完全一致**，残留不影响任何功能。

### 新增脚本

| 文件 | 作用 |
|---|---|
| `install-docker-ce.sh` | 安装原生 docker-ce（清理 Docker Desktop 软链、配置守护进程代理、加入 docker 组） |
| `configure-docker-mirror.sh` | 配置 `/etc/docker/daemon.json` 镜像加速（会备份已有配置） |

两个脚本均为纯 ASCII 输出，可重复执行。

---

## 九、2026-09-29 工具链 PATH 事故与回退

### 起因

Machine PATH 索引 12/14 是旧工具链条目，而 Windows 的进程 PATH 是
**Machine 在前、User 在后**，所以 User PATH 里 WinGet 装的新版本一直被遮蔽。

### 执行

`set-toolchain-path.ps1` 做了位置替换，把两条旧条目换成 WinGet 路径。
替换本身是成功的（备份 `Machine-PATH-backup-20260929-223427.txt`）。

### 后果：gcc 完全不可用

WinLibs gcc 16.1.0 **无法处理非 ASCII 路径**。实测矩阵：

| 组合 | 结果 |
|---|---|
| 16.1.0 + 中文 TEMP + 中文安装路径 | ❌ 汇编阶段 |
| 16.1.0 + ASCII TEMP + 中文安装路径 | ❌ 链接阶段（找不到 `crt2.o`） |
| 16.1.0 + 中文 TEMP + ASCII 安装路径 | ❌ 汇编阶段 |
| 16.1.0 + ASCII TEMP + ASCII 安装路径 | ✅ |
| 15.2.0 + 中文 TEMP + ASCII 安装路径 | ✅ |

本机 TEMP 是 `C:\Users\琳珉琨珸\AppData\Local\Temp`，WinGet 又把包装在含中文的
路径下，因此 **gcc 16.1.0 在默认配置下不可能工作**。

对照组：**clang 22.1.8 在同一个中文路径下完全正常**（clang 的路径处理是正确的），
旧 gcc 15.2.0 也正常。

### 回退

`fix-toolchain-path.ps1`（默认 `-Mode Revert`）从
`D:\Backups\Machine-PATH-backup-20260929-223427.txt` 还原 Machine PATH。
还原后 gcc 15.2.0、g++、cmake 3.29.2 全部恢复，C 与 C++ 编译测试均通过。

### 结论（2026-09-30 已实质性修正，见下节）

- **Windows 侧不要使用 WinLibs 的 gcc**，原因不是版本，而是这个构建系列本身的问题
  （详见第十节）。
- **clang 22.1.8（WinGet llvm-mingw）可继续使用**，它不受中文路径影响。
- 教训：**"版本更新"不等于"可用的更新"**。切换编译器后必须做真实编译+运行测试，
  只看 `--version` 会漏掉这类路径/ABI 问题。

---

## 十、2026-09-30 工具链问题彻底解决

### 第一步：修正一个错误的泛化结论

第九节写的是"WinLibs gcc **16.1.0** 无法处理非 ASCII 路径"，但当时的实测只覆盖了
三个构建，且有一个关键对照**条件设错了**：测 Strawberry 的 gcc 时我给它用了
**ASCII TEMP**，所以得出了"这是 16.1.0 特有的回归"的错误印象。

补齐测试后（**全部在默认中文 TEMP 下**）：

| 构建 | 安装路径 | 结果 |
|---|---|---|
| **MinGW-Builds 15.2.0** | ASCII | ✅ 成功 |
| **WinLibs r8（Strawberry）13.2.0** | ASCII | ❌ 失败，`can't create ...Temp\xx.o` |
| **WinLibs r1（WinGet）16.1.0** | 中文 | ❌ 失败 |
| WinLibs 16.1.0 + ASCII TEMP | 中文 | ❌ 仍失败 |

**真实规律：不是某个版本的问题，而是「WinLibs 系构建」全系无法处理中文 TEMP；
MinGW-Builds 系则完全正常。**

> 教训：**A/B 对照实验里，被测变量的历史状态必须一致。** 我无意中让对照组
> 带着一个已改变的变量（ASCII TEMP）去测试，直接导致结论范围错误。

### 第二步：换 MinGW-Builds 的新构建（不需要改 TEMP）

`niXman/mingw-builds-binaries` 最新为 **16.2.0-rt_v14-rev1**。

**变体必须匹配**：看起来当前是 `x86_64-win32-seh-rev0`，但其 `--with-sysroot`
指向 `x86_64-1520-win32-seh-**ucrt**-rt_v13-rev0`，且产物的 DLL 依赖是
`api-ms-win-crt-*.dll` —— 说明**实际运行时是 UCRT**。因此选：

```
x86_64-16.2.0-release-win32-seh-ucrt-rt_v14-rev1.7z     (102.9 MB)
```

线程模型（win32）、异常模型（seh）、运行时（UCRT）全部一致，**只有 gcc 版本变化**。

### 验证结果

| 项目 | 结果 |
|---|---|
| C 编译（中文 TEMP） | ✅ |
| C++20 编译运行（`<thread>` 4 线程 + `<mutex>` + `<filesystem>` + `<numeric>`） | ✅ |
| 运行时 | UCRT，与旧版一致 |
| gcc / g++ / gfortran | 16.2.0 |
| gdb / binutils / make | 17.2 / 2.47 / 4.4.1 |
| 安装路径 | 纯 ASCII ✓ |

**因此完全不需要修改全局 TEMP。** 这一点很关键：原方案要动的是影响全机所有软件的
设置，还有多账户共享 `C:\Temp` 的 ACL 隐患；换构建则零全局改动。

### 切换方式：只改 junction，不碰 PATH

Machine PATH 索引 12 是 `C:\mingw64\bin`，而 `C:\mingw64` 是一个 **junction**。因此：

```
C:\mingw64   Junction:  D:\Toolchains\mingw64  →  D:\Toolchains\mingw64-16.2.0\mingw64
```

| 好处 | 说明 |
|---|---|
| **PATH 一个字都不用改** | 零风险，不会像上次那样误伤 PATH |
| **完全可逆** | `switch-mingw-toolchain.ps1 -Revert` 一条命令还原 |
| **路径保持 ASCII** | `C:\mingw64` 永远是 ASCII |

脚本：`switch-mingw-toolchain.ps1`（需管理员，自动提权）

### 额外好处：避开了 CMake 4 的破坏性变更

WinLibs 包**捆绑了自己的 cmake 4.3.2 / ninja / cppcheck / ctags / doxygen**，
一旦接管 PATH 会遮蔽 Strawberry 的版本，而 CMake 4 取消了对
`cmake_minimum_required(VERSION <3.5)` 的兼容，老项目会直接 configure 失败。

**MinGW-Builds 不捆绑 cmake**，所以 Strawberry 的 **cmake 3.29.2 / ninja 1.12.0
原样保留**，这个问题自动消失。

### 当前工具链全景

| 工具 | 版本 | 位置 |
|---|---|---|
| gcc / g++ / gfortran | 16.2.0 | `C:\mingw64\bin`（junction） |
| clang / clang++ | 22.1.8 | WinGet `MartinStorsjo.LLVM-MinGW.UCRT` |
| cmake | 3.29.2 | `C:\Strawberry\c\bin` |
| ninja | 1.12.0 | `C:\Strawberry\c\bin` |
| gdb | 17.2 | `C:\mingw64\bin` |

备份保留：旧 gcc 15.2.0 仍在 `D:\Toolchains\mingw64`（720 MB，回滚用）；
安装包在 `E:\Git\_gcc16\`（103 MB）。

> 注意：**WinLibs 仍然留在机器上**（WinGet 包与 Strawberry 的 13.2.0）。
> 它们因为中文 TEMP 而无法编译，但**不影响任何东西**——因为
> `C:\mingw64\bin`（索引 12）在 `C:\Strawberry\c\bin`（索引 17）之前。
> 若要彻底避免混淆可卸载，但没必要。

---

## 十一、回滚

```powershell
# 查看可用的备份时间戳
pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\rollback.ps1

# 回滚到指定时间戳
pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Git\wsl-config\rollback.ps1 20260915-210456
```

备份位置：

- `C:\Users\琳珉琨珸\.wslconfig.bak-<时间戳>`
- 各发行版内 `/etc/wsl.conf.bak-<时间戳>`

`rollback.ps1` 已实测有效：2026-09-15 的全量重做中，它把 `.wslconfig` 和四个发行版的
`/etc/wsl.conf` 精确还原到改动前的状态，随后 `apply.ps1` 再重新应用，最终验证全部通过。

### 现有备份

| 时间戳 | 内容 |
|---|---|
| `20260915-210456` | 原始状态（改动前的 `.wslconfig` 与四个 `wsl.conf`） |
| `20260915-210824` | 仅全局：去掉 `sparseVhd` 之前的中间版本 |
| `20260915-211244` | 原始状态（全量重做时，回滚后再次备份所得，与 210456 等价） |

回滚到原始状态用 `20260915-210456` 或 `20260915-211244` 均可。

---

## 十二、2026-09-29 系统冗余软件清理

脚本：`cleanup-redundant.ps1`（纯 ASCII，可重复执行，`-SkipDism` 可跳过慢步骤）

### 已移除

| 项目 | 说明 |
|---|---|
| Wise Memory Optimizer 4.2.4 | 强制 TrimWorkingSet 回收内存，被换出的页面再次访问会触发硬缺页，**通常降低而非提升性能** |
| Wise Care 365 8.0.5 | 注册表清理类工具 |
| Wise Folder Hider 5.1.1 | 同上 |
| `WiseBootAssistant` 服务 | 随卸载停止 |
| `Wise Care 365.job` / `Wise Turbo Checker.job` | 两个登录计划任务 |
| `SunJavaUpdateSched` | HKLM WOW6432 Run 启动项 |
| Java SE Development Kit 8 Update 201 | 2019 年构建，`JAVA_HOME` 与 PATH 均指向 Adoptium JDK 21 |

**刻意保留**：Java 8 Update 481 JRE —— 老应用可能依赖 JRE 8 运行时。

### 刻意未动（重要更正）

`AppData\Local\Google`（949 MB）和 `AppData\Local\NetEase`（944 MB）一度被我判为陈旧，
**实际都是活跃数据**：前者是 Chrome 的用户资料（书签/密码/Cookie），后者是网易云音乐。
误判原因是我读了**父目录**的修改时间（2025-08），而内部文件当天仍在写入。

> 教训：判断目录是否废弃必须看**递归后的最新写入时间**，不能看顶层目录时间戳。

### DISM 结果

`DISM /Online /Cleanup-Image /StartComponentCleanup` 执行成功（exit 0），
但 WinSxS 清理前后均为 **12.87 GB，未回收任何空间** —— 组件存储本就干净。
未使用 `/ResetBase`，因为那会失去卸载已安装更新的能力。

### 顺带发现

- **`D:\$RECYCLE.BIN` 10.71 GB** —— 可清空（属用户主动删除的内容）
- **分页文件分布在三个盘**：C 16.0 GB + D 5.0 GB + E 5.0 GB = **26.3 GB**，
  全部为「系统托管」。合并到单盘可回收约 10 GB（需管理员 + 重启）。
  注：`Get-Item` 直接读取 `pagefile.sys` 会静默失败，需用 `Win32_PageFileUsage` 查询。
- **`D:\steam\steamapps\workshop` 471.99 GB** —— D 盘最大占用（Wallpaper Engine 创意工坊内容）

---

## 十三、2026-09-29 分页文件迁移到 E 盘

脚本：`set-pagefile.ps1`（纯 ASCII，`-CKeepMB 0` 可连 C 盘的一起去掉）

### 为什么值得迁移：实测硬件拓扑

```
Disk 0 - Samsung SSD 990 EVO Plus 2TB, NVMe  ->  E:
Disk 1 - CT1000E100SSD8,               NVMe  ->  C: 和 D:
```

**C: 和 D: 在同一块物理盘上**，两个分页文件在争抢同一设备的 I/O；
**E: 是另一块独立且更快的 NVMe SSD**。所以迁移不只是省空间，而是把页面文件的
I/O 从系统盘分流到第二个物理设备。

### 配置

| 盘 | 迁移前 | 迁移后 |
|---|---|---|
| C: | 16405 MB 系统托管 | **4096 MB 固定** |
| D: | 5120 MB 系统托管 | **移除** |
| E: | 5120 MB 系统托管 | **系统托管（主分页）** |

`AutomaticManagedPagefile` 已设为 `False`，改由显式条目控制。

**C: 保留 4 GB 的原因**：Windows 只能把内核崩溃转储写入**引导卷**的分页文件。
C: 完全不放会失去 BSOD 转储能力。不在意的话用 `-CKeepMB 0` 再省 4 GB。

预计回收：**C: 12 GB + D: 5 GB = 17 GB**，重启后生效。

### 踩坑记录：`New-CimInstance` 的 uint32 类型问题

第一次执行时脚本在**已删除全部三个旧条目之后**才失败：

```
New-CimInstance : 属性"InitialSize"的类型不匹配
```

`Win32_PageFileSetting.InitialSize / MaximumSize` 是 `uint32`，传入 PowerShell 的
`[int]` 会报类型错误。此时 `Win32_PageFileSetting` 已为空且
`AutomaticManagedPagefile=False`，**若此刻重启将完全没有任何分页文件**。

修正后又出现 `值超出范围`，最终由**注册表回退路径**写成功：

```
HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management
  PagingFiles (REG_MULTI_SZ) = "C:\pagefile.sys 4096 4096", "E:\pagefile.sys 0 0"
```

`PagingFiles` 才是权威来源，`Win32_PageFileSetting` 只是它的 WMI 视图。

> 教训：**破坏性步骤（删除旧配置）与重建步骤之间不能有任何可能失败的间隙**。
> 正确顺序是先构造新值、确认可写，再一次性替换。

---

## 十四、2026-09-29 卸载残留排查

脚本：`clean-leftovers.ps1`（纯 ASCII，含"刻意不删"清单与逐项校验）

### 已清除（11 项）

| 类别 | 项目 |
|---|---|
| Wise | `HKLM\SOFTWARE\WiseCleaner`、`HKLM\SOFTWARE\WOW6432Node\WiseCleaner`、`HKCU\SOFTWARE\WiseCleaner` |
| RAS 跟踪 | `Tracing\Docker Desktop Installer_RASAPI32`、`_RASMANCS`、`Tracing\WiseCare365_RASAPI32`、`Tracing\WiseTray_RASAPI32` |
| 死快捷方式 | `开始菜单\Docker Desktop.lnk`（目标已不存在） |
| 悬空 shell 扩展 | `HKCU\SOFTWARE\Classes\.dockerfile\shellex\{8895b1c6-…}`（该 CLSID 在任何注册表位置都未注册，shell 永远无法加载） |
| Java 更新器残留 | `HKCU\SOFTWARE\JavaSoft\DeploymentProperties`、`Java Update` |

### 刻意不删（附理由）

| 项目 | 理由 |
|---|---|
| `HKCU\SOFTWARE\JavaSoft\Prefs` | 内含 `Prefs\jetbrains\...` —— **PyCharm 的设备 ID 与账号数据**，删了要重新登录 |
| `HKCU\SOFTWARE\Classes\VSCode.dockerfile` | `AppUserModelID = Microsoft.VisualStudioCode`，属于 VS Code |
| `HKCU\SOFTWARE\Classes\.dockerfile` 根键 | VS Code 在 `OpenWithProgids` 里注册了它 |
| `C:\Program Files\Java\jre1.8.0_481` | 刻意保留的 JRE 8 |
| `C:\ProgramData\Oracle\Java\.oracle_jre_usage` | 上述 JRE 的使用追踪目录 |

### 重大发现：360（悟空）是**安装状态**，不是残留

排查中一度把 `HKCU\SOFTWARE\360Safe` 的 1242 个子键/3623 个值当成残留，
**实际 360 完整安装在 `D:\wukong`**（0.53 GB / 619 文件，含 `uninst.exe`），
只是因为**没有卸载注册项**，所以在"应用和功能"里看不到，看起来像残留。

```
ZhuDongFangYu (主动防御)  Running  Auto     D:\wukong\deepscan\zhudongfangyu.exe
Q360AMPPL                 Stopped  Manual   D:\wukong\safemon\wscreg.exe
WukongTray (启动项)                          D:\wukong\safemon\WukongTray.exe /start
```

**运行中的内核驱动与 Kaspersky 叠加：**

| 产品 | 运行中的内核驱动 |
|---|---|
| Kaspersky | 17 个，含 `klif`(文件过滤) `klhk` `klflt` `kldisk` `klwtp`(网络) `klkbdflt` `klmouflt` 等 |
| 360 | `360FsFlt`(文件过滤) `360netmon`(网络) `360Sensor` |
| 360（已注册未运行） | `360AntiHacker` `360Hvm`、`360elam64`（引导启动） |

**两个文件系统过滤驱动 + 两个网络监控驱动叠在同一条 I/O 路径上**，是卡顿/蓝屏/
启动失败的经典诱因。另有 `C:\ProgramData\360safe\360Disabled`（1 字节，2026-09-29 19:46）。

> **绝对不要手动删 360 的注册表或驱动服务项**：`360FsFlt` 是正在运行的文件系统
> 过滤驱动，摘除它会导致蓝屏或无法启动。必须先运行 `D:\wukong\uninst.exe`
> 由官方卸载器正确卸载驱动，之后再来清注册表。
>
> 判断一个软件是否已卸载，不能只看"应用和功能"里有没有条目——**缺卸载注册项
> 不等于已卸载**。

### 追加教训：命令行里的非 ASCII 同样会坏

本次有一条命令因正则里写了中文（`'360|悟空|安全卫士|...'`）导致解析失败，
中文被破坏成乱码。**不只是 .ps1 文件，通过命令行传递的非 ASCII 字符同样不可靠。**
传递给 pwsh 的正则、路径、字符串请一律使用 ASCII。

### 360 卸载完成（同一日稍后）

用户运行了 `D:\wukong\uninst.exe`，卸载基本成功：

| 项 | 卸载前 | 卸载后 |
|---|---|---|
| `D:\wukong` | 0.53 GB / 619 文件 | 11.85 MB / 14 文件（8 个 DLL 被 Explorer 占用，待重启） |
| 6 个驱动 `.sys` 文件 | 全部存在 | **全部已从磁盘删除** |
| `C:\ProgramData\360safe` 等 | 存在 | 已删除 |
| 服务注册项 | 8 个 | 全部清除（含本次清理的 `360netmon`、`Q360AMPPL`） |
| 注册表树 | 1242 子键 | **0** |
| 启动项 / 计划任务 / 卸载项 | 有 | 无 |

**剩余项全部卡在同一次重启上**（脚本 `clean-360-leftovers.ps1` 处理了不需要重启的部分）：

- `360FsFlt`、`360netmon` 驱动仍在内存（`.sys` 已从磁盘删除、服务项已移除，
  `StartMode` 显示 `Unknown`）—— 这是标准的待重启卸载状态，无法手动卸载
- `D:\wukong\safemon` 下 8 个 DLL 被 Explorer 作为 shell 扩展加载
- 904 条 `PendingFileRenameOperations`（223 其他 / 111 Temp / 83 Windows 日志 / 30 wukong / 5 Chrome）

**一次重启同时解决三件事**：分页文件新配置生效（回收约 17 GB）、
360 驱动从内存卸载、待删文件清理。

> 附注：`HKCU\SOFTWARE\360\360se5/360se6` 经核实属于**360 安全浏览器**的配置，
> 而该浏览器并未安装（无目录、无卸载项、无 `360se*.exe`、无进程），故一并清除。

### `E:\360RecycleBin` 的定性（846.79 MB，已删除）

该目录创建于 2026-09-29 19:45:18–19:45:34 的 **16 秒内**（与 `360Disabled` 标记同刻），
一度被误认为残留垃圾。**实际是 360「清理残留」功能的备份区**——它把判定为垃圾的文件
**移动**到此处而非直接删除，以便恢复。

`.dat` 文件是 **UTF-16 明文**，格式为：

```
Ver:1.0
CatTitle:<分类的中文说明>
<备份路径>|<原始路径>|<字节数>|<Unix时间戳>
...
```

`CatTitle` 由 360 自己写入，直接说明了每类是什么：

| 分类 | CatTitle | 文件数 | MB |
|---|---|---|---|
| 2042 | 腾讯会议卸载后残留的文件 | 535 | 233.98 |
| 3909 | 剪映专业版的缓存文件 | 84 | 206.68 |
| 3572 | 哔哩哔哩客户端安装包 | 1 | 197.61 |
| 3646 | 网易云音乐日志 | 1 | 158.88 |
| 5001 | Net程序集缓存文件 | 44 | 36.27 |
| 其余 13 类 | 各类缓存/日志/图标缓存 | 72 | 13.37 |

删除前的边界核查：

- **微信相关 4 条**全部是 `xwechat_files\...\cache\...\weappicon\*.jpg`（小程序图标缓存，4–24 KB），不含聊天记录
- **剪映 207 MB** 全部位于 `user data\**cache**\` 下（`AITextTemplate\Resource\*.zip`、`ressdk_db\*.db`），是下载的资源缓存而非工程文件
- 两个大 exe 经版本信息确认为**安装包**：哔哩哔哩 1.17.1.4402、网易云音乐 3.1.41.205529
- 按 `.doc/.xls/.pdf/.psd/.jpg/.mp4` 等用户数据类型筛选 → **命中为空**

结论：无任何不可再生内容，已删除。E 盘 442.93 → 443.76 GB。

> 提示：剪映仍在安装，删除其缓存后下次用到 AI 文字模板会重新下载，不影响工程文件。
>
> 附注：E 盘根目录另有 `$RECYCLE.BIN`，那是 **Windows 自己的回收站**，与 360 无关。

### 重启后的验证结果（2026-09-29 23:27 重启）

**一次重启解决了全部待办：**

| 项目 | 重启前 | 重启后 |
|---|---|---|
| 分页文件 | C 16405 + D 5120 + E 5120 | **C 4096 + D 移除 + E 生效** |
| C 盘可用 | 56.86 GB | **70.38 GB**（+13.52，符合预期） |
| D 盘可用 | 84.71 GB | **89.72 GB**（+5.01，完全符合预期） |
| 360 驱动在内存 | `360FsFlt`、`360netmon` | **0** |
| `D:\wukong` | 11.85 MB | **不存在** |
| 待删文件 | 904 条 | 4 条 |
| Kaspersky | AVP 服务 Stopped 但 17 个驱动加载（不自洽） | **AVP Running + avp/avpui 进程 + 驱动一致** ✓ 自愈 |

最后一个 360 孤儿驱动文件 `C:\Windows\System32\drivers\360AvFlt.sys`
（版本信息为 **360杀毒** v1.1.0.1078，与已卸载的"悟空"是不同产品）重启后仍在，
且独占打开被拒。用 `takeown /F ... /A` 取得所有权 + `icacls ... /grant *S-1-5-32-544:F`
后成功删除。脚本：`clean-360-driver.ps1`。

### 遗留：E 盘分页文件超配（36 GB）

`E:\pagefile.sys` 配置为"系统托管"（`0 0`），Windows 按物理内存 31.2 GB
自动分配了 **36864 MB**，而实测峰值仅 1163 MB。

**这是重启后唯一的空间净损失**：分页文件总量 26.1 GB → 40 GB，磁盘净亏 13.9 GB。

`clean-360-driver.ps1 -EPagefileMB <n>` 可改为固定大小：

| E: 设为 | 回收 | 分页文件合计 | 提交限制 |
|---|---|---|---|
| 8192 MB | 28 GB | 12 GB | 43.2 GB |
| 12288 MB | 24 GB | 16 GB | 47.2 GB |
| 16384 MB | 20 GB | 20 GB | 51.2 GB |
| 24576 MB | 12 GB | 28 GB | 59.2 GB |

> **决定（2026-09-29）：保持"系统托管"不变。** 用户确认 E 盘空间充裕
> （可用 412 GB），36 GB 占比可忽略，且系统托管可在提交压力上升时自动扩张，
> 无需人工维护。**这不是遗漏，是有意保留。**
>
> 如日后 E 盘吃紧，可用上述命令改为固定大小（需重启生效）。

> 自查纠错：汇总输出里我用了 `@(Test-Path $p).Count` 判断目录是否存在，
> 但 `@($false).Count` 返回 **1**，导致把"不存在"误报成"存在"（`D:\wukong` 那次）。
> 布尔值应写成 `[int](Test-Path $p)` 或直接输出 `Test-Path`；
> 集合计数（`.Count`）与布尔转数组（`@($bool).Count`）是两种语义，混用会静默出错。

---

## 十五、2026-09-30 第二轮优化排查

工具链问题解决后，对整个系统做了一轮扫描，重点是**装了但没用**和**卸载后的残留**。

### 已清理

| 项目 | 收益 | 依据 |
|---|---|---|
| **WinLibs gcc 16.1.0**（WinGet 包） | **913 MB** | 见第十节：中文 TEMP 下无法编译；且被 `C:\mingw64` 完全遮蔽，是死代码。`winget uninstall` 后**User PATH 条目被自动清理** |
| NuGet 缓存 | **1023 MB** | `dotnet nuget locals all --clear`；纯缓存，按需重建 |
| pnpm store | 80 MB / 67 个包 | `pnpm store prune` |
| 用户 Temp（7 天前的文件） | 2.2 MB | 见下方说明 |
| `C:\llvm` | 163 KB | 孤儿目录，只剩一个 `Uninstall.exe` |
| 8 个孤儿启动项 | 0 | `StartupApproved\Run` 中对应软件目录已不存在：Thunder、IDMan、electron.app.Notion、Docker Desktop、QuarkUpdater ×4 |
| `SoftLandingCreativeManagementTask` | 0 | **动作（Execute）为空**，且带一个来源不明的 WNF 触发器 |

备份：`D:\Backups\StartupApproved-Run-HKCU-20260930.reg`、
`D:\Backups\SoftLanding-task-20260930.xml`、
`D:\Backups\User-PATH-before-winlibs-removal-20260930.txt`

> **关于 Temp 的实测结论**：用户 Temp 目录 1046 MB，但其中**只有 5 个文件（2.2 MB）
> 超过 7 天**。也就是说这个目录的体积几乎全是活跃文件，清理它没有意义——
> 只看目录大小容易误判，必须看文件的时间分布。

> **保留判断**：`StartupApproved` 里还有 `Yuanbao`、`BaiduYunGuanjia` 两个条目，
> 但其软件目录**仍然存在**，所以**未删**。孤儿判定必须靠"对应软件是否还在"，
> 不能只看"是否在 Run 键中"——那些软件可能只是当前没写 Run 键而已。

### 刻意保留（用户决定）

| 项目 | 大小 | 原因 |
|---|---|---|
| `C:\Program Files\LLVM` | 2896 MB | 不在 PATH 且无引用，但与 WinGet 的 llvm-mingw 面向**不同目标**（MSVC vs GNU）；若用 clang-cl 就需要它 |
| `C:\ProgramData\Package Cache` | 2888 MB | 安装器缓存，删除会破坏软件的「修复安装」 |
| `D:\Toolchains\mingw64`（旧 gcc 15.2.0） | 720 MB | 回滚目标 |
| `C:\DiskGenius_WinPE` | 432 MB | 应急启动镜像，系统崩溃时要用 |
| `C:\ProgramData\Unicorn`、`GamePPPublic` | 862 MB | 用途待查（UDM / PCBenchmark） |

### 安全相关观察（均未改动）

| 项目 | 状态 | 说明 |
|---|---|---|
| **`PrivaZer_SkipUAC` 计划任务** | **保留（用户决定）** | `RunLevel=Highest`，其作用是让 PrivaZer 免 UAC 提权。**风险边界**：动作是 `PrivaZer.exe $(Arg0)`，参数被限制为 PrivaZer 自己的命令行，**不是任意命令执行**。用户仍在使用 PrivaZer，接受该便利 |
| `SecurityHealth` 启动项被禁用 | 保留 | Windows 安全中心**托盘图标**不显示。功能上无影响：Kaspersky 是主杀软（WSC 状态码 `0x41000`），Defender 被动，防火墙三个配置文件全开 |
| `CreateExplorerShellUnelevatedTask` | 保留 | Windows 自建任务（`explorer.exe /NoUACCheck`），非第三方 |
| 16 个启动项 | 保留 | 实测运行中的仅 3 个（Steam 54 MB、Everything 10 MB、VMware 托盘 15.9 MB），**合计约 80 MB**。影响主要在开机耗时而非内存 |

> 注意 `SoftLandingCreativeManagementTask` 与 `CreateExplorerShellUnelevatedTask` 的对比：
> 前者动作**为空**（不可能执行任何东西）故删除；后者虽含 `/NoUACCheck` 但**是 Windows
> 自带任务**，删除反而可能影响 Explorer 行为。**判断依据是「谁创建的 + 实际做什么」，
> 不是「名字里有没有可疑词」。**

### DISM 组件清理

按用户要求执行 `dism /Online /Cleanup-Image /StartComponentCleanup /NoRestart`
（`C:\Windows\WinSxS` 13.2 GB）。日志：`E:\Git\_dism\dism.log`。

> 副作用：清理后**无法再卸载已安装的 Windows 更新**（被取代的组件版本已删除）。

---

## 十六、2026-09-30 第三轮深挖：可选功能 / 保留存储 / 遗漏大件

本节记录**调查结果**。用户只授权执行了其中一项（GamePP 数据），其余仅归档备用。

### 已执行：删除 GamePP 跑分数据（439 MB）

`C:\ProgramData\GamePPPublic`（游戏加加的 PCBenchmark 场景数据，`scene.pak` 就占 324 MB）。

删除前做了完整性核查，**确认游戏加加已彻底卸载**：

| 核查项 | 结果 |
|---|---|
| 卸载登记项 | 无 |
| 主程序 exe | 全盘未找到 |
| 服务 / 进程 / 启动项 | 均无 |
| `AppData\Local\GamePP` | 0 MB，最后写入 2025-09-22 |

**C 盘 67.07 → 67.50 GB（+439 MB）**，目录已不存在。

> ⚠️ **重要教训：`Access is denied` 未必是"文件被占用"**
>
> 首次用非提权进程删除时失败，我一度判断为"部分文件被占用"。加上
> `-ErrorAction SilentlyContinue` 后真实错误被完全吞掉，陷入了错误方向。
>
> 显示真实错误后才发现是 `UnauthorizedAccessException`，而 `takeown` 给出了决定性线索：
> **"The current logged on user does not have ownership privileges"**。
>
> 根因是 **UAC 令牌过滤**：该目录所有者是 `BUILTIN\Administrators`（FullControl），
> 但非提权进程的令牌里 Administrators 是"仅拒绝"的 SID，**用不了这个组的权限**。
> 提权后一条 `Remove-Item` 直接成功。
>
> **教训：删不动时先看真实错误，不要用 `SilentlyContinue` 猜原因；
> 且"权限不足"和"文件占用"是完全不同的诊断方向。**

### 已查明但未执行（用户选择保留）

| 项目 | 大小 | 查明结论 |
|---|---|---|
| **保留存储（Reserved Storage）** | **6.84 GB** | 从 `ReserveManager` 注册表读到确切值：硬预留 5.00 GB + 软预留 1.50 GB + 调整值 0.34 GB。DISM 只报"已启用"不报大小 |
| **Store 应用** | 8.78 GB / 138 个 | 其中 **1.96 GB 为明确 bloat**：YourPhone 374、GamingApp 362、GamingServices 237、GetHelp 272、PCManager 206、跨设备 104、反馈中心 80、To Do 75、Clipchamp 64、ZuneMusic 36、Game Bar 33、Bing 新闻/天气 58、时钟 25 等 |
| **IIS 全栈** | 小 | **17 个 IIS 功能 + 2 个 WAS 功能已启用**；`W3SVC` 与 `AppHostSvc` 均 `Auto` 且 Running，**占用 80 端口**；`C:\inetpub` 仅 0.2 MB（无任何站点） |
| **Hogwarts Legacy** | 1.26 GB | 经核实**是 `*.ushaderprecache` 三类 DirectX 着色器预编译缓存**（Graphics 750 MB + DriverByteCode 391 MB + Compute 120 MB），**不是存档**。存档在 Steam userdata，`AppData\Local\Hogwarts Legacy` 为 0 MB |
| **Samsung Magician 安装包** | 195 MB | 两份 **SHA256 完全相同**（`645CC9F19E411645...`）：`Samsung\Backup\...Backup.exe` 与 `Samsung Magician\Site Link\...installer.exe` |
| **Unicorn 绘画素材** | 423 MB | `Paint001`…`Paint016+` 笔刷素材。注册表指向 `HKCU\SOFTWARE\Unicorn\PaintAid` → `D:\painttool\PaintAid` v2.7.4.0、`UDMPaint` v3.0.7.0 PRO **IsTrial=1** |
| **.NET Core 3.1.9** | 小 | 2022-12 已停止支持 |

### 安全相关观察（均未改动）

| 项目 | 说明 |
|---|---|
| **`DoudouAIService`（逗逗游戏伙伴）** | `Auto` 自启且正在运行，434 MB。内含 `liteav_screen.dll` / `liteav.dll`（腾讯实时音视频 SDK，**含屏幕采集能力**）、`steam_api.dll`、`GameScene.db` |
| **`Steam++.Accelerator`** | Watt Toolkit（`4651ED44255E`，436 MB）的加速组件，**正监听 443 端口** |
| `ImDiskRD` 服务 | `Auto` 启动但已停止（`C:\Program Files\ImDisk`，1.5 MB） |

### 方法记录：保留存储的大小怎么查

DISM 的 `/Get-ReservedStorageState` 只返回启用/禁用，**不报大小**；
`vssadmin`、`Storage` WMI 命名空间也都查不到。唯一可靠来源是：

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager'
#   BaseHardReserveSize    = 5368709120   (5.00 GB)
#   BaseSoftReserveSize    = 1610612736   (1.50 GB)
#   HardReserveAdjustment  =  359854080   (0.34 GB)
```

禁用命令（**本次未执行**）：

```powershell
DISM /Online /Set-ReservedStorageState /State:Disabled
```

> 权衡：C 盘 67 GB 空闲时禁用是安全的，且可逆（`/State:Enabled` 恢复）。
> 代价是将来若 C 盘被填满，功能更新可能因空间不足而失败。

---

## 十七、2026-09-30 第四轮：配置层优化（非磁盘）

前几轮都在省磁盘，本轮转向**配置层**。结论是：磁盘类优化已接近尾声，
真正的剩余价值在电源与常驻进程。

### 已执行

| 项目 | 变更 | 依据 |
|---|---|---|
| **电源计划** | 高性能 → **平衡** | 见下方对比表 |
| **夸克更新器计划任务** | Ready → **Disabled** | 每次登录 + 每天运行，拉起 4 个 Chromium 更新进程 |

回滚：`powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c`；
`Enable-ScheduledTask -TaskName 'QuarkUpdaterTaskUser1.0.0.21{...}' -TaskPath '\QuarkUpdaterUser\QuarkUpdater\'`

备份：`D:\Backups\power-scheme-before-20260930.txt`、`D:\Backups\QuarkUpdater-task-20260930.xml`

> 两项都**不需要管理员权限**。

### 电源计划逐项对比（AC / DC 电池）

| 设置项 | 高性能（原） | 平衡（现） | 说明 |
|---|---|---|---|
| 最小处理器状态 (%) | 100 / 5 | **80 / 5** | 仅 AC 有差 |
| **PCIe 链路电源管理** | **0 / 0** | **2 / 2** | **AC 与电池都不同 ← 关键** |
| USB 选择性暂停 | 1 / 1 | 1 / 1 | 相同 |
| 关闭显示器超时 (秒) | 0 / 240 | 0 / 180 | 电池有差 |
| 睡眠超时 (秒) | 0 / 240 | 0 / 180 | 电池有差 |
| 硬盘关闭 (秒) | 30 / 30 | 30 / 60 | 电池有差 |

`PCIe ASPM: 0=关闭省电 1=中等 2=最大省电`

**关键发现**：原计划的 PCIe 链路电源管理是 `0`（**关闭省电**），
**且 AC 与电池模式都是 0** —— 意味着 NVMe SSD 与显卡的 PCIe 链路从不进入低功耗状态，
插着电也一样。这是笔记本空闲发热与续航的真实来源。

> ⚠️ 注意：**OEM 关闭 ASPM 有时是刻意的**（避免某些硬盘/采集卡出现卡顿）。
> 本机是三星 990 EVO Plus，通常无兼容性问题。若出现异常可一键切回。

### 本轮的两处误判（已更正）

**一、把 `uploadDownload.exe` 误判为可疑程序**

它位于 `E:\mclaud\mCloud\processes\`，无版本信息、持续占用 CPU、79 个线程。
我据"无版本信息 + 路径在盘根 + 持续跑 CPU"起疑。**签名校验推翻了判断**：

```
签名状态: Valid
签名者: CN=中移互联网有限公司, O=中移互联网有限公司, L=广州, S=广东
产品: 中国移动云盘 v8.9.1
```

它是中国移动云盘（`E:\mclaud\mCloud\`，827 MB）的 Electron 辅助进程——
**这类二进制通常不带版本信息，不能作为可疑依据**。无启动项/服务/计划任务，是手动启动的。

**二、电源计划的结论说过了头**

看到 `PROCTHROTTLEMIN = 100%` 就断言"CPU 永不降频、续航受损"。
一查才发现 **DC（电池）模式本来就是 5%**，处理器项的实际差异只有 AC 下 100% vs 80%。
**真正的差异是 PCIe ASPM，而这是我第一遍没查的项。**

> 教训：**看到一个刺眼的数值不等于找到瓶颈。**
> 电源计划有几十个设置项，必须逐项对比 AC/DC 两个维度，
> 不能凭单项数值下结论——第一次我就漏掉了真正的关键项。

### 已确认最优（无需改动）

| 项目 | 状态 |
|---|---|
| TRIM | `DisableDeleteNotify = 0` 全卷启用 |
| 长路径支持 | `LongPathsEnabled = 1` |
| 遥测 | `AllowTelemetry = 0` |
| USB 选择性暂停 | 已启用 |
| 网络 | RSS 启用、窗口自动调优 normal |
| 分页文件 | E 盘峰值 **25.5 GB**，36 GB 系统托管配置正确（见下方更正） |

> **重要更正**：第十三节曾建议把 E 盘分页文件缩到 16 GB。
> **那是错的**——实测峰值已达 **25498 MB**，另有 C 盘 4095/4096 MB 用满。
> 用户当初"保持系统托管"的决定是正确的。
> **教训：分页文件峰值必须在长时间重负载之后再看**，早期 555 MB / 8387 MB 的读数
> 都不足以支撑"缩容"的建议。

### 评估后认为不值得动

| 项目 | 理由 |
|---|---|
| `DisableLastAccess = 2` → 1 | 现代 SSD 上收益微乎其微 |
| 8.3 短文件名禁用 | 同上 |
| 事件日志 | >10 MB 的合计仅 80.3 MB |
| Samsung / Nahimic / GameManager 等 OEM 服务 | 合计约 250 MB，各有用途 |
| 保留存储 6.84 GB | 用户选择保留（见第十六节） |

### 常驻进程现状（供日后参考）

```
物理 31.2 GB   已用 8.4 GB   可用 22.8 GB   进程数 250 → 248
```

**内存不是瓶颈**（用了不到三分之一），因此精简常驻进程的收益主要在 CPU、
发热与续航，而非内存。当前占用最高者：

| 进程 | 内存 | 说明 |
|---|---|---|
| DeepSeek Harness ×6 | 1109 MB | 当前使用的应用 |
| svchost ×53 | 719 MB | 系统 |
| **Paradox Launcher ×4** | **668 MB** | 为《Hearts of Iron IV》启动但游戏未运行，**关掉即可释放** |
| mCloud ×14 | 525 MB | 中国移动云盘 |
| steamwebhelper ×7 | 440 MB | Steam |
| SamsungMagician ×4 | 115 MB | 三星固态工具 |

---

## 十八、2026-09-30 第五轮：全系统配置体检

覆盖面比前几轮宽：安全基线、包管理器、备份、交互设置、启动项。

### 已执行

| 项目 | 变更 | 备份 |
|---|---|---|
| **存储感知 · 回收站** | 1 天 → **30 天** | `D:\Backups\StorageSense-StoragePolicy-20260930.reg` |
| **自动播放** | 未禁用 → **已禁用** | — |
| **npm registry** | `registry.npmjs.org` → `registry.npmmirror.com` | `D:\Backups\npmrc-before-20260930.txt` |
| **pnpm registry** | → `registry.npmmirror.com` | 同上（共用 `.npmrc`） |
| **pip index-url** | 无配置 → **阿里云** `mirrors.aliyun.com/pypi/simple/` | — |
| **OneDrive Run 键** | 已从 `HKCU\...\Run` 移除 | `D:\Backups\HKCU-Run-before-onedrive-20260930.reg` |

### ⚠️ 重大更正：`StartupApproved` 我从头到尾读反了

`StartupApproved\Run` 的 12 字节 REG_BINARY 值，**首字节的含义是**：

```
0x02 / 0x06  =  已启用
0x03         =  已禁用
```

**我在第十五、十七两节里用的判断逻辑是反的**（把 `02/06` 当成禁用、其余当成启用），
导致连续两轮把**已禁用的启动项报成已启用**。

用正确逻辑重扫的实际结果：

| 位置 | 结果 |
|---|---|
| HKCU | **11 项全部已禁用**（Steam、OneDrive、Kimi、夸克、百度网盘检测、雷蛇、元宝、LosslessScaling、QuarkUpdater、Discord、Player2） |
| HKLM | SecurityHealth 已启用；Everything 已禁用 |
| HKLM32 | vmware-tray、GaomonTablet、SunJavaUpdateSched、IncrediBuild 全部已禁用 |
| **合计** | **启用 1 项，禁用 16 项** |

**也就是说用户早就把启动项基本都关掉了。** 我却基于错误读数在第十七节建议"精简启动项"，
结论完全相反。可笑的是我还在第十七节写了"教训：看到一个刺眼的数值不等于找到瓶颈"，
紧接着又犯了同类错误——**这次不是数值刺眼，而是我的解析逻辑本身错了，而我没做交叉验证**。

唯一仍然有效的相关改动是夸克的**计划任务**：它的 Run 键入口早已被禁用，
但计划任务当时确实是 `Ready`，所以禁用它是对的。

> **教训：解析二进制/编码格式的注册表值时，必须用一个已知状态的条目做校准。**
> 本机 `SunJavaUpdateSched`、`IncrediBuild` 这类明显已废弃的项本可作为反例校验逻辑，
> 我却没有用。**只靠记忆判断字节含义是不可靠的。**

### pip 镜像：清华源不可用，已换阿里云

首次配置清华 TUNA 后实测下载失败：

```
Looking in indexes: https://pypi.tuna.tsinghua.edu.cn/simple
ERROR: Could not find a version that satisfies the requirement six (from versions: none)
```

排查后确认**是清华源本身的问题，不是网络问题**：

| 源 | 索引页 HTTP | pip 实测下载 |
|---|---|---|
| 清华 TUNA | 200 / 311 ms | **✗ 失败** |
| 阿里云 | 200 / 597 ms | ✓ 成功 |
| 中科大 USTC | 200 / 1048 ms | ✓ 成功 |
| 腾讯云 | 200 / 398 ms | ✓ 成功 |
| 官方 PyPI | 200 / 746 ms | — |

索引页能访问但 pip 拿不到数据，属于该镜像与 pip 的 API 交互问题。
**已改用阿里云并通过配置文件完成真实下载验证。**

> **教训：配置镜像源后必须做一次真实下载验证，不能只看配置是否写入。**
> 如果我没测，你会留下一个"看起来配好了、实际完全不能用"的 pip.

### 安全基线审计：无可优化

| 项目 | 状态 |
|---|---|
| 内核隔离 HVCI + VBS | 已启用且运行中 ✓ |
| UAC | 启用 / 默认提示级别 / 安全桌面 ✓ |
| LSA 保护 | `RunAsPPL = 2`（含 UEFI 锁定，最高级）✓ |
| SMBv1 / RDP | 均已禁用 ✓ |
| PATH 完整性 | Machine 23 条 + User 14 条**全部有效，零死链** ✓ |
| PATH 长度 | 1656 字符，远离上限 ✓ |
| 游戏 DVR / 远程协助 | 均已关闭 ✓ |
| 自动播放 | 本轮已禁用 ✓ |

### 已排除的优化项

| 项目 | 排除理由 |
|---|---|
| **Git 性能调优** | 实测仓库仅 **0.3 MB / 179 个文件**，`untrackedcache` 等面向大仓库的调优收益严格为零 |
| `DisableLastAccess` / 8.3 短名 | 现代 SSD 上收益微乎其微 |
| 事件日志 | >10 MB 的合计仅 80.3 MB |
| 启动延迟 `StartupDelayInMSec` | 改 0 会让启动项抢在桌面之前加载，体感更慢，不划算 |

### 环境现状记录

**安装了 5 个云盘客户端**（用户选择保留）：

```
中国移动云盘  E:\mclaud        ← 当前 14 个进程在运行
百度网盘      D:\BaiduNetdisk
夸克网盘      D:\Quark
PikPak        E:\pikpak
联通云盘      AppData\Local\wocloud-updater
```

**数据分布**（决定备份优先级）：

| 位置 | 大小 | 性质 |
|---|---|---|
| `E:\ABC` | 890 GB | 待查 |
| `D:\steam\steamapps\workshop` | 472 GB | 壁纸工坊，可再生 |
| `E:\SteamLibrary` | 283 GB | 游戏 |
| `D:\qqdownloads` | 42 GB | 下载 |
| **用户文档合计** | **约 11.3 GB** | **真正不可再生** |

> 用户选择暂不建立备份。此结论已记录：**不可再生数据只有约 11 GB，
> 而机器上有 1.7 TB 内容，绝大多数可重新获取。**

**安全基线外的其他现状**：

```
服务    317 个（自动启动 101，运行中 150）
计划任务 198 个（Ready 162，Disabled 30，非微软路径 15）
内存    8.4 GB / 31.2 GB
```

---

## 十九、2026-09-30 用户数据备份

用户问的是"11 GB 会不会增长，增长不大就备份"。**答案是用数据给出的，且推翻了几个我先前的判断。**

### 增长实测：不小，但构成决定了备份成本

按年统计（文件修改时间）：

```
2024         480 个     196.5 MB
2025      19,463 个   1,329.2 MB
2026      21,291 个   9,310.4 MB   ← 9 个月
```

**2026 年约 1 GB/月、12 GB/年**——不是"增长不大"。

但时间分布显示：最近 90 天占 55%、最近 365 天占 84%，
而**2 年以上未动的仍有 929 MB**——说明老数据是沉淀下来的，新增的多数是可再生的。

### 三处判断更正

**一、HOI4 存档不是损坏文件**

我用"HOI4 存档是 ZIP，检查 `50 4B` 文件头"做判定，结果 12 个样本全部"非 ZIP"，
差点得出"这些是残缺文件、可以删"的结论。实际文件头是：

```
48 4F 49 34 62 69 6E 35  =  ASCII "HOI4bin5"
```

**这是 HOI4 的二进制存档格式**——游戏设置里写着 `save_as_binary=yes`。
它们**是有效的游戏存档**，49 个共 5.38 GB，仍在持续产生（9 月新增 21 个 / 2 GB）。

> 教训：**判定文件有效性时，必须确认格式假设本身成立。**
> 我基于旧版本 HOI4 的记忆做判断，而没先读一眼游戏设置。

**二、Minecraft 存档位置**

`.bobby\` 下的 65 MB `.mca` 是 **Bobby 模组的服务器区块缓存**（可重建），
与存档无关。真正的存档在：

```
%APPDATA%\.minecraft\versions\1.7.10-Forge_10.13.4.1614-LiteLoader-OptiFine_E7\saves\新的世界
```

**三、`Desktop\重要` 是全机最有价值的数据**

```
github-recovery-codes.txt     ← GitHub 账户恢复码
githubapikey.txt / deepseekapikey.txt / mineruapi.txt
pixiv-backup-codes.txt        ← 备份码
解压密码.txt
BadTrackRecord...rpt  70.5 MB ← 硬盘检测报告
```

**体积很小，但密码学上不可再生。** 排备份第一位。

> ⚠️ 同时这是一个**安全提示**：这些密钥目前以**明文**存放在桌面上。
> 建议迁移到密码管理器。

### 备份实现

**脚本**：`backup-userdata.ps1`（PS7，不需管理员）
**目标**：`E:\Backup\UserData`

**为什么目标是 E 盘**

```
磁盘 0（三星 990 EVO Plus）  →  E:
磁盘 1（CT1000E100SSD8）     →  C: 和 D:
```

**C 与 D 在同一块物理硬盘上**，把 C 的数据备份到 D 挡不住硬盘故障。
只有跨到 E 盘才真正起作用。

> 局限：本地跨盘备份只能防单盘故障，**防不住整机丢失 / 勒索软件 / 误删**。
> 异机保护仍需云盘或移动硬盘。

**备份范围（约 1.82 GB）**

| 项目 | 内容 |
|---|---|
| `Desktop\重要` | 密钥 / 恢复码 70.5 MB |
| `Desktop\绘画资料` | 绘画原稿与资料 1020 MB |
| `Pictures` | 图片 91.5 MB |
| `Videos` | 录像 551 MB |
| `Documents\Dyson Sphere Program` | 游戏存档 67.8 MB |
| `Documents`（排除后） | 文档 69.8 MB |
| `Saved Games` | 0.4 MB |
| `.minecraft\...\saves` | 我的世界存档 17.5 MB |

**刻意排除**：`Documents\Paradox Interactive`（5.4 GB HOI4 存档）、`My Games`、
`BaiduNetdiskTmp`、`Desktop\MTool`（1.36 GB 工具本体）、`Desktop\Eagle`（281 MB 程序）、
`Desktop\铃兰花圃...\.bobby`（65 MB 缓存）。

**计划任务**：`Backup-UserData-Weekly`，每周日 20:00，用户级权限。

### 校验结果

```
逐项对比 : 7/7 文件数与体积完全一致
哈希抽样 : 6/6 完全一致（密钥、PSD、录像、存档）
不一致项 : 0
```

### 过程中修掉的四个问题

| # | 问题 | 处理 |
|---|---|---|
| 1 | `W` 函数被传了 `-ForegroundColor` 参数，会直接报错 | 移除该参数 |
| 2 | **首次运行 `E:\Backup` 不存在，写日志直接失败** | 预先创建日志目录；`-DryRun` 抓到了这个缺陷 |
| 3 | `Documents` 的镜像操作可能删掉先前单独复制的戴森球存档 | 把 `Dyson Sphere Program` 加入排除项，消除对执行顺序的依赖 |
| 4 | **计划任务用相对名 `pwsh.exe`，试运行报 `0x80070002` 找不到文件** | 改为绝对路径 `C:\Program Files\PowerShell\7\pwsh.exe` |

> 第 4 点的教训：**计划任务调度器不会像交互式 shell 那样解析 PATH**，
> 即使该路径确实在 Machine PATH 中。任务动作一律用绝对路径。

> 第 2、3 点的教训：**`-DryRun` 模式不是形式主义**。
> 第 2 点如果直接正式运行，会在第一步就中断；
> 第 3 点更隐蔽——它不会报错，只会**静默地在下一次镜像时删掉已备份的数据**，
> 而这类问题只有在真正做"源 vs 目标逐项对比"时才会暴露。

### 幂等性验证

修正后再跑一次，8 项全部返回 `robocopy 退出码 0`（无变化、无需复制），
目标仍是 1821.6 MB / 1459 文件——**重复执行安全**。

---

## 二十、2026-09-30 游戏存档清理

用户提出 HOI4 存档是"之前玩的忘清理了，没用了"。**清理前先核了一遍事实，
发现与描述有一处出入，提出后由用户确认再执行。**

### 存档现状与用户描述的出入

| 项目 | 数据 |
|---|---|
| 存档时间跨度 | 2026-06-26 ~ 2026-09-29（96 天 ~ 1.7 天前） |
| 最近 7 天内修改 | 3 个 / 294 MB |
| 最近 30 天内修改 | 21 个 / 2022 MB |
| Paradox Launcher | **当时正在运行**（4 个进程） |

最新存档是 **1.7 天前**的，并非"很久没玩"。我提出这一点后用户仍确认清理，
于是采用**保留最近 3 个**的折中方案。

> 做法：**用户的主观判断与客观数据不一致时，先把数据摆出来，由用户决定，
> 而不是直接照做或直接拒绝。**

### 已清理内容

| 项目 | 大小 |
|---|---|
| HOI4 存档（46 个，7 天前的） | **5089 MB** |
| HOI4 shadercache / launcher-cache / naval_dist.cache / logs / crashes | 321 MB |
| **Victoria 3 存档（8 个）** | **249.5 MB** |
| Victoria 3 shadercache | **759.8 MB** |
| Victoria 3 logs / launcher-cache | 13.6 MB |
| Stellaris launcher-cache / logs / crashes / shadercache | 104.7 MB |
| **合计** | **约 6.54 GB** |

**C 盘：67.70 → 74.13 GB**

### 顺带发现另外两个 Paradox 游戏

清理 HOI4 后核对剩余体积，发现 `Paradox Interactive` 仍有 1424 MB，进一步查明是：

```
Hearts of Iron IV   295.9 MB
Victoria 3         1022.9 MB   ← shadercache 就占 759.8 MB
Stellaris           104.9 MB   ← 无任何存档，全是缓存与日志
```

三个游戏在 Steam 库里都还装着。**若只看 HOI4 目录就会漏掉这 1128 MB。**

### 安全措施

**保留的存档**（用户选择保留最近 3 个）：

```
RUS_1941_06_08_18_temp.hoi4    75.7 MB   2026-09-29
autosave_temp.hoi4             73.4 MB   2026-09-29
USA_1962_10_01_13_temp.hoi4   144.7 MB   2026-09-26
```

**明确保留的游戏配置**（删了要重设，全程未碰）：
`settings.txt`、`mod\`、`playsets_backup\`、`game rules\`、`account\`、
`launcher-v2.sqlite`、`dlc_load.json`、`pops_filestorage\`

**删除前的前置检查**：确认 `hoi4.exe` / `stellaris.exe` / `victoria3.exe` 均未运行。

### 与备份的关系

第十九节的备份**刻意排除了 `Documents\Paradox Interactive`**，
因此本次清理不影响备份完整性——但也意味着**这些存档没有副本，删除后不可恢复**。
这一点在删除前已向用户说明。

### 一处检查项误报

删除后的配置完好性检查里，`Victoria 3\settings.txt` 报 `✗`。
核实后确认**该文件在删除前就不存在**（三个游戏里只有 V3 没有它），
删除清单中也从未包含它——**是我的检查项把"本来就没有"当成了"被删掉了"**。

---

## 二十一、2026-09-30 编程语言环境体检

首次系统审计各语言的**安装完备性与配置**。下面按语言记录结论。

### 语言清单总览

| 语言 | 版本 | 位置 | 状态 |
|---|---|---|---|
| **Python** | 3.14.6（+3.13 未在 PATH） | `%LOCALAPPDATA%\Programs\Python` | ✅ 正常 |
| **Node.js** | v26.7.0 | `%USERPROFILE%\nodejs\node-v26.7.0-win-x64` | ✅ 正常 |
| **Rust** | 1.99.0-nightly + 1.98.1-stable | `D:\rust` | ⚠️ 见下 |
| **Go** | 1.26.5 | `C:\Program Files\Go` | ✅ 正常，镜像已配 |
| **Java** | JDK 21.0.12 LTS | Adoptium | ✅ 正常 |
| **.NET** | SDK 10.0.101 / 10.0.302 | `C:\Program Files\dotnet` | ⚠️ 已清理 EOL 运行时 |
| **C/C++** | gcc 16.2.0 + clang 22.1.8 | `C:\mingw64` / WinGet | ✅ 正常 |
| **Perl** | Strawberry Perl | `C:\Strawberry` | ✅ 正常 |

**已确认配置正确的**：`GOPROXY=goproxy.cn` ✓、`JAVA_HOME` → JDK 21 ✓、
`CARGO_HOME`/`RUSTUP_HOME` 已重定向到 D 盘 ✓、npm/pnpm → npmmirror ✓、pip → 阿里云 ✓、
PATH 全部条目有效无死链 ✓

### 已执行：Rust 残留清理（180.9 MB）

发现**两份 cargo**：

```
D:\rust\.cargo\bin        2026-08-09  12.22 MB   User PATH 索引 4 ← 生效
C:\Users\...\.cargo\bin   2025-12-28  12.92 MB   User PATH 索引 5 ← 被遮蔽
```

SHA256 不同，是两个不同版本。旧目录**只有 `bin`**（14 个 rustup 代理 exe），
无 registry、无 config —— 是当年 `CARGO_HOME` 还是默认位置时留下的残留。

处理：删除目录 + 从 User PATH 移除该条目。
校验：`Test-Path` 为 False、不在回收站、`cargo` 仍正确解析到 `D:\rust\.cargo\bin`。

> **注意一个测量陷阱**：删除前后用 `[System.IO.DriveInfo]::new('C').AvailableFreeSpace`
> 测得的差值只有 13 MB，与 180.9 MB 严重不符。改用 `Get-PSDrive` / WMI / `fsutil`
> 三种方式复核，读数稳定但差值依旧。
> **结论：在活跃使用的系统上，磁盘可用空间的瞬时差值不可作为删除是否成功的证据**，
> 应以目录级证据（路径是否消失、回收站是否为空、程序是否仍可用）为准。

### 已执行：加装 Rust stable 工具链

原状态：**只有 `nightly-x86_64-pc-windows-gnu`**，且是默认。

核实后确认 **`-gnu` 是被迫选择而非配置失误**：

```
vswhere 检测到的 VS 实例 : （空）
C:\Program Files\Microsoft Visual Studio : 不存在
Windows SDK : 只有 NETFXSDK
```

没有 MSVC 工具链，就不可能用 `x86_64-pc-windows-msvc`。

处理：安装 `stable-x86_64-pc-windows-gnu`（rustc 1.98.1），
**默认工具链保持不变**（仍是 nightly）。

```
stable-x86_64-pc-windows-gnu
nightly-x86_64-pc-windows-gnu (active, default)
```

### 已执行：.NET EOL 运行时清理（1307 MB）

清理前装了六个大版本的运行时，其中四个已停止支持：

| 版本 | 状态 | 停止支持 |
|---|---|---|
| 3.1.9 | ❌ EOL | 2022-12 |
| 6.0.36 | ❌ EOL | 2024-11 |
| 7.0.11 | ❌ EOL | 2025-05 |
| 9.0.17 | ❌ EOL | 2026-05 |
| 8.0.20 / 8.0.26 | ✅ LTS | 2026-11 |
| 10.0.x | ✅ 当前 LTS | — |

**关键实现细节：.NET 安装器是 WiX Burn 结构**，同一版本注册**两个**卸载入口：

```
Bundle : "C:\ProgramData\Package Cache\{GUID}\xxx.exe" /uninstall    ← 外层
MSI    : MsiExec.exe /X{GUID}                                        ← 内层
```

**单独卸 MSI 会留下孤儿 bundle 条目。** 因此脚本先卸全部 Bundle
（5 项，退出码 0），再尝试 MSI —— 20 项全部返回 **1605（产品未安装）**，
证明它们已被 bundle 连带移除。**把 1605 视为成功而非失败，是这里的关键判断。**

结果：

```
x64 dotnet : 2163 → 1691 MB
x86 dotnet :  439 →  149 MB
C 盘       : 73.83 → 75.1 GB  (+1307 MB)
EOL 残留条目 : 无
```

脚本：`clean-dotnet-eol.ps1`（PS7，自动提权，带 `-DryRun`）
日志：`D:\Backups\dotnet-eol-cleanup.log`
注册表备份：`D:\Backups\Uninstall-{x64,x86}-before-dotnet-cleanup-20260930.reg`

**破坏性验证**（删除运行时后必须做）：

```
项目 WorkerService1 → <TargetFramework>net10.0</TargetFramework>   ← 不受影响
dotnet SDK          → 10.0.302 正常
实测 dotnet new console --framework net10.0 → build → run → "Hello, World!" ✓
```

### 命令行编码问题复现

本轮有一次命令**在执行前就被编码层破坏**：

```
Write-Host "  dotnet 目录:")
→ 报错：Write-Host "  dotnet Ŀ¼:")     ← "目录" 变成 "Ŀ¼"，且多出一个括号
```

这与第七节记录的问题同源（PS 5.1 的 ANSI 解码）。**规避方式：把带中文的操作
写成 `.ps1` 文件并用 `pwsh -File` 执行，绕开命令行参数这一层。**
本轮 `.NET` 清理脚本正是因为先改成文件才得以顺利执行。

### 发现但未处理的项（用户选择保留）

| 项目 | 大小 | 说明 |
|---|---|---|
| Python 3.13 | 149 MB | 未在 PATH，但 `py` 启动器可识别。3.14 很新，留作回退合理 |
| .NET 旧 SDK 10.0.101 | 398.5 MB | 与 10.0.302 并存 |
| .NET RC 版 workload manifest | 小 | 10.0.100-rc.2 的 iOS/Android/macOS/Maui 等 |
| Visual Studio 安装器残留 | 99 MB | VS 本体已卸载，只剩 Installer |
| Microsoft Copilot | 1164 MB | `C:\Program Files (x86)\Microsoft\Copilot` |
| pkg-config 0.26 | — | **2010 年的版本**，现代 C/C++ 构建常要求 0.29+ |
| uv / poetry / deno / bun / yarn / corepack / gradle / maven / meson / vcpkg / conan | — | 均未安装 |

> `pkg-config 0.26` 值得单独一提：它来自 Strawberry Perl，
> 而 Meson 及部分 CMake 项目会因版本过低直接构建失败。
> 若将来 C/C++ 构建报 pkg-config 版本错误，安装 `pkgconf` 即可解决。

### 遗留：Node 与 Python 无版本管理器

```
rustup : 已装（可切换 Rust 版本）
nvm / fnm / volta / pyenv / asdf / mise : 均未安装
```

Node 是以 zip 解压方式放在 `%USERPROFILE%\nodejs\` 下的独立目录，Python 亦然。
两者都**只能有一个版本**——需要多版本时得手动管理。暂不影响使用。

---

## 二十二、2026-09-30 开发环境配置补全

第二十一节查的是**安装完备性**，本节补上**配置质量与开发体验**。

### 已执行

| 项目 | 变更 | 效果 |
|---|---|---|
| **VS Code 扩展残留** | 删 4 项 | 3958 → **3513.7 MB**（释放 444 MB） |
| **开发者模式** | 启用 | **非提权 mklink 立即生效** |
| **PYTHONUTF8** | `=1` + `PYTHONIOENCODING=utf-8` | stdout 编码变为 utf-8 |
| **Windows Terminal** | 注册 App Paths + 加 PS7 profile + 改默认 | 默认 profile 5.1 → **PowerShell 7** |
| **pytest / pipx** | 安装 | pytest 9.1.1 / pipx 1.17.8 |

### VS Code 扩展：3958 MB 里的四处残留

扩展目录共 76 个扩展 / 3958 MB，其中四处是残留：

```
244.2 MB  anthropic.claude-code-2.1.283       旧版本
 52.4 MB  rust-lang.rust-analyzer-0.3.3057    同 ID 的旧版本
 89.8 MB  .1d6816dc-28db-48ad-8791-9203674b45ea
 58.0 MB  .e7e964d4-4a49-413c-a231-83aba5a1d96c
```

**判定依据不是"看名字"，而是拿 `extensions.json` 登记项做比对**：

```
rust-lang.rust-analyzer   v0.3.3065  -> rust-lang.rust-analyzer-0.3.3065-win32-x64
anthropic.claude-code     v2.1.284   -> anthropic.claude-code-2.1.284-win32-x64
```

只有**未被登记**的目录才删。两个隐藏目录的身份也各自查明
（`.1d6816dc` 含 `nbcode\` 与 NetBeans 相关；`.e7e964d4` 的 `package.json`
写着 `name=rust-analyzer version=0.3.2803`）。

> 前置检查：确认 VS Code 未运行。删除后 `extensions.json` 仍为 74 项，关键扩展
> （claude-code 2.1.284、openai.chatgpt、ms-python.python）全部完好。

### Windows Terminal：先前的诊断是错的

第十七节我写过"WT 只检测 `C:\Program Files\PowerShell\7\pwsh.exe`，
装 MSI 后重启 WT 就会出现 profile"。**这个说法不完整。**

真正的原因是 WT 的动态 profile 生成器依赖这个注册表项定位 `pwsh.exe`：

```
HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe   ← 不存在
```

**MSI 安装时没有注册它**，所以单纯重启 WT 也不会生成 profile。

处理：

1. 注册 `App Paths\pwsh.exe` → `C:\Program Files\PowerShell\7\pwsh.exe`
2. 往 `settings.json` 写入 PS7 profile：
   ```json
   { "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
     "name": "PowerShell 7",
     "commandline": "C:\\Program Files\\PowerShell\\7\\pwsh.exe",
     "icon": "C:\\Program Files\\PowerShell\\7\\assets\\Powershell_black.ico",
     "source": "Windows.Terminal.PowershellCore" }
   ```
3. `defaultProfile` 从 `{61c54bbd-...}`（Windows PowerShell 5.1）改为上述 GUID

> 顺带发现：WT 里原本已有一个名为 `PowerShell` 的 profile，那是**MSIX 版残留**
> （指向已不存在的 `WindowsApps` 路径），一并替换掉了。

备份：`D:\Backups\windows-terminal-settings.bak-20260930.json`

### 开发者模式：为什么值得开

启用前实测 `mklink` 失败。实际影响：

- npm / pnpm / yarn 安装含符号链接的包会失败或需要管理员
- git 的 `core.symlinks` 无法正常工作
- WSL 的部分操作需要提权

写入 `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock`：

```
AllowDevelopmentWithoutDevLicense = 1   (DWORD)
AllowAllTrustedApps               = 1   (DWORD)
```

**实测非提权 `mklink` 立即成功，无需重启。**

关闭方式：设置 > 系统 > 开发者选项 > 开发人员模式。

### PYTHONUTF8：针对中文用户名的编码健壮性

本机用户名含中文（`琳珉琨琸`），而此前所有编码相关环境变量均未设置。
Python 在 Windows 上默认按 ANSI 代码页（本机 936/GBK）处理 stdio，
这正是本会话反复遇到的编码问题的同一根源。

设置后实测：

```
stdout 编码 = utf-8
首选编码    = utf-8
UTF-8 模式  = 1
```

> 权衡：UTF-8 模式会改变 locale 相关行为，极少数依赖系统代码页的老代码可能不兼容。
> 移除这两个变量即可还原。

### 评估后未执行

| 项目 | 说明 |
|---|---|
| **openai.chatgpt 的 Linux 二进制** | 该扩展 1128 MB，其中 `bin\linux-x86_64\` 约 348 MB 在 Windows 上无用。用户选择保留——升级扩展会重新下载，且扩展可能有完整性校验 |
| Python 3.13（149 MB） | 未在 PATH，作为 3.14 的回退保留 |
| .NET 旧 SDK 10.0.101（398.5 MB） | 与 10.0.302 并存 |
| .NET RC 版 workload manifest | 体积小 |
| Visual Studio 安装器残留（99 MB） | 便于将来重装 VS |
| Microsoft Copilot（1164 MB） | — |
| **pkg-config 0.26（2010 年版本）** | 现代 C/C++ 构建常要求 0.29+，若将来构建报版本错误，装 `pkgconf` 即可 |
| Node/Python 版本管理器 | 均无（rustup 可切 Rust 版本） |

### 结构性观察

**Node 生态的"缺失"其实是正常的**：`tsc` / `eslint` / `prettier` / `vite` 都不在全局，
但这**本来就是正确做法**——它们应作为项目级 `devDependencies` 安装。
只有 `corepack`（Node 自带但本机 zip 版未启用）算一个小缺口。

**Python 生态则确实偏少**：审计时 `pipx` / `ruff` / `black` / `mypy` / `pytest` /
`ipython` / `jupyter` / `virtualenv` 全部缺失，仅有 25 个包
（numpy、matplotlib、pillow、lief、capstone、pefile 等，偏数据处理与逆向方向）。
本轮补了 `pytest` 与 `pipx`（`ruff` 已随 VS Code 扩展存在）。

**构建产物很干净**：`target/`（Rust）为 0、Go 模块缓存 119 MB、`node_modules` 无 >20 MB 项、
`.NET bin/obj` 仅 2.3 MB、NuGet 缓存 0。合计可回收不到 400 MB，
说明这台机器没有"编译残留堆积"问题。

---

## 二十三、2026-09-30 `DeepSeek Messages transport failed` 排查（未定位到根因）

用户报告 DSH 出现该错误。本节记录**排除过程与结论**，
目的是让日后遇到同类问题时不必重复排查。

### 结论：一次没有留下任何痕迹的瞬时失败

排查结束时：DSH 到 DeepSeek 的两条连接正常，网络质量良好，**任何日志均无该错误记录**。

### 八项假设，全部排除（均有实测证据）

| # | 假设 | 实测结果 |
|---|---|---|
| 1 | 本会话的改动引起 | 六项改动（VS Code 扩展、开发者模式、PYTHONUTF8、WT profile、pytest/pipx、App Paths）**均不涉及网络/代理/DNS/防火墙** |
| 2 | hosts 被改写导致 | Watt Toolkit 确实改了 130+ 条，但**无任何 DeepSeek 条目** |
| 3 | 证书被 MITM 拦截 | `api.deepseek.com` 证书链为 `TrustAsia → DigiCert Global Root G2`，**不是** BeyondDimension/XunYou |
| 4 | Radmin VPN 抢默认路由 | 两条默认路由确实存在，但度量 **WLAN=0 vs Radmin=9256**，差距悬殊 |
| 5 | 代理配置错误 | `HTTP_PROXY`/`HTTPS_PROXY` 等 8 个变量**全部未设置**；系统代理关闭；WinHTTP 为 Direct access |
| 6 | API 连通性差 | **8/8 成功**，113–305 ms，平均 150 ms，全部返回预期的 401 |
| 7 | IPv6 优先导致卡顿 | **DeepSeek 域名无 AAAA 记录**；Node 解析全为 IPv4；DSH 对外 IPv6 连接数为 0 |
| 8 | DSH 自身日志有记录 | 搜索全部日志与会话文件，**仅命中用户自己发出的那句话** |

### 排查过程中我自己的三次误判

**一、把 Radmin VPN 当成路由抢占者**
看到"两条默认路由"就怀疑流量会走 VPN。实际 Windows 按**总度量**选择，
`RouteMetric + InterfaceMetric`：WLAN 为 0，Radmin 为 9256。**只看是否存在第二条路由是不够的。**

**二、把 1.1.1.1 超时当成 IPv6 不稳定的证据**

```
IPv6 直连 1.1.1.1 → 超时 10004 ms
```

由此推断"IPv6 部分可用"，进而怀疑 Node 的 `verbatim` DNS 顺序会先试 IPv6。
**但补充测试发现 IPv4 直连 1.1.1.1 同样超时（8006 ms）**——那是
**1.1.1.1 本身被墙**，与 IPv6 无关。**只测一个协议就下结论是不成立的。**

**三、假设未验证就准备改配置**
IPv6 假说成立时会建议设 `NODE_OPTIONS=--dns-result-order=ipv4first`。
但 DeepSeek 域名**根本没有 AAAA 记录**，该设置对它毫无作用。
**若不先验证 DNS 记录，就会加一个"看起来合理、实际无效"的配置。**

### 顺带查明的两件事

**一、Watt Toolkit 的工作方式**（解释了本会话的一个疑问）

它用**反向代理模式**：把 130+ 域名指向 `127.0.0.1`，由 `Steam++.Accelerator`
（监听 **443** 与 **81**）转发。改写范围包括 Steam 全家桶、Google 翻译、
hCaptcha、Arkose Labs、HuggingFace、**GitHub 全家桶**、Docker Hub、Nexus Mods、
ArtStation、Pinterest、Imgur、Spotify、Vercel 等。

> 这解释了为什么本会话中 `api.github.com` 的调用"能用"——它其实是被
> Watt Toolkit 本地转发的。也因此，先前下载 PowerShell MSI 与 gcc 时
> 改用 `gh-proxy.com` 是**绕开了 Watt Toolkit**的路径。

它同时装入了 MITM 根证书（受信任根证书列表中的
`O=BeyondDimension`），另有迅游加速器的 `CN=XunYouRootCA`。
**这些证书未拦截 DeepSeek 流量。**

**二、IPv6 环境是"部分可用"**

`Nahimic3` 与 `mCloud` 有 IPv6 连接建立成功，但 `1.1.1.1` 的 IPv4/IPv6 均不可达。
属于国内网络常态，**未做任何改动**。

### 建议：下次复现时的三步定位法

1. **立刻重试发送** —— 成功即确认是瞬时抖动，无需处理
2. **若持续失败，临时退出 Watt Toolkit** —— 它是本机唯一的 443 监听者，
   嫌疑最大；若退出后恢复，说明是它的转发问题
3. **仍失败时检查 429 限流** —— 排查中 `chat.deepseek.com` 曾返回 **429**

---

## 二十四、2026-09-30 编程语言配置深化（第二轮）

第二十二节查的是"装没装"，本轮查**配置项与版本健康度**。

### 已执行

| 项目 | 变更 | 验证 |
|---|---|---|
| **Rust stable 组件补全** | 加 `clippy` / `rustfmt` / `rust-docs` | clippy 实测产出 lint，fmt 实测检出格式差异 |
| **pip 包升级** | 11 个包 | `pip list --outdated` 已无过期项 |
| **环境变量** | `DOTNET_NOLOGO=1`、`PIP_DISABLE_PIP_VERSION_CHECK=1` | 已写入 User 作用域 |
| **pip 镜像切换** | 阿里云 → **中科大** | 同一操作 10 分钟未完成 → **42 秒完成** |

pip 包升级明细：

```
pip 26.1.2→26.2.1    numpy 2.5.1→2.5.3    scipy 1.18.0→1.18.1
matplotlib 3.11.1→3.11.2   protobuf 7.35.1→7.36.2   fonttools 4.63.0→4.66.1
contourpy 1.3.3→1.4.0      msgpack 1.2.1→1.2.3      kiwisolver 1.5.0→1.5.1
filelock 4.0.6→4.0.7       pyparsing 3.3.2→3.3.3
```

### ⚠️ 本轮最重要的发现：阿里云 PyPI 镜像对本机限速到 45 KB/s

第二十二节我把 pip 源设成了阿里云，本轮升级时**卡了 10 分钟**。
起初判断为"下载停滞"，改用 `--timeout 30 --retries 10` 重试，**仍然卡住**。
直到逐级测试才定位真因：

| URL | HTTP | 耗时 | 实际传输 |
|---|---|---|---|
| `mirrors.aliyun.com/` | 301 | 310 ms | — |
| `mirrors.aliyun.com/pypi/` | 200 | 607 ms | — |
| `mirrors.aliyun.com/pypi/simple/` | 200 | **15040 ms** | 45.7 MB 中只传了 **672 KB** |
| `mirrors.aliyun.com/pypi/simple/numpy/` | 200 | **15026 ms** | 1.3 MB 中只传了 **680 KB** |

**规律：静态小页面正常，传输量一大就降到约 45 KB/s。**
37.4 MB 的 scipy wheel 按此速率需要 **14 分钟**——所以"卡住"其实是"慢到看起来像卡住"。

对比（同样取 1.3 MB）：

```
清华      771 ~ 1383 KB/s
中科大     612 ~  771 KB/s
阿里云     ~45 KB/s          ← 慢 17~30 倍
```

**换到中科大后，同一个升级操作 42 秒完成。**

> **这是我在第二十二节的选源失误。** 当时因为清华的索引页能打开但 pip 报
> `from versions: none`，就选了阿里云——**而我当时的测试里中科大是明确成功的**，
> 本该直接选它。**两个候选都测过，却选了有问题的那个。**

> **教训：镜像的"可用"与"够快"是两件事。** 只验证一次请求成功是不够的，
> 要验证**持续吞吐**。而且既然做了多镜像对比，就应当按实测结果选优，
> 而不是"第一个能用就用"。

### 另一处：我上轮造成的组件缺失

第二十二节我用 `rustup toolchain install --profile minimal` 装 stable 图省时间，
**代价是 stable 下 `cargo clippy` 与 `cargo fmt` 直接不可用**：

```
minimal 装出来: cargo · rust-mingw · rust-std · rustc
补全后:        + clippy · rustfmt · rust-docs
```

> **教训：`minimal` profile 会静默砍掉日常必用的组件。** 用 stable 就是为了日常开发，
> 省那 50 MB 反而制造了一个"看起来装好了、实际缺工具"的状态。

### 我在这轮又犯的两次测试错误

**一、`import protobuf` 报 ModuleNotFoundError**

我据此一度以为安装失败。实际是 **protobuf 的包名是 `protobuf`，导入名是 `google.protobuf`**
（`from google import protobuf`）。**用包名去 import 是错的。**

**二、把测试脚本命名为 `_pytest.py`，导致 pytest 导入失败**

报错为 `partially initialized module 'pytest' ... circular import`。
真因是 **pytest 内部有 `_pytest` 包**，而 Python 会把脚本所在目录放进 `sys.path`，
于是 `from _pytest import __version__` 解析到了**我自己的文件**。

> 两个错误都属于"测试代码本身的缺陷被误读为被测对象的问题"。
> **验证工具时，测试代码的可靠性必须与被测对象同等对待。**

### 已确认本就正确的项

| 项目 | 状态 |
|---|---|
| `DOTNET_CLI_TELEMETRY_OPTOUT` | **已经是 `true`**（我原以为未设置） |
| `GOTOOLCHAIN` | `auto`（Go 1.21+ 默认，无需改） |
| `GOPROXY` | `https://goproxy.cn,direct` ✓ |
| `JAVA_HOME` | 指向 JDK 21 ✓ |
| `E:\Git\.venv` | 健康可用（Python 3.14.6，18 个包） |
| `corepack` | **Node 25 起已从发行版移除**，Node 26 没有它是正常的 |

### 评估后未执行

| 项目 | 说明 |
|---|---|
| Python 3.13（149 MB） | 仅 6 个包、2025-09 后未动过。用户选择保留作回退 |
| `GOSUMDB=sum.golang.org` | 理论上是国内拉 Go 包的卡点，但 goproxy.cn 会代为解析；未实测到问题，不动 |
| `NODE_OPTIONS` / `MAVEN_OPTS` | 无实际需求 |
| NuGet 国内镜像 | 实测 `dotnet` 还原正常（3.66 秒），未觉慢 |

---

## 二十五、2026-10-01 Alt+Tab 切换卡顿排查

用户反馈"页面切换不顺滑"。经确认场景是 **Alt+Tab 窗口切换**。

### 逐项排除（四项怀疑，三项不成立）

| 怀疑项 | 实测 |
|---|---|
| **显示器刷新率** | **180 Hz**（最大 180），2560×1600 —— 头号嫌疑排除 |
| **DSH 的 GPU 开关** | 无任何 `--disable-gpu` 类参数；实测 3D 引擎占用 4.9%，专用显存 334 MB —— 硬件加速正常 |
| **辅助功能动画总开关** | `Accessibility\Animation` 未设置，未启用"关闭所有动画" |
| **窗口/任务栏动画** | ⚠️ **`MinAnimate=0`、`TaskbarAnimations=0`、`ListViewAlphaSelect=0`** —— 确认为关闭 |

### 真正的主因：Windows 11 默认把浏览器标签页塞进 Alt+Tab

```
MultiTaskingAltTabFilter = (未设置 → Windows 11 默认 3)
                           3 = 窗口 + 所有标签页
```

用户的 Edge 窗口标题直接暴露了负载：

```
"……游戏解说 和另外 7 个页面 - 个人 - Microsoft Edge"
                              ↑ 8 个标签页
```

**改前每按一次 Alt+Tab 要渲染约 9 个缩略图（1 窗口 + 8 标签页），改后只剩 1 个。**

> 这是我先前没料到的方向。我最初把注意力放在"动画被关"上，
> 而动画只是次要因素——**面板内容的数量才是决定性的**。

### 已执行

| 项目 | 变更 |
|---|---|
| `MinAnimate`（`Control Panel\Desktop\WindowMetrics`） | `0` → `1` |
| `TaskbarAnimations` | `0` → `1` |
| `ListViewAlphaSelect` | `0` → `1` |
| `EnableTransparency`（`DWM`） | 未设置 → `1` |
| **`MultiTaskingAltTabFilter`** | 未设置（=3） → **`0`（仅窗口）** |

重启 explorer.exe 使设置生效（内存 362 MB → 243 MB）。

备份：`D:\Backups\Explorer-before-smoothness-20261001.reg`、
`D:\Backups\Desktop-before-smoothness-20261001.reg`

### 关于"动画被关"

被关掉的三个项（`MinAnimate` / `TaskbarAnimations` / `ListViewAlphaSelect`）
是典型的**"游戏优化三件套"**——只关动画，其余视觉项（`ListviewShadow`、
`EnableAeroPeek`）保持开启，说明它来自优化工具或 FPS 教程的针对性修改。

**这类改动的收益极小**（桌面动画几乎不占资源），代价是**所有界面切换失去视觉过渡**。
仅当目标是极致帧率时才值得，日常使用得不偿失。

### 我在这轮的一个过程失误

第一次排查时，我用**命令行内联脚本**读取 DSH 的 GPU 参数，输出显示
"有进程带 `--disable-gpu`"，我据此准备把它当作原因之一。

实际是**命令被编码层破坏**——数组字面量被解析成了一个字符串，
正则把一个不存在的模式匹配成了"命中"。改用**脚本文件**重测后，
DSH **完全没有**任何 GPU 限制参数。

> **本会话第二次栽在同一件事上**（第二十四节也遇到过命令行编码破坏）。
> **凡是逻辑稍复杂、含中文或含数组/正则的排查，一律用 `.ps1` 文件执行，
> 不要写成命令行内联脚本。**

### 仍可继续的方向

| 方向 | 说明 |
|---|---|
| `AltTabSettings = 1` | 改用经典 Alt+Tab（纯图标、无缩略图），极快但外观朴素 |
| 更新核显驱动 | AMD Radeon 610M 驱动为 2025-05-30，已 **489 天**未更新；独显是 2026-08-20（42 天） |
| 减少常驻窗口 | 实测 `dwm` 专用显存占 1122 MB，说明桌面合成已在独显上进行 |

---

## 二十六、2026-10-01 视觉效果开销实测与独显直连确认

用户问了两件事：**"开动画和透明效果吃资源吗"**、**"独显直连下核显需要更新吗"**。
两者都用实测回答，不用印象。

### 一、视觉效果开销：A/B 实测，差异在噪声范围内

DWM（桌面窗口管理器）负责所有窗口动画与透明模糊的 GPU 合成，
因此它的 GPU 占用就是"视觉效果"的直接成本。脚本：`measure-visual-cost.ps1`。

各阶段采样 12 次、间隔 900 ms：

| 阶段 | 设置 | DWM GPU 平均 | 峰值 | 系统 GPU 合计 |
|---|---|---|---|---|
| A | 透明**开** | 5.96% | 7.66% | 14.49% |
| B | 透明**关** | 5.73% | 5.88% | 14.21% |
| C | 透明**开**（恢复） | 5.77% | 5.81% | 14.24% |

**关键在读数的自相矛盾**：阶段 C 同样是"开着透明"，读数是 5.77% ——
**与阶段 B（关着）几乎相同，却与阶段 A（同样开着）相差 0.19 个百分点**。

**这说明那 0.2 个百分点主要是时间波动，而非透明效果的成本。**

> **如果没有阶段 C 这个对照，我会得出"透明效果花 0.23 个百分点"的错误结论。**
> **A/B 测试必须包含"恢复回原状"的第三次测量**，否则无法区分
> "设置的效果"与"时间的漂移"。

**结论**：在 RTX 5060 上，窗口动画与透明模糊的开销**在测量噪声以内**。
反过来说——**关掉它们也省不下任何东西**，这正是"游戏优化三件套"得不偿失之处：
付出生硬的交互体验，换来的收益无法测量。

### 二、独显直连：已确认启用

```
NVIDIA GeForce RTX 5060 Laptop GPU    180 Hz    2560 x 1600
AMD Radeon(TM) 610M                   —         (无显示模式)
```

**核显连显示模式都没有** —— 说明它不参与画面输出，即**独显直连已启用**。
`dwm` 专用显存 821 MB 也印证合成器跑在独显上。

### 三、核显驱动要不要更新

**对画面流畅度：没有影响，优先级低。**

核显仍被以下场景使用：

| 场景 | 说明 |
|---|---|
| 视频硬解码 | 部分播放器（如 PotPlayer）默认走核显解码 |
| 电池模式 | 节能渲染可能调回核显 |
| 标记为「省电」的应用 | 即便独显直连，仍渲染在核显再拷贝过来 |
| 外接显示器 | 部分输出路径经过核显 |

> ⚠️ **OEM 笔记本更新显卡驱动应优先用机械革命官网的版本。**
> AMD 通用驱动在 MUX 机型上偶发兼容问题（切换模式后黑屏、亮度失效）。
> 489 天的驱动差通常意味着"OEM 未发布新版"，而非"用户忘了更新"。

### 顺带发现：GPU 偏好注册表堆积

`HKCU\SOFTWARE\Microsoft\DirectX\UserGpuPreferences` 下有 **170+ 条**应用 GPU 偏好
（绝大多数是游戏标记为 `GpuPreference=2` 高性能）。其中包含指向**已删除路径**的残留：

```
C:\ProgramData\GamePPPublic\PCBenchmark\GPP_PCAwaken.exe      ← 该目录已于第二十节删除
C:\ProgramData\GamePPPublic\PCBenchmark\GPPBenchmarkSrv.exe   ← 同上
```

纯注册表整洁问题，无功能影响，未处理。

---

## 二十七、2026-10-01 "放大缩小页面不流畅" —— 定位到 DSH 插件

用户追加反馈"现在放大缩小页面也不流畅，整体弄一下吧"。做了十维度系统审计后，
**结论是：问题不在 Windows，在 DSH 装的动画插件。**

### 第一步：GPU 偏好注册表清理（已完成）

| 阶段 | 条目总数 | 路径型 | 失效 |
|---|---|---|---|
| 清理前 | 152 | 145 | 110 |
| 清理后 | **40** | **35** | **0** |

累计删除 **113 条**失效条目，保留 35 条有效应用条目与 5 项全局设置。
脚本：`clean-gpu-prefs.ps1`（带 `-DryRun`），备份
`D:\Backups\GPU-preferences-before-cleanup-20261001-001330.reg`。

### 第二步：十维度流畅度审计（`audit-smoothness.ps1`）

| 维度 | 结果 |
|---|---|
| **Game DVR 后台录制** | **已关闭** ✓（`GameDVR_Enabled=0`、`CaptureService=Stopped`、Xbox Game Bar 未运行） |
| 刷新率 | 180 Hz 满速 ✓ |
| GPU 占用 | 平均 13.3%，仅 `dwm` 有活动 —— **显卡不紧张** |
| CPU 总占用 | 12.1%（24 逻辑处理器） |
| 内存 | 19.8 GB 空闲 / 31.2 GB —— **不紧张** |
| 存储 | C 74.5 GB / D 87.3 GB / E 554.4 GB 可用 ✓ |
| HAGS | `HwSchMode` 未设置（由系统决定） |
| 进程总数 | **275 个** |
| 叠加层 | NVIDIA(9) · Discord(8) · Nahimic(6) · mCloud(14) · Wallpaper Engine(2) |
| 常驻服务 | NahimicService、Wallpaper Engine Service、AMD 系列、Razer Game Manager |
| 计划任务 | NahimicTask32/64、SamsungMagician、ResolutionHost、CacheTask 等在运行 |

**所有系统层面指标都正常**——这正是关键：资源都不紧张，卡顿却存在，
说明瓶颈在别处。

### 第三步：定位到真正的元凶

采样 DSH 各进程的 CPU 时间增量（脚本文件执行，避免命令行编码破坏）：

```
PID 32272  renderer      3.18 秒 / 3 秒  = 106% 单核    ← 持续满载
PID 38960  renderer      0.03 秒 / 3 秒  =   1%         ← 第二个 renderer，空闲
PID 4904   gpu-process   1.20 秒 / 3 秒  =  40%
```

**对照组（同样 3 秒采样）：**

```
DSH        6 进程  →  渲染进程 2.81 秒
Edge      17 进程  →  渲染进程 0 秒
WebView2  19 进程  →  渲染进程 0.08 秒
```

**DSH 比同类应用高两个数量级。**

### 根因：壁纸引擎插件的动态壁纸 + 每帧模糊

DSH 的 `package.json` 里装了：

```
dsh-plugin-wallpaper-engine                          v1.0.1   3.3 MB
dsh-plugin-whale-pet                                 v0.2.8   0.5 MB
@smalltailqwq/dsh-client-ui-skin-deep-whale-manager  v0.1.5
@openviking/dsh-memory-plugin                        v0.5.8
@tt-a1i/archify-dsh                                  v0.1.0
```

壁纸引擎插件**自己的描述**说明了它在做什么：

> "Wallpaper Engine backgrounds for the DSH web GUI: render your local Wallpaper
> Engine Video/Web wallpapers **behind the chat** ... with **iOS-style liquid glass**,
> adjustable **scrim/border/blur** ..."

其 `lib/client.js` 有 **1087 KB**，还带 `scene-player.js`（83 KB）与
`scene-render-worker.mjs`。

**机制**：满屏动态壁纸持续重绘，叠加 `backdrop-filter` 模糊——
**模糊需要每帧重新计算**。渲染进程因此长期占用一个完整核心。

**为什么这会导致缩放卡顿**：Chromium 的页面缩放会触发全文档重排与重新栅格化。
主线程已被动画占满，缩放请求只能排队等待，于是表现为"卡"。

### 已排除项（都不是原因）

```
✗ 刷新率          180 Hz 满速
✗ GPU 加速        DSH 3D 引擎正常，无 --disable-gpu 类参数
✗ 视觉效果        动画/透明开销在噪声内（第二十六节 A/B 实测）
✗ Game DVR        已关闭
✗ 内存/GPU/CPU    全部充裕
✗ Alt+Tab 过滤    已改为仅窗口
```

### 处理建议（需在 DSH 设置界面操作）

由轻到重：

| 步骤 | 操作 | 预期 |
|---|---|---|
| A | 关闭或调低壁纸的**模糊 / 液态玻璃** | 去掉最贵的每帧模糊 |
| B | 动态壁纸改为**静态帧** | 消除持续重绘，保留观感 |
| C | 关闭/卸载 `dsh-plugin-wallpaper-engine` | 最彻底 |
| D | 关闭 `dsh-plugin-whale-pet` | 消除宠物动画 |

> **未由我直接修改。** DSH 是用户正在使用的界面，改错会直接影响当前对话；
> 且插件设置在 `storages` 中查不到（可能存于 Electron 的 localStorage/IndexedDB），
> 从外部编辑不可靠。**应在 DSH 设置界面操作，改完由我复测 renderer 占用验证效果。**

### 本轮我自己的两次失误

**一、通配符又栽了一次（本会话第三次）**

清理 GPU 偏好时，`Remove-ItemProperty -Name 'D:\qqdownloads\[TS整合]...'`
**报告成功但实际什么都没删** —— 属性名里的 `[TS整合]` 被当成字符类。
最终用 .NET API 解决：

```powershell
$k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path, $true)
$k.DeleteValue($name, $false)
```

> **注册表属性名与文件路径都可能含 `[ ]`，凡涉及它们一律用字面量方式
> （`-LiteralPath` / .NET API），不要用接受通配符的 cmdlet 参数。**

**二、备份文件因时间戳多生成了一份**

脚本内 `$stamp` 在每次运行时重算，导致预演与实际执行产生两个文件名不同的备份。
已删除较旧的那个。**教训：备份路径应在一次操作内固定，不该随执行次数变化。**

### 本会话关于通配符的三次教训汇总

| 次 | 位置 | 后果 |
|---|---|---|
| 1 | `Test-Path $path`（GPU 偏好路径含 `[ ]`） | 111 条误报为失效（实为 110） |
| 2 | `Remove-ItemProperty -Name`（属性名含 `[ ]`） | 报告成功但未删除 |
| 3 | `Split-Path -LiteralPath`（参数集不匹配） | 报错，改用 `[System.IO.Path]` |

---

## 二十八、2026-10-01 找回「零成本但被关掉」的设置

用户问：**还有什么类似 Alt+Tab 那种「不吃资源、但被关掉的」设置？**
脚本：`audit-free-settings.ps1`（审计）、`apply-free-settings.ps1`（应用）。

收录标准：**不耗资源 + 提升体验 + 容易被优化工具或教程误关**。

### 我在这轮审计中的 6 处误判（先说自己错的）

审计脚本里我给每项写了"理想值"，**其中一半是拍脑袋定的，复核后发现是错的**：

| 我标为"关闭"的项 | 核实结果 |
|---|---|
| `NtfsDisableLastAccessUpdate = 0x80000002` | **这是 Windows 默认**。低位 2 = "系统管理，更新**已启用**"，高位是系统接管标志。`fsutil` 权威读数：`DisableLastAccess = 2 (System Managed, ... ENABLED)`。**我设的理想值 0x80000003 才是"禁用"，标反了** |
| `MouseSensitivity = 7` | 纯个人偏好，无对错。我设的"理想值 10"毫无依据 |
| `LaunchTo = 2` | **Windows 11 原厂默认**就是快速访问，不是被改过 |
| `SeparateProcess = 0` | Win11 已把文件夹窗口放在独立进程，此项是**无效遗留** |
| `DisallowShaking = 1` | 禁用"抖动最小化"，很多人主动关掉防误触，属偏好 |
| `AutoEndTasks=1` + `HungAppTimeout=3000` | **这是"加快关机"的激进调整，不是零成本体验项** —— 归类错误 |

> **教训：给设置写"理想值"时，必须能说出该值的来源（Microsoft 文档 / 实测 / 原厂默认），
> 不能凭"感觉这个应该开着"就下判断。** 否则审计会把正常状态报成问题，
> 用户照着改反而把事情弄坏。

### 真正符合标准的 7 项（已全部应用）

| 项目 | 改动 | 为什么算零成本 |
|---|---|---|
| `ForegroundFlashCount` | **7 → 3** | 原厂默认就是 7 次闪烁，一个后台弹窗会让图标闪 7 下。改成 3 次纯粹减少打扰 |
| `EnableClipboardHistory` | 未设置 → **1** | Win+V 剪贴板历史。只在复制时记录，**不常驻、不轮询** |
| `TaskbarEndTask` | 未设置 → **1** | 任务栏右键多一项"结束任务"，比开任务管理器快 |
| `HwSchMode` | 未设置 → **2** | HAGS。前面实测 GPU 很闲（13%），不会增加负担 |
| `TaskbarMn` | 未设置 → **0** | 隐藏聊天(Teams)按钮 —— 纯减项 |
| `ShowCopilotButton` | 未设置 → **0** | 隐藏 Copilot 按钮（Copilot 本体已卸载） |
| `HideRecommendedSection` | 未设置 → **1** | 开始菜单不显示"推荐的项目" —— 纯减项 |

### 同时修正的风险项（用户选择"恢复安全值"）

```
AutoEndTasks            1     -> 0        关机时询问，不自动强杀
HungAppTimeout          3000  -> 5000     无响应判定回到默认
WaitToKillAppTimeout    10000 -> 20000    等待存盘时间回到文档默认
```

`AutoEndTasks=1` 意味着**程序还在存盘也会被直接杀掉**。它属于"性能优先"而非"体验优化"，
代价是丢数据风险。

### 验证结果

10 / 10 通过：

```
[OK] ForegroundFlashCount = 3        [OK] TaskbarEndTask = 1
[OK] EnableClipboardHistory = 1      [OK] TaskbarMn = 0
[OK] ShowCopilotButton = 0           [OK] HideRecommendedSection = 1
[OK] AutoEndTasks = 0                [OK] HungAppTimeout = 5000
[OK] WaitToKillAppTimeout = 20000    [OK] HwSchMode = 2
```

> `HwSchMode` 需**重启电脑**生效；其余项立即或重启 explorer 后生效。

### 备份

```
D:\Backups\free-settings-before-20261001.txt          改动前快照
D:\Backups\desktop-before-freesettings-20261001.reg
D:\Backups\adv-before-freesettings-20261001.reg
D:\Backups\graphicsdrivers-before-hags-20261001.reg
```

### 又一次提权踩坑

第一次提权改 `HwSchMode` 没成功（UAC 未完成）。第二次改用 `.cmd` + `RunAs`，
**注册表改动成功但日志写入失败**：

```
The process cannot access the file 'D:\Backups\hags-apply.log'
because it is being used by another process.
```

原因是 `.cmd` 里 `>> "日志"` 的重定向**与脚本内部的 `Add-Content` 指向同一个文件**，
两者争用句柄。

> **教训：提权脚本若自己写日志，外层 `.cmd` 就不要再把 stdout 重定向到同一个文件。**
> 本次以独立校验为准（`HwSchMode = 2` 确认写入），未受日志失败影响。

---

## 二十九、2026-10-01 零成本设置第二轮（推广与提示）

第一轮覆盖任务栏/动画/鼠标/关机/HAGS；本轮查**广告推送、资源管理器深层项、
DNS over HTTPS、浏览器效率、Win11 右键菜单、输入法**。

### ⚠️ 我先写出了一个大 bug：整个审计没读注册表

第一版审计输出里，所有项的值列是**空白**而不是 `(未设置)`：

```
[OFF] SoftLandingEnabled                 =        ← 值列空白
```

原因在参数声明：

```powershell
param( [string]$Now, ... )      # ← 这里
...
if ($null -eq $v -and $Path) { $v = ...读注册表... }
```

**PowerShell 会把 `$null` 强制转换成空字符串 `""`**（因为声明了 `[string]`），
于是 `$null -eq $v` 永远为假，**读取注册表的分支从未执行**。

结果：第一版给出的 **11 条"建议"全部基于空值**，其中至少 6 条是假结论
（例如把已经关好的 `SubscribedContent-338389Enabled = 0` 报成需要修改）。

修正为 `[object]$Now` 后重跑，真实结果从 11 项收敛到 **5 项**。

> **教训：PowerShell 的类型约束会静默改变 `$null` 的语义。**
> 用"值是否为 `$null`"作哨兵时，参数**绝不能声明为 `[string]`**。
> 另外——**审计脚本自己也要被验证**：输出里出现异常的空值/统一值，
> 就该先怀疑脚本而不是被审计的系统。

### 修正后的真实结果

**用户早已关好的（4 项）**：

```
SubscribedContent-338389Enabled = 0    使用建议推送
SubscribedContent-338388Enabled = 0    开始菜单推荐应用
SystemPaneSuggestionsEnabled    = 0    设置里的建议
IsDynamicSearchBoxEnabled       = 0    搜索框亮点
Start_TrackDocs / Start_TrackProgs = 0  记录最近使用（隐私优先）
```

**真正还开着的（5 项，已全部关闭）**：

| 项目 | 原值 | 说明 |
|---|---|---|
| **`SilentInstalledAppsEnabled`** | **1** | 会**静默安装推广 App** —— 本轮唯一有实际影响的一项 |
| `SoftLandingEnabled` | 未设置 | "Windows 提示与建议"弹窗 |
| `SubscribedContent-310093Enabled` | 未设置 | "Windows 欢迎体验" |
| `ShowSyncProviderNotifications` | 未设置 | 资源管理器里的 OneDrive 推广通知 |
| `ShowCloudFilesInQuickAccess` | 未设置 | 快速访问混入云盘文件 |

验证 5/5 通过。备份：`contentdelivery-before-20261001.reg`、`adv2-before-20261001.reg`。

### 顺带确认「本来就很好」的项

```
电源模式          = ded574b5-...  = 【最佳性能】（已在最高档）
中文输入法         = 云候选开、动态候选排序开
网络探测          = EnableActiveProbing = 1（关掉会误报"无 Internet"）
```

### 发现但用户选择不做

**Win11 经典右键菜单**：`HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32`
设为空字符串即可恢复完整菜单（无需再点"显示更多选项"），零开销、可逆。
**属偏好项**（有人反而喜欢新菜单），用户保留 Win11 默认。

### DNS over HTTPS：想启用需要先改 DNS 服务器

```
系统 EnableAutoDoh = 未设置（默认 2 = 自动）
网卡 DNS = 192.168.1.1 / 192.168.3.1   ← 路由器地址，不支持 DoH
```

Win11 内置了 1.1.1.1、8.8.8.8、9.9.9.9 等 DoH 模板，但**当前用的是路由器 DNS**。
要启用必须先指定支持 DoH 的上游 —— 这**不是纯开关**，属于改动网络配置，故未自动建议。

### 结论：这一类设置已经基本挖尽

两轮累计：

| 轮次 | 审计范围 | 找到的真项 |
|---|---|---|
| 第一轮（第二十八节） | 任务栏、动画、鼠标、关机、通知、HAGS | **10 项**（含 3 项风险修正） |
| 第二轮（本节） | 广告推送、资源管理器、电源、输入法、浏览器 | **5 项** |

**第二轮的数量和质量都明显下降**，且其中只有 1 项（`SilentInstalledAppsEnabled`）
有实际影响。继续深挖的边际收益已经很低。

**剩下真正有价值的都不属于"零成本开关"类别**：

| 方向 | 为什么不算零成本开关 |
|---|---|
| DNS over HTTPS | 需要更换 DNS 服务器 |
| 经典右键菜单 | 偏好取舍 |
| 快速启动开关 | 开机速度 vs 状态干净的取舍 |
| 更新核显驱动 | OEM 机型有兼容风险 |
| **关闭 DSH 壁纸插件动画** | **这才是"缩放卡顿"的真凶（第二十七节），但它不是注册表开关** |
