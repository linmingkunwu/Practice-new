"""
图表生成 — 使用 matplotlib 将数据可视化
=========================================

【这个文件是做什么的？】
把枯燥的数字变成直观的图表。

【matplotlib 的架构】
matplotlib 模仿了 MATLAB 的绘图方式，它有两个层面的 API:

1. pyplot (plt): 高层"状态机"接口
   - 维护一个"当前 figure"和"当前 axes"
   - plt.plot(), plt.title() 等操作在当前 axes 上进行
   - 适合快速原型和交互式探索

2. 面向对象接口:
   - fig, ax = plt.subplots()
   - ax.plot(), ax.set_title() 等明确指定操作对象
   - 适合复杂图表和多子图布局
   - 本项目统一使用这种方式（更清晰、更可控）

【Figure 和 Axes 的区别】
  Figure = 整张画布（可以包含多个 Axes）
  Axes = 一个具体的坐标系（有 x 轴、y 轴、标题等）
  一个 Figure 包含 1+ 个 Axes。

【matplotlib 的后端 (Backend)】
后端决定了图表的"输出目标":
  - 交互后端: TkAgg, Qt5Agg → 弹出窗口显示
  - 非交互后端: Agg, PDF, SVG → 保存为文件
  matplotlib.use("Agg") 强制使用 Anti-Grain Geometry 后端，
  将图表渲染为像素（PNG 格式），适合无图形界面的服务器环境。
"""

import os
import numpy as np
import matplotlib
matplotlib.use("Agg")  # 必须在 import pyplot 之前设置！
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
from matplotlib.patches import Patch
from typing import List

from .game import GameResult
from .analysis import (
    compute_convergence_curves,
    compute_round_by_round_win_rate,
)
from .dice import three_dice_sum_distribution


# ============================================================
# 调色板
# ============================================================

# 所有颜色来自 dataviz 参考调色板，经过色盲可访问性验证。
# 蓝-橙是色轮上对比最强的互补色对之一，对红绿色盲也友好。

BLUE = "#2a78d6"         # 槽位1: 正常骰子 — 蓝色
ORANGE = "#eb6834"       # 槽位2: 操纵骰子 — 橙色
BLUE_LIGHT = "#9ec5f4"   # 蓝色序列的浅色 — "大"区域
SURFACE = "#fcfcfb"      # 图表底色 — 接近纯白但更柔和
INK_PRIMARY = "#0b0b0b"     # 主要文字: 近乎纯黑
INK_SECONDARY = "#52514e"   # 次要文字: 深灰
INK_MUTED = "#898781"       # 静音文字: 浅灰
GRIDLINE = "#e1e0d9"        # 网格线: 非常浅的灰
BASELINE = "#c3c2b7"        # 坐标轴线


# ============================================================
# 字体和样式 — matplotlib 配置系统
# ============================================================

def _find_cjk_font() -> str:
    """
    查找系统中可用的中文字体。

    【Python 知识点: matplotlib 的字体管理】
    matplotlib 维护了一个字体列表 (fontManager.ttflist)。
    每个字体有 name（显示名）、fname（文件路径）等属性。
    {f.name for f in fm.fontManager.ttflist} 是集合推导式，
    等价于 set(f.name for f in ...)，创建不重复的字体名集合。

    【集合推导式 (Set Comprehension)】
    {表达式 for 变量 in 可迭代对象}
    和列表推导式一样，但生成集合（去重、无序）。
    """
    import matplotlib.font_manager as fm
    candidates = [
        "Noto Sans SC", "Noto Sans CJK SC", "Source Han Sans SC",
        "Microsoft YaHei", "SimHei",
    ]
    available = {f.name for f in fm.fontManager.ttflist}
    for font in candidates:
        if font in available:
            return font
    return "sans-serif"


def setup_style():
    """
    设置 matplotlib 全局样式。

    【Python 知识点: plt.rcParams — 运行时配置字典】
    rcParams 是一个类似 dict 的对象，存储 matplotlib 的全局配置。
    用 .update({key: value, ...}) 批量修改。
    修改后对当前进程中的所有图表生效。

    这和 CSS 给网页设置样式是同一个思路:
      rcParams["font.size"] = 11   ≈  body { font-size: 11px; }
      rcParams["axes.facecolor"]   ≈  .axes { background-color: ...; }

    【Python 知识点: dict.update() 方法】
    传入一个字典，将所有键值对合并到原字典中。
    如果键已存在则覆盖，不存在则添加。
    这里用字典字面量 {} 直接传入，一次性设置所有样式。
    """
    cjk_font = _find_cjk_font()
    plt.rcParams.update({
        "figure.facecolor": SURFACE,
        "axes.facecolor": SURFACE,
        "axes.edgecolor": BASELINE,
        "axes.labelcolor": INK_PRIMARY,
        "axes.titlecolor": INK_PRIMARY,
        "text.color": INK_PRIMARY,
        "xtick.color": INK_MUTED,
        "ytick.color": INK_MUTED,
        "grid.color": GRIDLINE,
        "grid.alpha": 0.8,
        "grid.linewidth": 0.5,
        "legend.facecolor": SURFACE,
        "legend.edgecolor": GRIDLINE,
        "legend.framealpha": 0.9,
        "font.family": "sans-serif",
        "font.sans-serif": [cjk_font, "DejaVu Sans", "Arial", "sans-serif"],
        "font.size": 11,
        "axes.titlesize": 14,
        "axes.labelsize": 12,
        "xtick.labelsize": 10,
        "ytick.labelsize": 10,
        "legend.fontsize": 10,
        "figure.dpi": 150,
        "savefig.dpi": 150,
        "savefig.bbox": "tight",
        "savefig.facecolor": SURFACE,
    })


def _savefig(fig, filename: str, output_dir: str):
    """
    保存图表到文件并释放内存。

    【Python 知识点: os.makedirs 的 exist_ok 参数】
    os.makedirs(path, exist_ok=True)
    递归创建目录。exist_ok=True 表示：
      如果目录已存在 → 不报错（静默跳过）
      默认 exist_ok=False → 目录存在时抛 FileExistsError
    这对于输出目录特别有用——不需要先手动 mkdir。

    【Python 知识点: os.path.join — 跨平台路径拼接】
    os.path.join("output", "charts", "01.png")
      → Windows: "output\\charts\\01.png"
      → Linux:   "output/charts/01.png"
    永远不要手动拼接路径（"output/" + "file"），
    因为路径分隔符在 Windows(\\)和 Linux(/)上不同。
    Python 3.9+ 可用 pathlib.Path 替代 os.path。

    【Python 知识点: plt.close(fig) — 为什么重要？】
    matplotlib 默认保留所有 Figure 对象在内存中（用于交互模式）。
    如果不关闭，每张图占用 ~10-50 MB，生成 100 张图 → 内存爆炸。
    close(fig) 显式释放该 Figure 的资源。
    """
    os.makedirs(output_dir, exist_ok=True)
    path = os.path.join(output_dir, filename)
    fig.savefig(path, bbox_inches="tight", pad_inches=0.5)
    print(f"  已保存: {path}")
    plt.close(fig)


# ============================================================
#  Chart 1: 三骰子和值分布
# ============================================================
def plot_sum_distribution(output_dir: str = "output/charts"):
    """
    图表1 — 三骰子和值的理论概率分布 (柱状图)。

    【Python 知识点: matplotlib 的绘图流程】
    1. fig, ax = plt.subplots(...)  → 创建画布和坐标系
    2. ax.bar(...)  → 在坐标系上画柱子（返回 BarContainer 对象）
    3. ax.axvline(...)  → 画竖直线
    4. ax.text(...)  → 添加文字标注
    5. ax.set_xlabel(...), ax.set_title(...)  → 设置标签和标题
    6. ax.legend(...)  → 添加图例
    7. _savefig(fig, ...)  → 保存

    【plt.subplots() 的参数】
    figsize=(12, 5): 画布尺寸，单位英寸。12×5 = 长方形适合单行展示。
    """
    probs = three_dice_sum_distribution()
    sums = list(probs.sum_distribution.keys())
    probabilities = [probs.sum_distribution[s] * 100 for s in sums]

    fig, ax = plt.subplots(figsize=(12, 5))

    # 颜色分类: 蓝色="小"，浅蓝="大"
    colors = [BLUE if s <= 10 else BLUE_LIGHT for s in sums]

    # 【Python 知识点: matplotlib 的图元 (Artist)】
    # ax.bar() 返回 BarContainer 对象。这里不需要用它，
    # 但如果要修改柱子属性（如透明度），可以保存返回值。
    ax.bar(sums, probabilities, color=colors, width=0.7,
           edgecolor="white", linewidth=0.5)

    # 小/大分界线
    ax.axvline(x=10.5, color=INK_SECONDARY, linewidth=1.5,
               linestyle="--", zorder=3)
    ax.text(10.5, max(probabilities) * 0.95,
            "  ≤10 小  │  >10 大",
            ha="left", va="top", fontsize=10, color=INK_SECONDARY,
            # 【Python 知识点: bbox 参数字典】
            # bbox=dict(...) 给文字添加背景框，防止被网格线干扰阅读
            bbox=dict(facecolor=SURFACE, edgecolor="none", alpha=0.8, pad=2))

    # 标注概率值
    for s, p in zip(sums, probabilities):
        # 【Python 知识点: zip() — 并行迭代】
        # zip([3,4,5], [0.5,1.4,2.8]) → (3,0.5), (4,1.4), (5,2.8)
        # 两个列表并行配对，常用于同时遍历多个序列。
        # 如果列表长度不同，以最短的为准。
        if p > 3:
            ax.text(s, p + 0.3, f"{p:.1f}%", ha="center", va="bottom",
                    fontsize=7, color=INK_MUTED)

    ax.set_xlabel("三骰子和值")
    ax.set_ylabel("概率 (%)")
    ax.set_title("三骰子和值分布（正常骰子，216 种组合）",
                 fontweight="bold", pad=16)
    ax.set_xticks(sums)
    ax.set_xlim(2, 19)
    # FormatStrFormatter: 自定义 y 轴标签格式
    ax.yaxis.set_major_formatter(ticker.FormatStrFormatter('%.0f%%'))

    # 【Python 知识点: set_axisbelow(True)】
    # 设置网格线在数据层的下面。默认网格线在数据上面，
    # 可能遮挡柱子。set_axisbelow(True) 把它们放到后面。
    ax.yaxis.grid(True, alpha=0.5)
    ax.set_axisbelow(True)

    # 图例: Patch 对象表示纯色色块
    legend_elements = [
        Patch(facecolor=BLUE, label='"小" (≤10): 50.0%'),
        Patch(facecolor=BLUE_LIGHT, label='"大" (>10): 50.0%'),
    ]
    ax.legend(handles=legend_elements, loc="upper left", frameon=True)

    _savefig(fig, "01_sum_distribution.png", output_dir)


# ============================================================
#  Chart 2: LLN 收敛图
# ============================================================
def plot_lln_convergence(
    normal_results: List[GameResult],
    rigged_results: List[GameResult],
    output_dir: str = "output/charts",
    max_rounds: int = 300,
):
    """
    图表2 — 大数定律(LLN)收敛图（核心图表）。

    【Python 知识点: 数据降采样 (Downsampling)】
    原始数据有 ~2.6M 个点。如果全部画出来:
      - 渲染极慢（几秒到几十秒）
      - 文件巨大（几十 MB）
      - 屏幕上看不出区别（几百点已足够平滑）
    因此 compute_convergence_curves 内部用 np.logspace 做对数间隔采样
    （≤500 点，前面密集后面稀疏），返回的曲线和置信带已对齐，
    本函数直接绘制，不再二次降采样。
    """
    r_normal, rates_normal, lo_n, hi_n = compute_convergence_curves(
        normal_results, max_rounds
    )
    r_rigged, rates_rigged, lo_r, hi_r = compute_convergence_curves(
        rigged_results, max_rounds
    )

    fig, ax = plt.subplots(figsize=(13, 6))

    # 【Python 知识点: fill_between — 区域填充】
    # 在两条曲线之间填充颜色，用于显示置信带。
    # alpha=0.06 非常透明——只给出"区域存在"的暗示，不遮挡主曲线。
    ax.fill_between(r_normal, lo_n, hi_n,
                    color=BLUE, alpha=0.06, linewidth=0)
    ax.fill_between(r_rigged, lo_r, hi_r,
                    color=ORANGE, alpha=0.06, linewidth=0)

    # 主曲线
    ax.plot(r_normal, rates_normal,
            color=BLUE, linewidth=1.8, label="正常骰子", zorder=4)
    ax.plot(r_rigged, rates_rigged,
            color=ORANGE, linewidth=1.8, label="操纵骰子 (R3+)", zorder=4)

    # 理论极限虚线
    ax.axhline(y=0.5, color=BLUE, linewidth=1.0, linestyle="--",
               alpha=0.5, zorder=2)
    ax.axhline(y=1/6, color=ORANGE, linewidth=1.0, linestyle="--",
               alpha=0.5, zorder=2)

    # 【Python 知识点: max() 内置函数】
    # max(r_normal[-1], r_rigged[-1]) 取两个数组最后一个元素的较大者。
    # r_normal[-1] 是 Python 的"负索引": -1 表示最后一个元素。
    last_r = max(r_normal[-1], r_rigged[-1])
    ax.text(last_r * 0.97, 0.505, "P = 0.500", ha="right", va="bottom",
            fontsize=9, color=BLUE, alpha=0.7)
    ax.text(last_r * 0.97, 0.172, "P = 0.167", ha="right", va="top",
            fontsize=9, color=ORANGE, alpha=0.7)

    ax.axvline(x=3, color=INK_MUTED, linewidth=0.8, linestyle=":",
               alpha=0.6)
    ax.text(3.5, 0.08, "第3轮起\n操纵开始", fontsize=8,
            color=INK_MUTED, va="bottom")

    ax.set_xlabel("投掷轮数 (累计)")
    ax.set_ylabel("累积胜率")
    ax.set_title("大数定律验证 — 累积胜率收敛图",
                 fontweight="bold", pad=16)
    ax.legend(loc="upper right", frameon=True)

    ax.set_xlim(1, last_r)
    ax.set_ylim(0, 0.65)
    # PercentFormatter: 将 0-1 范围的值显示为 0%-100%
    ax.yaxis.set_major_formatter(ticker.PercentFormatter(1.0))

    ax.yaxis.grid(True, alpha=0.5)
    ax.set_axisbelow(True)

    _savefig(fig, "02_lln_convergence.png", output_dir)


# ============================================================
#  Chart 3: 轮数分布直方图
# ============================================================
def plot_rolls_distribution(
    normal_results: List[GameResult],
    rigged_results: List[GameResult],
    output_dir: str = "output/charts",
):
    """
    图表3 — 达到5胜所需轮数的分布对比 (直方图)。

    【Python 知识点: plt.subplots 的多子图模式】
    fig, (ax1, ax2) = plt.subplots(2, 1, ...)
    返回 Figure 和 Axes 元组。2行1列 → (ax_top, ax_bottom)。
    可以这样解包:
      fig, axes = plt.subplots(2, 3)  → axes 是 2×3 的数组
      ax = axes[0, 1]                  → 第0行第1列

    【Python 知识点: constrained_layout】
    替代 tight_layout() 的更智能布局引擎。
    在创建 Figure 时启用（不能事后启用）。
    自动调整子图间距、标签位置，避免重叠。
    对于固定结构的多子图布局比 tight_layout 更可靠。
    """
    normal_rolls = np.array([g.total_rolls for g in normal_results])
    rigged_rolls = np.array([g.total_rolls for g in rigged_results])

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 7), sharex=False,
                                    gridspec_kw={"hspace": 0.35},
                                    constrained_layout=True)

    # 【Python 知识点: np.percentile — 分位数】
    # np.percentile(data, 99.5) = 截断值，99.5% 的数据在此以下。
    # 用于切掉尾部的极端值，让直方图聚焦在主要数据范围。
    x_min = min(normal_rolls.min(), 5)
    x_max_rigged = int(np.percentile(rigged_rolls, 99.5))

    bins_normal = np.arange(x_min - 0.5, normal_rolls.max() + 1.5)
    bins_rigged = np.arange(x_min - 0.5, x_max_rigged + 1.5)

    # --- 正常骰子 ---
    ax1.hist(normal_rolls, bins=bins_normal, color=BLUE, alpha=0.75,
             edgecolor="white", linewidth=0.3, density=True)
    ax1.axvline(x=np.mean(normal_rolls), color=INK_PRIMARY,
                linewidth=1.2, linestyle="--",
                label=f"均值 = {np.mean(normal_rolls):.1f} 轮")
    ax1.axvline(x=10, color=BLUE, linewidth=1.5, linestyle=":",
                alpha=0.7, label="理论值 = 10 轮")
    ax1.set_title("正常骰子 — 达到 5 胜所需轮数分布", fontweight="bold")
    ax1.set_ylabel("概率密度")
    ax1.legend(loc="upper right", fontsize=9)
    ax1.yaxis.grid(True, alpha=0.5)
    ax1.set_axisbelow(True)

    # --- 操纵骰子 ---
    ax2.hist(rigged_rolls, bins=bins_rigged, color=ORANGE, alpha=0.75,
             edgecolor="white", linewidth=0.3, density=True)
    ax2.axvline(x=np.mean(rigged_rolls), color=INK_PRIMARY,
                linewidth=1.2, linestyle="--",
                label=f"均值 = {np.mean(rigged_rolls):.1f} 轮")
    ax2.axvline(x=26, color=ORANGE, linewidth=1.5, linestyle=":",
                alpha=0.7, label="理论值 = 26 轮")
    ax2.set_title("操纵骰子 — 达到 5 胜所需轮数分布", fontweight="bold")
    ax2.set_xlabel("投掷轮数")
    ax2.set_ylabel("概率密度")
    ax2.legend(loc="upper right", fontsize=9)
    ax2.yaxis.grid(True, alpha=0.5)
    ax2.set_axisbelow(True)

    _savefig(fig, "03_rolls_distribution.png", output_dir)


# ============================================================
#  Chart 4: 各轮胜率对比
# ============================================================
def plot_round_win_rates(
    normal_results: List[GameResult],
    rigged_results: List[GameResult],
    output_dir: str = "output/charts",
):
    """
    图表4 — 每轮独立胜率的对比 (分组柱状图)。

    【Python 知识点: 列表推导式 + 方法调用】
    [normal_rates.get(r, np.nan) * 100 for r in rounds]
    get(r, np.nan) 安全取值: 如果键 r 不存在返回 NaN 而非报错。
    在后几轮可能有些游戏已经结束，该轮不再有数据。
    NaN 在 matplotlib 中会被跳过（不画柱子）。
    """
    normal_rates = compute_round_by_round_win_rate(normal_results)
    rigged_rates = compute_round_by_round_win_rate(rigged_results)

    max_round = min(12, max(max(normal_rates.keys()),
                            max(rigged_rates.keys())))
    rounds = list(range(1, max_round + 1))
    normal_vals = [normal_rates.get(r, np.nan) * 100 for r in rounds]
    rigged_vals = [rigged_rates.get(r, np.nan) * 100 for r in rounds]

    # np.arange 用于分组柱状图的位置计算
    x = np.arange(len(rounds))
    width = 0.35

    fig, ax = plt.subplots(figsize=(12, 5.5))

    ax.bar(x - width/2, normal_vals, width, color=BLUE, alpha=0.85,
           edgecolor="white", linewidth=0.3, label="正常骰子")
    ax.bar(x + width/2, rigged_vals, width, color=ORANGE, alpha=0.85,
           edgecolor="white", linewidth=0.3, label="操纵骰子")

    ax.axhline(y=50, color=BLUE, linewidth=1.0, linestyle="--", alpha=0.4)
    ax.axhline(y=100/6, color=ORANGE, linewidth=1.0, linestyle="--", alpha=0.4)

    ax.text(max_round + 0.3, 50, "50%", ha="left", va="center",
            fontsize=8, color=BLUE, alpha=0.6)
    ax.text(max_round + 0.3, 100/6, "16.7%", ha="left", va="center",
            fontsize=8, color=ORANGE, alpha=0.6)

    ax.axvline(x=1.5, color=INK_MUTED, linewidth=0.8, linestyle=":",
               alpha=0.5)
    ax.text(1.5, 95, "← 正常 | 操纵 →", ha="center", fontsize=9,
            color=INK_MUTED,
            bbox=dict(facecolor=SURFACE, edgecolor="none", alpha=0.8, pad=2))

    ax.set_xlabel("投掷轮数")
    ax.set_ylabel("胜率 (%)")
    ax.set_title("各轮胜率对比 — 操纵骰子从第 3 轮开始生效",
                 fontweight="bold", pad=16)
    ax.set_xticks(x)
    # 【Python 知识点: f-string 在列表推导式中】
    # [f"第{r}轮" for r in rounds] → ["第1轮", "第2轮", ...]
    ax.set_xticklabels([f"第{r}轮" for r in rounds])
    ax.set_ylim(0, 65)
    ax.legend(loc="upper right", frameon=True)

    ax.yaxis.grid(True, alpha=0.5)
    ax.set_axisbelow(True)

    _savefig(fig, "04_round_win_rates.png", output_dir)


# ============================================================
#  Chart 5: 综合对比面板
# ============================================================
def plot_summary_comparison(
    normal_results: List[GameResult],
    rigged_results: List[GameResult],
    output_dir: str = "output/charts",
):
    """
    图表5 — 三合一综合对比面板。

    【Python 知识点: 列表字面量 vs list() 构造】
    [normal_pooled * 100, rigged_pooled * 100]
    直接写列表字面量比 list() 更快、更惯用。
    只在需要从其他可迭代对象转换时才用 list()。
    """
    normal_rolls = np.array([g.total_rolls for g in normal_results])
    rigged_rolls = np.array([g.total_rolls for g in rigged_results])

    normal_pooled = (sum(g.total_wins for g in normal_results) /
                     sum(g.total_rolls for g in normal_results))
    rigged_pooled = (sum(g.total_wins for g in rigged_results) /
                     sum(g.total_rolls for g in rigged_results))

    fig, axes = plt.subplots(1, 3, figsize=(14, 4.5),
                              constrained_layout=True)

    # --- 子图1: 期望轮数 ---
    ax = axes[0]
    means = [np.mean(normal_rolls), np.mean(rigged_rolls)]

    # 【Python 知识点: ddof 参数再强调】
    # ddof=1 获取的是样本标准差（分母 n-1）。
    # 因为我们用样本均值估计总体均值，失去一个自由度。
    stds = [np.std(normal_rolls, ddof=1), np.std(rigged_rolls, ddof=1)]

    ax.bar(["正常骰子", "操纵骰子"], means, color=[BLUE, ORANGE],
           width=0.5, edgecolor="white", linewidth=0.5)
    # errorbar: 在柱子上叠加误差棒
    ax.errorbar([0, 1], means, yerr=stds, fmt="none", color=INK_PRIMARY,
                linewidth=1.5, capsize=5, capthick=1.5)
    ax.set_title("期望轮数 (μ ± σ)", fontweight="bold")
    ax.set_ylabel("投掷轮数")
    for i, (m, s) in enumerate(zip(means, stds)):
        ax.text(i, m + s + 1.5, f"{m:.1f}±{s:.1f}", ha="center",
                fontsize=10, color=INK_SECONDARY)
    ax.yaxis.grid(True, alpha=0.5)
    ax.set_axisbelow(True)

    # --- 子图2: 合并胜率 ---
    ax = axes[1]
    wr_vals = [normal_pooled * 100, rigged_pooled * 100]
    ax.bar(["正常骰子", "操纵骰子"], wr_vals, color=[BLUE, ORANGE],
           width=0.5, edgecolor="white", linewidth=0.5)
    ax.set_title("合并胜率 (总胜场/总轮数)", fontweight="bold")
    ax.set_ylabel("胜率 (%)")
    ax.axhline(y=50, color=BLUE, linewidth=0.8, linestyle="--", alpha=0.3)
    ax.axhline(y=100*5/26, color=ORANGE, linewidth=0.8, linestyle="--",
               alpha=0.3, label=f"理论值: {100*5/26:.1f}%")
    for i, m in enumerate(wr_vals):
        ax.text(i, m + 0.5, f"{m:.1f}%", ha="center", fontsize=11,
                color=INK_SECONDARY, fontweight="bold")
    ax.legend(loc="lower right", fontsize=8)
    ax.yaxis.grid(True, alpha=0.5)
    ax.set_axisbelow(True)

    # --- 子图3: 箱线图 ---
    ax = axes[2]
    # 【Python 知识点: boxplot 返回字典】
    # bp 是一个字典，键为 'boxes', 'medians', 'whiskers' 等，
    # 值是对应图形对象的列表。可以后续修改属性。
    bp = ax.boxplot(
        [normal_rolls, rigged_rolls],
        patch_artist=True,
        widths=0.4,
        medianprops={"color": INK_PRIMARY, "linewidth": 1.5},
        whiskerprops={"color": INK_MUTED},
        capprops={"color": INK_MUTED},
        flierprops={"marker": ".", "markersize": 3, "alpha": 0.3,
                    "color": INK_MUTED},
    )
    ax.set_xticklabels(["正常骰子", "操纵骰子"])

    # 给箱子填色: bp["boxes"] 是包含两个箱子的列表
    # [0] = 正常骰子的箱子, [1] = 操纵骰子的箱子
    bp["boxes"][0].set_facecolor(BLUE)
    bp["boxes"][0].set_alpha(0.6)
    bp["boxes"][1].set_facecolor(ORANGE)
    bp["boxes"][1].set_alpha(0.6)

    ax.set_title("轮数分布箱线图", fontweight="bold")
    ax.set_ylabel("投掷轮数")
    ax.yaxis.grid(True, alpha=0.5)
    ax.set_axisbelow(True)

    # suptitle: Figure 级别的大标题（横跨所有子图）
    fig.suptitle("正常 vs 操纵骰子 — 关键指标对比",
                 fontweight="bold", fontsize=15, y=1.02)
    _savefig(fig, "05_summary_comparison.png", output_dir)


# ============================================================
# 批量生成 — 编排函数调用
# ============================================================

def generate_all_charts(
    normal_results: List[GameResult],
    rigged_results: List[GameResult],
    output_dir: str = "output/charts",
):
    """
    一键生成全部 5 张图表。

    【Python 知识点: 函数作为"编排器"】
    这个函数不包含任何图表绘制逻辑，只是按顺序调用其他函数。
    这种模式称为"编排"(orchestration)：
      - 每个函数负责单一职责
      - 编排函数负责组合和协调
      - 便于单独测试和修改某个图表

    【Python 知识点: os.path.abspath — 绝对路径】
    将相对路径转换为绝对路径。
    os.path.abspath("output/charts")
      → "E:\\Projects\\WorkerService1\\output\\charts"
    确保打印出的路径是用户可以直接在文件管理器中定位的完整路径。
    """
    print()
    print("生成分析图表...")
    print("-" * 32)

    setup_style()

    print("  [1/5] 三骰子和值分布...")
    plot_sum_distribution(output_dir)

    print("  [2/5] 大数定律收敛图...")
    plot_lln_convergence(normal_results, rigged_results, output_dir)

    print("  [3/5] 达到5胜所需轮数分布...")
    plot_rolls_distribution(normal_results, rigged_results, output_dir)

    print("  [4/5] 各轮胜率对比...")
    plot_round_win_rates(normal_results, rigged_results, output_dir)

    print("  [5/5] 综合对比...")
    plot_summary_comparison(normal_results, rigged_results, output_dir)

    print()
    print(f"全部图表已生成至: {os.path.abspath(output_dir)}/")
