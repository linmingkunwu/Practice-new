"""
模拟引擎 — 21 点回合引擎与蒙特卡洛实验
=======================================

【这个文件是做什么的？】
1. 回合引擎: 严格按规则执行一局 21 点（发牌/看牌/决策/补牌/结算）
2. 蒙特卡洛: 用同一引擎批量跑几千靴牌或几十万局无限牌库模拟
3. 交互玩法: 命令行里真人玩 21 点（python main.py --play）

【与 dice-game 的结构对应】
dice-game/game.py 提供 play_game(单局) 与 monte_carlo(批量)；
这里对应 play_round_shoe / monte_carlo_shoe / simulate_infinite_rounds。

【涉及的核心概念】
• 蒙特卡洛方法: 用大量随机抽样逼近真实分布（dice-game 已详述）
• 不放回抽样: 牌靴抽牌改变剩余牌结构（与理论模块的"无限牌库"
  模型形成对比 —— 这也是为什么需要两个采样器）
• 大数定律: 模拟局数越多，样本均值越接近理论期望
• 随机种子: 保证实验可复现、可配对（种子相同 → 每靴的洗牌
  顺序完全相同，配对统计检验以"靴"为单元成立）
• 伪随机数: Mersenne Twister（cards.py 已介绍）
"""

# ============================================================
# 导入依赖
# ============================================================

import random
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

# 【Python 知识点: 相对导入】
from .cards import Card, Shoe, RANKS, TEN_RANKS, hand_value
from .strategies import (
    Action, BaseStrategy, PlayContext, true_count_of,
)

# 从 theory 借状态转移（无限牌库补牌用同一套点数规则）
# 【为什么要复用而不是重写？】
# 点数规则（A 软硬、爆牌）必须在 theory/引擎之间唯一 ——
# 规则分叉是模拟与理论对不上号的头号原因。
from .theory import transition, is_blackjack


# ============================================================
# 数据结构 — 单局记录
# ============================================================

@dataclass
class RoundRecord:
    """
    一局的完整结算记录（用于统计分析）。

    属性说明:
      round_index: 本场实验第几局（从 1 起）
      shoe_index: 来自第几靴牌（-1 = 无限牌库模拟）
      upcard: 庄家首牌
      bet_units: 实际下注单位
      net: 净收益（单位: 基础注。1 单位注赢 1，黑杰克赢 1.5，
           加倍后输赢 ×2）
      kind: 结果类别: 'win' / 'push' / 'lose'
      tc: 本局开始时的真数（无限牌库或非算牌场景为 0.0）
      dealer_outcome: 庄家最终结果（无限牌库采样器回填，
          取值 'natural'/'bust'/17~21；牌靴模式为 None）
    """
    round_index: int
    shoe_index: int
    upcard: str
    bet_units: float
    net: float
    kind: str
    tc: float = 0.0
    dealer_outcome: Optional[str] = None


@dataclass
class ShoeSimulation:
    """
    一次牌靴蒙特卡洛实验的结果集合。

    【Python 知识点: dataclass 里放"对象字段"】
    records 是可变列表，用 field(default_factory=list)
    保证每次创建实例得到独立列表（dice-game 反复强调的陷阱）。
    """
    strategy: BaseStrategy
    n_shoes: int
    decks: int
    seed: Optional[int]
    cut_fraction: float
    records: List[RoundRecord] = field(default_factory=list)

    @property
    def name(self) -> str:
        """策略名，便于报告输出。"""
        return self.strategy.name


# ============================================================
# 结算工具 — 点数比较（两种引擎共用）
# ============================================================

def settle(total: int, dealer_total: int) -> Tuple[float, str]:
    """
    玩家点数 vs 庄家点数 → (净收益倍数, 类别)。
    dealer_total = -1 表示庄家爆牌。
    """
    if dealer_total == -1:           # 庄家爆牌 → 玩家赢
        return 1.0, "win"
    if total > dealer_total:
        return 1.0, "win"
    if total == dealer_total:
        return 0.0, "push"
    return -1.0, "lose"


# ============================================================
# 引擎 1 — 无限牌库采样器（理论校验专用）
# ============================================================

def _infinite_draw(rng: random.Random) -> str:
    """无限牌库: 每张牌点数在 13 种中均匀抽取（放回）。"""
    return rng.choice(RANKS)


def sample_dealer_playout(upcard: str, rng: random.Random) -> str:
    """
    模拟一靴(次)庄家补牌过程，返回最终结果:
      'natural' : 庄家黑杰克（首两张 A+十点）
      'bust'    : 爆牌
      '17'~'21' : 最终点数（含软 17 停牌，S17）

    【注意: 无条件采样】
    本函数不排除黑杰克 —— 它忠实还原"发牌员先翻洞牌再看牌"
    的物理过程，黑杰克也是合法结果。相比之下，theory.py 的
    dealer_final_distribution 是"给定没有黑杰克"的条件分布
    （因为玩家决策时已知道这一点）。统计校验时两者要区分开。
    """
    hole = _infinite_draw(rng)
    # 庄家黑杰克判定（与引擎规则一致）
    if (upcard == "A" and hole in TEN_RANKS) or (upcard in TEN_RANKS and hole == "A"):
        return "natural"

    ranks = [upcard, hole]
    total, soft = hand_value(ranks)
    while total < 17:                       # S17: 软 17 也停
        ranks.append(_infinite_draw(rng))
        total, soft = hand_value(ranks)
    return "bust" if total > 21 else str(total)


def simulate_infinite_rounds(
    strategy: BaseStrategy,
    n_rounds: int,
    seed: Optional[int] = None,
    fixed_upcard: Optional[str] = None,
) -> List[RoundRecord]:
    """
    无限牌库下跑 n_rounds 局（每局独立同分布）。

    【用途】
    - 校验 theory.py 的理论值（庄家分布、行动 EV、整局期望）
    - 画大数定律收敛曲线（累积均值 → 理论值）

    【与牌靴引擎的区别】
    每次抽牌都在 13 种点数中等概率抽取（放回），
    没有剩余牌结构变化 —— 这是"理论模型的蒙特卡洛实现"。
    洞牌在开局即抽出（先翻洞牌再看牌）: 无限牌库下每次抽取
    独立同分布，洞牌先抽或后抽完全等价，故采用最简单的写法。

    【Python 知识点: random.Random 局部实例】
    与 cards.py 的 build_shoe_cards 同理: 用局部实例隔离随机源，
    同一 seed 结果完全可复现，也不干扰全局 random 的状态。
    """
    rng = random.Random(seed)
    records: List[RoundRecord] = []

    for i in range(1, n_rounds + 1):
        # ---- 发牌 ----
        if fixed_upcard is not None:
            upcard = fixed_upcard
        else:
            upcard = _infinite_draw(rng)
        c1, c2 = _infinite_draw(rng), _infinite_draw(rng)
        hole = _infinite_draw(rng)

        # ---- 黑杰克 / 看牌结算 ----
        player_nat = is_blackjack([c1, c2])
        dealer_nat = ((upcard == "A" and hole in TEN_RANKS)
                      or (upcard in TEN_RANKS and hole == "A"))
        dealer_outcome: Optional[str] = "natural" if dealer_nat else None

        bet = 1.0  # 校验用固定注
        net = 0.0
        kind = "push"

        if player_nat and dealer_nat:
            net, kind = 0.0, "push"
        elif player_nat:
            net, kind = 1.5, "win"
        elif dealer_nat:
            net, kind = -1.0, "lose"
        else:
            # ---- 玩家决策阶段 ----
            ranks = [c1, c2]
            total, soft = hand_value(ranks)
            two_card = True
            busted = False
            while total < 21:
                ctx = PlayContext(
                    total=total, soft=soft, two_card=two_card,
                    upcard=upcard, hand_ranks=tuple(ranks),
                    shoe=None,
                )
                action = strategy.decide(ctx)
                if action == "S":
                    break
                if action == "D" and two_card:
                    ranks.append(_infinite_draw(rng))
                    total, soft = hand_value(ranks)
                    if total > 21:
                        busted = True
                    bet = 2.0
                    break                      # 加倍后强制停牌
                # H
                ranks.append(_infinite_draw(rng))
                total, soft = hand_value(ranks)
                two_card = False
                if total > 21:
                    busted = True
                    break

            if busted:
                net, kind = -bet, "lose"
            else:
                # ---- 庄家补牌（洞牌已翻出，玩家已停） ----
                d_ranks = [upcard, hole]
                d_total, d_soft = hand_value(d_ranks)
                while d_total < 17:
                    d_ranks.append(_infinite_draw(rng))
                    d_total, d_soft = hand_value(d_ranks)
                if d_total > 21:
                    dealer_outcome = "bust"
                    net, kind = bet, "win"
                else:
                    dealer_outcome = str(d_total)
                    net, kind = settle(total, d_total)
                    net *= bet               # 加倍时按 2 倍结算

        records.append(RoundRecord(
            round_index=i, shoe_index=-1, upcard=upcard,
            bet_units=bet, net=net, kind=kind, tc=0.0,
            dealer_outcome=dealer_outcome,
        ))

    return records


def simulate_state_action_ev(
    total: int, soft: bool, two_card: bool, upcard: str,
    action: Action, n: int, seed: Optional[int] = None,
) -> List[float]:
    """
    对"固定局面 + 固定行动"采样 n 次净收益（不含黑杰克路径）。

    【用途】逐行动校验 theory.action_ev:
    例如 (16, 硬, 首两张, 10) 停牌的样本均值应 ≈ -0.5404。

    【为什么只支持停牌(S)与加倍(D)？】
    "要牌"在真实策略里是"连续决策"——要了之后还要不要、
    什么时候停，由后续策略决定，无法脱离策略单独定义
    （抽一张就强制停的"要牌"不是真实规则）。
    因此 H 的期望不做单独采样: 它的值由 theory 的贝尔曼
    递归(decision_value)定义，并在整局期望校验中统一验证。
    对 S/D 而言"行动 = 立即终止决策"，语义唯一，可以采样。

    【实现要点】
    1. 玩家已在指定局面，直接按行动推进:
       停牌 → 不抽牌；加倍 → 抽一张（爆了输 2 倍）。
    2. 庄家侧必须"条件化无黑杰克"，与 theory 的条件分布对齐:
       首牌 A → 洞牌排除十点；首牌 10 → 洞牌排除 A。
    3. 返回净收益列表（单位赌注），供 analysis 做均值检验。
    """
    if action not in ("S", "D"):
        raise ValueError("simulate_state_action_ev 只支持停牌/加倍")

    rng = random.Random(seed)
    nets: List[float] = []
    for _ in range(n):
        # 条件化洞牌（与 theory.dealer_final_distribution 对齐）
        if upcard == "A":
            hole = rng.choice([h for h in RANKS if h not in TEN_RANKS])
        elif upcard in TEN_RANKS:
            hole = rng.choice([h for h in RANKS if h != "A"])
        else:
            hole = rng.choice(RANKS)

        if action == "D":
            rank = _infinite_draw(rng)
            nxt = transition(total, soft, rank)
            if nxt is None:
                nets.append(-2.0)              # 加倍后爆牌
                continue
            total_after = nxt[0]
        else:
            total_after = total

        # 庄家从 (upcard, hole) 补牌到 ≥17（S17）
        d_ranks = [upcard, hole]
        d_total, d_soft = hand_value(d_ranks)
        while d_total < 17:
            d_ranks.append(_infinite_draw(rng))
            d_total, d_soft = hand_value(d_ranks)

        if d_total > 21:
            nets.append(2.0 if action == "D" else 1.0)
        else:
            mult, _ = settle(total_after, d_total)
            nets.append(mult * (2.0 if action == "D" else 1.0))
    return nets


# ============================================================
# 引擎 2 — 牌靴回合（真实赌场模型）
# ============================================================

def play_round_shoe(shoe: Shoe, strategy: BaseStrategy,
                    round_index: int, shoe_index: int) -> RoundRecord:
    """
    在牌靴 shoe 上打一局，返回完整的 RoundRecord。
    （策略若含随机决策，直接使用模块级 random —— 其种子由
    monte_carlo_shoe 统一设置，保证可复现。）

    【牌靴与无限牌库模型的差异】
    1. 抽牌不放回: 每抽一张剩余牌堆就变化（超几何分布），
       而无限牌库每次抽取独立同分布
    2. 洞牌揭晓时机: 首牌 A/10 时看牌翻洞牌；首牌 2~9 时洞牌
       等玩家行动完才发 —— 真实赌场的流程（对无限牌库无差别，
       因为每次抽取独立；对有限牌靴则影响牌堆组成的时序）

    【洞牌的发放时机 —— 真实赌场的规则细节】
    庄家首牌是 A 或 10 时"看牌"(peek): 立即翻洞牌检查黑杰克。
    首牌是 2~9 时不可能有黑杰克，洞牌要等玩家行动完才发 ——
    否则洞牌被提前抽走，会轻微扰动玩家要牌时的牌堆组成。
    统计上差异极小，但既然是"真实赌场模型"，就按真实流程来。
    """
    # ---- 下注（用牌靴真数，此时还没发牌） ----
    bet = float(strategy.bet_units(PlayContext(
        total=0, soft=False, two_card=False, upcard="?",
        hand_ranks=(), shoe=shoe,
    )))
    tc = true_count_of(shoe)

    # ---- 发牌: 玩家两张 + 庄家首牌 ----
    p1, p2 = shoe.draw(), shoe.draw()
    up = shoe.draw()
    upcard = up.rank
    hole: Optional[Card] = None

    player_nat = is_blackjack([p1.rank, p2.rank])

    # ---- 庄家看牌: 首牌 A/10 时翻洞牌 ----
    if upcard == "A" or upcard in TEN_RANKS:
        hole = shoe.draw()
        dealer_nat = ((upcard == "A" and hole.rank in TEN_RANKS)
                      or (upcard in TEN_RANKS and hole.rank == "A"))
        if dealer_nat:
            # 庄家黑杰克: 玩家黑杰克才平局，否则直接输
            if player_nat:
                net, kind = 0.0, "push"
            else:
                net, kind = -bet, "lose"
            return RoundRecord(
                round_index=round_index, shoe_index=shoe_index,
                upcard=upcard, bet_units=bet, net=net, kind=kind, tc=tc,
            )

    # ---- 玩家黑杰克(庄家确认无黑杰克后): 立即赔 1.5 ----
    if player_nat:
        return RoundRecord(
            round_index=round_index, shoe_index=shoe_index,
            upcard=upcard, bet_units=bet, net=1.5 * bet, kind="win", tc=tc,
        )

    # ---- 玩家决策阶段（此时已确认庄家不是黑杰克） ----
    ranks = [p1.rank, p2.rank]
    total, soft = hand_value(ranks)
    two_card = True
    busted = False
    while total < 21 and not busted:
        ctx = PlayContext(
            total=total, soft=soft, two_card=two_card,
            upcard=upcard, hand_ranks=tuple(ranks), shoe=shoe,
        )
        action = strategy.decide(ctx)
        if action == "S":
            break
        if action == "D" and two_card:
            ranks.append(shoe.draw().rank)
            total, soft = hand_value(ranks)
            bet = 2.0 * bet
            busted = total > 21
            break
        # H: 要牌
        ranks.append(shoe.draw().rank)
        total, soft = hand_value(ranks)
        two_card = False
        busted = total > 21

    if busted:
        net, kind = -bet, "lose"
    else:
        # ---- 庄家补牌: 未看牌时此刻才发洞牌 ----
        if hole is None:
            hole = shoe.draw()
        d_ranks = [upcard, hole.rank]
        d_total, d_soft = hand_value(d_ranks)
        while d_total < 17:
            d_ranks.append(shoe.draw().rank)
            d_total, d_soft = hand_value(d_ranks)
        if d_total > 21:
            net, kind = bet, "win"
        else:
            net, kind = settle(total, d_total)
            net *= bet

    return RoundRecord(
        round_index=round_index, shoe_index=shoe_index,
        upcard=upcard, bet_units=bet, net=net, kind=kind, tc=tc,
    )


def monte_carlo_shoe(
    strategy: BaseStrategy,
    n_shoes: int = 1500,
    decks: int = 6,
    seed: Optional[int] = 42,
    cut_fraction: float = 0.25,
) -> ShoeSimulation:
    """
    牌靴蒙特卡洛: 打 n_shoes 靴牌（每靴用到切牌卡为止）。

    【种子的两层设计 —— 配对实验的关键】
    1. 全局 random.seed(seed): 所有调用 random 模块的随机源
       （策略内部若有随机决策）从这个种子开始 —— 保证同一
       策略 + 同一 seed 的两次实验逐局相同（可复现）。
    2. 每靴牌用独立实例 Random(seed_derived)：靴的洗牌序列
       只由 (seed, 靴序号) 决定，与策略无关 —— 因此两个策略
       在相同 seed 下会面对"逐靴相同的牌堆"（每靴的初始洗牌
       与发牌顺序完全一致）。注意: 两个策略要牌的多少不同，
       同一靴内的"第几局"并不逐局对齐，所以配对单元是"靴"
       （每靴一张牌堆、一份运气），而不是局 —— analysis 的
       per_shoe_means 正是按靴聚合。牌运被控制住后，
       剩下的差异只能来自策略本身。
    """
    if seed is not None:
        random.seed(seed)

    simulation = ShoeSimulation(
        strategy=strategy, n_shoes=n_shoes, decks=decks,
        seed=seed, cut_fraction=cut_fraction,
    )
    round_index = 0
    for shoe_index in range(n_shoes):
        shoe_seed = None if seed is None else seed * 1_000_003 + shoe_index
        shoe = Shoe(deck_count=decks, seed=shoe_seed,
                    cut_fraction=cut_fraction)
        while not shoe.needs_reshuffle():
            round_index += 1
            record = play_round_shoe(shoe, strategy, round_index, shoe_index)
            simulation.records.append(record)
    return simulation


# ============================================================
# 交互玩法 — 终端真人 21 点
# ============================================================

def _fmt_hand(cards: List[Card], hide_hole: bool = False) -> str:
    """把 Card 列表格式化: "A♠ 7♦ (硬18)"；hide_hole 时首张显示 ??"""
    parts = []
    for i, c in enumerate(cards):
        if hide_hole and i == 1:
            parts.append("??")
        else:
            parts.append(str(c))
    ranks = [c.rank for c in cards]
    total, soft = hand_value(ranks)
    label = "软" if soft else "硬"
    return "  ".join(parts) + f"  ({label}{total})"


def play_interactive(seed: Optional[int] = None, decks: int = 6) -> None:
    """
    终端交互 21 点（python main.py --play 进入）。

    【玩法说明】
      h = 要牌   s = 停牌   d = 加倍(仅首两张)   q = 退出
    初始筹码 100 单位，每局下注 1 单位（加倍翻倍）。
    牌靴用完 75% 自动洗牌。庄家规则 S17、黑杰克 1.5 倍。

    【Python 知识点: while True + break 的输入循环】
    输入可能非法（既不是 h/s/d/q）—— 循环内 continue
    重新询问，直到合法输入或退出。
    """
    bankroll = 100.0
    shoe = Shoe(deck_count=decks, seed=seed, cut_fraction=0.25)
    round_index = 0

    print("=" * 60)
    print("  21 点 — 终端互动版（庄家软17停牌 / 黑杰克1.5倍）")
    print(f"  初始筹码: {bankroll:.0f} 单位  每局下注 1 单位")
    print("  输入 h=要牌 s=停牌 d=加倍(仅首两张) q=退出")
    print("=" * 60)

    while bankroll >= 1.0:
        round_index += 1
        if shoe.needs_reshuffle():
            shoe.reshuffle()
            print("\n[切牌卡触发，重新洗牌]")

        # 发牌: 玩家两张 + 庄家首牌（洞牌视情况后发）
        p1, p2 = shoe.draw(), shoe.draw()
        up = shoe.draw()
        upcard = up.rank
        hole: Optional[Card] = None
        player_cards = [p1, p2]

        print(f"\n第 {round_index} 局  庄家首牌: {up}   我的牌: {_fmt_hand(player_cards)}")

        # 庄家看牌（首牌 A/10）与玩家黑杰克结算
        p_nat = is_blackjack([p1.rank, p2.rank])
        if upcard == "A" or upcard in TEN_RANKS:
            hole = shoe.draw()
            d_nat = ((upcard == "A" and hole.rank in TEN_RANKS)
                     or (upcard in TEN_RANKS and hole.rank == "A"))
            if d_nat:
                if p_nat:
                    print("双方黑杰克 → 平局")
                else:
                    bankroll -= 1.0
                    print(f"庄家黑杰克! -1 (筹码 {bankroll:.0f})")
                continue

        if p_nat:
            bankroll += 1.5
            print(f"黑杰克! +1.5 (筹码 {bankroll:.0f})")
            continue

        # 决策循环
        total, soft = hand_value([c.rank for c in player_cards])
        two_card = True
        busted = False
        doubled = False
        while total < 21 and not busted:
            hint = f"[{soft and '软' or '硬'}{total}]"
            can_double = two_card and bankroll >= 2.0
            options = f"h/s{'/d' if can_double else ''}/q"
            while True:
                # 【Python 知识点: try/except 兜底输入中断】
                # 终端被关闭 / 管道结束(EOF) / Ctrl+C 时 input() 会抛
                # EOFError / KeyboardInterrupt —— 统一当作"退出"处理，
                # 避免难看的 traceback。
                try:
                    cmd = input(f"  行动? ({options}) {hint} > ").strip().lower()
                except (EOFError, KeyboardInterrupt):
                    print()
                    cmd = "q"
                if cmd in ("h", "s", "q") or (cmd == "d" and can_double):
                    break
                print("  输入无效，请重试。")
            if cmd == "q":
                print(f"提前离场，带走 {bankroll:.0f} 单位。")
                return
            if cmd == "s":
                break
            if cmd == "d":
                doubled = True
                card = shoe.draw()
                player_cards.append(card)
                print(f"  加倍! 补到 {card}  → {_fmt_hand(player_cards)}")
                total, soft = hand_value([c.rank for c in player_cards])
                busted = total > 21
                break
            card = shoe.draw()
            player_cards.append(card)
            print(f"  要牌: {card}  → {_fmt_hand(player_cards)}")
            total, soft = hand_value([c.rank for c in player_cards])
            two_card = False
            busted = total > 21

        stake = 2.0 if doubled else 1.0
        if busted:
            bankroll -= stake
            print(f"爆牌! 输 {stake:.0f} (筹码 {bankroll:.0f})")
            continue

        # 庄家补牌: 先翻出洞牌（首牌 2~9 时此刻才发洞牌）
        if hole is None:
            hole = shoe.draw()
        d_cards = [up, hole]
        print(f"  停牌。庄家翻洞牌: {hole}  → 庄家 {_fmt_hand(d_cards)}")
        d_total, d_soft = hand_value([c.rank for c in d_cards])
        while d_total < 17:
            dc = shoe.draw()
            d_cards.append(dc)
            d_total, d_soft = hand_value([c.rank for c in d_cards])
            print(f"  庄家要牌: {dc}  → {_fmt_hand(d_cards)}")

        if d_total > 21:
            bankroll += stake
            print(f"庄家爆牌! 赢 {stake:.0f} (筹码 {bankroll:.0f})")
        elif total > d_total:
            bankroll += stake
            print(f"点数 {total} > 庄家 {d_total}: 赢 {stake:.0f} (筹码 {bankroll:.0f})")
        elif total == d_total:
            print(f"点数相同 {total} = 庄家 {d_total}: 平局 (筹码 {bankroll:.0f})")
        else:
            bankroll -= stake
            print(f"点数 {total} < 庄家 {d_total}: 输 {stake:.0f} (筹码 {bankroll:.0f})")

    print("\n筹码耗尽，游戏结束。感谢游玩!")
