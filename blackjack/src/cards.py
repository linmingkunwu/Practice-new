"""
扑克牌基础 — 牌、牌靴与手牌点值
=================================

【这个文件是做什么的？】
21 点游戏中最底层的"物理层"：定义牌的花色与点数、
构建可洗牌的牌靴（Shoe）、计算一手牌的点值与软/硬属性。
理论模块（theory.py）和模拟模块（game.py）都依赖这里的工具函数。

【注释风格说明】
本项目的注释与工程结构参考同仓库的 dice-game 项目
（骰子游戏 — 大数定律验证），沿用其教学式注解风格。

【涉及的核心数学概念】
• 古典概型: 一副牌 52 张，每种点数 4 张（四种花色）
• 不放回抽样: 牌被发出后不会回到牌靴 → 每次抽牌的概率随
  剩余牌而变化（这正是"算牌"能成立的数学根源）
• 超几何分布: 从有限总体中不放回抽样的计数分布；
  例如 6 副牌里还有多少张 A，服从超几何分布
• 排列与洗牌: 52 张牌的排列数 = 52! ≈ 8.07×10⁶⁷

【21 点的点数规则】
   A = 1 或 11（视手牌而定，见 hand_value）
   2~9 = 面值
   T/J/Q/K = 10（四种"十点牌"）
   "软手牌"(soft hand): 包含一张按 11 计算的 A；
   "硬手牌"(hard hand): 不包含按 11 计算的 A。
"""

# ============================================================
# 导入依赖
# ============================================================

# 【Python 知识点: random 模块】
# 与 dice-game 一样使用 Mersenne Twister 伪随机数生成器。
# 注意: 本文件不再直接调用 random.randint，而是创建
# random.Random(seed) 的"局部实例"——
# 好处见 build_shoe() 中的详细讲解。
import random

# 【Python 知识点: typing 类型注解】
# Tuple[str, ...]: 任意长度的 str 元组
# List[Card]: Card 对象的列表
# Optional[int]: int 或 None（表示"可以不传"）
from typing import Dict, List, Optional, Tuple


# ============================================================
# 模块级常量 — 游戏的全部"物理参数"
# ============================================================
# 【Python 知识点: 模块加载时执行】
# 下面这些代码在 import 本模块时立即执行（dice-game 的 dice.py
# 中也强调过这一点）。把常量集中放在顶部，是"静态配置"的惯例。

# 13 种点数。T 代表 10 点牌（Ten），J/Q/K 是花牌。
# 之所以把点数存成"单字符"，是为了方便后面的计数系统
# （算牌时按点数分类统计，不需要区分花色）。
RANKS: Tuple[str, ...] = (
    "A", "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K",
)

# 四种花色。♠♥♣♦ 是 Unicode 字符，终端中可以直接显示。
SUITS: Tuple[str, ...] = ("♠", "♥", "♣", "♦")

# 十点牌集合: T、J、Q、K。A 与十点牌组成"黑杰克"（natural）。
# frozenset 是不可变集合 —— 可以放进另一个集合、也可以作为
# 字典的键，比普通 set 更"安全"（不会被意外修改）。
TEN_RANKS = frozenset({"T", "J", "Q", "K"})

# 每张牌按"1"计时的点值（A 先记为 1，是否升为 11 由 hand_value 决定）
RANK_VALUE: Dict[str, int] = {
    "A": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8,
    "9": 9, "T": 10, "J": 10, "Q": 10, "K": 10,
}

# 每副牌 52 张 = 13 种点数 × 4 种花色
CARDS_PER_DECK = 52


def rank_value(rank: str) -> int:
    """返回一张牌按 1 计的点值（A=1，十点牌=10）。"""
    return RANK_VALUE[rank]


# ============================================================
# 数据结构 — 单张牌
# ============================================================

# 【Python 知识点: @dataclass 自动生成方法】
# dice.py 中详细讲过 @dataclass：它根据带类型注解的字段
# 自动生成 __init__ / __repr__ / __eq__ 等方法。
# 这里加了两个定制:
#   order=True (默认): 实例可以排序/比较
#   frozen=True: 字段只读 —— 牌发出去后点数花色不能变，
#   用不可变对象表达"值对象"语义更安全。
from dataclasses import dataclass


@dataclass(frozen=True, order=True)
class Card:
    """
    一张扑克牌。

    属性说明:
      rank: 点数字符（'A'~'9', 'T', 'J', 'Q', 'K'）
      suit: 花色字符（'♠', '♥', '♣', '♦'）
    注意: 为了算牌方便，我们不区分 T/J/Q/K（都是 10 点），
    但保留 J/Q/K 用于发牌时的直观显示。
    """
    rank: str
    suit: str

    # 【Python 知识点: @property 只读计算属性】
    # 与 dice-game 的 win_rate 同理：点值不是独立存储的字段，
    # 而是由 rank 实时计算得到，避免两处数据不一致。
    @property
    def value(self) -> int:
        """按 1 计的点值。"""
        return rank_value(self.rank)

    # 【Python 知识点: __str__ vs __repr__】
    # __repr__ 面向开发者（repr(obj) / 调试）；
    # __str__ 面向用户（print / f-string）。
    # 我们重写 __str__ 让打印更直观: Card(rank='T', suit='♠')
    # 直接显示成 "10♠"。
    def __str__(self) -> str:
        show = self.rank if self.rank != "T" else "10"
        return f"{show}{self.suit}"


# ============================================================
# 手牌点值 — A 的双重身份
# ============================================================

def hand_value(ranks: List[str]) -> Tuple[int, bool]:
    """
    计算一手牌的点值，返回 (总点数, 是否为软手牌)。

    【A 的处理 —— 21 点最核心的规则】
    1. 先把所有 A 都当作 1，得到"最小和" s
    2. 若手里有 A 且 s <= 11，则可以把一个 A 升级为 11:
       总点数 = s + 10，且这是"软手牌"
    3. 否则总点数 = s（硬手牌）

    为什么要 "s <= 11"？
      把 A 当作 11 等价于把和增加 10。
      只有当 s + 10 <= 21 即 s <= 11 时才不爆牌。

    【示例】
      ['A','6']   → s=7 ≤ 11 → (17, True)  软 17
      ['A','A']   → s=2 ≤ 11 → (12, True)  软 12（只有一个A按11计）
      ['A','T']   → s=11 ≤ 11 → (21, True) 黑杰克(21, 软)
      ['A','6','K'] → s=17 > 11 → (17, False) 硬 17（A只能算1了）
      ['T','T']   → (20, False) 硬 20

    【Python 知识点: 生成器表达式 + 内置 sum】
    sum(RANK_VALUE[r] for r in ranks) 是"生成器表达式"，
    惰性求和，不产生中间列表（dice.py 中讲过）。

    【Python 知识点: in 运算符】
    'A' in ranks 检查列表是否包含 'A'，O(n) 线性扫描。
    手牌最多十几张，开销可忽略。
    """
    low_sum = sum(RANK_VALUE[r] for r in ranks)  # 所有 A 按 1 计
    if "A" in ranks and low_sum <= 11:
        return low_sum + 10, True
    return low_sum, False


def card_hand_value(cards: List[Card]) -> Tuple[int, bool]:
    """
    与 hand_value 相同，但输入是 Card 对象列表（发牌器直接使用）。
    通过列表推导式提取点数后复用 hand_value。
    """
    return hand_value([c.rank for c in cards])


# ============================================================
# 牌靴 — 不放回抽样的实现
# ============================================================

def build_shoe_cards(deck_count: int, seed: Optional[int] = None) -> List[Card]:
    """
    构建 deck_count 副牌并洗匀，返回打乱后的 52×deck_count 张牌。

    【Python 知识点: 列表推导式的嵌套】
    [Card(rank, suit)
     for _ in range(deck_count)
     for rank in RANKS
     for suit in SUITS]
    等价于三层 for 循环，按"从左到右"的顺序展开:
      for _ in range(deck_count):     # 第一层: 几副牌
          for rank in RANKS:          # 第二层: 13 种点数
              for suit in SUITS:      # 第三层: 4 种花色
                  Card(rank, suit)

    【为什么是 52×deck_count 而不是给每种点数 4×deck_count 张"纯点数牌"？】
    因为"真实感"需要花色 —— 玩家看到 10♥ 和 10♠ 是不同的牌。
    但注意: 花色不影响任何概率计算，它们只是装饰。

    【Python 知识点: random.Random(seed) — 局部随机实例】
    直接 random.shuffle(x) 会使用"全局随机生成器"，
    其状态受任何地方调用 random.seed() 影响（dice-game 提过）。
    这里改用 random.Random(seed) 创建独立实例:
      ✓ 本函数内部状态自洽，外部 random 调用不影响洗牌结果
      ✓ 同一 seed 必然产生同一洗牌序列（可复现）
      ✗ 代价: 与全局生成器的序列无关，多花一丁点内存
    seed=None 时 Random() 从操作系统熵源取随机种子（真随机，不可复现）。

    【洗牌与排列】
    random.shuffle 实现的是 Fisher–Yates 洗牌算法:
    从后往前，对位置 i，从 [0, i] 随机选一个位置交换。
    52 张牌共有 52! 种排列 —— 比宇宙中的原子数还多，
    因此"通过洗牌规律作弊"在计算上不可行。
    """
    rng = random.Random(seed)
    cards = [
        Card(rank, suit)
        for _ in range(deck_count)
        for rank in RANKS
        for suit in SUITS
    ]
    rng.shuffle(cards)
    return cards


class Shoe:
    """
    牌靴: 管理多副牌的"不放回抽取"。

    【为什么用类而不是函数？】
    一靴牌需要跨很多回合持续维护状态:
      - 剩余哪些牌（顺序）
      - 已经发出哪些点数的牌（供算牌使用）
    dice-game 中用 dataclass GameResult 记录游戏过程，
    这里用带方法的普通类，因为它有"行为"而不只是"数据"。

    【牌靴与超几何分布】
    从 N 张剩余牌中抽一张牌，抽中某种点数的概率 = 该点数剩余数 / N。
    每抽一张，分母减 1 —— 这就是"不放回抽样"。
    放回抽样（无限牌库）对应的分母恒为 52×牌库数。
    真实赌场用前者，理论简化模型常用后者。
    """

    # 【Python 知识点: 类变量 vs 实例变量】
    # 类体内的 deck_count: int 只是类型注解（没有赋值），
    # 它必须在 __init__ 中作为实例变量被赋值。
    def __init__(self, deck_count: int = 6, seed: Optional[int] = None,
                 cut_fraction: float = 0.25):
        """
        参数说明:
          deck_count: 几副牌合在一起（赌场常见 6 副或 8 副）
          seed: 随机种子（None = 真随机）
          cut_fraction: 剩多少比例的牌就洗牌（"切牌卡"位置）。
            0.25 = 用掉约 75% 的牌后重新洗牌。
            切牌卡是算牌玩家的天敌: 切得越深（cut_fraction 越小），
            尾段高真数区（对玩家有利）越容易被完整利用。
        """
        self.deck_count = deck_count
        self.seed = seed
        self.cut_fraction = cut_fraction

        # 已经发出的牌按点数计数: {'A': 3, '2': 0, ...}
        # 【Python 知识点: 字典推导式】
        # {r: 0 for r in RANKS} 等价于手动写 13 行。
        self.dealt_counts: Dict[str, int] = {r: 0 for r in RANKS}

        self.reshuffle()

    def reshuffle(self) -> None:
        """重新洗牌（新靴开始 / 切牌卡触发）。

        注意: 本方法由"调用方"决定何时调用（引擎在每局开始前
        检查 needs_reshuffle）。如果 draw() 内部偷偷自动洗牌，
        引擎"打满一靴就换靴"的判断就永远无法触发—— 会无限循环。
        """
        self.cards = build_shoe_cards(self.deck_count, self.seed)
        self.dealt_counts = {r: 0 for r in RANKS}
        # 切牌卡位置: 剩余牌数少于此值就触发洗牌
        self.cut_at = int(self.cut_fraction * CARDS_PER_DECK * self.deck_count)

    # 【Python 知识点: 只读 property 封装内部状态】
    # 外部只能读 cards_remaining，不能直接改内部列表长度。
    @property
    def cards_remaining(self) -> int:
        """剩余牌数。"""
        return len(self.cards)

    @property
    def decks_remaining(self) -> float:
        """剩余牌折算成"几副牌"（浮点数）。

        【算牌中的真数 (True Count)】
        算牌时要把"流水数"除以"剩余副数"得到真数:
          True Count = Running Count / decks_remaining
        原因是流水数必须"按比例换算"才有意义:
        剩 5 副牌时流水数 +5 很普通，剩 0.5 副牌时 +5 极不寻常。
        """
        return self.cards_remaining / CARDS_PER_DECK

    def needs_reshuffle(self) -> bool:
        """是否触发切牌卡（剩余牌太少）？"""
        return self.cards_remaining <= self.cut_at

    def draw(self) -> Card:
        """
        从靴顶发一张牌（不放回）。

        【Python 知识点: list.pop() 的效率】
        list.pop() 不传参数时弹出"最后一个"元素，时间复杂度 O(1)；
        list.pop(0) 弹出第一个元素则需要把后面所有元素前移，O(n)。
        我们发牌总是取列表末尾: 卡片顺序已在洗牌时完全打乱，
        从哪一头取在概率上等价，因此选高效的末尾弹出。

        【调用约定】调用方必须保证洗牌时机正确: 若牌已用尽
        （cards_remaining == 0），抛出 RuntimeError 而不是
        偷偷洗牌 —— 洗牌是"换靴"的标志，必须由引擎显式控制。
        一局进行中跨过切牌卡是允许的（本手牌打完才洗牌），
        所以这里只防"真空"。
        """
        if not self.cards:
            raise RuntimeError(
                "牌靴已空: 切牌比例过小时单局可能耗尽牌靴，"
                "请增大 cut_fraction。"
            )
        card = self.cards.pop()
        self.dealt_counts[card.rank] += 1
        return card

    def remaining_count(self, rank: str) -> int:
        """
        某种点数还剩多少张。

        【数学背景 — 超几何分布】
        6 副牌初始有 24 张 A。已知已发出 a 张 A 后，
        剩余 A 数 = 24 - a，是确定性的（不是随机的！）。
        真正的随机性在于: 已经发出的 a 张 A 本身服从超几何分布，
        所以"剩余 A 数"是一个随机变量。
        算牌的实质就是通过观察已发牌来估计剩余牌的结构。
        """
        return self.deck_count * 4 - self.dealt_counts[rank]

    def __len__(self) -> int:
        """支持 len(shoe) 直接取剩余牌数。"""
        return self.cards_remaining
