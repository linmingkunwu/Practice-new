"""
21 点理论概率 — 最优策略的动态规划求解
======================================

【这个文件是做什么的？】
用数学公式精确计算 21 点中各种事件的概率与期望收益，
并求出"最优策略"（每个局面该停牌/要牌/加倍）。
这些理论值是模拟（game.py）与统计检验（analysis.py）的"标准答案"。

【规则模型（必须与 game.py 完全一致）】
  • 无限牌库模型: 每张牌的点数独立同分布（每次抽牌 13 种点数
    各占 1/13，抽牌之间互不影响）—— 数学上最干净的近似，
    也是本文所有"理论值"的计算前提
  • 庄家在软 17 也停牌（S17）
  • 玩家可在"首两张牌"时加倍（只能再要一张，赌注翻倍）
  • 不分牌、不买保险、不投降
  • 黑杰克（natural，首两张为 A+十点牌）赔 1.5 倍；
    庄家首牌为 A 或 10 时"看牌"（peek），若为黑杰克立即揭晓
  • 玩家点数到 21 自动停牌；平局(点数相同)退还赌注

【涉及的核心数学概念】
• 条件概率与条件分布: 给定庄家首牌后，庄家最终点数的条件分布
• 全概率公式: E[X] = Σ P(Bᵢ)·E[X|Bᵢ]，按抽到的牌分解期望
• 动态规划 / 贝尔曼最优方程:
    V(状态) = max(停牌的期望, 要牌后续状态的期望…)
    最优行动 = 使 V(状态) 最大的行动
• 递归与备忘录（记忆化搜索）: 同一子状态只算一次
• 大数定律: 这些理论期望值 = 海量模拟中样本均值的极限
• 几何分布的启示: 庄家不停补牌直到 ≥17，连补 k 张的概率
  按几何式衰减 —— 这是分布"尾巴"的由来
• 线性期望: 加倍只是把所有收益 ×2，所以 EV(加倍)
  可以在停牌 EV 基础上直接缩放

【公认的"锚点"数值（用于自检，结果见报告）】
  1. 庄家爆牌率（无限牌库，给定首牌）是教科书常见数值，
     如首牌 6 时约 0.42，首牌 10（无黑杰克）约 0.23
  2. "模仿庄家"策略（打到 ≥17 就停，不加倍）的劣势约为 5.5%~6%
     —— 本文件计算出的 -5.7% 落在该区间，可作为整体正确性校验
  3. 最优策略表应与文献中的基础策略表一致:
     硬 12 对 4/5/6 停、对 2/3/7+ 要牌；
     16 对 10 要牌（二者期望几乎相等，是著名"临界手"）；
     9 对 3~6 加倍；A,7 对 3~6 加倍、对 9/10/A 要牌……
"""

# ============================================================
# 导入依赖
# ============================================================

# 【Python 知识点: functools.cache — 记忆化】
# dice.py 讲过 @cache 用于"纯函数"（同样输入必得同样输出）。
# 动态规划 = 递归 + 记忆化:
#   每个 (点数, 软硬, 是否首两张, 庄家首牌) 状态只计算一次，
#   后续全部命中缓存 —— 状态数约 30×2×10，计算量极小。
# 注意: 若函数有随机性（random 调用），缓存会导致错误结果！
# 本模块所有函数都是纯计算，安全。
from functools import cache
from typing import Dict, List, Literal, Optional, Tuple

# 【Python 知识点: 相对导入】
# 与 dice-game 的 src/analysis.py 相同: 点号表示"当前包"。
from .cards import RANKS, TEN_RANKS, hand_value, rank_value


# ============================================================
# 类型别名
# ============================================================

# 行动空间: 停牌(Stand) / 要牌(Hit) / 加倍(Double)
Action = Literal["S", "H", "D"]

# 庄家最终结果分布: 键 = 点数 int(17~21) 或 'bust' 字符串
# 【Python 知识点: 类型别名】
# DealerDist = Dict[object, float] 只是"给类型起名字"，运行时无开销；
# 注解里写 DealerDist 比写一长串 Dict[...] 更易读。
DealerDist = Dict[object, float]


# ============================================================
# 状态转移 — 一手牌加一张牌后会变成什么
# ============================================================

def transition(total: int, soft: bool, rank: str) -> Optional[Tuple[int, bool]]:
    """
    从状态 (total, soft) 再要一张 rank，返回新状态 (新点数, 是否软)；
    若爆牌返回 None。

    【推导 —— 以"加一张 A"为例】
    设当前状态的点数和为 t（soft=True 时有一个 A 按 11 计）。

    (a) 软手 + A:
        新的 A 只能先按 1 计。原来的 11 是否还能保留？
        等价于问: 把所有 A 都按 1 计的和 s = t - 10 再加 1 后，
        是否仍 ≤ 11（可以再把一个 A 升级为 11）？
          s + 1 ≤ 11  ⟺  t ≤ 20  → 新状态软 (t+1)
          s + 1 > 11  ⟺  t = 21  → 只能硬计 (12)  ← 注意不是爆牌!
        示例: A,A,7,3（软 21）再要 A → 所有 A 按 1: 12 → 硬 12

    (b) 硬手 + A:
        和 s = t（没有按 11 的 A）加 1:
          t + 1 ≤ 11 → 可以把新 A 升级: 软 (t+11)
          否则 A 只能算 1: 若 t+1 > 21 爆牌，否则硬 (t+1)

    (c) 加非 A 牌 v（v = 2..10）:
        软手: t+v ≤ 21 → 软 (t+v)（原 11 保留）；
              否则降级: 硬 (t+v-10)，必不爆牌
        硬手: t+v ≤ 21 → 硬 (t+v)，否则爆牌 → None

    【Python 知识点: 返回 Optional[Tuple] + 三元表达式】
    Python 用 None 表示"不存在"（这里是爆牌）。
    调用方要习惯先判 None: if n is None: 爆牌处理。
    """
    v = rank_value(rank)
    if rank == "A":
        if soft:
            return (total + 1, True) if total <= 20 else (12, False)
        if total + 1 <= 11:
            return (total + 11, True)
        # 硬手 21 再要 A: total+1 = 22 > 21 → 爆牌
        return None if total + 1 > 21 else (total + 1, False)
    if soft:
        # 软手加非 A: 优先保留 11；超 21 则把 A 降为 1
        return (total + v, True) if total + v <= 21 else (total + v - 10, False)
    return (total + v, False) if total + v <= 21 else None


# ============================================================
# 庄家最终点数分布 — 动态规划（S17: 到 17 就停）
# ============================================================

@cache
def _dealer_finish(total: int, soft: bool) -> DealerDist:
    """
    庄家从状态 (total, soft) 开始补牌（<17 一直要，到 17 停），
    返回最终结果的概率分布: {17: p17, ..., 21: p21, 'bust': p_bust}。

    【数学原理 — 全概率公式的递归形式】
    设 f(状态) 为最终分布。若已 ≥17: 立即停止，分布只有一个点。
    否则:
      f(状态) = Σ_{每张可能的牌 r} (1/13) × 转移后的 f'(状态)
    这就是把"下一步抽到什么牌"作为条件分解 —— 与 dice.py
    中枚举 216 种骰子结果、按古典概型计数是同一思想，
    只不过这里的状态空间是"点数和软硬"而不是具体手牌。

    【为什么可以只记 (total, soft) 不记手牌组成？】
    无限牌库: 抽下一张牌的概率恒为 1/13，与已抽出的牌无关，
    因此同样 (total, soft) 的未来完全相同 —— 马尔可夫性。

    【收敛性（递归为什么不无限？）】
    每抽一张牌，各张牌的"按1计之和"至少 +1，最多 21 次后
    必然 ≥17 或爆牌 → 递归深度有限。缓存保证每个状态只展开一次。

    【Python 知识点: dict.get(key, default) 累加模式】
    res[k] = res.get(k, 0.0) + p
    比 "if k not in res: res[k]=0; res[k]+=p" 简洁，
    dice.py 的逐轮统计用过同样的模式。
    """
    if total >= 17:  # S17: 包括软 17 在内全部停牌
        return {total: 1.0}
    result: DealerDist = {}
    for rank in RANKS:
        nxt = transition(total, soft, rank)
        if nxt is None:  # 爆牌
            result["bust"] = result.get("bust", 0.0) + 1.0 / 13
        else:
            sub = _dealer_finish(*nxt)
            for key, p in sub.items():
                result[key] = result.get(key, 0.0) + p / 13
    return result


def dealer_final_distribution(upcard: str) -> DealerDist:
    """
    给定庄家首牌 upcard，其最终结果的概率分布
    （在"庄家首两张不是黑杰克"的条件下；原因见下）。

    【为什么要排除黑杰克？】
    庄家首牌是 A 或 10 点时会"看牌"(peek):
      • 首牌 A 而洞牌是十点 → 庄家黑杰克，牌局立即结束，
        玩家根本没有机会要牌/停牌/加倍
      • 首牌 10 而洞牌是 A → 同理
    因此玩家做任何决策时，都已知道"庄家没有黑杰克"。
    计算玩家行动的期望时，必须用这个条件分布，而不是无条件分布。

    【条件分布怎么求？】
    1. 枚举洞牌: 首牌 A 时洞牌只能是 9 种非十点牌
       （A,2,...,9，各 1/9）；首牌 10 时洞牌只能是 12 种非 A 牌
       （各 1/12）；其余首牌 13 种洞牌各 1/13
    2. 每种洞牌构成庄家初始状态 (total, soft)
    3. 用 _dealer_finish 得到该状态的最终分布
    4. 按洞牌概率加权平均

    【Python 知识点: 列表推导式 + 条件过滤】
    [h for h in RANKS if not (...)] 一次写出"允许的洞牌"，
    替代手写 if 分支循环。
    """
    if upcard == "A":
        holes = [h for h in RANKS if h not in TEN_RANKS]       # 9 种
    elif upcard in TEN_RANKS:
        holes = [h for h in RANKS if h != "A"]                 # 12 种
    else:
        holes = list(RANKS)                                    # 13 种

    dist: DealerDist = {}
    for hole in holes:
        total, soft = hand_value([upcard, hole])
        sub = _dealer_finish(total, soft)
        for key, p in sub.items():
            dist[key] = dist.get(key, 0.0) + p / len(holes)
    return dist


def dealer_natural_probability(upcard: str) -> float:
    """庄家拿到黑杰克的概率（首牌已知时）。

    首牌 A: 洞牌须为十点牌 → 4/13
    首牌十点: 洞牌须为 A → 1/13
    其余首牌: 不可能黑杰克 → 0
    """
    if upcard == "A":
        return 4.0 / 13.0
    if upcard in TEN_RANKS:
        return 1.0 / 13.0
    return 0.0


# 预计算: 每种首牌的条件最终分布（模块加载时算好，见 dice.py 的说明）
DISTRIBUTIONS: Dict[str, DealerDist] = {
    u: dealer_final_distribution(u) for u in RANKS
}


# ============================================================
# 停牌 / 加倍 — 直接由分布求期望
# ============================================================

def stand_ev(player_total: int, upcard: str) -> float:
    """
    玩家点数 player_total 停牌时的期望净收益（单位赌注）。

    【收益分解 — 条件期望】
    对庄家每个最终结果求收益再乘概率求和:
      庄家爆牌        → +1
      庄家点数 < 我   → +1
      庄家点数 = 我   → 0（平局退还）
      庄家点数 > 我   → -1
    E = Σ p(结果) × 收益(结果)

    【示例】对 6 停牌（点 16）:
      P(庄家爆牌 | 6) ≈ 0.423，庄家 17~21 赢过我 → 其余约 0.577
      EV ≈ 0.423 - 0.577 ≈ -0.154  ← 负数也要停，
      因为要牌的期望更差（下文 16 vs 6 的表格会验证）

    【Python 知识点: dict 的键类型不统一】
    分布字典里 17..21 是 int 键，爆牌是字符串 'bust' 键。
    这是刻意的简化: 分支时先判 k == 'bust'。
    """
    ev = 0.0
    for outcome, p in DISTRIBUTIONS[upcard].items():
        if outcome == "bust":
            ev += p
        elif outcome < player_total:
            ev += p
        elif outcome > player_total:
            ev -= p
        # outcome == player_total → 平局，收益 0，不加不减
    return ev


def double_ev(player_total: int, soft: bool, upcard: str) -> float:
    """
    加倍（只加一张牌，赌注 ×2）的期望收益。

    【线性期望 — 最优雅的数学性质】
    加倍 = 先要一张牌，然后无条件停牌，且所有收益 ×2。
    因此:
      EV(加倍) = 2 × Σ_{牌 r} (1/13) × EV(停牌 | 加牌后状态)

    注意: 与"要牌"不同，加倍后如果点数仍 ≤21 就强制停牌，
    不能继续要 —— 这正是加倍与要牌的差别所在。

    【Python 知识点: 在 for 循环里用 continue 而不是 else 块】
    下面两种写法等价:
      for r in ranks:
          if 条件: continue
          处理
      for r in ranks:
          if not 条件: 处理
    用 continue 让"爆牌"这种特例提前跳过，主线逻辑更平直。
    """
    ev = 0.0
    for rank in RANKS:
        nxt = transition(player_total, soft, rank)
        if nxt is None:                       # 加倍后爆牌: 输双倍
            ev += -2.0 / 13
            continue
        ev += 2.0 * stand_ev(nxt[0], upcard) / 13
    return ev


# ============================================================
# 最优策略 — 贝尔曼最优方程
# ============================================================

@cache
def decision_value(total: int, soft: bool, two_card: bool, upcard: str) -> Tuple[float, Action]:
    """
    状态 (total, soft, 是否首两张, 庄家首牌) 的最优期望收益，
    以及对应的最优行动。

    【贝尔曼最优方程】
    V(s) = max( EV(停牌|s), EV(加倍|s)[仅首两张], EV(要牌|s) )

    其中要牌的期望依赖"要牌后的新状态"继续用 V 求值:
      EV(要牌) = Σ_{r} (1/13) × [ 爆牌 ? -1 : V(新状态) ]
    这是一个"自己调用自己"的方程 —— 递归直到点数 ≥21 为止。

    【直观理解（类比）】
    在 16 对 10 这种"临界手"上:
      V(16,10) = max(停牌 ≈ -0.540, 要牌 ≈ -0.540)
    两者几乎一样差 —— 这就是为什么"16 对 10 怎么打都难受"。
    而在 11 对 6 上:
      V = max(停牌 ≈ -0.154, 加倍 ≈ +0.667, 要牌 ≈ +0.334)
    加倍遥遥领先 → 教科书"11 对 6 加倍"。

    【Python 知识点: 递归 + @cache 的黄金组合】
    decision_value 递归调用自身 —— 没有缓存会指数爆炸
    （每层 13 种抽牌 × 层数），有缓存则每个状态只算一次。
    状态总数 ~ (8..21 点数 × 软硬 × 首两张与否) × 13 首牌 ≈ 几千个，
    全部算完只需要毫秒级时间。

    【Python 知识点: 返回元组 (值, 行动)】
    一次递归同时带回"最优值"和"最优行动"，避免重复计算
    argmax；调用方用元组解包接收:
      ev, act = decision_value(...)
    """
    best_ev, best_action = stand_ev(total, upcard), "S"

    # 加倍只允许在首两张（引擎保证 two_card 状态 ≤ 20，不会天然21）
    if two_card:
        ev_d = double_ev(total, soft, upcard)
        if ev_d > best_ev:
            best_ev, best_action = ev_d, "D"

    # 要牌: 逐张牌展开，爆牌记 -1，否则递归求后续最优值
    ev_h = 0.0
    for rank in RANKS:
        nxt = transition(total, soft, rank)
        if nxt is None:
            ev_h += -1.0 / 13
        else:
            ev_h += decision_value(nxt[0], nxt[1], False, upcard)[0] / 13
    if ev_h > best_ev:
        best_ev, best_action = ev_h, "H"

    return best_ev, best_action


def optimal_action(total: int, soft: bool, two_card: bool, upcard: str) -> Action:
    """
    查询最优行动（供 strategies.BasicStrategy 与报告表格使用）。
    点数 ≥21 时强制停牌（引擎不会询问，这里兜底）。
    """
    if total >= 21:
        return "S"
    return decision_value(total, soft, two_card, upcard)[1]


def action_ev(total: int, soft: bool, two_card: bool, upcard: str, action: Action) -> float:
    """
    某个明确行动（不一定是最优）的期望 —— 供 analysis.py
    做"理论 vs 蒙特卡洛"逐行动验证，以及报告中的对比表。
    """
    if action == "S":
        return stand_ev(total, upcard)
    if action == "D":
        if not two_card:
            raise ValueError("加倍只允许在首两张牌时进行")
        return double_ev(total, soft, upcard)
    # 要牌: 后续仍按最优策略打（这是"当前要牌"的合理对比口径）
    ev = 0.0
    for rank in RANKS:
        nxt = transition(total, soft, rank)
        if nxt is None:
            ev += -1.0 / 13
        else:
            ev += decision_value(nxt[0], nxt[1], False, upcard)[0] / 13
    return ev


# ============================================================
# 整局期望 — 黑杰克与庄家看牌的处理
# ============================================================

def is_blackjack(ranks: List[str]) -> bool:
    """
    判断首两张牌是否为黑杰克（A + 任意十点牌）。
    点数顺序无关: 先到 A 后到 10，或反过来都算。
    """
    return len(ranks) == 2 and "A" in ranks and any(
        r in TEN_RANKS for r in ranks
    )


def hand_round_ev(rank1: str, rank2: str, upcard: str) -> float:
    """
    给定玩家首两张 (rank1, rank2) 与庄家首牌，整局的期望收益。

    【分情况讨论（全概率公式）】
    case 1: 玩家是黑杰克
      庄家不是黑杰克 → +1.5；是黑杰克 → 平局 0
      EV = 1.5 × (1 - P(庄家黑杰克))
    case 2: 玩家不是黑杰克，庄家首牌 A/10 且是黑杰克
      玩家还没行动就输了 → -1
    case 3: 其余情况（玩家行动阶段）
      用条件分布 DISTRIBUTIONS[upcard] 下的最优策略值 V
      并乘上"庄家确实没有黑杰克"的条件概率 (1 - P_nat):
      EV = -P_nat + (1-P_nat) × V
      —— 因为 V 本身是在"无庄家黑杰克"条件下计算的
      （见 dealer_final_distribution 的说明）

    这三种情况互斥且完备 → 直接相加即全概率公式。
    """
    p_nat = dealer_natural_probability(upcard)

    if is_blackjack([rank1, rank2]):
        return 1.5 * (1.0 - p_nat)

    total, soft = hand_value([rank1, rank2])

    if p_nat > 0:
        # case 2 与 case 3 合并: 庄家黑杰克概率 p_nat 直接输
        return -p_nat + (1.0 - p_nat) * decision_value(total, soft, True, upcard)[0]
    return decision_value(total, soft, True, upcard)[0]


def _aggregate_over_starting_hands(hand_ev_fn) -> float:
    """
    对所有"玩家首两张 × 庄家首牌"按概率加权，求整局平均期望。

    【组合计数 — 首两张牌的联合分布】
    玩家两张牌是有放回的两次独立抽取（无限牌库），
    共 13×13 = 169 种有序组合，每种概率 1/169。
    用"无序枚举 + 权重"更省:
      同点数 (r, r)            : 1 种有序组合 → 权重 1
      不同点数 (r₁, r₂), r₁<r₂ : 2 种有序组合 → 权重 2
    对每种无序组合乘权重 / 169，再对庄家首牌 13 种各乘 1/13。

    【Python 知识点: 一等函数（函数作为参数）】
    参数 hand_ev_fn 是"函数"—— Python 里函数也是对象。
    传入不同的整局期望函数，同一个聚合器可以复用于
    最优策略 / 永远停牌 / 模仿庄家等不同策略的 EV 计算。
    """
    total_ev = 0.0
    for i, r1 in enumerate(RANKS):
        for r2 in RANKS[i:]:
            weight = 1.0 if r1 == r2 else 2.0
            for upcard in RANKS:
                total_ev += weight * hand_ev_fn(r1, r2, upcard) / 13.0 / 169.0
    return total_ev


def _round_ev_optimal(r1: str, r2: str, u: str) -> float:
    """最优策略（含加倍）的整局期望。"""
    return hand_round_ev(r1, r2, u)


def _round_ev_stand_only(r1: str, r2: str, u: str) -> float:
    """策略 1: 永不叫牌（首两张直接停）。"""
    p_nat = dealer_natural_probability(u)
    if is_blackjack([r1, r2]):
        return 1.5 * (1.0 - p_nat)

    total, _ = hand_value([r1, r2])
    if p_nat > 0:
        return -p_nat + (1.0 - p_nat) * stand_ev(total, u)
    return stand_ev(total, u)


@cache
def _mimic_value(total: int, soft: bool, upcard: str) -> float:
    """
    策略 2: 模仿庄家 —— 点数 <17 就一直要，≥17 停（不加倍）。
    递归结构与 _dealer_finish 完全平行，只是结算时与庄家比大小。
    它是最简单的"确定性策略"，常被文献用作 -5.5%~-6% 的基准。
    """
    if total >= 17:
        return stand_ev(total, upcard)
    ev = 0.0
    for rank in RANKS:
        nxt = transition(total, soft, rank)
        if nxt is None:
            ev += -1.0 / 13
        else:
            ev += _mimic_value(nxt[0], nxt[1], upcard) / 13
    return ev


def _round_ev_mimic(r1: str, r2: str, u: str) -> float:
    """策略 2（模仿庄家）的整局期望。"""
    p_nat = dealer_natural_probability(u)
    if is_blackjack([r1, r2]):
        return 1.5 * (1.0 - p_nat)
    total, soft = hand_value([r1, r2])
    if p_nat > 0:
        return -p_nat + (1.0 - p_nat) * _mimic_value(total, soft, u)
    return _mimic_value(total, soft, u)


@cache
def _hs_value(total: int, soft: bool, upcard: str) -> float:
    """
    策略 3: 最优叫/停（禁加倍）。
    与 decision_value 相同，只是行动空间只有 {停, 要}。
    用来展示"加倍"这条规则值多少钱（对比策略 4）。
    """
    best = stand_ev(total, upcard)
    ev = 0.0
    for rank in RANKS:
        nxt = transition(total, soft, rank)
        if nxt is None:
            ev += -1.0 / 13
        else:
            ev += _hs_value(nxt[0], nxt[1], upcard) / 13
    return max(best, ev)


def _round_ev_hs(r1: str, r2: str, u: str) -> float:
    """策略 3（最优叫停、禁加倍）的整局期望。"""
    p_nat = dealer_natural_probability(u)
    if is_blackjack([r1, r2]):
        return 1.5 * (1.0 - p_nat)
    total, soft = hand_value([r1, r2])
    if p_nat > 0:
        return -p_nat + (1.0 - p_nat) * _hs_value(total, soft, u)
    return _hs_value(total, soft, u)


def strategy_ev_ladder() -> Dict[str, float]:
    """
    四种策略的整局期望（单位赌注）:
      1. 永不叫牌           —— 玩家把一切交给庄家爆牌
      2. 模仿庄家           —— 经典文献基准（约 -5.5%~-6%）
      3. 最优叫/停(禁加倍)  —— 加倍规则缺席时的最好成绩
      4. 完整最优策略       —— 本文件的标准答案
    递增的期望展示了"决策的质量阶梯"，
    每跨一级都在回答: 这条规则/这个决策值多少钱？
    """
    return {
        "永远停牌": _aggregate_over_starting_hands(_round_ev_stand_only),
        "模仿庄家": _aggregate_over_starting_hands(_round_ev_mimic),
        "最优叫停(禁加倍)": _aggregate_over_starting_hands(_round_ev_hs),
        "完整最优策略": _aggregate_over_starting_hands(_round_ev_optimal),
    }


def overall_expected_value() -> float:
    """完整最优策略的整局期望（常用作理论锚点 μ₀）。"""
    return _aggregate_over_starting_hands(_round_ev_optimal)


# ============================================================
# 报告输出 — 理论概率分析报告
# ============================================================

def print_dealer_distribution_table() -> None:
    """打印庄家最终分布表（每种首牌一行）。"""
    print("  " + "".join(f"{k:>7}" for k in ["爆牌", "17", "18", "19", "20", "21"]))
    for u in RANKS:
        d = DISTRIBUTIONS[u]
        row = f"  首牌 {u:>2}:"
        row += f"{d.get('bust', 0):>8.4f}"
        for k in range(17, 22):
            row += f"{d.get(k, 0):>8.4f}"
        print(row)


def _action_symbols(total: int, soft: bool) -> str:
    """打印一张行动表的辅助函数。"""
    cells = []
    for u in RANKS:
        cells.append(optimal_action(total, soft, two_card=True, upcard=u))
    return " ".join(f"{a:>2}" for a in cells)


def print_strategy_tables() -> None:
    """
    打印硬手/软手的最优行动表。
    【说明】表中给的是"首两张牌"（允许加倍）的行动；
    若已要过牌（无加倍资格），把 D 视为 H 即可
    （加倍与要牌在首牌后数值上几乎总是同向）。
    """
    header = "首牌  " + " ".join(f"{u:>2}" for u in RANKS)
    print(header)
    print("  " + "-" * (len(header) - 2))
    for t in range(8, 18):
        print(f"硬{t:>2}  " + _action_symbols(t, False))
    for srank in ["2", "3", "4", "5", "6", "7", "8", "9"]:
        total, soft = hand_value(["A", srank])
        print(f"A{srank}软{total:>2} " + _action_symbols(total, soft))
    print()
    print("  【图例】S=停牌  H=要牌  D=加倍(仅首两张)")


def print_theoretical_report() -> None:
    """
    打印完整的理论概率分析报告（main.py 第 1 步调用）。
    """
    print("=" * 70)
    print("  21 点 — 理论概率分析报告（无限牌库 / S17 / 黑杰克1.5倍）")
    print("=" * 70)
    print("  规则: 庄家软17停牌；玩家首两张可加倍；不分牌/保险/投降")

    print()
    print("—" * 54)
    print("  1. 庄家最终点数分布（给定首牌，已排除庄家黑杰克）")
    print("—" * 54)
    print_dealer_distribution_table()
    print()
    print("  校验: 每行概率之和应为 1.0；首牌 6 的爆牌率 ≈ 0.423")
    print("        是文献中的经典数值，可用于自检。")

    print()
    print("—" * 54)
    print("  2. 几个代表性局面的期望收益（理论值）")
    print("—" * 54)
    examples = [
        (16, False, "T", "16 vs 10（著名临界手）"),
        (12, False, "2", "12 vs 2（硬12的尴尬）"),
        (11, False, "6", "11 vs 6（加倍天堂）"),
        (20, False, "6", "20 vs 6（躺赢局）"),
        (17, True, "6", "A6 vs 6（软17加倍）"),
        (18, True, "9", "A7 vs 9（软18）"),
    ]
    for total, soft, u, label in examples:
        line = f"  {label:<20}"
        line += f"停牌 {stand_ev(total, u):+8.4f}"
        line += f"   加倍 {double_ev(total, soft, u):+8.4f}   "
        acts = [optimal_action(total, soft, True, u)]
        ev, act = decision_value(total, soft, True, u)
        line += f"最优 {act} ({ev:+.4f})"
        print(line)
    print("  A/T 等首牌情形已按'庄家看牌'条件处理。")

    print()
    print("—" * 54)
    print("  3. 策略质量阶梯（整局平均期望，单位赌注）")
    print("—" * 54)
    ladder = strategy_ev_ladder()
    keys = list(ladder.keys())
    for i, name in enumerate(keys):
        ev = ladder[name]
        print(f"    {name:<12} EV = {ev:+.4f}   (赌场优势 { -ev*100:.2f}%)")
        if i > 0:
            gain = (ev - ladder[keys[i - 1]]) * 100
            print(f"      ↑ 相对上一策略提升 {gain:+.2f} 个百分点")
    print()
    print("  对照: '模仿庄家' ≈ -5.7% 与文献基准(-5.5%~-6%)吻合；")
    print("  完整最优(含加倍)在'不分牌+无限牌库'模型下约为 -1.1%；")
    print("  现实中 6 副牌+允许分牌时基础策略的优势约为 -0.4%~-0.5%，")
    print("  差值主要来自分牌与有限牌库的组成效应。")

    print()
    print("—" * 54)
    print("  4. 最优行动表（首牌列 → 玩家行动）")
    print("—" * 54)
    print_strategy_tables()

    print("=" * 70)
    print()
