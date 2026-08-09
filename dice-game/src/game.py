"""
蒙特卡洛模拟 — 三骰子游戏的计算机模拟
======================================

【这个文件是做什么的？】
用计算机生成大量随机游戏，模拟真实投骰子的过程。
通过统计成千上万局游戏的结果，验证理论计算的正确性。

【什么是蒙特卡洛模拟？】
蒙特卡洛方法(Monte Carlo method)是一种通过大量随机抽样来
近似计算数学问题的方法。名字来源于摩纳哥的赌场城市，
因为这种方法本质上就是在"赌博"——用随机性来求解问题。

【涉及的核心概念】
• 随机数生成: 计算机如何模拟骰子的随机性
• 伪随机数: 计算机生成的"随机"其实是确定性的算法
• 随机种子(seed): 控制随机序列的起点，保证结果可复现
• 大样本近似: 模拟次数越多，结果越接近真实值
"""

# ============================================================
# 导入依赖
# ============================================================

# 【Python 知识点: random 模块】
# Python 的 random 模块使用 Mersenne Twister 算法生成伪随机数。
# 它是目前最广泛使用的通用伪随机数生成器之一。
#
# 核心函数:
#   random.randint(a, b): 生成 [a, b] 范围内的随机整数（含两端）
#   random.seed(n): 重置随机数生成器的状态到固定起点
#   random.random(): 生成 [0.0, 1.0) 的随机浮点数
#
# 【注意】random 模块不适合加密用途！
# 加密场景请使用 secrets 模块（Python 3.6+）。
import random

# 【Python 知识点: dataclass 的 field() 函数】
# field() 用于定制 dataclass 中单个字段的行为。
# 最常用的选项:
#   default: 默认值（与直接写 =value 等价）
#   default_factory: 接收一个无参函数，每次创建实例时调用它来生成默认值
#   repr: 是否包含在 __repr__ 输出中（默认 True）
#   compare: 是否参与 __eq__ 比较（默认 True）
#
# 为什么需要 default_factory？
#   rounds: List = []   ← 危险！所有实例共享同一个列表对象
#   rounds: List = field(default_factory=list)  ← 安全！每次创建新列表
# 原因: Python 只在类定义时计算一次默认值，而不是每次创建实例时。
# 所以可变默认值会被所有实例共享——这是 Python 最著名的陷阱之一。
from dataclasses import dataclass, field

# 【Python 知识点: typing 模块的泛型类型】
# List[RoundResult]: 元素为 RoundResult 类型的列表
# Dict: 字典（键→值的映射）
# Optional[int]: Union[int, None] 的简写，"int 或 None"
#   Python 3.10+ 可用 int | None 替代 Optional[int]
from typing import List, Dict, Literal, Optional

# ============================================================
# 类型定义
# ============================================================

Bet = Literal["big", "small"]


# ============================================================
# 数据结构 — 用 dataclass 记录游戏过程
# ============================================================

@dataclass
class RoundResult:
    """
    单轮投掷的完整记录。

    属性说明:
      round_number: 第几轮（从 1 开始递增）
      bet: 押注方向
      dice_values: 三个骰子点数 [d1, d2, d3]
      total: 总和 = sum(dice_values)
      is_big: 是否"大"（和 > 10）
      won: 是否猜中
      is_rigged: 该轮是否启动操纵骰子
    """
    round_number: int
    bet: Bet
    dice_values: List[int]
    total: int
    is_big: bool
    won: bool
    is_rigged: bool


@dataclass
class GameResult:
    """
    一局游戏的完整记录。

    【field(default_factory=list) 详解】
    为什么不用 rounds: List[RoundResult] = []？
    如果你写:
      game1 = GameResult(...)
      game2 = GameResult(...)
      game1.rounds.append(...)
    那么 game2.rounds 也会包含 game1 添加的元素！
    因为它们共享了同一个 list 对象。
    default_factory=list 确保每个实例获得一个全新的独立列表。
    """
    n_wins_target: int
    rigged: bool
    bet: Bet

    # 【Python 知识点: field() 的参数】
    # default_factory 接收一个"可调用对象"（函数、类等），不是调用结果。
    # 正确: field(default_factory=list)  ← 传入 list 类本身
    # 错误: field(default_factory=list())  ← 传入空列表（会被所有实例共享！）
    rounds: List[RoundResult] = field(default_factory=list)

    total_rolls: int = 0
    total_wins: int = 0
    total_losses: int = 0

    # 【Python 知识点: @property 装饰器】
    # @property 将一个方法变成"属性"（attribute）。
    # 调用时不需要括号: game.win_rate（而不是 game.win_rate()）
    #
    # 好处:
    #   1. 语义更清晰（它代表对象的一个"属性"，不是"动作"）
    #   2. 可以在不改外部代码的情况下，将简单属性升级为计算属性
    #   3. 配合 @xxx.setter 可以实现赋值时的验证逻辑
    #
    # 【注意】property 是只读的（没有定义 setter）。
    # 如果尝试 game.win_rate = 0.5 会报 AttributeError。
    @property
    def win_rate(self) -> float:
        """
        这局游戏的整体胜率 = 猜中次数 / 总轮数。

        【注意: "胜率"不等于"单轮获胜概率"】
        由于游戏在达到 n_wins_target 胜时停止，
        胜率 = n_wins_target / total_rolls。
        这不是每轮的独立胜率，而是整局的结果汇总。
        """
        if self.total_rolls == 0:
            return 0.0
        return self.total_wins / self.total_rolls


# ============================================================
# 骰子投掷 — 伪随机数的使用
# ============================================================

def roll_normal_dice(n: int = 3) -> List[int]:
    """
    投掷 n 个公平骰子。

    【Python 知识点: 列表推导式的又一种写法】
    [random.randint(1, 6) for _ in range(n)]
                        ↑ 注意这个下划线 ↑
    _ 是 Python 中的惯用写法，表示"这个变量的值我不关心"。
    因为循环体中不需要知道是第几次迭代，只需要重复 n 次。
    用 _ 让读者一眼就知道循环变量不被使用。

    【random.randint 的范围】
    random.randint(1, 6) 返回 [1, 6] 区间内的整数，包含两端。
    这和其他语言的"左闭右开"惯例不同！
    例如 numpy 的 np.random.randint(1, 7) 是 [1, 7) = [1, 6]。
    使用时要注意文档。
    """
    return [random.randint(1, 6) for _ in range(n)]


def roll_rigged_dice(bet: Bet, n: int = 3, rigged_index: int = 0) -> List[int]:
    """
    投掷含一个被操纵骰子的 n 个骰子。

    【Python 知识点: 条件表达式（三元运算符）】
    rigged_value = 1 if bet == "big" else 6
    等价于:
      if bet == "big":
          rigged_value = 1
      else:
          rigged_value = 6
    但更简洁。Python 的三元语法是 "A if 条件 else B"，
    和其他语言 "条件 ? A : B" 不同。
    适合简单的二选一，复杂逻辑还是用 if/else 更清晰。
    """
    rigged_value = 1 if bet == "big" else 6

    # 逐个生成骰子值
    dice = []
    for i in range(n):
        if i == rigged_index:
            dice.append(rigged_value)           # 被操纵的骰子
        else:
            dice.append(random.randint(1, 6))   # 正常骰子
    return dice


# ============================================================
# 游戏逻辑 — while 循环 + 条件判断
# ============================================================

def play_game(
    n_wins: int = 5,
    rigged: bool = False,
    bet: Bet = "big",
    rigged_start_round: int = 3,
    seed: Optional[int] = None,
) -> GameResult:
    """
    模拟完整的一局游戏。

    【Python 知识点: Optional[int] 的含义】
    seed: Optional[int] = None 等价于 seed: int | None = None。
    表示这个参数可以是一个整数，也可以是 None。
    这是 Python 表示"可选参数"的类型安全写法。

    【Python 知识点: while 循环】
    while result.total_wins < n_wins:
        round_num += 1
        ...
    while 循环在条件为 True 时一直执行。
    这里没有固定的循环次数——游戏可能在 5 轮或 100 轮结束。

    注意: 必须确保循环条件最终会变为 False，
    否则会无限循环。对操纵骰子来说，胜率 1/6 > 0，
    所以一定会达到 n_wins 胜，不会死循环。

    【Python 知识点: random.seed() 的作用域】
    调用 random.seed(x) 会设置全局随机数生成器的状态。
    后续所有对 random 模块的调用都受此影响。
    所以如果先用 seed(42) 生成了一些随机数，再 seed(42) 重置，
    会重新生成相同的序列。这是"可复现性"的基础。
    """
    if seed is not None:
        random.seed(seed)

    result = GameResult(
        n_wins_target=n_wins,
        rigged=rigged,
        bet=bet,
    )

    round_num = 0
    while result.total_wins < n_wins:
        round_num += 1
        is_rigged_round = rigged and round_num >= rigged_start_round

        if is_rigged_round:
            dice_values = roll_rigged_dice(bet)
        else:
            dice_values = roll_normal_dice()

        total = sum(dice_values)
        is_big = total > 10

        # 【Python 知识点: 布尔逻辑运算】
        # (A and B) or (C and not D) — Python 的布尔运算符
        # and: 两边都为 True 才返回 True
        # or: 至少一边为 True 就返回 True
        # not: 取反
        # 运算符优先级: not > and > or
        won = (bet == "big" and is_big) or (bet == "small" and not is_big)

        # 记录本轮完整信息
        result.rounds.append(RoundResult(
            round_number=round_num,
            bet=bet,
            dice_values=dice_values,
            total=total,
            is_big=is_big,
            won=won,
            is_rigged=is_rigged_round,
        ))

        if won:
            result.total_wins += 1
        else:
            result.total_losses += 1

    result.total_rolls = round_num
    return result


# ============================================================
# 批量模拟 — for 循环 + 列表累积
# ============================================================

def monte_carlo(
    n_games: int = 100000,
    n_wins: int = 5,
    rigged: bool = False,
    bet: Bet = "big",
    seed: Optional[int] = None,
) -> List[GameResult]:
    """
    蒙特卡洛批量模拟 — 运行 n_games 局游戏。

    【Python 知识点: List[GameResult] 返回类型】
    这个函数返回一个列表，包含 n_games 个 GameResult 对象。
    100,000 局游戏的结果全部保存在内存中。
    每个 GameResult 包含所有轮次的记录，所以内存占用较大:
      正常: ~1M 个 RoundResult  ≈  ~80 MB
      操纵: ~2.6M 个 RoundResult ≈ ~200 MB
    对于现代计算机来说完全可接受。

    【每局独立种子的设计】
    game_seed = seed + i 是简单但有效的策略。
    但要注意: 如果 seed=None，game_seed 也是 None，
    此时每局使用系统熵源的真随机种子，不可复现。

    【Python 知识点: range(n) 生成器】
    range(100000) 不会创建 100000 个元素的列表！
    它是一个懒加载的序列对象，只在迭代时逐个产生值。
    Python 3 中 range() 返回的不是 list，内存占用 O(1)。
    """
    if seed is not None:
        random.seed(seed)

    results = []
    for i in range(n_games):
        # 【Python 知识点: 条件表达式用于参数】
        # seed + i if seed is not None else None
        # 必须处理 None 的情况，否则 None + i 会报 TypeError
        game_seed = seed + i if seed is not None else None
        result = play_game(
            n_wins=n_wins,
            rigged=rigged,
            bet=bet,
            seed=game_seed,
        )
        results.append(result)

    return results


def run_simulation(n_games: int = 100000) -> Dict:
    """
    运行完整的对比模拟: 正常 vs 操纵。

    【Python 知识点: Dict 返回类型】
    返回字典而非对象的场景:
      - 键集合在运行时动态确定
      - 结构简单（只有几个键）
      - 调用方直接用 [] 或 .get() 访问
    对于更复杂/固定的结构，建议用 dataclass 代替裸字典。

    【Python 知识点: print 中的千分位格式】
    {n_games:,} — 逗号格式说明符在数字中插入千分位分隔符。
    100000 → "100,000"
    依赖于操作系统的区域设置（中文 Windows 用逗号）。
    """
    print(f"正在模拟 {n_games:,} 局正常骰子游戏...")
    normal_results = monte_carlo(
        n_games=n_games, n_wins=5, rigged=False, bet="big", seed=42
    )

    print(f"正在模拟 {n_games:,} 局操纵骰子游戏...")
    rigged_results = monte_carlo(
        n_games=n_games, n_wins=5, rigged=True, bet="big", seed=42
    )

    print("模拟完成。")

    return {
        "n_games": n_games,
        "normal": normal_results,
        "rigged": rigged_results,
    }
