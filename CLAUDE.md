# CLAUDE.md

本文件是 Claude Code 在此仓库中工作时应遵循的规则与约定。

## 仓库概览

个人学习与实验项目集合，包含三个子项目：

- `dice-game/` — 三骰子游戏（Python），用蒙特卡洛模拟验证大数定律并做统计分析
- `WorkerService1/` — .NET 10 Worker Service 后台服务模板
- `learning-python/` — Python 学习笔记，按主题分类（基础语法 / 高级语法 / AI相关 / 练习作业）

## 技术栈

- **Python 3.10+**：`dice-game` 依赖 `numpy` / `scipy` / `matplotlib`
- **.NET 10.0**：`WorkerService1` 依赖 `Microsoft.Extensions.Hosting`

## 常用命令

### Dice Game（Python）

```bash
cd dice-game
pip install -r requirements.txt
PYTHONIOENCODING=utf-8 python main.py
```

### Worker Service（.NET）

```bash
cd WorkerService1
dotnet run
```

## 编码规范

- 注释与文档使用中文；学习类代码用 `【知识点】` 标题块解释语法点
- Python 遵循 PEP 8，模块/类/函数写 docstring
- 入口脚本需兼容从任意目录运行（参照 `dice-game/main.py` 中 `sys.path` 的写法）
- 向 Windows 控制台输出中文时，用 `PYTHONIOENCODING=utf-8` 指定编码，避免乱码

## 目录约定

- Python 业务逻辑放 `src/` 包内，`main.py` 仅做入口编排，不堆业务
- 新增 Python 学习笔记按主题归入 `learning-python/<主题>/`
- 每个子项目维护自己的 `requirements.txt` / `.csproj`，不混用
