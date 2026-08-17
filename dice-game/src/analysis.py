"""
统计分析 — 对蒙特卡洛模拟结果进行统计推断
============================================

【这个文件是做什么的？】
把 game.py 生成的海量模拟数据转化为有意义的统计结论。

【涉及的核心 Python 库】
• NumPy: 高性能数组运算，所有统计计算的基础
• SciPy: 科学计算，提供概率分布和统计检验

【NumPy 和 Python 列表的核心区别】
  Python list: [1, 2, 3]  → 通用容器，元素可以是任意类型
  NumPy array: np.array([1,2,3])  → 同类型数组，支持向量化运算

  向量化运算示例:
    Python: [x*2 for x in data]       → 循环，慢
    NumPy:  data * 2                   → 全数组同时运算，快

  NumPy 为什么快？
  1. 底层用 C 实现，绕过 Python 的解释器
  2. 连续内存布局，CPU 缓存友好
  3. SIMD 指令优化（一条指令处理多个数据）

【涉及的核心统计概念】
• 描述统计、置信区间、Delta 方法
• Wilson 得分区间、KS 检验
• 大数定律的数值验证
"""

# 【Python 知识点: import ... as ...】
# import numpy as np 为模块起别名。
# 这是一种约定俗成的缩写: numpy→np, pandas→pd, matplotlib.pyplot→plt
# 使用别名让代码更紧凑，也是社区惯例。
import numpy as np
from typing import List, Dict, Tuple
from dataclasses import dataclass
from scipy import stats as sp_stats

# 【Python 知识点: 相对导入 (Relative Import)】
# from .game import GameResult
# 点号(.)表示"当前包"（即 src/ 目录）。
# .game  = 同目录下的 game.py
# ..utils = 上级目录的 utils.py
# 相对导入只能用在包内部（有 __init__.py 的目录）。
# 好处: 包改名或移动时不需要修改内部导入。
from .game import GameResult
from .dice import (
    normal_win_probability,
    rigged_win_probability,
    expected_rolls_normal,
    expected_rolls_and_variance_rigged,
)


# ============================================================
# 数据结构
# ============================================================

@dataclass
class SimulationStats:
    """模拟统计摘要。"""
    n_games: int
    label: str
    mean_rolls: float
    std_rolls: float
    median_rolls: float
    min_rolls: int
    max_rolls: int
    mean_win_rate: float
    std_win_rate: float
    theoretical_win_prob: float
    theoretical_pooled_rate: float
    theoretical_expected_rolls: float
    theoretical_variance_rolls: float
    ci_95_rolls: Tuple[float, float]
    ci_95_win_rate: Tuple[float, float]


# ============================================================
# 描述性统计 — NumPy 数组操作
# ============================================================

def compute_stats(results: List[GameResult], label: str, rigged: bool) -> SimulationStats:
    """
    从海量模拟结果中提炼关键统计指标。

    【Python 知识点: 列表推导式 → NumPy 数组】
    np.array([g.total_rolls for g in results])
    1. 列表推导式提取每局的 total_rolls 属性 → Python 列表
    2. np.array() 将 Python 列表转为 NumPy 数组
    这一步后就可以使用 NumPy 的所有统计函数。

    【Python 知识点: NumPy 的统计函数】
    np.mean(arr): 算术平均 Σx/n
    np.std(arr, ddof=1): 样本标准差
      ddof=1 (Delta Degrees of Freedom) 是"贝塞尔校正"。
      样本方差公式除以 n-1 而非 n，因为样本均值比总体均值
      更接近数据，直接除以 n 会低估方差。
      通俗理解: 少一个自由度所以除以 n-1。
    np.median(arr): 中位数，排序后正中间的值
      不会像均值那样受极端值影响。
      如果数据是 [5,6,7,100]，均值=29.5，中位数=6.5

    【Python 知识点: 生成器表达式 vs 列表推导式】
    sum(g.total_wins for g in results)    ← 生成器，更省内存
    sum([g.total_wins for g in results])  ← 先创建列表，再多此一举
    对于 100K 个元素，性能差异不大，但生成器是正确的惯用法。
    """
    if not results:
        raise ValueError("results must not be empty")

    # 提取所有游戏的轮数，转为 NumPy 数组
    rolls = np.array([g.total_rolls for g in results])
    n = len(results)

    mean_rolls = float(np.mean(rolls))
    std_rolls = float(np.std(rolls, ddof=1))
    median_rolls = float(np.median(rolls))

    # 合并胜率
    total_wins_all = sum(g.total_wins for g in results)
    total_rounds_all = sum(g.total_rolls for g in results)
    pooled_win_rate = total_wins_all / total_rounds_all

    # Delta 方法计算合并胜率的标准误
    # 【Python 知识点: 短路求值 or】
    # results[0].n_wins_target if results else 5
    # 这个条件表达式先检查 results 是否非空。
    # 如果 results 是空列表，不会尝试 results[0]（会 IndexError）。
    # 也可以用: (results or [None])[0] 但这不够清晰。
    n_wins_target = results[0].n_wins_target
    se_pooled_rate = (n_wins_target / mean_rolls**2) * (std_rolls / np.sqrt(n))

    mean_win_rate = pooled_win_rate
    std_win_rate = float(np.std([g.win_rate for g in results], ddof=1))

    # 理论值
    if rigged:
        theo_p = rigged_win_probability()
        # 【Python 知识点: 元组解包】
        # expected_rolls_and_variance_rigged 返回 (期望, 方差)
        theo_e, theo_var = expected_rolls_and_variance_rigged(5)
        theo_pooled_rate = 5.0 / theo_e
    else:
        theo_p = normal_win_probability()
        theo_e = expected_rolls_normal(5)
        # 负二项分布方差公式: Var = r·(1-p)/p² = 5×0.5/0.25 = 10
        theo_var = n_wins_target * (1 - theo_p) / (theo_p ** 2)
        theo_pooled_rate = theo_p

    # 置信区间
    se_rolls = std_rolls / np.sqrt(n)
    ci_rolls = (mean_rolls - 1.96 * se_rolls, mean_rolls + 1.96 * se_rolls)

    ci_wr = (mean_win_rate - 1.96 * se_pooled_rate,
             mean_win_rate + 1.96 * se_pooled_rate)

    return SimulationStats(
        n_games=n,
        label=label,
        mean_rolls=mean_rolls,
        std_rolls=std_rolls,
        median_rolls=median_rolls,
        # 【Python 知识点: NumPy → Python 标量】
        # np.min(rolls) 返回 numpy.int64，不是 Python int。
        # int() 做显式转换，避免类型不一致的问题。
        # 对于打印和序列化，Python 原生类型更友好。
        min_rolls=int(np.min(rolls)),
        max_rolls=int(np.max(rolls)),
        mean_win_rate=mean_win_rate,
        std_win_rate=std_win_rate,
        theoretical_win_prob=theo_p,
        theoretical_pooled_rate=theo_pooled_rate,
        theoretical_expected_rolls=theo_e,
        theoretical_variance_rolls=theo_var,
        ci_95_rolls=ci_rolls,
        ci_95_win_rate=ci_wr,
    )


# ============================================================
# 大数定律 (LLN) 验证 — NumPy 累积运算
# ============================================================

def compute_convergence_curves(
    results: List[GameResult],
    max_rounds: int = 500,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """
    计算累积胜率的收敛曲线。

    【Python 知识点: Python 3.9+ 的内置 tuple 类型注解】
    tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]
    表示返回一个包含 4 个 NumPy 数组的元组。
    Python 3.8 及更早需要用 typing.Tuple[ndarray, ndarray, ndarray, ndarray]。
    两种写法等价，小写版本更简洁。

    【返回值的采样对齐】
    返回的 4 个数组都只在对数采样点 idx 处取值（长度 ≤ 500），
    曲线和置信带因此天然对齐，可直接绘制。
    之前的实现返回全量数组，绘图时再做步进降采样，
    会导致置信带与采样点错位（大部分填充点被跳过，带宽范围失真）。

    【Python 知识点: NumPy 的累积运算和向量化】
    这是本文件中 NumPy 使用最密集的函数。

    np.cumsum(arr):
      累积求和。输入 [1, 2, 3, 4] → 输出 [1, 3, 6, 10]
      比 Python 循环快 100+ 倍（底层 C 实现）。

    NumPy 数组的向量化除法:
      cum_wins / rounds → 两个等长数组逐元素相除
      等价于 [w/r for w, r in zip(cum_wins, rounds)]
      但 NumPy 版本在 C 层完成，速度差异巨大。

    np.full(shape, value):
      创建指定形状的数组，所有元素初始化为给定值。
      np.full(100, np.nan) → [nan, nan, ..., nan] (100个)
      比 [np.nan] * 100 更灵活（支持多维）。

    np.logspace(start, stop, num):
      在对数尺度上均匀分布的 num 个点。
      np.logspace(0, 3, 4) → [1, 10, 100, 1000]
      用于 CI 计算时前面密集（变化快），后面稀疏（变化慢）。

    np.unique(arr):
      返回数组中的唯一值并排序。用于去除重复索引。

    np.arange(start, stop):
      类似 range() 但返回 NumPy 数组。
      np.arange(5) → array([0, 1, 2, 3, 4])
    """
    # 将所有游戏的所有轮次串联为一个超长序列
    all_wins = []
    for game in results:
        for rr in game.rounds[:max_rounds]:
            all_wins.append(1 if rr.won else 0)

    total_rounds = len(all_wins)
    if total_rounds == 0:
        return (np.array([]), np.array([]), np.array([]), np.array([]))

    # 【Python 知识点: NumPy 数组的生成和运算】
    # np.arange(1, n+1) → 创建 [1, 2, 3, ..., n] 的数组
    rounds = np.arange(1, total_rounds + 1)

    # np.cumsum 是累积求和，返回与原数组等长的数组
    cum_wins = np.cumsum(all_wins)

    # 两个 NumPy 数组相除: 逐元素除法（向量化运算）
    cum_rates = cum_wins / rounds

    # Wilson 得分置信区间
    # 用对数间隔采样，计算量从 2.6M 降到 ~500 个点
    n_sample_pts = min(500, total_rounds)
    if total_rounds > n_sample_pts:
        # 用对数间隔采样，计算量从 2.6M 降到 ~500 个点。
        # 开头补上索引 0，确保曲线从第 1 轮开始绘制。
        idx = np.unique(
            np.append(
                0,
                np.logspace(0, np.log10(total_rounds - 1), n_sample_pts).astype(int),
            )
        )
    else:
        idx = np.arange(total_rounds)

    z = 1.96  # 95% 置信水平的 z 值

    # 【Python 知识点: np.nan — "Not a Number"】
    # NaN 是一个特殊的浮点值，表示"缺失"或"未定义"。
    # 在 matplotlib 中，NaN 值会被自动跳过（线会断开）。
    # np.nanmean, np.nanstd 等函数会忽略 NaN 值。
    # 这里初始化为 NaN，只填充采样点的 CI 值。
    ci_lower = np.full(total_rounds, np.nan)
    ci_upper = np.full(total_rounds, np.nan)

    for i in idx:
        n = i + 1
        # 【Python 知识点: NumPy 类型转换】
        # cum_wins 的元素是 numpy.float64，int() 转为 Python int
        w = int(cum_wins[i])
        p_hat = w / n
        denom = 1 + z**2 / n
        center = (p_hat + z**2 / (2 * n)) / denom
        margin = z * np.sqrt(
            (p_hat * (1 - p_hat) + z**2 / (4 * n)) / n
        ) / denom
        ci_lower[i] = max(0, center - margin)
        ci_upper[i] = min(1, center + margin)

    # 返回与采样点对齐的数组：曲线与置信带都只在 idx 处取值，
    # 直接用于绘图，避免 NaN 与降采样错位。
    return rounds[idx], cum_rates[idx], ci_lower[idx], ci_upper[idx]


# ============================================================
# 逐轮分析
# ============================================================

def compute_rolls_distribution(
    results: List[GameResult],
) -> Tuple[np.ndarray, np.ndarray]:
    """
    达到 n_wins 胜所需轮数的经验分布。

    【Python 知识点: np.unique 的 return_counts 参数】
    np.unique(values, return_counts=True)
    返回 (唯一值数组, 出现次数数组)。
    例如 [5,5,5,6,6,7] → ([5,6,7], [3,2,1])
    非常方便的"分组计数"功能。
    """
    rolls = np.array([g.total_rolls for g in results])
    unique, counts = np.unique(rolls, return_counts=True)
    pmf = counts / counts.sum()
    return unique, pmf


def compute_round_by_round_win_rate(results: List[GameResult]) -> Dict[int, float]:
    """
    计算每一轮的独立胜率，展示操纵骰子从第 3 轮起的胜率骤降。

    【Python 知识点: dict.get(key, default) 的安全取值】
    round_totals.get(rn, 0)
    从字典中取 rn 对应的值；如果 rn 不存在，返回 0（不抛 KeyError）。
    等价于:
      try: v = d[rn]
      except KeyError: v = 0
    但更简洁。常用于累加计数模式。

    【Python 知识点: 字典推导式 with sorted keys】
    {rn: rate for rn in sorted(round_totals.keys())}
    字典推导式本身不保证顺序（Python 3.6-），
    但 sorted() 返回排序后的键列表，确保输出有序。
    Python 3.7+ 字典保证按插入顺序，但显式排序仍然更安全。
    """
    if not results:
        return {}

    round_wins: Dict[int, int] = {}
    round_totals: Dict[int, int] = {}

    for game in results:
        for rr in game.rounds:
            rn = rr.round_number
            round_totals[rn] = round_totals.get(rn, 0) + 1
            if rr.won:
                round_wins[rn] = round_wins.get(rn, 0) + 1

    return {
        rn: round_wins.get(rn, 0) / round_totals.get(rn, 1)
        for rn in sorted(round_totals.keys())
    }


# ============================================================
# 统计检验 — SciPy 的妙用
# ============================================================

def ks_test_rolls_distribution(
    results: List[GameResult],
    rigged: bool = False,
) -> Dict:
    """
    验证模拟结果的分布是否与理论一致。

    【Python 知识点: SciPy 的统计检验 API】
    scipy.stats 提供了几乎所有经典统计检验的实现:

    kstest(data, cdf):
      双样本 KS 检验。比较经验分布和理论 CDF。
      参数 cdf 可以是:
        - 一个可调用对象（函数/lambda）
        - 一个分布名（如 'norm', 'expon'）
      返回 KstestResult 对象，包含 statistic 和 pvalue。

    【Python 知识点: lambda 匿名函数】
    lambda x: sp_stats.nbinom.cdf(x, r, p)
    lambda 创建一个没有名字的函数:
      - x 是参数
      - : 后面是返回值表达式
    lambda 只能包含一个表达式（不能有语句、循环等）。
    适合简单的"包装"场景，如这里的参数绑定。

    等价于:
      def theo_cdf(x):
          return sp_stats.nbinom.cdf(x, r, p)
      kstest(failures, theo_cdf)

    【注意: lambda 不是必须的！】
    对于复杂逻辑，用 def 定义命名函数更好（可读性、可调试性）。
    lambda 只适合"一句话能说清"的简单转换。
    """
    rolls = np.array([g.total_rolls for g in results])

    if rigged:
        theo_e = expected_rolls_and_variance_rigged(5)[0]
        diff_pct = abs(float(np.mean(rolls)) - theo_e) / theo_e * 100
        return {
            "test": "Mean deviation check (rigged distribution is non-standard)",
            "observed_mean": float(np.mean(rolls)),
            "theoretical_mean": theo_e,
            "deviation_pct": f"{diff_pct:.3f}%",
            "note": "操纵模式的轮数分布不是标准负二项，使用均值偏差验证",
        }
    else:
        r, p = 5, 0.5

        # 【Python 知识点: NumPy 数组的广播 (Broadcasting)】
        # rolls - r 中，r 是标量，rolls 是数组。
        # NumPy 自动将 r "广播"到和 rolls 一样的形状，
        # 然后逐元素相减。这是 NumPy 最强大的特性之一。
        failures = rolls - r

        # 【Python 知识点: SciPy 的 kstest + lambda 组合】
        # lambda x: sp_stats.nbinom.cdf(x, r, p) 包装了参数 r 和 p
        ks_result = sp_stats.kstest(
            failures,
            lambda x: sp_stats.nbinom.cdf(x, r, p),
        )

        # 【Python 知识点: 科学计算结果的属性访问】
        # scipy 的许多函数返回特殊的 result 对象。
        # 可以通过 .statistic 和 .pvalue 属性访问结果。
        # Python 标准是: 元组用于简单返回值，命名元组/dataclass 用于复杂结果。
        ks_stat = float(ks_result.statistic)
        p_value = float(ks_result.pvalue)

        # 【Python 知识点: float() 转换】
        # ks_result.statistic 可能是 numpy.float64。
        # 转为 Python float 确保在 print 和 JSON 序列化时
        # 行为一致（numpy 标量和 Python 标量有细微差异）。
        diff_pct = abs(float(np.mean(rolls)) - 10.0) / 10.0 * 100

        return {
            "test": "Kolmogorov-Smirnov (failures ~ NB(r=5, p=0.5))",
            "statistic": ks_stat,
            "p_value": p_value,
            "significant_at_5pct": p_value < 0.05,
            "mean_deviation_pct": f"{diff_pct:.4f}%",
            "note": (
                f"n=100K 时 KS 检验力极高，微小偏差也可检出；"
                f"均值偏差仅 {diff_pct:.3f}%，模拟与理论高度吻合"
            ),
        }


def print_simulation_report(
    stats_normal: SimulationStats,
    stats_rigged: SimulationStats,
) -> None:
    """打印模拟统计报告的格式化输出。"""
    print()
    print("=" * 64)
    print("  蒙特卡洛模拟 — 统计分析报告")
    print("=" * 64)
    print(f"  模拟局数: {stats_normal.n_games:,}")
    print()

    for s in [stats_normal, stats_rigged]:
        print("—" * 48)
        print(f"  {s.label}")
        print("—" * 48)
        print(f"  期望轮数 (理论):    {s.theoretical_expected_rolls:.2f}")
        print(f"  期望轮数 (模拟):    {s.mean_rolls:.2f}")
        print(f"  95% CI 轮数:       ({s.ci_95_rolls[0]:.2f}, {s.ci_95_rolls[1]:.2f})")
        print(f"  标准差 (轮数):      {s.std_rolls:.2f}")
        print(f"  中位数 (轮数):      {s.median_rolls:.1f}")
        print(f"  范围 (轮数):        [{s.min_rolls}, {s.max_rolls}]")
        print()
        print(f"  单轮胜率 (LLN极限): {s.theoretical_win_prob:.4f}")
        print(f"  合并胜率 (理论):     {s.theoretical_pooled_rate:.4f}")
        print(f"  合并胜率 (模拟):     {s.mean_win_rate:.4f}")
        print(f"  95% CI 胜率:       ({s.ci_95_win_rate[0]:.4f}, {s.ci_95_win_rate[1]:.4f})")
        print(f"  标准差 (胜率):      {s.std_win_rate:.4f}")
        print()

    ratio = stats_rigged.mean_rolls / stats_normal.mean_rolls
    print("—" * 48)
    print("  正常 vs 操纵 对比")
    print("—" * 48)
    print(f"  期望轮数比 (操纵/正常): {ratio:.2f}x")
    print(f"  胜率比     (操纵/正常): {stats_rigged.mean_win_rate/stats_normal.mean_win_rate:.2f}x")
    print()
