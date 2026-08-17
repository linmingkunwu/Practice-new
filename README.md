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
├── learning-python/          # 📚 Python 学习笔记与练习
│   ├── AI相关/              # AI 相关小练习
│   ├── 基础语法/            # 基础语法示例
│   ├── 高级语法/            # 高级语法示例
│   └── 练习作业/            # 练习作业
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

## 许可证

私有仓库，保留所有权利。
