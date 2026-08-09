"""
骰子概率计算 — 三骰子游戏的理论概率分布
============================================

【这个文件是做什么的？】
用数学公式精确计算骰子游戏中各种事件的概率，不依赖模拟。
这些理论值是后续蒙特卡洛模拟的"标准答案"。

【涉及的核心数学概念】
• 古典概型: 所有结果等可能时，概率 = 有利结果数 / 总结果数
• 负二项分布: 获得第 r 次成功所需的总试验次数
• 全期望/全方差公式: 分阶段计算复杂随机过程的期望和方差
• 大数定律(LLN): 试验次数越多，样本均值越接近理论期望

【骰子游戏的数学本质】
三个六面骰子 → 6×6×6 = 216 种等可能结果
和值范围: 3 (1+1+1) ~ 18 (6+6+6)
"小" = 和 ≤ 10, "大" = 和 > 10
巧合: 正好各 108 种，概率各 50%
"""

# ============================================================
# 导入依赖 — Python 的模块系统
# ============================================================
# Python 通过 import 语句引入其他模块的功能。
# 导入可以发生在文件的任何位置，但惯例是全部放在文件顶部。
# 导入顺序: 标准库 → 第三方库 → 本地模块（中间空行分隔）
#
# 【Python 模块搜索路径】
# 当你写 from itertools import product 时，Python 按以下顺序查找:
#   1. 当前文件所在目录
#   2. PYTHONPATH 环境变量中的目录
#   3. 标准库目录
#   4. site-packages（pip 安装的第三方包）
# 这意味着如果你创建了一个叫 itertools.py 的文件，它会"遮蔽"标准库！

# itertools.product: 生成笛卡尔积（Cartesian Product）
#   【笛卡尔积是什么？】
#   两个集合的笛卡尔积是"所有可能的配对"。
#   例如 {A,B} × {1,2} = {(A,1),(A,2),(B,1),(B,2)}
#   product([1,2,3], repeat=2) → (1,1),(1,2),(1,3),(2,1)...
#   repeat=3 表示 [1..6] × [1..6] × [1..6]（三个骰子）
#
#   【Python 知识: product 返回的是"迭代器"】
#   迭代器是一种"懒加载"的对象，只在需要时才生成下一个值。
#   这比一次性生成所有数据更省内存。
#   我们用 list(product(...)) 把它转成列表，因为后面要多次使用。
from itertools import product

# collections.Counter: 计数器
#   【Counter 是什么？】
#   Counter 是 dict 的子类，专门用来计数。
#   传入一个可迭代对象（如列表），它自动统计每个元素出现的次数。
#   Counter([7, 7, 8, 8, 8]) → Counter({8: 3, 7: 2})
#   可以用 .items() 遍历 → (7, 2), (8, 3)
#   它比手动写 for 循环 + dict 累加更简洁高效。
from collections import Counter

# dataclasses.dataclass: 数据类装饰器
#   【@dataclass 做了什么？】
#   Python 的类通常需要手写 __init__、__repr__、__eq__ 等方法。
#   @dataclass 装饰器会根据类属性自动生成这些方法。
#   对比:
#     # 传统写法（约20行）
#     class Point:
#         def __init__(self, x, y): self.x = x; self.y = y
#         def __repr__(self): return f"Point(x={self.x}, y={self.y})"
#         def __eq__(self, o): return self.x == o.x and self.y == o.y
#     # @dataclass 写法（3行）
#     @dataclass
#     class Point:
#         x: float
#         y: float
#
#   【装饰器是什么？】
#   @something 放在函数/类定义前，本质上是:
#     class DiceProbabilities: ...       # 定义类
#     DiceProbabilities = dataclass(DiceProbabilities)  # 传给装饰器函数，替换原定义
#   装饰器可以在不修改原代码的情况下"增强"函数/类的功能。
from dataclasses import dataclass

# functools.cache: 函数结果缓存
#   【什么是缓存/Memoization？】
#   把函数的输入→输出结果存起来。下次同样的输入，不重新计算，直接返回缓存值。
#   这用空间换时间: 多点内存占用，但省去重复计算。
#
#   【@cache 的适用条件】
#   函数必须是"纯函数"（pure function）:
#     ✓ 同样输入永远产生同样输出（确定性的）
#     ✓ 不依赖外部状态（不读文件、不读全局变量）
#     ✓ 不修改外部状态（无副作用）
#   如果函数有随机性（如 random.randint），缓存会导致每次返回相同的"随机"值！
#
#   【Python 3.9+ 才有的 @cache】
#   老版本用 @lru_cache(maxsize=None) 替代。@cache 是其简化版。
from functools import cache

# typing: 类型注解工具
#   【类型注解是做什么的？】
#   告诉读者（和IDE）"这个变量应该是什么类型"。
#   但注意: Python 不会在运行时强制检查类型！
#   类型注解纯粹是"文档"性质的，用于:
#     - IDE 代码补全和错误提示
#     - mypy/pyright 等静态类型检查工具
#     - 提高代码可读性
#
#   Dict[int, float]: 泛型类型，表示"键是int、值是float的字典"
#   Tuple[float, float]: 定长元组，"两个float"
#   Literal["big", "small"]: 字面量类型，"只能是这两个字符串之一"
#   Python 3.9+ 可以用小写 dict[int, float] 替代 Dict[int, float]
#   但 Dict 写法兼容老版本，仍是业界主流
from typing import Dict, Tuple, Literal

# scipy.stats.binom: 二项分布的统计函数
#   【scipy 是什么？】
#   SciPy 是 Python 的科学计算库，建立在 NumPy 之上。
#   scipy.stats 子模块包含各种概率分布的数学函数。
#   这种"from package.submodule import something" 的写法
#   是 Python 深层模块导入的标准方式。
#
#   【二项分布 Binomial(n, p)】
#   做 n 次独立试验，每次成功概率 p。X = 成功次数。
#   binom.pmf(k, n, p): Probability Mass Function，P(X=k)
#   binom.cdf(k, n, p): Cumulative Distribution Function，P(X≤k)
from scipy.stats import binom

# ============================================================
# 类型定义 — 用 Literal 约束可选值
# ============================================================
# Literal 是 Python 3.8 引入的类型提示，用于限制变量只能取特定字面值。
# 如果不小心写成了 Bet = "medium"，IDE 会立即标红提示错误。
# 这比用 str 类型更安全，也比定义 Enum 更轻量。
Bet = Literal["big", "small"]


# ============================================================
# 预计算常量 — 模块级别的"静态配置"
# ============================================================
# 【Python 知识点: 模块加载时执行】
# 下面这几行代码在 import 这个模块时就会执行（不是等到函数被调用时）。
# Python 执行 .py 文件是从上到下的: 遇到 class/def 会"定义"它们，
# 但遇到普通语句会立即执行。所以这些常量在模块加载后就计算好了。
#
# 【命名约定: 下划线前缀 _NAME】
# Python 中用 _ 开头表示"这是内部实现细节，外部不应直接使用"。
# 这不是强制性的（Python 没有真正的 private），但是一种约定。
# 如果你写 from dice import *，_ 开头的名字不会被导出。
#
# 【Python 知识点: product 和 list()】
# product(range(1,7), repeat=2) 返回一个迭代器（不是列表）。
# 迭代器只能遍历一次，且不支持 len() 和索引 [i]。
# 用 list() 转成列表后，可以多次使用、获取长度、随机访问。
_TWO_DICE_OUTCOMES = list(product(range(1, 7), repeat=2))
_TWO_DICE_TOTAL = len(_TWO_DICE_OUTCOMES)  # = 36

# 【Python 知识点: 生成器表达式 (Generator Expression)】
# sum(1 for a, b in _TWO_DICE_OUTCOMES if a + b > 9)
#                      ↑ 注意没有方括号 ↑
# 这看起来像列表推导式但没有括号——它是"生成器表达式"。
# 区别:
#   [x for x in data]     → 列表推导式，创建完整列表，占内存
#   (x for x in data)     → 生成器表达式，惰性求值，省内存
#   sum(x for x in data)  → 函数调用时括号可省略，最为常见
# 这里不需要保留中间结果，只是求和，用生成器更高效。
# 对 36 个元素来说性能差异微小，但对百万级数据差异显著。
_RIGGED_WINS_BIG = sum(1 for a, b in _TWO_DICE_OUTCOMES if a + b > 9)
_RIGGED_WINS_SMALL = sum(1 for a, b in _TWO_DICE_OUTCOMES if a + b <= 4)


# ============================================================
# 数据结构 — @dataclass 的完整使用
# ============================================================

@dataclass
class DiceProbabilities:
    """
    三骰子和值的概率分布容器。

    【@dataclass 自动生成了什么？】
    @dataclass 检查类属性（有类型注解的变量），自动生成:

    1. __init__(self, sum_distribution, p_small, p_big)
       → 构造函数，按属性定义顺序接收参数

    2. __repr__(self)
       → print(obj) 时的输出。默认格式:
         DiceProbabilities(sum_distribution={...}, p_small=0.5, p_big=0.5)
       我们重写了它来做更友好的输出。

    3. __eq__(self, other)
       → obj1 == obj2 的比较逻辑。逐个比较所有属性。

    【字段顺序很重要！】
    @dataclass 按定义顺序生成 __init__ 参数。
    有默认值的字段必须放在没有默认值的字段后面。
    这是 Python 函数参数的一般规则。

    【属性说明】
      sum_distribution: 字典，键是和值(3~18)，值是概率(0~1)
        例如 {3: 0.0046, 4: 0.0139, ..., 10: 0.125, ..., 18: 0.0046}
        所有概率加起来 = 1.0
      p_small: P(和 ≤ 10)，押"小"的获胜概率
      p_big:   P(和 > 10)，押"大"的获胜概率
    """
    sum_distribution: Dict[int, float]
    p_small: float
    p_big: float

    def __repr__(self) -> str:
        """
        自定义字符串表示。

        【f-string 格式说明符】
        {self.p_small:.4f} 中的 :.4f 是格式说明符:
          :  开始格式说明
          .4 保留 4 位小数
          f  浮点数格式

        常见格式说明符:
          {x:.2f}  → 3.14       (浮点，2位小数)
          {x:.0f}  → 3          (浮点，0位小数，会四舍五入)
          {x:.2%}  → 31.42%     (百分比，自动 ×100)
          {x:,}    → 1,000,000  (千分位逗号)
          {x:>10}  → "         3" (右对齐，宽度10)
        """
        return (
            f"DiceProbabilities(p_small={self.p_small:.4f}, "
            f"p_big={self.p_big:.4f})"
        )


# ============================================================
# 核心计算函数
# ============================================================

@cache
def three_dice_sum_distribution() -> DiceProbabilities:
    """
    计算三个公平骰子的和值分布。

    【数学原理 — 古典概型】
    三个骰子共 6³ = 216 种等可能结果。对于公平骰子，每种结果概率 = 1/216。
    P(和为 k) = (和为 k 的组合数) / 216

    【算法】
    1. 枚举所有 216 种 (d1,d2,d3) 组合
    2. 统计每种和值出现的次数
    3. 次数/216 = 概率

    【@cache 装饰器 — 深入理解】
    functools.cache 内部维护一个字典: {参数 → 返回值}。
    这个函数没有参数，所以字典只有一个条目。
    第一次调用: 计算 → 存入缓存
    后续调用: 直接从缓存读取（几乎零开销）

    注意事项:
      ✓ 适用于纯函数（相同输入→相同输出）
      ✓ 适用于计算量大的函数
      ✗ 不适用于有副作用（如写文件、print）的函数
      ✗ 不适用于返回值包含可变对象且调用方会修改它的情况
          （因为缓存返回的是同一个对象引用！）

    【计算结果】
    和=10 及以下: 108 种 → 50%
    和=11 及以上: 108 种 → 50%
    这个 50-50 的巧合是因为分布关于 10.5 对称。
    """
    # 【Python 知识点: 列表推导式 (List Comprehension)】
    # [sum(t) for t in outcomes]
    # 这行代码等价于:
    #   sums = []
    #   for t in outcomes:
    #       sums.append(sum(t))
    # 列表推导式更简洁、更快（底层是 C 实现）。
    #
    # sum(t) 是 Python 内置函数，对元组/列表的元素求和。
    # sum((3, 5, 2)) = 10
    outcomes = list(product(range(1, 7), repeat=3))
    total = len(outcomes)  # 216
    sums = [sum(t) for t in outcomes]
    counter = Counter(sums)

    # 【Python 知识点: 字典推导式 (Dict Comprehension)】
    # {s: count/total for s, count in sorted(counter.items())}
    # 语法: {键表达式: 值表达式 for 变量 in 可迭代对象}
    #
    # counter.items() 返回 (键, 值) 元组的可迭代对象
    # sorted() 按键（和值 3→18）排序
    dist = {s: count / total for s, count in sorted(counter.items())}

    # 【Python 知识点: 生成器表达式作 sum() 参数】
    # sum(count for s, count in counter.items() if s <= 10)
    #                 ↑ 没有括号 = 生成器表达式 ↑
    # 注意这里用了 if 过滤: 只累加满足条件的计数
    p_small = sum(count for s, count in counter.items() if s <= 10) / total
    p_big = sum(count for s, count in counter.items() if s > 10) / total

    # 【Python 知识点: 具名参数 vs 位置参数】
    # DiceProbabilities(dist, p_small, p_big) ← 位置参数，依赖顺序
    # DiceProbabilities(sum_distribution=dist, p_small=p_small, p_big=p_big)
    #   ← 具名参数(keyword argument)，顺序无关，更清晰
    # 这里用具名参数提高可读性。
    return DiceProbabilities(
        sum_distribution=dist,
        p_small=p_small,
        p_big=p_big,
    )


def normal_win_probability(bet: Bet = "big") -> float:
    """
    正常骰子下的单轮获胜概率。

    【Python 知识点: 默认参数值】
    bet: Bet = "big" 表示如果调用时不传 bet 参数，默认值为 "big"。
    所以 normal_win_probability() 等价于 normal_win_probability("big")。

    【默认参数的"陷阱"】
    Python 在函数定义时（而不是调用时）计算默认参数值。
    所以绝对不要把可变对象作为默认值:
      def bad(x, lst=[]):    ← 危险！同一个列表被所有调用共享
      def good(x, lst=None): ← 正确，在函数内部用 lst = lst or []
    这里默认值 "big" 是字符串（不可变对象），所以安全。

    【为什么是 50%？】
    三个骰子和值的分布关于 10.5 完美对称。
    P(和 ≤ 10) = P(和 ≥ 11)，因为每个结果 (a,b,c) 对应一个
    镜像结果 (7-a, 7-b, 7-c)，使得和值从 k 变为 21-k。
    """
    probs = three_dice_sum_distribution()
    if bet == "big":
        return probs.p_big
    else:
        return probs.p_small


def rigged_win_probability(bet: Bet = "big") -> float:
    """
    被操纵骰子下的单轮获胜概率（第 3 轮起）。

    【操纵规则】
    - 玩家押"大" → 操纵骰子强制 = 1（最不利于"大"的值）
    - 玩家押"小" → 操纵骰子强制 = 6（最不利于"小"的值）

    【数学推导 — 以押"大"为例】
    操纵骰子 = 1，剩下两个公平骰子和 S ∈ [2, 12]
    获胜条件: 1+S > 10 → S > 9 → S∈{10,11,12}
    两骰子和=10: (4,6),(5,5),(6,4) → 3 种
    两骰子和=11: (5,6),(6,5) → 2 种
    两骰子和=12: (6,6) → 1 种
    合计 6 种，概率 = 6/36 = 1/6

    【Python 知识点: 使用模块级常量】
    _RIGGED_WINS_BIG 和 _TWO_DICE_TOTAL 是模块加载时计算的常量。
    直接引用比重新计算快得多（O(1) vs O(36)）。
    """
    if bet == "big":
        return _RIGGED_WINS_BIG / _TWO_DICE_TOTAL
    else:
        return _RIGGED_WINS_SMALL / _TWO_DICE_TOTAL


def expected_rolls_normal(n_wins: int = 5) -> float:
    """
    正常骰子下，达到 n_wins 胜所需的期望投掷轮数。

    【Python 知识点: 类型注解不是强制的】
    参数 n_wins 注解为 int，但 Python 不会阻止你传入 float 或 str。
    只是 IDE 和类型检查器会发出警告。这是 Python "鸭子类型"哲学的体现。
    运行时如果类型不对，会在具体使用时（如数学运算）报 TypeError。

    【什么是负二项分布？】
    做一系列独立试验，每次成功概率为 p，直到获得 r 次成功为止。
    总试验次数服从负二项分布。期望值公式: E[X] = r / p

    【直观理解】
    每次投掷有 50% 概率获胜，平均每 2 次投掷赢得 1 次。
    要赢 5 次，平均需要 5 × 2 = 10 次投掷。
    """
    p = normal_win_probability()
    return n_wins / p


def expected_rolls_and_variance_rigged(n_wins: int = 5) -> Tuple[float, float]:
    """
    被操纵骰子下，达到 n_wins 胜的期望轮数和方差。

    【Python 知识点: 返回多个值 / 元组解包 (Tuple Unpacking)】
    这个函数返回 Tuple[float, float]。
    调用时可以用元组解包同时接收两个值:
      e, var = expected_rolls_and_variance_rigged(5)
      # e = 26.0, var = 138.0
    如果只需要其中一个:
      e, _ = expected_rolls_and_variance_rigged(5)  # _ 是"我不关心这个值"的约定
    这比返回列表或字典更直观、更高效。

    【为什么这个计算比正常骰子复杂？】
    因为游戏分两个阶段，胜率不同:
      阶段 1 (第1-2轮): p₁ = 0.5  (正常骰子)
      阶段 2 (第 3 轮起): p₂ = 1/6 (操纵骰子)

    前两轮结束后，根据获胜数 W 的不同，后续期望也不同。
    W ~ Binomial(n=2, p=0.5)，即:
      P(W=0) = 0.25  (前两轮全输)
      P(W=1) = 0.50  (赢1次)
      P(W=2) = 0.25  (赢2次)

    【数值结果】
    E[总轮数] = 0.25×32 + 0.5×26 + 0.25×20 = 26 轮
    Var[总轮数] = 138, σ ≈ 11.75
    正常: E=10, σ≈3.16  → 稳定
    操纵: E=26, σ≈11.75 → 波动大
    """
    p = rigged_win_probability()  # 1/6
    q = 1 - p                     # 5/6

    # 【Python 知识点: raise 语句 — 主动抛出异常】
    # raise ValueError(msg) 会在运行时立即中断程序，除非被 try/except 捕获。
    # ValueError 是 Python 内置异常，用于"参数值不合法"的情况。
    # 这和 Java/C++ 的 throw 类似。
    if n_wins <= 2:
        raise ValueError(
            f"n_wins={n_wins} ≤ 2: 游戏可能在前两轮结束，"
            "此函数仅适用于 n_wins > 2 的场景。"
        )

    # 【Python 知识点: 闭包 (Closure)】
    # 这两个函数定义在另一个函数内部，称为"嵌套函数"或"闭包"。
    # 它们可以访问外部函数的变量（n_wins, p, q），
    # 但外部不能直接调用它们。这是一种"封装"手段。
    def e_given_w(w: int) -> float:
        """给定前两轮获胜数 w，期望总轮数。"""
        return 2.0 + (n_wins - w) / p

    def var_given_w(w: int) -> float:
        """给定前两轮获胜数 w，总轮数的条件方差。"""
        return (n_wins - w) * q / (p * p)

    # 【Python 知识点: binom.pmf — 概率质量函数】
    # binom.pmf(k, n, p) = C(n,k) × p^k × (1-p)^(n-k)
    # C(n,k) 是组合数 "n选k": C(2,0)=1, C(2,1)=2, C(2,2)=1
    # 注意 SciPy 的函数命名: pmf=概率质量(离散), pdf=概率密度(连续)
    expected = 0.0
    for w in range(3):
        prob_w = binom.pmf(w, 2, 0.5)
        expected += prob_w * e_given_w(w)

    # 【Python 知识点: ** 运算符】
    # x ** 2 是 x 的平方，等价于 pow(x, 2) 或 math.pow(x, 2)。
    # x ** 0.5 是平方根，等价于 math.sqrt(x)。
    # Python 的 ** 运算符优先级很高: a * b ** 2 = a * (b**2)
    var_of_conditional_expectation = 0.0
    for w in range(3):
        prob_w = binom.pmf(w, 2, 0.5)
        var_of_conditional_expectation += (
            prob_w * (e_given_w(w) - expected) ** 2
        )

    expected_conditional_variance = 0.0
    for w in range(3):
        prob_w = binom.pmf(w, 2, 0.5)
        expected_conditional_variance += prob_w * var_given_w(w)

    variance = var_of_conditional_expectation + expected_conditional_variance

    return expected, variance


# ============================================================
# 报告输出 — Python 字符串操作
# ============================================================

def print_theoretical_report() -> None:
    """
    打印理论概率分析报告。

    【Python 知识点: -> None 的含义】
    表示这个函数不返回任何有意义的值（只做副作用，如打印）。
    没有 return 语句的函数默认返回 None。
    显式写 -> None 是为了告诉读者"我是有意不返回值的"。

    【Python 知识点: 字符串乘法】
    "=" * 64 生成 64 个等号连成的分隔线。
    字符串和整数相乘 = 重复拼接。
    同理 "—" * 48 = 48 个破折号。

    【Python 知识点: f-string 的表达式嵌入】
    {probs.p_small*216:.0f} 中包含了算术运算。
    f-string 的 {} 内可以是任意 Python 表达式，不限于变量名。
    甚至可以写 {a + b}、{func(x)}、{x if cond else y}。
    不过为了可读性，复杂表达式最好先算好再放入。
    """
    probs = three_dice_sum_distribution()
    p_normal = normal_win_probability()
    p_rigged = rigged_win_probability()
    # 元组解包: 接收两个返回值
    e_normal = expected_rolls_normal(5)
    e_rigged, var_rigged = expected_rolls_and_variance_rigged(5)

    print("=" * 64)
    print("  三骰子游戏 — 理论概率分析报告")
    print("=" * 64)
    print()
    print("【规则】三个骰子，和≤10为小，>10为大，猜中5次获胜")
    print("       第3轮起一个骰子被操纵：猜大出1，猜小出6")
    print()

    print("—" * 48)
    print("  1. 三骰子和值分布（正常）")
    print("—" * 48)
    print("  总组合数: 6^3 = 216")
    print(f"  小 (≤10): {probs.p_small*216:.0f}/216 = {probs.p_small:.4f} = {probs.p_small*100:.2f}%")
    print(f"  大 (>10): {probs.p_big*216:.0f}/216 = {probs.p_big:.4f} = {probs.p_big*100:.2f}%")
    print()

    print("—" * 48)
    print("  2. 单轮获胜概率")
    print("—" * 48)
    print(f"  正常骰子:     P(win) = {p_normal:.4f} = {p_normal*100:.2f}%")
    print(f"  操纵骰子(R3+): P(win) = {p_rigged:.4f} = {p_rigged*100:.2f}%")
    print(f"  胜率下降幅度: {(1 - p_rigged/p_normal)*100:.1f}%")
    print()

    print("—" * 48)
    print("  3. 达到5胜的期望轮数")
    print("—" * 48)
    print(f"  正常骰子: E[rolls] = {e_normal:.1f} 轮")
    # var_rigged**0.5 = 平方根，等价于 math.sqrt(var_rigged)
    print(f"  操纵骰子: E[rolls] = {e_rigged:.1f} 轮 (标准差 σ = {var_rigged**0.5:.1f})")
    print(f"  差距:      {e_rigged - e_normal:.1f} 轮")
    print()

    print("—" * 48)
    print("  4. 大数定律分析")
    print("—" * 48)
    print("  正常骰子: 每轮胜负 i.i.d. Bernoulli(0.5)")
    print("    → 样本胜率依概率收敛到 0.5 ✓")
    print()
    print("  操纵骰子: 前2轮 Bernoulli(0.5)，第3轮起 i.i.d. Bernoulli(1/6)")
    print("    → 前2轮的影响随轮数增加趋于 0")
    print("    → 样本胜率依概率收敛到 1/6 ≈ 0.1667 ✓")
    print("    → 大数定律仍然成立！")
    print()
    print("  关键洞察: 大数定律不要求「公平」概率，只要求随机变量")
    print("  具有有限期望且满足独立性条件。操纵骰子改变了概率，")
    print("  但没有违反 i.i.d. 假设（从第3轮起）。")
    print()
    print("=" * 64)
