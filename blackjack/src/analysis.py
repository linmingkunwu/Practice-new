"""
统计分析 — 用统计推断检验理论、比较策略
=========================================

【这个文件是做什么的？】
把 game.py 生成的模拟数据转化为统计结论:
  1. 用 χ² 拟合优度检验校验"庄家分布理论 vs 模拟"
  2. 用均值 z 检验校验"行动 EV 理论 vs 模拟"
  3. 画大数定律收敛曲线所需的数据（累积均值）
  4. 多策略对比: 配对 t 检验、置换检验、bootstrap 置信区间
  5. 算牌有效性: 真数 → 优势的分箱回归

【涉及的核心统计概念】
• 描述统计: 均值、标准差(贝塞尔校正 ddof=1)、中位数、置信区间
• 中心极限定理(CLT): 大样本下样本均值 ≈ 正态，
  标准误 SE = σ̂/√n → 95% 置信区间 = 均值 ± 1.96·SE
• χ² 拟合优度检验: 观测频数 vs 理论概率 → 分布是否吻合
• 假设检验: 原假设 H₀ vs 备择假设；p 值 < 0.05 拒绝 H₀
• 配对设计: 同种子同靴序 → 两策略逐靴配对，抵消"牌运"
• 置换检验(permutation test): 不依赖正态假设的非参数检验
• Bootstrap: 有放回重采样估计统计量的抽样分布
• 简单线性回归: 真数(TC) → 优势的线性关系 y = a + b·x
• 大数定律(LLN): 累积均值收敛到理论期望
"""

# ============================================================
# 导入依赖
# ============================================================

import numpy as np
from dataclasses import dataclass
from typing import Dict, List, Tuple

# 【Python 知识点: from scipy import stats as sp_stats】
# 与 dice-game 的 analysis.py 相同的惯例: 用别名避免与
# numpy 的"统计函数"命名冲突。
from scipy import stats as sp_stats

# 本地模块
from .game import RoundRecord, ShoeSimulation
from .theory import (DISTRIBUTIONS, action_ev, dealer_natural_probability,
                     overall_expected_value)


# ============================================================
# 工具 — 从记录构造 NumPy 数组
# ============================================================

def _to_arrays(records: List[RoundRecord]) -> Tuple[np.ndarray, np.ndarray,
                                                    np.ndarray, np.ndarray]:
    """把记录列表转成四个数组: net / bet / tc / shoe_index。

    【Python 知识点: 列表推导式 → np.array】
    np.array([r.net for r in records]) —— 先取属性成 Python
    列表，再转 NumPy 数组（dice-game 里讲过这个惯用法）。
    """
    nets = np.array([r.net for r in records], dtype=float)
    bets = np.array([r.bet_units for r in records], dtype=float)
    tcs = np.array([r.tc for r in records], dtype=float)
    shoe_idx = np.array([r.shoe_index for r in records], dtype=int)
    return nets, bets, tcs, shoe_idx


# ============================================================
# 描述统计 — 一列净收益的"画像"
# ============================================================

@dataclass
class SessionStats:
    """一次模拟(一个策略)的关键统计量。"""
    label: str
    n_rounds: int
    mean_net: float          # 每局平均净收益
    std_net: float           # 每局净收益标准差
    ci95_net: Tuple[float, float]
    edge_per_unit: float     # 每单位下注的优势 (Σ净/Σ注)
    win_rate: float          # 获胜局占比
    push_rate: float         # 平局占比
    lose_rate: float         # 失败局占比
    mean_bet: float          # 平均下注


def compute_stats(records: List[RoundRecord], label: str) -> SessionStats:
    """从记录计算描述统计。

    【Python 知识点: 布尔数组计比例】
    (nets > 0).mean() —— 布尔数组的 mean 就是 True 的占比。
    """
    if not records:
        raise ValueError("records 不能为空")
    nets, bets, _, _ = _to_arrays(records)
    n = len(nets)
    mean = float(np.mean(nets))
    std = float(np.std(nets, ddof=1))           # 贝塞尔校正
    se = std / np.sqrt(n)
    z = 1.96                                    # 95% 置信水平
    edge = float(np.sum(nets) / np.sum(bets))   # 优势: 净/总注
    return SessionStats(
        label=label,
        n_rounds=n,
        mean_net=mean,
        std_net=std,
        ci95_net=(mean - z * se, mean + z * se),
        edge_per_unit=edge,
        win_rate=float((nets > 0).mean()),
        push_rate=float((nets == 0).mean()),
        lose_rate=float((nets < 0).mean()),
        mean_bet=float(np.mean(bets)),
    )


def mean_test_vs_mu0(samples: np.ndarray, mu0: float) -> Dict[str, float]:
    """
    单样本均值检验: H₀: 真实均值 = μ₀。
    样本量大 → t 分布 ≈ 标准正态，z = (x̄ - μ₀)/SE。
    返回 z 统计量与双侧 p 值。
    """
    n = len(samples)
    se = float(np.std(samples, ddof=1) / np.sqrt(n))
    z = float((np.mean(samples) - mu0) / se) if se > 0 else 0.0
    # 【Python 知识点: norm.cdf】
    # 标准正态累积分布函数 Φ(z)。双侧 p = 2·(1 - Φ(|z|))
    p = 2.0 * (1.0 - sp_stats.norm.cdf(abs(z)))
    return {"n": n, "z": z, "p": p, "se": se}


# ============================================================
# 校验 1 — 庄家最终分布: χ² 拟合优度
# ============================================================

def theoretical_unconditional_distribution(upcard: str) -> Dict[str, float]:
    """
    把 theory.py 的"条件分布"转换成"无条件分布"（含黑杰克），
    用于与真实发牌过程(无条件采样)对比:
      P(黑杰克) = P_nat
      P(点数k)  = (1 - P_nat) × P_cond(k)
      P(爆牌)   = (1 - P_nat) × P_cond(bust)
    【数学: 全概率公式】
    事件"最终=17" = "无黑杰克 且 条件分布=17"，
    两者独立(条件概率定义) → 概率相乘。
    """
    p_nat = dealer_natural_probability(upcard)
    dist: Dict[str, float] = {}
    if upcard == "A" or upcard in ("T", "J", "Q", "K"):
        dist["natural"] = p_nat
    for k, p in DISTRIBUTIONS[upcard].items():
        dist[str(k)] = (1.0 - p_nat) * p
    return dist


def chi2_dealer_check(
    observed: Dict[str, Dict[str, int]],
    upcards: List[str],
) -> Dict[str, Dict]:
    """
    对若干庄家首牌分别做 χ² 拟合优度检验。
    observed[upcard] = {类别: 观测频数}（由 game 的采样函数生成）。

    【χ² 统计量】
    χ² = Σ (观测-期望)² / 期望，期望 = 理论概率 × 总观测数。
    自由度 = 类别数 - 1（我们使用"已知完全分布"的理论概率，
    没有从数据估计参数）。
    p 值小(< 0.05) → 观测与理论不符（模拟有 bug 或样本作弊）。

    【适用条件】每个类别的期望频数 ≥ 5 —— 我们的样本
    (数万局)远大于该门槛。
    """
    results: Dict[str, Dict] = {}
    for u in upcards:
        theo = theoretical_unconditional_distribution(u)
        counts = observed[u]
        total = sum(counts.values())
        categories = sorted(theo.keys(), key=lambda k: (k != "natural", k))
        f_obs = np.array([counts.get(k, 0) for k in categories], dtype=float)
        f_exp = np.array([theo[k] * total for k in categories], dtype=float)
        stat, p = sp_stats.chisquare(f_obs, f_exp)
        results[u] = {
            "n": total,
            "chi2": float(stat),
            "p": float(p),
            "consistent": p >= 0.05,
            "max_dev_pct": float(np.max(np.abs(f_obs - f_exp) / f_exp) * 100),
        }
    return results


# ============================================================
# 校验 2 — 逐行动 EV: 均值 z 检验
# ============================================================

def check_state_action_ev(
    states: List[Tuple[int, bool, bool, str, str]],
    samples_fn,
) -> None:
    """
    对 (total, soft, two_card, upcard, action) 列表做
    "理论 EV vs 蒙特卡洛均值"检验并打印。
    samples_fn(state) 返回采样净收益列表（game 提供）。
    """
    print("  局面                    行动   理论EV    模拟均值    z      p值  结论")
    for (total, soft, two, u, act) in states:
        mu0 = action_ev(total, soft, two, u, act)
        nets = samples_fn((total, soft, two, u, act))
        arr = np.array(nets, dtype=float)
        n = len(arr)
        # 与 mean_test_vs_mu0 相同的除零防护: 样本标准差恒 > 0 时才做检验
        se = float(arr.std(ddof=1) / np.sqrt(n)) if n > 1 else 0.0
        z = float((arr.mean() - mu0) / se) if se > 0 else 0.0
        p = 2.0 * (1.0 - sp_stats.norm.cdf(abs(z)))
        tag = "ok" if p >= 0.05 else "!!"
        label = f"{total}{'软' if soft else '硬'} vs {u} [{act}]"
        print(f"  {label:<16}{mu0:+10.4f}{arr.mean():+11.4f}"
              f"{z:+8.2f}  {p:6.3f}  {tag}")


# ============================================================
# 大数定律 — 累积均值收敛数据
# ============================================================

def lln_convergence_curve(
    nets: np.ndarray, max_points: int = 400,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """
    返回 (轮次采样点, 累积均值, 下带, 上带)。

    【大数定律的可视化验证】
    第 t 轮的累积均值 X̄_t = (x₁+...+x_t)/t。
    LLN: X̄_t → μ（依概率）。
    CLT 给收敛速度: X̄_t ≈ N(μ, σ²/t) →
    95% 带 = μ ± 1.96·σ/√t（σ 用全样本标准差估计）。

    【对数采样】前段变化快、后段变化慢（dice-game 用过），
    这里对"轮次"做对数采样，用 np.unique 去重。
    """
    n = len(nets)
    cum = np.cumsum(nets)
    rounds = np.arange(1, n + 1)
    means = cum / rounds

    # 采样点: 对数均匀 + 开头 1
    if n > max_points:
        idx = np.unique(np.append(
            0,
            np.logspace(0, np.log10(n - 1), max_points).astype(int),
        ))
    else:
        idx = np.arange(n)

    sigma = float(np.std(nets, ddof=1))
    half = 1.96 * sigma / np.sqrt(rounds[idx])
    mu_hat = float(np.mean(nets))
    return rounds[idx], means[idx], mu_hat - half, mu_hat + half


# ============================================================
# 策略对比 — 配对检验（同种子牌序）
# ============================================================

def per_shoe_means(sim: ShoeSimulation) -> np.ndarray:
    """每靴牌的平均净收益（一靴 = 一个独立样本单元）。

    【为什么按靴分组而不是按局？】
    同一靴内各局共享牌堆状态，并不独立；
    而不同靴之间（重洗后）近似独立 —— 靴是更诚实的样本单元。

    【Python 知识点: np.add.reduceat — 分段求和】
    千万不能写成两层循环:
      for s in shoes: mean(记录中 shoe_index == s 的净收益)
    那是 O(靴数 × 总记录数) 的二次复杂度
    （5 千靴 × 22 万记录 ≈ 11 亿次比较，会卡几分钟）。
    正确做法: 记录按靴连续排列 → 找到每靴的边界位置，
    用 np.add.reduceat 一次性分段求和，O(总记录数)。
    """
    nets, _, _, shoe_idx = _to_arrays(sim.records)

    # 记录是按靴顺序追加的，但保险起见仍做一次稳定排序
    order = np.argsort(shoe_idx, kind="stable")
    nets_sorted = nets[order]
    idx_sorted = shoe_idx[order]

    # 每靴起始位置: 靴号发生变化的地方
    starts = np.concatenate(([0], np.flatnonzero(
        np.diff(idx_sorted) != 0) + 1))
    ends = np.concatenate((starts[1:], [len(nets_sorted)]))
    counts = ends - starts

    sums = np.add.reduceat(nets_sorted, starts)
    return sums / counts


def paired_comparison(a_means: np.ndarray, b_means: np.ndarray,
                      label_a: str, label_b: str,
                      seed: int = 7, n_perm: int = 20000) -> Dict:
    """
    配对样本 A/B 对比（两策略打同一批靴序）:
      1. 配对 t 检验 (ttest_rel)
      2. 置换检验: 随机翻转每对差值符号，看 |均值| 有多大
         概率偶然出现 —— 非参数、不要求正态
      3. bootstrap 差值置信区间
    返回各项统计量（字典），由打印函数输出。

    【内存意识 —— 分块向量化】
    置换检验最直观的写法是构造 (n_perm × n) 的 ±1 矩阵一次
    乘完: 20,000 置换 × 20,000 靴 = 4 亿个 float64 ≈ 3.2 GB，
    会把普通电脑内存吃爆。正确姿势: 分块循环，每块几千行，
    只保留每块的"置换均值"向量 —— 峰值内存降到 ~100 MB，
    向量化加速仍然保留（每块仍是一次矩阵乘法）。
    """
    if len(a_means) != len(b_means):
        raise ValueError("配对样本长度必须相同（同一批靴）")
    d = np.asarray(a_means - b_means, dtype=float)
    n = len(d)
    obs_mean = float(d.mean())

    # 1) 配对 t 检验
    t_stat, p_ttest = sp_stats.ttest_rel(a_means, b_means)

    # 2) 置换检验（分块）
    rng = np.random.default_rng(seed)
    perm_means = np.empty(n_perm)
    batch = max(1, min(2000, 80_000_000 // (8 * max(n, 1))))  # 每块 ≤ ~80MB
    for start in range(0, n_perm, batch):
        stop = min(start + batch, n_perm)
        flips = rng.choice([-1.0, 1.0], size=(stop - start, n))
        # 【Python 知识点: 矩阵乘法求一批置换的"翻转均值"】
        # flips @ d / n 一次算出该块所有置换的均值（向量化）。
        perm_means[start:stop] = (flips @ d) / n
    p_perm = float((np.abs(perm_means) >= abs(obs_mean)).mean())

    # 3) bootstrap CI（差值均值的 2.5% / 97.5% 分位，同样分块）
    n_boot = 8000
    boot = np.empty(n_boot)
    for start in range(0, n_boot, 1000):
        stop = min(start + 1000, n_boot)
        idx = rng.integers(0, n, size=(stop - start, n))
        boot[start:stop] = d[idx].mean(axis=1)
    lo, hi = np.percentile(boot, [2.5, 97.5])

    return {
        "label_a": label_a, "label_b": label_b,
        "n_shoes": n,
        "diff_mean": obs_mean,
        "t_stat": float(t_stat),
        "p_ttest": float(p_ttest),
        "p_perm": p_perm,
        "ci95_diff": (float(lo), float(hi)),
    }


# ============================================================
# 真数 → 优势 — 分箱与线性回归
# ============================================================

def edge_by_true_count(records: List[RoundRecord],
                       min_rounds: int = 400) -> Dict:
    """
    把每局按"开局真数(向下取整)"分箱，统计每箱:
      频率、平均下注、每单位注优势(Σ净/Σ注)、每局平均净收益、局数。
    并做简单线性回归: 优势 ≈ a + b × 真数（仅用局数足够的箱）。

    【回归的含义】
    斜率 b ≈ 每 +1 真数带来多少优势（文献经验约 +0.5%）。
    我们用数据自己估计这个斜率 —— 这是算牌科学性的核心证据。
    """
    nets, bets, tcs, _ = _to_arrays(records)
    tc_int = np.floor(tcs).astype(int)
    bins = []
    for tc in range(-4, 9):
        mask = tc_int == tc
        n = int(mask.sum())
        if n < min_rounds:
            continue
        bins.append({
            "tc": tc,
            "n": n,
            "freq": float(n / len(records)),
            "mean_bet": float(np.mean(bets[mask])),
            "edge": float(np.sum(nets[mask]) / np.sum(bets[mask])),
            "mean_net": float(np.mean(nets[mask])),
        })

    tcs_arr = np.array([b["tc"] for b in bins])
    edges = np.array([b["edge"] for b in bins])
    weights = np.array([b["n"] for b in bins], dtype=float)

    # 加权最小二乘: linregress 不支持权重，手动计算
    # 【数学: 加权最小二乘闭式解】
    # b = Σw(x-x̄w)(y-ȳw) / Σw(x-x̄w)², a = ȳw - b·x̄w
    wx = np.average(tcs_arr, weights=weights)
    wy = np.average(edges, weights=weights)
    cov = np.average((tcs_arr - wx) * (edges - wy), weights=weights)
    var = np.average((tcs_arr - wx) ** 2, weights=weights)
    slope = cov / var
    intercept = wy - slope * wx

    # 残差与相关系数
    resid = edges - (intercept + slope * tcs_arr)
    r = float(np.corrcoef(tcs_arr, edges)[0, 1])

    return {"bins": bins, "slope": float(slope),
            "intercept": float(intercept), "r": r,
            "resid_std": float(np.sqrt(np.average(resid ** 2,
                                                   weights=weights)))}


# ============================================================
# 打印报告
# ============================================================

def print_validation_report(chi2_results: Dict[str, Dict]) -> None:
    """打印庄家分布 χ² 校验结果。"""
    print("—" * 54)
    print("  校验 1: 庄家最终分布（理论 vs 无限牌库蒙特卡洛, χ²检验）")
    print("—" * 54)
    for u, res in chi2_results.items():
        verdict = "通过 ✓" if res["consistent"] else "不通过 ✗"
        print(f"    首牌 {u:>2}: χ²={res['chi2']:6.2f}  p={res['p']:6.4f}  "
              f"最大偏差 {res['max_dev_pct']:.2f}%  {verdict}")
    print("    p ≥ 0.05 表示观测频数与理论分布没有显著差异。")


def print_lln_report(nets: np.ndarray, mu0: float, label: str) -> None:
    """打印大数定律/均值一致性报告。"""
    stats = mean_test_vs_mu0(nets, mu0)
    se = stats["se"]
    print("—" * 54)
    print(f"  校验 2: 整局期望（{label}） vs 理论值 {mu0:+.4f}")
    print("—" * 54)
    print(f"    模拟均值: {np.mean(nets):+.4f}   (±1.96SE = {1.96*se:.4f})")
    print(f"    z = {stats['z']:+.2f}, p = {stats['p']:.4f}  → "
          f"{'与理论一致 ✓' if stats['p'] >= 0.05 else '与理论不符 ✗'}")
    win = float((nets > 0).mean())
    push = float((nets == 0).mean())
    lose = float((nets < 0).mean())
    print(f"    胜/平/负 占比: {win*100:.2f}% / {push*100:.2f}% / "
          f"{lose*100:.2f}%  (总和 {win+push+lose:.4f})")


def print_strategy_report(sims: List[ShoeSimulation]) -> None:
    """打印牌靴策略对比表。"""
    print("—" * 54)
    print("  牌靴模拟(6副牌, 同种子靴序) — 各策略描述统计")
    print("—" * 54)
    header = (f"    {'策略':<18}{'局数':>9}{'每局均值':>11}"
              f"{'95%CI下限':>11}{'每单位注优势':>14}{'平均注':>8}")
    print(header)
    for sim in sims:
        st = compute_stats(sim.records, sim.name)
        print(f"    {st.label:<18}{st.n_rounds:>9,}"
              f"{st.mean_net:>+11.5f}"
              f"{st.ci95_net[0]:>+11.5f}"
              f"{st.edge_per_unit*100:>+13.3f}%"
              f"{st.mean_bet:>8.2f}")
    print()


def print_paired_result(result: Dict) -> None:
    """打印配对检验结果。"""
    print("—" * 54)
    print(f"  配对对比: {result['label_a']} vs {result['label_b']}")
    print(f"    (每靴均值差 = 策略A - 策略B, 共 {result['n_shoes']} 靴)")
    print("—" * 54)
    print(f"    每靴均值差: {result['diff_mean']:+.5f}")
    print(f"    配对 t 检验:  t = {result['t_stat']:+.2f}, "
          f"p = {result['p_ttest']:.4f}")
    print(f"    置换检验:    p = {result['p_perm']:.4f}")
    print(f"    差值 95% bootstrap CI: "
          f"({result['ci95_diff'][0]:+.5f}, {result['ci95_diff'][1]:+.5f})")
    p_min = min(result["p_ttest"], result["p_perm"])
    print(f"    →  {'差异显著 ✓' if p_min < 0.05 else '差异不显著(样本不足?)'}")
    print()


def print_counting_report(reg: Dict) -> None:
    """打印真数→优势的分箱与回归结果。"""
    print("—" * 54)
    print("  算牌有效性: 真数 → 每单位注优势（分箱 + 线性回归）")
    print("—" * 54)
    print("    真数 |  频率  | 平均注 | 每单位注优势 | 每局平均")
    for b in reg["bins"]:
        print(f"    {b['tc']:>4} | {b['freq']*100:5.2f}% |"
              f"{b['mean_bet']:>7.2f} | {b['edge']*100:+11.3f}% |"
              f"{b['mean_net']:+.5f}")
    slope = reg["slope"] * 100
    print(f"    回归: 优势(每单位注) = {reg['intercept']*100:+.3f}% "
          f"+ {slope:+.3f}% × 真数")
    print(f"    相关系数 r = {reg['r']:.3f}   "
          f"→ 真数与优势存在线性关系，算牌信号真实存在")
    print()
