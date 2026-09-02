"""
玩家策略 — 从随机乱打到科学算牌
=================================

【这个文件是做什么的？】
把"玩家怎么打"抽象成可替换的策略对象。同一个引擎
（game.py）可以驱动随机策略、固定阈值策略、基础策略
和算牌策略，从而在统计上公平地对比它们的优劣。

【涉及的核心数学与决策概念】
• 决策函数: 策略 = "根据局面选择行动"的映射 (局面 → 行动)
• 贪心/阈值策略: "点数 ≥17 就停"这类简单规则
• 查找表策略: 基础策略把理论模块算好的最优行动表查出来
• 算牌(Counting): 通过统计已出牌推算剩余牌结构。
  Hi-Lo 系统给牌打分: 2~6 记 +1，7~9 记 0，10/A 记 -1。
  流水数(Running Count)高 → 剩余牌中 10 点多 → 对玩家有利
  （庄家更容易爆牌、玩家更容易出黑杰克/21）
• 真数(True Count) = 流水数 ÷ 剩余副数 —— 把计分按"浓度"
  归一化，是算牌的科学核心
• 风险与下注: 真数高时加大赌注（"看牌下注"），
  数学上等价于把资金倾斜到正期望的时机上

【策略一览】
  策略             特点                             期望(无限牌库,理论)
  RandomStrategy   全随机（掷硬币式决策）            很差（实测每局约 -0.34 单位）
  ThresholdStrategy 点数 ≥ 阈值就停，不加倍            阈值 17 = 模仿庄家 ≈ -5.7%
  BasicStrategy    查理论最优行动表                     ≈ -1.1%（含加倍）
  CountingStrategy 基础策略 + Hi-Lo 算牌 + 梯级下注     需要鞋式牌局 + 统计验证
"""

# ============================================================
# 导入依赖
# ============================================================

# 【Python 知识点: 类型注解与文档字符串的约定】
# ctx: PlayContext —— 所有策略接收同一个"局面上下文"对象，
# 引擎与策略的接口因此稳定。
import random
from dataclasses import dataclass
from typing import Literal, Optional, Tuple

# 行动类型与 theory 保持一致
Action = Literal["S", "H", "D"]

# Hi-Lo 计分表（模块级常量，算牌系统的"评分规则"）
# 【数学: 为什么 2~6 记 +1、10/A 记 -1？】
# 每副牌中 2~6 共 20 张（约 38.5%），10/A 共 20 张（16 张十点+4 张 A）。
# 高张(10/A)对玩家有利，低张(2~6)对庄家有利（庄家不容易爆牌）。
# 计分系统让"剩余牌对谁有利"变成单一数字。
_HI_LO = {
    "A": -1, "2": +1, "3": +1, "4": +1, "5": +1, "6": +1, "7": 0,
    "8": 0, "9": 0, "T": -1, "J": -1, "Q": -1, "K": -1,
}

# 一副完整的 Hi-Lo 计数和为 0（"平衡计数系统"），
# 这是 Hi-Lo 便于心算的原因之一。


def true_count_of(shoe) -> float:
    """
    给定牌靴计算当前真数（模块级工具，引擎也需要用）。
    shoe 为 None（无限牌库）时返回 0.0。
    """
    if shoe is None:
        return 0.0
    dealt = shoe.dealt_counts
    running = sum(dealt[r] * _HI_LO[r] for r in dealt)
    decks = shoe.decks_remaining
    if decks <= 0.01:
        decks = 1.0
    return running / decks


# ============================================================
# 局面上下文 — 引擎与策略之间的"接口契约"
# ============================================================

@dataclass
class PlayContext:
    """
    一次决策所需的全部信息（引擎每轮询问策略时构造）。

    属性说明:
      total: 玩家当前点数（21 点上限内的值）
      soft: 是否软手牌
      two_card: 是否仍是首两张（决定能否加倍）
      upcard: 庄家首牌点数（'A'/'2'/.../'K'）
      hand_ranks: 玩家当前手牌的点数列表（用于需要看牌型的策略）
      shoe: 当前牌靴对象；None 表示无限牌库模拟（无法算牌）
    """
    total: int
    soft: bool
    two_card: bool
    upcard: str
    hand_ranks: Tuple[str, ...]
    shoe: Optional[object] = None  # 用 object 避免循环导入（type: Shoe）


# ============================================================
# 策略基类
# ============================================================

class BaseStrategy:
    """
    所有策略的基类。子类只需实现 decide()，
    默认每次下注 1 单位（固定注）。

    【Python 知识点: 继承与方法覆写】
    子类覆写父类方法时，签名应保持一致（鸭子类型）。
    引擎通过 isinstance/duck typing 调用，不关心具体类型。
    """

    def __init__(self, name: str = "策略"):
        self.name = name

    def decide(self, ctx: PlayContext) -> Action:
        """根据局面返回行动。子类必须覆写。"""
        raise NotImplementedError

    def bet_units(self, ctx: PlayContext) -> int:
        """本回合下注多少单位（默认固定 1）。"""
        return 1

    def __repr__(self) -> str:
        return f"<{self.name}>"


# ============================================================
# 策略 1: 随机策略 — "闭着眼睛打"
# ============================================================

class RandomStrategy(BaseStrategy):
    """
    以固定概率随机选行动:
      停牌 45%，要牌 45%，加倍 10%（仅首两张时才有加倍资格）。
    这是"零信息决策"的对照组 —— 任何优于它的策略
    都说明"信息 + 规则"在起作用。

    【数学: 随机策略的期望为什么很差？】
    该策略在 16 vs 6 这种"应该停"的局面也有 45% 概率要牌，
    在 11 vs 6 这种"应该加倍"的局面却大概率不加倍 ——
    期望被系统性拉低。统计部分会给出它的实测数值。
    """

    def __init__(self):
        super().__init__(name="随机策略")

    # 随机决策: 每次调用都重新掷"骰子"决定行动。
    # 用模块级 random（受 monte_carlo_shoe 的 seed 控制，
    # 保证同一 seed 下实验可复现）。
    def decide(self, ctx: PlayContext) -> Action:
        roll = random.random()
        if ctx.two_card and roll < 0.10:
            return "D"
        return "H" if roll < 0.55 else "S"


# ============================================================
# 策略 2: 阈值策略 — "到 17 就收手"
# ============================================================

class ThresholdStrategy(BaseStrategy):
    """
    点数达到阈值就停牌，否则一直要牌；从不加倍。

    【与"模仿庄家"的关系】
    阈值取 17 时，玩家行为与庄家完全相同（<17 要、≥17 停，
    软 17 也停）—— 这就是文献中的"模仿庄家"策略，
    期望 ≈ -5.7%（理论模块会打印）。

    【数学: 阈值策略为什么差？】
    它看不到庄家的首牌！16 vs 6（庄家易爆）与 16 vs 10
    （庄家难爆）在它眼里是同一个局面 —— 信息被丢弃了。
    """

    def __init__(self, hold_at: int = 17):
        super().__init__(name=f"阈值策略(到{hold_at}停)")
        self.hold_at = hold_at

    def decide(self, ctx: PlayContext) -> Action:
        if ctx.total < self.hold_at:
            return "H"
        return "S"


# ============================================================
# 策略 3: 基础策略 — 查最优行动表
# ============================================================

class BasicStrategy(BaseStrategy):
    """
    严格按照理论模块算出的最优行动表决策（无限牌库意义上的最优）。
    这是"人类能背下来的最佳打法"，统计部分用它作为对照组。

    【说明】
    真实赌场用多副牌(组成效应)时，个别局面与无限牌库的最优
    行动略有出入（例如 12 vs 2 在牌里 10 偏多时该停牌）。
    基础策略忽略这些二阶差异 —— 误差在 0.1% 量级。
    """

    def __init__(self):
        super().__init__(name="基础策略")

    def decide(self, ctx: PlayContext) -> Action:
        # 延迟导入: 避免 strategies ↔ theory 的循环导入风险
        from .theory import optimal_action
        return optimal_action(ctx.total, ctx.soft, ctx.two_card, ctx.upcard)


# ============================================================
# 策略 4: 算牌策略 — 基础策略 + Hi-Lo 真数下注
# ============================================================

class CountingStrategy(BaseStrategy):
    """
    基础策略 + Hi-Lo 算牌:
      1. 记流水数: 每张已出的牌按 _HI_LO 打分累加
      2. 换真数:   真数 = 流水数 ÷ 剩余副数
      3. 梯级下注: 真数低时下最小注，真数高时下大注
      4. 索引偏离: 少数局面偏离基础策略（如 16 vs 10 在
         真数 ≥0 时停牌），即"索引行动"(index plays)

    【为什么真数高时优势转向玩家？】
    剩余牌中 10/A 浓度越高:
      - 玩家与庄家拿到黑杰克的频率同步上升，但黑杰克赔 1.5 倍
        → 玩家从中获益更多
      - 庄家停在 12~16 的"尴尬点"时更容易补爆（10 直接爆）
      - 玩家停在 12~16 时同样更易爆 —— 但玩家可以选择在
        高真数时对 16 vs 10 停牌（索引行动），把损失让给庄家
    经验上（文献与大量模拟）: 真数每 +1，玩家期望约上升 0.5%，
    这就是"下注随真数上升"的数量依据。

    【梯级下注表】(下注单位 = 真数的阶梯函数，默认配置)
      真数 ≤1 → 1；2 → 4；3 → 8；4 → 12；5 → 16；≥6 → 20
    多数回合（约 3/4）真数 ≤1 只下最小注；阶梯大注只出现在
    少数高真数回合 —— 整体平均注实测约 2.3 单位。
    （演示用 1-20 注的激进斜坡；实际赌场会有限红与切牌卡压制，
     且 20 注 × 高方差需要非常雄厚的资金，见 analysis 的风险提示。）
    """

    def __init__(self, min_bet: int = 1, max_bet: int = 20):
        super().__init__(name=f"算牌策略({min_bet}-{max_bet}注)")
        self.min_bet = min_bet
        self.max_bet = max_bet
        # 真数(向下取整) → 下注单位
        self.ramp = {2: 4, 3: 8, 4: 12, 5: 16}

    # --------------------------------------------------------
    # 计数工具
    # --------------------------------------------------------

    def running_count(self, ctx: PlayContext) -> int:
        """
        流水数: 所有已出牌分数的累加。

        【实现注意】
        牌靴记录了 dealt_counts（每种点数已出张数），
        计数 = Σ dealt_counts[r] × _HI_LO[r]。
        Shoe 本身不关心计数 —— 计数是"玩家的视角"，
        放在策略里保持引擎与赌具的中立性。
        """
        if ctx.shoe is None:
            return 0
        dealt = ctx.shoe.dealt_counts
        return sum(dealt[r] * _HI_LO[r] for r in dealt)

    def true_count(self, ctx: PlayContext) -> float:
        """
        真数 = 流水数 ÷ 剩余副数。
        decks_remaining = 剩余张数 / 52（浮点数）。
        """
        if ctx.shoe is None:
            return 0.0
        decks = ctx.shoe.decks_remaining
        if decks <= 0.01:  # 防御: 剩余不足一张牌时近似为 1 副
            decks = 1.0
        return self.running_count(ctx) / decks

    def _tc_floor(self, ctx: PlayContext) -> int:
        """向下取整的真数（下注与索引决策都按整数真数）。"""
        return int(self.true_count(ctx))

    # --------------------------------------------------------
    # 决策与下注
    # --------------------------------------------------------

    def bet_units(self, ctx: PlayContext) -> int:
        """梯级下注: 真数 → 单位数。

        【重要: 低真数下小注、高真数下大注】
        映射表只覆盖正真数区间:
          tc ≤ 1 → min_bet（含所有负真数 —— 用 if 提前拦截，
          否则 dict.get(tc, ...) 会把没登记的负 tc 落到默认值！）
          tc = 2..5 → 阶梯递增
          tc ≥ 6 → max_bet
        这是"赌注与优势同向"的量化实现:
        把大注留给真数最高的少数回合。
        """
        tc = self._tc_floor(ctx)
        # 【Python 知识点: min/max 截断 + 字典查表】
        # 用字典映射比一长串 if/elif 更清晰；负真数必须显式拦截
        # （否则 dict.get(tc, ...) 会把没登记的负 tc 落到最大值）。
        if tc <= 1:
            return self.min_bet
        return min(self.max_bet, max(self.min_bet,
                                     self.ramp.get(tc, self.max_bet)))

    def decide(self, ctx: PlayContext) -> Action:
        # 先按基础策略, 再套用少数"索引行动"
        from .theory import optimal_action
        action = optimal_action(ctx.total, ctx.soft, ctx.two_card, ctx.upcard)
        if not ctx.soft and ctx.upcard in ("T", "J", "Q", "K"):
            tc = self._tc_floor(ctx)
            # 16 vs 10: 真数 ≥0 时停牌（基础策略是要牌）
            if ctx.total == 16 and tc >= 0:
                return "S"
            # 15 vs 10: 真数 ≥4 时停牌
            if ctx.total == 15 and tc >= 4:
                return "S"
        return action
