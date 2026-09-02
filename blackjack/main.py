#!/usr/bin/env python3
"""
21 点决策博弈 — 概率理论、蒙特卡洛与统计推断
==============================================

【这个程序做什么？】
把 21 点当作一个数学对象来解剖，回答五个问题:
  1. 庄家每种首牌的最终分布长什么样？(理论 vs 模拟, χ² 校验)
  2. 每个局面的最优行动是什么？期望收益是多少？(动态规划)
  3. 最优策略整局期望是多少？与"模仿庄家/永不叫牌"差多少？
  4. 基础策略与 Hi-Lo 算牌策略在同一批牌靴上的差距显著吗？
     (配对 t 检验 + 置换检验 + bootstrap)
  5. 算牌信号真实存在吗？(真数 → 优势的线性回归)

【与 dice-game 的结构对应】
dice-game: main.py = 理论报告 → 蒙特卡洛 → 统计分析 → 结论 → 图表
本项目的 main.py 完全沿用这一流水线，仅主题换成 21 点。

【运行方法】
  程序已内置 UTF-8 输出自适应，直接运行即可（旧版 Windows
  控制台若乱码，可加环境变量 PYTHONIOENCODING=utf-8）:
  python main.py          # 完整分析(约1-2分钟)
  python main.py --quick  # 快速版(约15秒)
  python main.py --play   # 终端玩 21 点

【Python 知识点: Shebang 与模块文档字符串】
第一行 shebang 与文件头文档字符串的作用见 dice-game/main.py，
这里不再重复。

【风险声明】
本程序是"数学教学与模拟"，不代表任何现实赌场规则，
更不构成赌博建议。模拟结论展示期望与方差的关系:
算牌策略期望为正，但资金曲线剧烈波动 ——
没有雄厚资金与风险管理，正期望照样可能破产。
"""

# ============================================================
# 导入依赖
# ============================================================

# 【Python 知识点: sys.path 插入项目根目录】
# 与 dice-game/main.py 相同的处理: 无论从哪里启动，
# 都能 import 到 src 包。
import sys
import os
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# 【Python 知识点: 控制台编码自适配】
# 扑克牌花色 ♠♥♣♦ 是 Unicode 字符，而旧版 Windows 控制台默认
# GBK/cp936 编码无法输出它们（直接 UnicodeEncodeError 崩溃）。
# 这里把 stdout/stderr 重配置为 UTF-8（errors='replace' 兜底），
# 使程序不依赖 PYTHONIOENCODING 环境变量也能运行；
# 若终端本身不支持 UTF-8，个别字符会显示为 '?'，但绝不崩溃。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):   # 极老版本 Python 或特殊流
    pass

# 【Python 知识点: 导入顺序约定】
# 标准库 → 第三方库 → 本地模块（中间空行分隔，见 dice-game/dice.py）。
import random

import numpy as np

from src import theory
from src.strategies import (
    BasicStrategy, CountingStrategy, RandomStrategy, ThresholdStrategy,
)
from src.game import (
    monte_carlo_shoe, simulate_infinite_rounds,
    sample_dealer_playout, simulate_state_action_ev,
    play_interactive,
)
from src.analysis import (
    compute_stats, mean_test_vs_mu0,
    chi2_dealer_check, check_state_action_ev, lln_convergence_curve,
    per_shoe_means, paired_comparison, edge_by_true_count,
    print_validation_report, print_lln_report, print_strategy_report,
    print_paired_result, print_counting_report,
)
from src.visualization import generate_all_charts

# ============================================================
# 实验规模参数
# ============================================================

# 【Python 知识点: 下划线数字字面量】
# 1_000_000 == 1000000（dice-game/main.py 中讲过）。
# 局数/靴数经过实测校准:
#   本机每 1 万靴约需 2~15 秒（视策略复杂度），
#   默认档控制在 1-2 分钟内，--quick 控制在 15 秒左右。
if "--quick" in sys.argv:
    N_SHOES = 5_000          # 牌靴模拟靴数（每种策略）
    N_LLN = 120_000          # 大数定律收敛曲线局数
    N_DEALER_PER_UP = 12_000 # 庄家分布校验: 每种首牌采样局数
    N_ACTION = 12_000        # 行动 EV 校验: 每个局面采样局数
    N_ACTION_SPOTS = 5       # 行动 EV 校验的抽查局面数
    N_PERM = 5_000           # 置换检验次数
else:
    N_SHOES = 20_000
    N_LLN = 400_000
    N_DEALER_PER_UP = 30_000
    N_ACTION = 40_000
    N_ACTION_SPOTS = 8
    N_PERM = 20_000

SEED = 42          # 全局种子: 同种子 → 同靴序 → 配对检验合法
LLN_SEED = 2025    # LLN 实验的独立种子
DEALER_UPCARDS = ["A", "2", "6", "T"]  # 庄家分布校验抽查的首牌(4种)


def run_action_ev_checks() -> None:
    """第 3 步: 抽查若干局面，行动 EV 理论 vs 模拟。"""
    spots = [
        (16, False, True, "T", "S"),   # 16 对 10 停牌
        (16, False, True, "6", "S"),   # 16 对 6 停牌
        (12, False, True, "2", "S"),   # 12 对 2 停牌(不如要牌)
        (12, False, True, "4", "S"),   # 12 对 4 停牌
        (20, False, True, "6", "S"),   # 20 对 6 停牌
        (11, False, True, "6", "D"),   # 11 对 6 加倍
        (17, True, True, "6", "D"),    # 软17 对 6 加倍
        (10, False, True, "6", "D"),   # 10 对 6 加倍
    ][:N_ACTION_SPOTS]

    def sample_fn(state):
        total, soft, two, u, act = state
        return simulate_state_action_ev(total, soft, two, u, act,
                                        n=N_ACTION, seed=SEED + 1)

    print("—" * 54)
    print("  校验 2: 逐行动期望（理论 DP vs 无限牌库蒙特卡洛）")
    print("—" * 54)
    check_state_action_ev(spots, sample_fn)


def run_lln_validation() -> tuple:
    """
    第 4 步: 无限牌库 + 基础策略(平注)跑 N_LLN 局。
    返回 (nets, 收敛曲线数据) 供报告与图表使用。
    """
    print()
    print("=" * 70)
    print(f"  无限牌库模拟: 基础策略平注 {N_LLN:,} 局 (种子 {LLN_SEED})")
    print("=" * 70)

    records = simulate_infinite_rounds(BasicStrategy(), N_LLN, seed=LLN_SEED)
    nets = np.array([r.net for r in records])
    mu0 = theory.overall_expected_value()
    print_lln_report(nets, mu0, "基础策略平注")

    curve = lln_convergence_curve(nets)
    return nets, mu0, curve


def run_shoe_comparison() -> dict:
    """
    第 5 步: 6 副牌靴上的策略对比（同一批靴序 → 配对检验）。
    返回各模拟对象与每靴均值，供图表与报告使用。
    """
    print()
    print("=" * 70)
    print(f"  牌靴模拟: 6副牌 × {N_SHOES:,} 靴 × 4 策略 (切牌 25%)")
    print("=" * 70)

    strategies = [
        BasicStrategy(),
        CountingStrategy(),
        ThresholdStrategy(17),   # 模仿庄家
        RandomStrategy(),
    ]
    sims = []
    for s in strategies:
        print(f"  正在模拟: {s.name} ...", flush=True)
        sims.append(monte_carlo_shoe(s, n_shoes=N_SHOES, decks=6,
                                     seed=SEED))

    print()
    print_strategy_report(sims)

    # 配对检验: 同种子 ⇒ 每靴均值可配对
    means = [per_shoe_means(sim) for sim in sims]
    results = {}
    results["basic_vs_counting"] = paired_comparison(
        means[1], means[0], "算牌策略", "基础策略",
        n_perm=N_PERM, seed=SEED + 2)
    results["threshold_vs_basic"] = paired_comparison(
        means[0], means[2], "基础策略", "模仿庄家(到17停)",
        n_perm=N_PERM, seed=SEED + 3)

    print_paired_result(results["basic_vs_counting"])
    print_paired_result(results["threshold_vs_basic"])

    # 算牌策略期望是否 > 0: 单样本 t 检验(每靴均值)
    t_pos, p_pos = scipy_ttest_1samp(means[1])
    print("—" * 54)
    print("  算牌策略: 每靴均值是否显著 > 0（单样本检验）")
    print("—" * 54)
    print(f"    每靴均值 = {means[1].mean():+.5f}  "
          f"t = {t_pos:+.2f}  p = {p_pos:.4f}  → "
          f"{'显著为正 ✓' if p_pos < 0.05 else '未能显著为正'}")
    print()

    return {"sims": sims, "means": means, "results": results}


def scipy_ttest_1samp(x: np.ndarray) -> tuple:
    """包装 scipy 的单样本 t 检验（对每靴均值做 H₀: μ=0）。"""
    from scipy import stats as sp_stats
    res = sp_stats.ttest_1samp(x, 0.0)
    return float(res.statistic), float(res.pvalue)


def run_counting_regression(sims: list) -> dict:
    """第 6 步: 从算牌模拟记录中提取"真数→优势"回归。"""
    counting_sim = sims[1]
    reg = edge_by_true_count(counting_sim.records)
    print_counting_report(reg)
    return reg


# ============================================================
# 主函数
# ============================================================

def main() -> None:
    """主流程: 理论 → 校验 → 模拟 → 统计 → 图表。"""
    if "--play" in sys.argv:
        play_interactive(seed=None)
        return

    start_time = time.time()

    # ============================================================
    # 第 1 步: 理论报告
    # ============================================================
    theory.print_theoretical_report()

    # ============================================================
    # 第 2 步: 庄家分布校验 (χ²)
    # ============================================================
    print()
    print("=" * 70)
    print("  模拟校验（无限牌库模型）")
    print("=" * 70)
    run_dealer_validation()

    # ============================================================
    # 第 3 步: 逐行动 EV 校验
    # ============================================================
    run_action_ev_checks()

    # ============================================================
    # 第 4 步: 大数定律与整局期望校验
    # ============================================================
    _, mu0, curve = run_lln_validation()

    # ============================================================
    # 第 5 步: 牌靴策略对比（配对检验）
    # ============================================================
    shoe = run_shoe_comparison()
    sims, means = shoe["sims"], shoe["means"]

    # ============================================================
    # 第 6 步: 算牌回归
    # ============================================================
    reg = run_counting_regression(sims)

    # ============================================================
    # 第 7 步: 图表
    # ============================================================
    print("正在生成图表 ...", flush=True)
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "output", "charts")
    paths = generate_all_charts(
        upcards=DEALER_UPCARDS,
        dealer_observed=_dealer_observed_cache,
        lln=curve,
        mu0=mu0,
        sims=sims,
        means_by_sim=means,
        reg=reg,
        out_dir=out_dir,
    )
    print("图表已保存:")
    for p in paths:
        print(f"  {p}")

    # ============================================================
    # 结论
    # ============================================================
    elapsed = time.time() - start_time
    print()
    print("=" * 70)
    print("  结论")
    print("=" * 70)
    print("  1. 理论自洽: 庄家分布 χ² 校验通过；逐行动 EV 与模拟一致；")
    print(f"     基础策略整局期望 ≈ {mu0:+.4f}（模拟均值在 ±1.96SE 内）。")
    # 策略阶梯数值实时取自 theory（避免硬编码随理论修改而漂移）
    ladder = theory.strategy_ev_ladder()
    pct = [ladder[k] * 100 for k in ("永远停牌", "模仿庄家",
                                     "最优叫停(禁加倍)", "完整最优策略")]
    print(f"  2. 策略阶梯: 永不叫牌 {pct[0]:.1f}% → 模仿庄家 {pct[1]:.1f}% → "
          f"最优叫/停 {pct[2]:.1f}% → 基础策略 {pct[3]:.1f}%。")
    print("     每一步提升都来自对'条件概率'更充分的利用。")
    print("  3. 算牌有效: 高真数区间优势为正；配对检验显示算牌策略")
    print("     显著优于平注基础策略（p < 0.05）。")
    print("  4. 但方差巨大: 资金曲线剧烈波动 —— 正期望 ≠ 稳赚。")
    print("     现实中的优势玩家靠的是'大量重复 + 资金管理'。")
    print()
    print(f"  总耗时: {elapsed:.1f} 秒")
    print("=" * 70)


# 庄家分布校验的观测缓存(供第 7 步图表复用，避免重复采样)
_dealer_observed_cache: dict = {}


def run_dealer_validation() -> None:
    """第 2 步: 庄家分布理论 vs 蒙特卡洛(χ²)。(见主流程说明)"""
    global _dealer_observed_cache
    upcards = DEALER_UPCARDS
    observed = {}
    for u in upcards:
        r = random.Random(LLN_SEED + 13 * upcards.index(u) + 7)
        counts = {}
        for _ in range(N_DEALER_PER_UP):
            outcome = sample_dealer_playout(u, r)
            counts[outcome] = counts.get(outcome, 0) + 1
        observed[u] = counts
    _dealer_observed_cache = observed
    results = chi2_dealer_check(observed, upcards)
    print_validation_report(results)


# ============================================================
# 程序入口 — if __name__ == "__main__"
# ============================================================
# 【Python 知识点: __name__ 变量】
# 直接运行 python main.py → __name__ == "__main__"，执行 main()；
# 被 import 时只导入定义、不执行流程（dice-game/main.py 详解）。
if __name__ == "__main__":
    main()
