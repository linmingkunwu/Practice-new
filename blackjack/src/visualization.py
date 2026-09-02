"""
数据可视化 — 把理论、模拟与统计画成图
=======================================

【这个文件是做什么的？】
将 theory/game/analysis 的结果绘制为 PNG 图表，输出到
output/charts/ 目录。共 6 张图:
  1. chart_dealer.png      庄家分布: 理论 vs 蒙特卡洛(4种首牌)
  2. chart_lln.png         大数定律: 累积每局净收益 → 理论 EV
  3. chart_strategy_table.png  最优行动表热力图(硬手/软手)
  4. chart_strategy_shoe.png   四种策略的"每靴均值"分布对比
  5. chart_bankroll.png    累积资金曲线(基础 vs 算牌)
  6. chart_count_edge.png  真数 → 每单位注优势(散点+回归线)

【可视化常识】
• 条形图: 类别对比 → 庄家分布理论vs模拟
• 折线图: 随时间/轮次的趋势 → LLN 收敛、资金曲线
• 热力图: 二维矩阵的数值 → 行动表
• 直方图: 分布形状对比 → 策略每靴均值
• 散点+回归: 两变量关系 → 真数与优势
"""

# ============================================================
# 导入依赖
# ============================================================

import os
from typing import Dict, List, Tuple

import numpy as np

# 【Python 知识点: matplotlib 的分层导入】
# pyplot 是"画图工具箱"；font_manager 管理字体列表。
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm

# 本地模块
from .theory import optimal_action
from .cards import RANKS, hand_value


# ============================================================
# 中文字体探测 — Windows/Linux/macOS 通用
# ============================================================

def _find_cjk_font() -> str:
    """
    从系统已安装字体里挑一个能显示中文的。
    matplotlib 维护字体列表 fontManager.ttflist；
    {f.name for f in fm.fontManager.ttflist} 是集合推导式。

    候选顺序: 微软雅黑(Windows) → 黑体 → 苹方(macOS) →
    文泉驿/Noto(Linux)。返回第一个可用的；全都没有就返回
    默认字体(中文会显示成方块，但不至于崩溃)。
    """
    candidates = [
        "Microsoft YaHei", "SimHei", "PingFang SC",
        "Noto Sans CJK SC", "WenQuanYi Zen Hei",
    ]
    available = {f.name for f in fm.fontManager.ttflist}
    for name in candidates:
        if name in available:
            return name
    return "DejaVu Sans"


def _setup_style() -> str:
    """
    配置全局绘图风格并返回选中的中文字体名。
    rcParams 是 matplotlib 的全局配置字典（dice-game 也用过）:
      font.family / font.sans-serif → 字体
      axes.facecolor                → 坐标区背景色
      figure.facecolor              → 画布背景色
    """
    cjk = _find_cjk_font()
    plt.rcParams.update({
        "font.family": "sans-serif",
        "font.sans-serif": [cjk, "DejaVu Sans"],
        "font.size": 11,
        "axes.facecolor": "#FAFAFA",
        "figure.facecolor": "white",
        "axes.grid": True,
        "grid.alpha": 0.35,
        "axes.spines.top": False,
        "axes.spines.right": False,
    })
    return cjk


# 配色（与 dice-game 同风格的"低饱和学术色"）
BLUE = "#4C72B0"
ORANGE = "#DD8452"
GREEN = "#55A868"
RED = "#C44E52"
INK = "#2B2B2B"
MUTED = "#8C8C8C"


# ============================================================
# 图 1 — 庄家分布: 理论 vs 模拟
# ============================================================

def chart_dealer_distribution(
    upcards: List[str],
    observed: Dict[str, Dict[str, int]],
    out_dir: str,
) -> str:
    """
    对每种首牌画"结果类别概率"的并排条形图:
    理论(无条件分布) 用半透明色块，蒙特卡洛 用描边色块。
    用 2×2 子图展示 4 种代表性首牌（A/6/T/2）。
    """
    from .analysis import theoretical_unconditional_distribution

    # 当前按 2×2 子图布局，恰好展示 4 种首牌
    if len(upcards) != 4:
        raise ValueError("chart_dealer_distribution 需要恰好 4 种首牌(2×2 布局)")

    fig, axes = plt.subplots(2, 2, figsize=(11, 7))
    axes = axes.ravel()
    for ax, u in zip(axes, upcards):
        theo = theoretical_unconditional_distribution(u)
        counts = observed[u]
        total = sum(counts.values())
        # 类别顺序: natural(若有) → 17..21 → bust
        cats = [k for k in ("natural", "17", "18", "19", "20", "21", "bust")
                if k in theo]
        x = np.arange(len(cats))
        p_theo = np.array([theo[k] for k in cats])
        p_sim = np.array([counts.get(k, 0) / total for k in cats])
        ax.bar(x - 0.2, p_theo, width=0.4, color=BLUE, alpha=0.35,
               label="理论")
        ax.bar(x + 0.2, p_sim, width=0.4, color=ORANGE, alpha=0.85,
               label="蒙特卡洛")
        ax.set_xticks(x)
        ax.set_xticklabels(cats)
        ax.set_title(f"庄家首牌 {u} 的最终结果分布", fontweight="bold")
        ax.legend(fontsize=9)
        ax.set_ylabel("概率")
    fig.suptitle("庄家最终分布: 理论概率 vs 无限牌库模拟",
                 fontweight="bold", fontsize=14, y=0.99)
    fig.tight_layout(rect=(0, 0, 1, 0.96))
    path = os.path.join(out_dir, "chart_dealer.png")
    fig.savefig(path, dpi=120)
    plt.close(fig)
    return path


# ============================================================
# 图 2 — 大数定律: 累积均值收敛
# ============================================================

def chart_lln_convergence(
    rounds: np.ndarray, means: np.ndarray,
    band_low: np.ndarray, band_high: np.ndarray,
    mu0: float, label: str, out_dir: str,
) -> str:
    """
    折线图: 累积每局净收益 vs 轮次(对数横轴)，
    阴影区为 95% 带(μ ± 1.96σ/√t)，虚线为理论 EV。
    图形上验证: 蓝色线最终钻进带内并停在虚线上 —— 大数定律。
    """
    fig, ax = plt.subplots(figsize=(9, 5.2))
    ax.plot(rounds, means, color=BLUE, lw=1.8, label=f"累积均值 ({label})")
    ax.fill_between(rounds, band_low, band_high, color=BLUE, alpha=0.12,
                    label="95% 带 ±1.96σ/√t")
    ax.axhline(mu0, color=RED, ls="--", lw=1.6, label=f"理论 EV = {mu0:+.4f}")
    ax.set_xscale("log")
    ax.set_xlabel("轮次 (对数刻度)")
    ax.set_ylabel("累积每局净收益")
    ax.set_title("大数定律: 样本均值随轮次收敛到理论期望",
                 fontweight="bold")
    ax.legend()
    fig.tight_layout()
    path = os.path.join(out_dir, "chart_lln.png")
    fig.savefig(path, dpi=120)
    plt.close(fig)
    return path


# ============================================================
# 图 3 — 最优行动表热力图
# ============================================================

def chart_strategy_table(out_dir: str) -> str:
    """
    把行动(S/H/D)映射成颜色画成热力图:
      绿=停牌(S), 红=要牌(H), 蓝=加倍(D)
    两幅子图: 硬手点数 8~17、软手 A2~A9(点 13~20)。
    一眼可见"策略的形状"—— 表格规律(对庄家 4-6 停牌、
    对弱牌加倍)在图上呈现为色块结构。
    """
    action_code = {"S": 0, "H": 1, "D": 2}

    def collect(rows_total_soft: List[Tuple[int, bool]]) -> Tuple[np.ndarray, List[str]]:
        """rows_total_soft: [(点数, 软), ...] → (数值矩阵, 行标签)。"""
        mat = []
        labels = []
        for total, soft in rows_total_soft:
            row = []
            for u in RANKS:
                act = optimal_action(total, soft, two_card=True, upcard=u)
                row.append(action_code[act])
            mat.append(row)
            tag = "软" if soft else ""
            labels.append(f"{total}{tag}")
        return np.array(mat), labels

    hard, hard_lbl = collect([(t, False) for t in range(8, 18)])
    soft_rows = []
    for s in ["2", "3", "4", "5", "6", "7", "8", "9"]:
        total, soft = hand_value(["A", s])
        soft_rows.append((total, soft))
    softm, soft_lbl = collect(soft_rows)

    from matplotlib.colors import ListedColormap
    cmap = ListedColormap([GREEN, RED, BLUE])
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5.6))

    for ax, mat, labels, title in (
            (ax1, hard, hard_lbl, "硬手 (首两张可加倍)"),
            (ax2, softm, soft_lbl, "软手 (A+点数, 首两张可加倍)")):
        im = ax.imshow(mat, cmap=cmap, vmin=0, vmax=2, aspect="auto")
        ax.set_xticks(range(len(RANKS)))
        ax.set_xticklabels([("A" if r == "A" else r) for r in RANKS])
        ax.set_yticks(range(len(labels)))
        ax.set_yticklabels(labels)
        ax.set_xlabel("庄家首牌")
        ax.set_ylabel("玩家点数")
        ax.set_title(title, fontweight="bold")
        # 在格子里写行动字母
        for i in range(mat.shape[0]):
            for j in range(mat.shape[1]):
                txt = ["S", "H", "D"][mat[i, j]]
                ax.text(j, i, txt, ha="center", va="center",
                        fontsize=8, color="white", fontweight="bold")
    # 图例: 颜色 → 行动
    handles = [plt.Rectangle((0, 0), 1, 1, color=c) for c in (GREEN, RED, BLUE)]
    fig.legend(handles, ["S = 停牌", "H = 要牌", "D = 加倍"], loc="lower center",
               ncol=3, frameon=False)
    fig.suptitle("最优基础策略行动表 (S17 / 无限牌库)",
                 fontweight="bold", fontsize=14, y=1.02)
    fig.tight_layout(rect=(0, 0.05, 1, 0.95))
    path = os.path.join(out_dir, "chart_strategy_table.png")
    fig.savefig(path, dpi=120, bbox_inches="tight")
    plt.close(fig)
    return path


# ============================================================
# 图 4 — 策略"每靴均值"分布直方图
# ============================================================

def chart_shoe_means(
    sims: List,
    means_by_sim: List[np.ndarray],
    out_dir: str,
) -> str:
    """
    每个策略画一条"每靴平均净收益"的直方图(半透明叠加)，
    并标出各自均值竖线。
    重叠程度直观展示: 分布靠右的策略更好；
    分布很宽说明单靴结果方差极大（赌博的本质）。
    """
    fig, ax = plt.subplots(figsize=(9.5, 5.4))
    colors = [BLUE, ORANGE, GREEN, RED]
    for sim, means, color in zip(sims, means_by_sim, colors):
        ax.hist(means, bins=60, alpha=0.45, color=color,
                label=f"{sim.name} (n={len(means)})")
        ax.axvline(means.mean(), color=color, ls="--", lw=1.6)
    ax.set_xlabel("每靴平均净收益（单位注）")
    ax.set_ylabel("靴数")
    ax.set_title("各策略的每靴均值分布（同 6 副牌靴序）", fontweight="bold")
    ax.legend(fontsize=9)
    fig.tight_layout()
    path = os.path.join(out_dir, "chart_strategy_shoe.png")
    fig.savefig(path, dpi=120)
    plt.close(fig)
    return path


# ============================================================
# 图 5 — 累积资金曲线
# ============================================================

def chart_bankroll_paths(
    sims: List,
    out_dir: str,
    max_rounds: int = 6000,
) -> str:
    """
    把每局净收益做累积求和 → 资金曲线。
    前 max_rounds 局: 基础策略稳定下滑 vs 算牌策略波动爬升。
    波动幅度揭示"赌博的方差" —— 曲线远不是直线。
    """
    fig, ax = plt.subplots(figsize=(9.5, 5.4))
    colors = [BLUE, ORANGE, GREEN, RED]
    for sim, color in zip(sims, colors):
        nets = np.array([r.net for r in sim.records[:max_rounds]])
        if len(nets) == 0:
            continue
        path = np.cumsum(nets)
        ax.plot(np.arange(1, len(path) + 1), path, color=color,
                lw=1.4, label=sim.name)
    ax.set_xlabel("局数")
    ax.set_ylabel("累计净收益（单位注）")
    ax.set_title("资金曲线: 基础策略 vs 其他策略（同靴序前 "
                 f"{max_rounds} 局）", fontweight="bold")
    ax.axhline(0, color=INK, lw=0.8)
    ax.legend(fontsize=9)
    fig.tight_layout()
    path = os.path.join(out_dir, "chart_bankroll.png")
    fig.savefig(path, dpi=120)
    plt.close(fig)
    return path


# ============================================================
# 图 6 — 真数 → 优势
# ============================================================

def chart_count_edge(reg: Dict, out_dir: str) -> str:
    """
    散点(每箱真数 vs 每单位注优势) + 加权回归线；
    散点大小 ∝ 局数。
    零线以上为正优势 —— 高真数区间确实转正。
    """
    bins = reg["bins"]
    xs = np.array([b["tc"] for b in bins])
    ys = np.array([b["edge"] * 100 for b in bins])
    sizes = np.array([max(b["n"] / 30, 4) for b in bins])

    fig, ax = plt.subplots(figsize=(8.6, 5))
    ax.scatter(xs, ys, s=sizes, color=BLUE, alpha=0.75,
               label="各真数箱(大小=局数)")
    xs_fit = np.linspace(xs.min(), xs.max(), 50)
    slope, intercept = reg["slope"] * 100, reg["intercept"] * 100
    ax.plot(xs_fit, intercept + slope * xs_fit, color=RED, lw=1.8,
            label=f"加权回归: {intercept:+.2f}% + {slope:+.2f}%×真数")
    ax.axhline(0, color=INK, lw=0.9, ls=":")
    ax.set_xlabel("真数 (向下取整)")
    ax.set_ylabel("每单位注优势 (%)")
    ax.set_title(f"算牌信号: 真数越高优势越大 (r = {reg['r']:.3f})",
                 fontweight="bold")
    ax.legend(fontsize=9)
    fig.tight_layout()
    path = os.path.join(out_dir, "chart_count_edge.png")
    fig.savefig(path, dpi=120)
    plt.close(fig)
    return path


# ============================================================
# 汇总入口
# ============================================================

def generate_all_charts(
    upcards: List[str],
    dealer_observed: Dict[str, Dict[str, int]],
    lln: Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray],
    mu0: float,
    sims: List,
    means_by_sim: List[np.ndarray],
    reg: Dict,
    out_dir: str,
) -> List[str]:
    """
    一次生成全部图表，返回生成的文件路径列表。
    main.py 负责创建 out_dir 并打印路径。
    """
    _setup_style()
    os.makedirs(out_dir, exist_ok=True)

    rounds, means, lo, hi = lln
    paths = [
        chart_dealer_distribution(upcards, dealer_observed, out_dir),
        chart_lln_convergence(rounds, means, lo, hi, mu0,
                              "基础策略,无限牌库", out_dir),
        chart_strategy_table(out_dir),
        chart_shoe_means(sims, means_by_sim, out_dir),
        chart_bankroll_paths(sims, out_dir),
        chart_count_edge(reg, out_dir),
    ]
    return paths
