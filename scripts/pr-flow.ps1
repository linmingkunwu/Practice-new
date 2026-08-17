<#
.SYNOPSIS
    一键 PR 流程：校验 → 建分支 → 提交 → 推送 → 创建 Pull Request

.DESCRIPTION
    把日常开发流程的机械步骤自动化（代码审查与改进由 AI/人工完成后调用）：
      1. 检查工作区是否有改动（无改动则退出）
      2. 自动校验：Python py_compile、dotnet build（按项目类型自动检测）
      3. 从 origin/<Base> 拉取最新并创建新分支（origin 不可用时回退本地 <Base>）
      4. git add -A + 提交（UTF-8 消息，无 BOM）
      5. 推送分支
      6. gh pr create 创建 Pull Request

.PARAMETER RepoPath
    仓库路径，默认当前目录。

.PARAMETER Branch
    分支名。默认自动生成：dev/<yyyyMMdd-HHmmss>。

.PARAMETER Title
    PR 标题。默认取提交信息。

.PARAMETER Body
    PR 正文。默认生成模板。

.PARAMETER Base
    目标分支，默认 main。

.PARAMETER CommitMessage
    提交信息。默认 "update: <时间戳>"。

.PARAMETER SkipChecks
    跳过自动校验。

.PARAMETER SkipPush
    只做本地提交，不推送、不建 PR。

.PARAMETER SkipPr
    推送但不创建 PR。

.EXAMPLE
    # 在当前仓库跑完整流程
    .\scripts\pr-flow.ps1 -Title "feat: 新增功能" -CommitMessage "feat: 新增功能"

.EXAMPLE
    # 只做本地提交
    .\scripts\pr-flow.ps1 -SkipPush
#>
[CmdletBinding()]
param(
    [string]$RepoPath = (Get-Location).Path,
    [string]$Branch,
    [string]$Title,
    [string]$Body,
    [string]$Base = "main",
    [string]$CommitMessage,
    [switch]$SkipChecks,
    [switch]$SkipPush,
    [switch]$SkipPr
)

$ErrorActionPreference = "Continue"

function Write-Step { param([string]$Msg) Write-Host "==> $Msg" -ForegroundColor Cyan }
function Write-Err { param([string]$Msg) Write-Host "!! $Msg" -ForegroundColor Red }

# UTF-8 写文件（无 BOM），避免中文乱码
function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

Push-Location $RepoPath
try {
    # ============================================================
    # 0. 环境与状态检查
    # ============================================================
    Write-Step "检查 git 仓库: $RepoPath"
    git rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Err "不是 git 仓库: $RepoPath"
        exit 1
    }

    $changes = git status --porcelain
    if (-not $changes) {
        Write-Err "工作区没有改动，无需 PR"
        exit 1
    }

    Write-Step "检测到以下改动:"
    $changes | ForEach-Object { Write-Host "   $_" }

    # ============================================================
    # 1. 自动校验（可用 -SkipChecks 跳过）
    # ============================================================
    if (-not $SkipChecks) {
        $changedFiles = git status --porcelain |
            ForEach-Object { $_.Substring(3) }

        $pyFiles = $changedFiles | Where-Object { $_ -like "*.py" }
        if ($pyFiles) {
            Write-Step "Python 语法校验 (py_compile)"
            $pyFiles | ForEach-Object {
                python -m py_compile $_
                if ($LASTEXITCODE -ne 0) { Write-Err "Python 校验失败: $_"; exit 1 }
            }
        }

        # 发现仓库内所有 .NET 工程，逐个构建
        $projFiles = Get-ChildItem -Recurse -Include *.csproj,*.sln -ErrorAction SilentlyContinue
        if ($projFiles) {
            Write-Step "dotnet build 校验"
            foreach ($f in $projFiles) {
                Write-Host "   building: $($f.FullName)"
                dotnet build $f.FullName --nologo -v q
                if ($LASTEXITCODE -ne 0) { Write-Err "dotnet build 失败: $($f.FullName)"; exit 1 }
            }
        }

        Write-Step "校验通过"
    }

    # ============================================================
    # 2. 从 origin/<Base> 创建新分支
    # ============================================================
    if (-not $Branch) { $Branch = "dev/" + (Get-Date -Format "yyyyMMdd-HHmmss") }

    # 优先从 origin/<Base> 拉取最新；origin 不可用（如纯本地仓库）时回退本地 <Base>
    $baseRef = "origin/$Base"
    Write-Step "从 $baseRef 创建分支: $Branch"
    git fetch origin 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Step "origin 不可用，改用本地分支 $Base"
        $baseRef = $Base
        git rev-parse --verify "$Base" 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Err "本地分支 $Base 不存在"
            exit 1
        }
    }

    $branchExists = git branch -a | Where-Object { $_ -like "*$Branch" }
    if ($branchExists) {
        Write-Err "分支已存在: $Branch"
        exit 1
    }

    # 工作区有未提交改动时，git switch 会因"改动会被覆盖"而拒绝。
    # 先 stash（含未跟踪文件）→ 切分支 → pop 恢复，再统一提交。
    $origBranch = git rev-parse --abbrev-ref HEAD
    $stashName = "pr-flow-" + [guid]::NewGuid().ToString("N")
    git stash push -u -m $stashName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Err "git stash 失败（无法暂存当前改动）"
        exit 1
    }

    git switch -c $Branch $baseRef 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        git switch $origBranch 2>$null | Out-Null
        git stash pop 2>$null | Out-Null
        Write-Err "创建分支失败（$baseRef 不存在？），已恢复原分支与改动"
        exit 1
    }

    git stash pop 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Err "stash pop 恢复改动冲突，请手动处理: git stash list / git stash pop"
        exit 1
    }

    # ============================================================
    # 3. 提交（UTF-8 消息，避免中文乱码）
    # ============================================================
    if (-not $CommitMessage) { $CommitMessage = "update: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
    if (-not $Title) { $Title = $CommitMessage }
    Write-Step "提交: $CommitMessage"

    git add -A
    $msgFile = Join-Path $env:TEMP ("prmsg-" + [guid]::NewGuid().ToString("N") + ".txt")
    Write-Utf8NoBom $msgFile ($CommitMessage + "`r`n")
    git commit -F $msgFile 2>$null | Out-Null
    Remove-Item $msgFile -Force -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) { Write-Err "git commit 失败"; exit 1 }

    # ============================================================
    # 4. 推送 + 创建 PR
    # ============================================================
    if (-not $SkipPush) {
        Write-Step "推送: origin $Branch"
        git push -u origin $Branch
        if ($LASTEXITCODE -ne 0) { Write-Err "git push 失败"; exit 1 }

        if (-not $SkipPr) {
            if (-not $Body) {
                $Body = @"
## 改动说明

- 提交信息: $CommitMessage
- 由 pr-flow.ps1 自动创建（代码审查与改进已完成）

## 校验

- [ ] Python py_compile
- [ ] dotnet build

## 验证

- [ ] 冒烟测试 / 本地运行
"@
            }
            Write-Step "创建 PR: $Title (base: $Base)"
            $bodyFile = Join-Path $env:TEMP ("prbody-" + [guid]::NewGuid().ToString("N") + ".md")
            Write-Utf8NoBom $bodyFile $Body
            $prUrl = gh pr create --base $Base --head $Branch --title $Title --body-file $bodyFile 2>&1
            Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue
            if ($LASTEXITCODE -ne 0) { Write-Err "gh pr create 失败: $prUrl"; exit 1 }
            Write-Host ""
            Write-Host "PR 已创建: $prUrl" -ForegroundColor Green
        }
    }

    Write-Host ""
    Write-Host "完成。分支: $Branch" -ForegroundColor Green
}
finally {
    Pop-Location
}
