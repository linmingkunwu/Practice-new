# PCL 2.99.0.0 下载功能解锁（本机自用补丁）

## 一、先说结论：那行代码的方向反了

你截图里的那一行（`Modules/ModSecret.vb` 第 18 行）：

```vb
Public Const RestrictMcDownload As Boolean = True
```

`RestrictMcDownload` 的字面意思是「**限制** MC 下载」，**True = 关闭下载**（PCL 2.99 更新日志原文：
「删除：为遵守相关法律法规，PCL 暂时不再提供 MC 下载功能」）。

所以要让下载功能回来，源码里应该改成 **`False`**，而不是反过来。

而且源码里它一共用在 6 个地方，全是「禁止」分支：

| 位置 | 作用 |
| --- | --- |
| `ModModpack.vb:11`、`:88` | 整合包安装前直接抛「不再提供 MC 下载功能」 |
| `PageDownloadInstall.xaml.vb:17` | 下载页的加载器被换成「关闭下载」的报错任务 |
| `PageDownloadModify.vb:315` | 修改版本页隐藏「Minecraft 版本」卡片 |
| `PageDownloadCompDetail.xaml.vb:275` | 资源页隐藏「安装」按钮 |
| `FormMain.xaml.vb:1079` | 拖入整合包时提示该错误 |

## 二、为什么不能直接改 exe 里那个字节

官方发布的 `Plain Craft Launcher 2.exe` 是**编译产物**，`Public Const` 是编译期常量：
`If RestrictMcDownload Then ... Else ...` 在编译时就被折叠成了「只剩禁止分支」，
真正的下载代码（Else 分支）**根本没有编进 exe**。

证据（原版 exe 的反编译 IL）：

```
=== PCL.PageDownloadInstall::LoaderInit ===
IL_001a ldstr "关闭下载"
IL_001d ldfld  Action`1<LoaderTask`2<...>>  $IR3-3
IL_0045 newobj LoaderTask`2<...>::.ctor(String, Action, Func, ThreadPriority)   ← 抛异常的任务
IL_0058 call   MyPageRight::PageLoaderInit<...>(...)                            ← 只剩下这一个分支
```

也就是说：把 exe 里 `True` 的常量改成 `False` 没用，必须**重新编译源码**才行。
（本机没有 Visual Studio / MSBuild 的 WPF 工具链，只有 .NET SDK，无法直接编译 PCL 的 net48 WPF 工程。）

## 三、本次实际做法：直接改 IL，把被替换掉的真加载器换回来

不重新编译整个 PCL，而是用 dnlib 对官方 exe 做两处等价改写：

1. **`PCL.PageDownloadInstall::LoaderInit`**（核心）
   把 `ldstr "关闭下载"` + 构造报错 `LoaderTask` 的那 12 条指令，
   换成 `ldsfld PCL.ModDownload::DlClientListLoader`（真正的版本列表加载器）。
   仓库里这个加载器、`LoadMinecraft_OnFinish`、`ShowMinecraftVersionList`、
   `BtnStart_Click` → `StartInstall` → `ModDownloadLib.McInstallStart`
   全部原样存在，只是入口被官方换掉了。

2. **`PCL.PageDownloadModify::LoadInstanceFinished`**
   `CardMinecraft.Visibility = Collapsed(2)` → `Visible(0)`，
   恢复「修改版本」页里的 Minecraft 版本卡片。

补丁后体积变化：5,980,160 B → 5,972,480 B（dnlib 重写 PE，内容等价）。
原始文件 SHA256：`6B6E1260CB5A1D6A303855F1C60CAB3D0BC1AEBBA7E40A964180188B271E7386`

## 四、验证方式（可复现）

PCL 自带自动化参数 `--test`（源码 `PageLaunchLeft.xaml.vb:88`）：
启动后自动依次切到「下载 → 资源下载 → 设置 → 更多 → 版本选择 → 更多」然后退出（返回码 123）。

原版日志（`logs/log_original.txt`）：

```
[ModLoader] 加载器 LoaderTask`2 关闭下载 状态改变：Loading
[ModLoader] 加载器 LoaderTask`2 关闭下载 状态改变：Failed
[ModLoader] 加载线程 关闭下载 出错：为遵守相关法律法规，PCL 暂时不再提供 MC 下载功能……
```

补丁版日志（`logs/log_patched.txt`、`logs/log_deployed.txt`）：

```
[ModLoader] 加载器 LoaderTask`2 DlClientList Main 状态改变：Loading
[ModNet]    发起网络请求（GET，https://launchermeta.mojang.com/mc/game/version_manifest.json）
[ModLoader] 加载器 LoaderTask`2 DlClientList Main 状态改变：Finished
[FormMain]  切换主要页面：Download, OtherHelp
```

`关闭下载` 报错消失，真实版本列表加载器正常跑完，退出码均为 123。

## 五、文件说明

| 文件 | 说明 |
| --- | --- |
| `Plain Craft Launcher 2.exe` | 已打补丁的版本（与 `E:\pcl\Plain Craft Launcher 2.exe` 相同） |
| `PCL_2.99.0.0_original.exe` | 官方原版备份 |
| `tool\Program.cs` | dnlib 补丁器（`patch` / `dump` 两个模式） |
| `logs\log_original.txt` | 原版 `--test` 日志（对照用） |
| `logs\log_patched.txt` | 补丁版 `--test` 日志 |
| `logs\log_deployed.txt` | 部署到 `E:\pcl` 后的 `--test` 日志 |

部署位置：`E:\pcl\Plain Craft Launcher 2.exe`
另有一份原版备份在 `E:\pcl\backup\Plain Craft Launcher 2.exe.orig`。

## 六、仍然存在的限制

1. **整合包一键安装仍然不可用**（版本选择页「导入整合包」、拖入压缩包、资源页「安装」按钮）。
   具体表现：
   - `ModModpack.ModpackInstall()`（无参，选文件入口）被折叠成只剩「提示 + 返回」7 条指令，
     所以点「导入整合包」/ 拖入 `.zip|.mrpack` 只会弹「为遵守相关法律法规……」；
   - `ModModpack.ModpackInstall`（解析入口）末尾被折叠成一句无条件 `throw`，
     原本的 `Select Case PackType` 分派代码被当作不可达代码删掉了；
   - 资源详情页的「安装」按钮被折叠隐藏（`PageDownloadCompDetail.xaml.vb:275`），
     所以连整合包文件都下载不到。
   好消息：真正的安装实现方法都还在 exe 里且完整 ——
   `InstallPackCurseForge`(579 条)、`InstallPackModrinth`(576)、`InstallPackHMCL`(231)、
   `InstallPackMMC`(341)、`InstallPackMCBBS`(409)、`InstallPackLauncherPack`(72)、`InstallPackCompress`(157)。
   被删的只是入口的「选文件 + 分派」，理论上可以再做一次 IL 重构补回来（风险高于本次补丁，需真实整合包实测）。
   → 目前「下载」页下载 **Minecraft 原版 + Forge/NeoForge/Fabric/OptiFine/LiteLoader 组件** 是好的；
   → 已装好的整合包照常启动（版本选择、Mod 管理、整合包导出都不受这两个 gate 影响）。
2. **PCL 自动更新会覆盖补丁**。看到「PCL 已更新至新版本」提示时不要点更新；
   若更新了，把 `tool` 重新跑一遍打在新 exe 上即可：
   ```powershell
   cd E:\Git\pcl-patch\tool
   dotnet run -c Release -- patch "E:\pcl\Plain Craft Launcher 2.exe" "E:\pcl\Plain Craft Launcher 2.exe.patched"
   # 校验没问题后再替换（先备份原文件）
   ```
   注意：新版本如果改了 `LoaderInit` 的 IL 结构，补丁器会报「找不到 ldstr 关闭下载」，需要重新定位。
3. **还原方法**：把 `PCL_2.99.0.0_original.exe` 复制回 `E:\pcl\Plain Craft Launcher 2.exe` 即可。
4. PCL 官方是因为「相关法律法规」移除下载功能的，这个补丁只是**本机自用**的本地修改，
   请不要分发改过的 exe，也不要在公开场合传播，风险自负。
