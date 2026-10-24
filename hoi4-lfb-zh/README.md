# TNO:2WRW Continued + Light From Lake Baikal —— 简体中文补丁（本地 mod）

## 为什么做

Steam 创意工坊 mod `3788892521`（Hearts of Iron IV，AppID 394360，「TNO:2WRW Continued + Light From Lake Baikal」v0.3.5）
和它依赖的 `3649456037`（「TNO: Second West Russian War Continued」v1.5.5）都只带 `localisation/english`，
没有 `localisation/simp_chinese`。游戏语言是简体中文时，HOI4 找不到中文词条就直接显示本地化键名，
于是书签/国策/事件会显示成 `COX_Bookmark_DESC`、`OMS_...` 这类“代码”。

## 补丁内容（v1.1）

补丁是一个本地 mod，包含两个本地化文件：

| 文件 | 覆盖对象 | 条目 | 中文 | 英文兜底 |
|---|---|---|---|---|
| `LFB_zh_l_simp_chinese.yml` | 合并版 3788892521 | 4,313 | 4,135 | 178 |
| `2WRW_Continued_zh_l_simp_chinese.yml` | 2WRW Continued 3649456037 | 29,133 | 14,449 | 14,684 |

- 已被 TNO 汉化包（2243912940）覆盖的键（LFB 299 条、2WRW 17,356 条）不重复定义，
  继续显示汉化包的旧译文。
- LFB 部分中文主要来自单体版「The New Order: Light From Lake Baikal」（3350747146）的简中
  （键名 92% 吻合；该版 v0.3，合并版 v0.3.5，个别文本可能略旧），另有 55 条来自 2WRW-TNO。
- 2WRW 部分中文来自「TNO: 2WRW-TNO」（3449417512，v1.6.99，自带简中）：
  只在该键的英文原文与 2WRW Continued 完全一致时才复用译文，避免张冠李戴；
  其余没有可靠中文的键用 2WRW 自己的英文原文兜底，保证不再显示键名。
- 文件为 UTF-8 with BOM、`l_simp_chinese:` 头、单行值、内嵌半角引号已转义为 `\"`。

## 安装 / 启用

补丁已写入：

```
C:\Users\<你>\Documents\Paradox Interactive\Hearts of Iron IV\mod\LFB_2WRW_zh_patch.mod
C:\Users\<你>\Documents\Paradox Interactive\Hearts of Iron IV\mod\LFB_2WRW_zh_patch\
```

启用步骤：启动器 → 播放集 / Playset → 勾选「TNO 2WRW+LFB 简体中文补丁」→ 保存 → 启动游戏。
**需要重启游戏生效**（改动的是本地化加载）。

## 卸载

启动器取消勾选，或删除上面 `.mod` 文件与同名文件夹。工坊目录未被修改，Steam 更新不会覆盖补丁。

## 重新生成（mod 更新后）

```powershell
pwsh -NoProfile -File E:\Git\hoi4-lfb-zh\generate-patch.ps1
```

脚本从工坊目录读取：

| 用途 | 路径 |
|---|---|
| 合并版键名与英文原文 | `...\394360\3788892521\localisation` |
| LFB 现成简体中文 | `...\394360\3350747146\localisation\simp_chinese` |
| 2WRW Continued 键名与英文原文 | `...\394360\3649456037\localisation\english` |
| 2WRW 简中译文来源 | `...\394360\3449417512\localisation\simp_chinese` |
| 已汉化的 TNO 键（跳过） | `...\394360\2243912940\localisation` |

## 已知限制

- 2WRW Continued 仍有约 14,684 条键只有英文（约占其内容的 1/3），因为「2WRW-TNO」也只翻了它的一部分。
- 汉化包覆盖的 17,356 条 2WRW 键显示的是 TNO 本体旧译文，可能与 2WRW 的改动不一致。
- 「TNO: 2WRW-TNO」（3449417512）是另一条 2WRW 分支，自带中文；**不要和 2WRW Continued 同时启用**，
  本补丁只把它当中文语料来源，保持它在播放集里禁用即可。
- TNO 汉化包自身有 2 个 yml 解析报错（`TNO_PostApoc` 第 415 行、`radio_tno_music` 第 732 行），
  可能让少部分 TNO 文本掉回键名。
