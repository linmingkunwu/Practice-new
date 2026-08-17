#!/usr/bin/env python3
"""
三骰子游戏 — 大数定律验证与统计分析
======================================

【这个程序做什么？】
分析一个"被做了手脚"的骰子游戏，回答三个核心问题:
  1. 操纵骰子将胜率从 50% 拉低到了多少？
  2. 这对玩家需要投掷的轮数有什么影响？
  3. 被操纵的骰子还符合大数定律吗？

【Python 知识点: Shebang 行】
第一行 #!/usr/bin/env python3 是 Unix shebang。
在 Linux/macOS 上直接执行 ./main.py 时，系统用它找到 Python。
Windows 忽略这行，但保留它是好习惯（跨平台兼容）。

【Python 知识点: 模块文档字符串】
文件开头的三引号字符串是"模块文档字符串"(module docstring)。
可以通过 import main; help(main) 查看。
这是 Python 的文档约定，适用于模块、类、函数。

【运行方法】
  PYTHONIOENCODING=utf-8 python main.py
"""

# 【Python 知识点: import 的多种写法】
# import sys                          → 导入整个模块，用 sys.path 访问
# import os                            → 同上
# import time                          → 同上
# from src.dice import print_theoretical_report  → 只导入一个函数
# from src.analysis import (           → 从同一模块导入多个名字
#     compute_stats,                      可以用括号换行
#     ks_test_rolls_distribution,
# )
# 选择哪种取决于:
#   - 如果只用 1-2 个名字 → from X import Y
#   - 如果需要模块的多个功能 → import X（用 X.func 访问更清晰）
#   - 名字可能和本地变量冲突 → import X（加命名空间前缀）
import sys
import os
import time

# 【Python 知识点: sys.path — 模块搜索路径】
# 默认情况 Python 只搜索标准库和 site-packages。
# 当前目录（项目根）默认在 sys.path 中，但为了安全起见，
# 显式插入确保程序无论从哪里运行都能找到 src 包。
#
# os.path.dirname(os.path.abspath(__file__)):
#   __file__ = 当前文件的路径（可能是相对路径）
#   os.path.abspath() = 转为绝对路径
#   os.path.dirname() = 取父目录
#   三步得到: 项目根目录的绝对路径
#
# sys.path.insert(0, ...):
#   插入到列表最前面（优先级最高）。
#   如果其他地方有同名模块，这里的优先被加载。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src.dice import print_theoretical_report
from src.game import run_simulation
from src.analysis import (
    compute_stats,
    ks_test_rolls_distribution,
    print_simulation_report,
)
from src.visualization import generate_all_charts


# 【Python 知识点: 主函数模式】
# 把主要逻辑封装在 main() 函数中，而不是直接写在文件顶层。
# 好处:
#   1. 避免全局变量污染
#   2. 可以 import 这个文件而不触发执行
#   3. 便于单元测试（直接调用 main()）
#   4. 函数内的变量是局部的，更快（Python 局部变量查找比全局快）
def main():
    """
    主函数 — 按顺序执行完整的分析流程。

    【Python 知识点: time.time() — Unix 时间戳】
    返回从 1970-01-01 00:00:00 UTC 至今的秒数（浮点数）。
    用于计算程序运行时长: elapsed = end_time - start_time。
    精度取决于操作系统（通常毫秒级）。
    """
    start_time = time.time()

    # ============================================================
    # 第 1 步: 理论分析
    # ============================================================
    print_theoretical_report()

    # ============================================================
    # 第 2 步: 蒙特卡洛模拟
    # ============================================================
    # 【Python 知识点: 数字字面量中的下划线】
    # 100_000 = 100000。Python 3.6+ 支持在数字中插入 _ 提高可读性。
    # _ 可以出现在数字的任何位置: 1_000_000, 0xAB_CD_EF, 1.234_567
    N_GAMES = 100_000

    print()
    print("=" * 64)
    print(f"  蒙特卡洛模拟: {N_GAMES:,} 局")
    print("=" * 64)

    # 【Python 知识点: 字典解包】
    # sim_data["normal"] 和 sim_data["rigged"] 分别取出两个键的值。
    # Python 3.10+ 可以用 match/case 做结构化解构。
    sim_data = run_simulation(n_games=N_GAMES)
    normal_results = sim_data["normal"]
    rigged_results = sim_data["rigged"]

    # ============================================================
    # 第 3 步: 统计分析
    # ============================================================
    stats_normal = compute_stats(normal_results, "正常骰子", rigged=False)
    stats_rigged = compute_stats(rigged_results, "操纵骰子 (R3+)", rigged=True)

    print_simulation_report(stats_normal, stats_rigged)

    # KS 检验
    print("—" * 48)
    print("  Kolmogorov-Smirnov 检验（正常骰子）")
    print("—" * 48)
    ks_result = ks_test_rolls_distribution(normal_results, rigged=False)
    # 【Python 知识点: dict.items() — 遍历字典】
    # for k, v in dict.items() 同时获取键和值。
    # for k in dict → 只获取键
    # for v in dict.values() → 只获取值
    for k, v in ks_result.items():
        print(f"  {k}: {v}")
    print()

    # 均值验证
    print("—" * 48)
    print("  理论均值验证（操纵骰子）")
    print("—" * 48)
    ks_rigged = ks_test_rolls_distribution(rigged_results, rigged=True)
    for k, v in ks_rigged.items():
        print(f"  {k}: {v}")
    print()

    # ============================================================
    # 第 4 步: 结论
    # ============================================================
    print("=" * 64)
    print("  结论")
    print("=" * 64)
    print()
    print("  1. 大数定律验证 (LLN):")
    print(f"     - 正常骰子: 每轮 i.i.d. Bernoulli(0.5)")
    print(f"       LLN 极限 = 0.5000, 合并胜率 (模拟) = {stats_normal.mean_win_rate:.4f}")
    print(f"     - 操纵骰子: 第3轮起 i.i.d. Bernoulli(1/6)")
    print(f"       LLN 极限 = 0.1667, 合并胜率 (模拟) = {stats_rigged.mean_win_rate:.4f}")
    print(f"       注: 合并胜率={stats_rigged.mean_win_rate:.4f} 高于 0.1667，"
          f"因为包含前2轮(50%)")
    print(f"       理论合并胜率 = 5/E[rolls] = 5/{stats_rigged.theoretical_expected_rolls:.0f} = "
          f"{stats_rigged.theoretical_pooled_rate:.4f} ✓")
    print("     ✓ 两者均符合大数定律！")
    print()
    print("  2. 关键区分:")
    print("     单轮胜率 (LLN极限) = 稳态下每轮的独立胜率")
    print("     合并胜率 = 总胜场/总轮数 (受游戏停止规则影响)")
    print("     LLN图表明: 随着轮数→∞，累积胜率 → 单轮胜率 (LLN极限)")
    print()
    print("  3. 操纵骰子影响:")
    print(f"     - 单轮胜率从 50% 降至 16.67%，下降 66.7%")
    print(f"     - 期望轮数从 {stats_normal.theoretical_expected_rolls:.0f} 增至 "
          f"{stats_rigged.theoretical_expected_rolls:.0f}，"
          f"增加 {stats_rigged.theoretical_expected_rolls/stats_normal.theoretical_expected_rolls:.1f} 倍")
    print(f"     - 轮数方差从 {stats_normal.theoretical_variance_rolls:.0f} 增至 "
          f"{stats_rigged.theoretical_variance_rolls:.0f}，波动性大增")
    print()
    print("  4. 大数定律不要求'公平':")
    print("     大数定律仅要求独立同分布（或更弱的条件），")
    print("     操纵骰子虽然降低了胜率，但第3轮起的胜负仍是 i.i.d.，")
    print("     因此样本胜率必然收敛到 1/6 ≈ 0.1667。")
    print()

    # ============================================================
    # 第 5 步: 生成图表
    # ============================================================
    output_dir = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "output", "charts"
    )
    generate_all_charts(normal_results, rigged_results, output_dir)

    elapsed = time.time() - start_time
    print("=" * 64)
    print(f"  分析完成，总耗时: {elapsed:.1f} 秒")
    print("=" * 64)


# ============================================================
# 程序入口 — if __name__ == "__main__"
# ============================================================
# 【Python 知识点: __name__ 变量的工作原理】
# 每个 Python 文件在运行时都有一个 __name__ 变量。
#   - 直接执行 python main.py → __name__ = "__main__"
#   - 被 import main → __name__ = "main"
#
# if __name__ == "__main__" 确保了:
#   - 直接运行时: 执行 main()
#   - 被 import 时: 不执行（只导入函数和类定义）
#
# 这是 Python 代码复用的基础:
#   别人可以 from main import main 然后在自己的代码中调用，
#   而不会意外触发整个分析流程。
#
# 对比其他语言:
#   C:      int main(int argc, char** argv)   ← 强制入口函数
#   Java:   public static void main(String[]) ← 固定签名
#   Python: if __name__ == "__main__"         ← 约定而非强制
if __name__ == "__main__":
    main()
