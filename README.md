# 个人代码仓库

个人学习与实验项目集合。

## 项目结构

```text
├── dice-game/               # 🎲 三骰子游戏 — 大数定律验证与统计分析
│   ├── main.py              # 入口程序
│   ├── requirements.txt     # Python 依赖
│   └── src/                 # 分析模块
│       ├── dice.py          # 理论概率计算
│       ├── game.py          # 蒙特卡洛模拟
│       ├── analysis.py      # 统计分析
│       └── visualization.py # Matplotlib 图表生成
├── WorkerService1/           # ⚙️ .NET Worker Service（后台服务模板）
│   ├── Program.cs
│   ├── Worker.cs
│   └── WorkerService1.csproj
├── .gitattributes            # Git 行尾规范化
├── .gitignore                # Git 忽略规则（VS + Python + OS）
└── README.md
```

## 环境要求

### Dice Game（Python）

- Python 3.10+
- 安装依赖：`pip install -r dice-game/requirements.txt`
- 运行：`cd dice-game && python main.py`

### Worker Service（.NET）

- .NET 10.0 SDK
- 运行：`cd WorkerService1 && dotnet run`

## 开发流程工具

`scripts/pr-flow.ps1` 一键完成日常 PR 流程：**校验 → 建分支 → 提交 → 推送 → 创建 Pull Request**。

```powershell
# 方式 1：直接调用脚本（在仓库目录下）
.\scripts\pr-flow.ps1 -Title "feat: 新增功能" -CommitMessage "feat: 新增功能"

# 方式 2：全局别名 prflow（已写入 PowerShell profile，开新终端即可用）
prflow -Title "feat: 新增功能" -CommitMessage "feat: 新增功能"

# 常用参数
#   -Branch <名字>      指定分支名（默认 dev/<时间戳>）
#   -Base <分支>        目标分支（默认 main）
#   -SkipChecks         跳过 py_compile / dotnet build 自动校验
#   -SkipPush           只做本地提交
```

自动校验逻辑：改动的 `.py` 文件逐个 `py_compile`；仓库内发现 `.csproj`/`.sln` 则逐个 `dotnet build`。新项目可直接从模板仓库 **linmingkunwu/project-template** 创建，自带本脚本与 GitHub Actions CI（PR 自动跑 Python/.NET 检查）。

## 许可证

私有仓库，保留所有权利。
