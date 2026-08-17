---
name: pr-flow
description: 日常开发一键 PR 流程：审查并改进代码 → 自动校验 → 建分支 → 提交 → 推送 → 创建 Pull Request
whenToUse: 用户要求"跑开发流程"、"帮我 PR"、"提交 PR"、"pr 一下"，或要求审查改进代码后提交 Pull Request 时
---

# pr-flow — 日常开发一键 PR 流程

把日常开发流程标准化：**审查改进 → 校验 → 建分支 → 提交 → 推送 → 创建 PR**，一次跑完并回报 PR 链接。

## 执行步骤

### 1. 审查与改进（AI 负责）
- 通读本次要提交的文件，修复 Bug、风格、结构问题
- 教学笔记、纯配置、标准模板类文件若无问题则不改动
- 改完先用 `python -m py_compile` / `dotnet build` / 小规模冒烟测试自行验证

### 2. 执行一键脚本（优先）
仓库内存在 `scripts\pr-flow.ps1` 时使用它（模板项目自带）；否则使用全局安装位置 `E:\Git\scripts\pr-flow.ps1`：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '<脚本路径>\pr-flow.ps1' -RepoPath '<仓库路径>' -Branch '<分支名>' -Title '<PR 标题>' -CommitMessage '<提交信息>'"
```

脚本自动完成：检测改动 → 改动文件 py_compile / 仓库内 csproj+sln dotnet build → stash→从 origin/main 建分支→pop 恢复 → UTF-8 提交 → 推送 → `gh pr create`。
可选参数：`-Base <分支>`（默认 main）、`-SkipChecks`、`-SkipPush`、`-SkipPr`。

### 3. 回退方案（脚本不可用时手动执行）
```powershell
git fetch origin
git switch -c <分支名> origin/main      # 有未提交改动时先 git stash -u，切完再 pop
git add -A
# 提交消息写 UTF-8 无 BOM 临时文件后: git commit -F <msg文件>
git push -u origin <分支名>
gh pr create --base main --head <分支名> --title "<标题>" --body-file <正文文件>
```

### 4. 回报
PR URL、分支名、改动文件清单、校验结果。

## 从 VSCode / 任意终端调用（headless 模式）

在项目目录打开 VSCode 集成终端，直接让 agent 跑整个流程（无需打开 Web 界面）：

```powershell
# 完整流程：审查改进 → 校验 → 建分支 → 提交 → 推送 → 创建 PR
dsh --profile headless "加载 pr-flow 技能，对当前仓库跑一遍开发流程"

# 更省事：已安装全局别名 dsh-flow（PowerShell profile 自带），默认即跑完整流程，可传自定义提示词
dsh-flow "对 dice-game 目录审查改进并提 PR"
```

说明：headless 以**当前目录**为工作区根，首次运行会自动初始化 headless profile；结束后直接打印最终答案并退出。

## 注意事项
- `pr-flow.ps1` 是 **UTF-8 BOM** 文件（Windows PowerShell 5.1 需要），必须用 PowerShell 执行，不要用 bash
- 提交消息/PR 正文含中文时：写 UTF-8 临时文件再 `-F`/`--body-file`，避免命令行编码乱码
- 本机 `gh` 已登录（repo scope）；Practice 仓库 origin 为 github.com/linmingkunwu/Practice
- 新建项目请从模板 github.com/linmingkunwu/project-template（Use this template）创建，自带本脚本、`.dsh/skills/pr-flow` 与 GitHub Actions CI
- GitHub Actions 的 `hashFiles()` 只能用于 step 级 `if`，不能用于 job 级（会导致运行直接失败）
