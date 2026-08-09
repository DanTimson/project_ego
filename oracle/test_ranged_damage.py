"""CX-012 deterministic vectors for the frozen ranged-damage calculator."""

import combat
import handlers
from combat import Combatant, current_resistance, resolve_ranged_attack, trunc0_half
from content import AbilityRegistry
from modifier import Hook, Modifier, Pipeline


class MidpointRng:
    """Resolver seam: makes attack 20 randomise to exactly 20."""

    def roll(self, x: int, stream: str = "combat") -> int:
        return x // 2


def numeric_modifier(ability: int, power: int = 1) -> Modifier:
    return Modifier(
        ability=ability, handler="cx012_numeric_branch",
        hook=Hook.DAMAGE_VS_TARGET, power=power,
        source=f"modifier {ability:#04x}")


def resistance_modifier(power: int) -> Modifier:
    return Modifier(
        ability=0x06, handler="stat_delta", hook=Hook.STAT_PASSIVE,
        power=power, params={"stat": "resist"},
        source="represented resistance provider")


def pipeline() -> Pipeline:
    registry = AbilityRegistry()
    handlers.register_all(registry)
    return Pipeline(registry)


def resolve(*, ranged_defence: int, resistance: int,
            modifiers: list[Modifier] | None = None,
            target_modifiers: list[Modifier] | None = None):
    attacker = Combatant(
        name="attacker", ranged_attack=20, life=30, life_base=30,
        stamina=10, stamina_base=10, morale=10,
        modifiers=list(modifiers or []))
    defender = Combatant(
        name="target", ranged_defence=ranged_defence, resist=resistance,
        life=40, life_base=40, stamina=10, stamina_base=10, morale=10,
        modifiers=list(target_modifiers or []))
    combat.bind_pipeline(pipeline())
    try:
        return resolve_ranged_attack(attacker, defender, MidpointRng())
    finally:
        combat.bind_pipeline(None)


def sources(traces) -> list[str]:
    return [step[0] for trace in traces for step in trace.steps]


def represented_resistance(base: int, provider_power: int):
    defender = Combatant(
        name="target", resist=base, life=40, life_base=40,
        stamina=0, stamina_base=10, morale=10,
        modifiers=[resistance_modifier(provider_power)])
    combat.bind_pipeline(pipeline())
    try:
        return current_resistance(defender)
    finally:
        combat.bind_pipeline(None)


def test_effective_resistance_provider_and_final_clamp() -> None:
    resistance, trace = represented_resistance(4, 3)
    # Base 4 + provider 3 stays 7 even at stamina 0; defence halving does not apply.
    assert resistance == 7

    resistance, trace = represented_resistance(2, -7)
    assert resistance == 0  # provider total -5, then the independent final clamp
    ordered = sources([trace])
    assert ordered.index("resistance provider total") < ordered.index(
        "final resistance clamp")
    clamp = next(step for step in trace.steps
                 if step[0] == "final resistance clamp")
    assert clamp[1:3] == (-5, 0)


def test_clamped_resistance_reaches_both_ranged_consumers() -> None:
    negative_provider = [resistance_modifier(-7)]  # base 2 -> provider total -5

    damage, traces, channel = resolve(
        ranged_defence=12, resistance=2,
        modifiers=[numeric_modifier(0x1C), numeric_modifier(0x5F, 3)],
        target_modifiers=negative_provider)
    # Clamp -5 to 0, then subtract 0x5F value 3: 20 - (0 - 3) = 23.
    assert (damage, channel) == (23, 2)
    ordered = sources(traces)
    assert ordered.index("final resistance clamp") < ordered.index(
        "modifier 0x5F resistance subtraction") < ordered.index(
        "defence subtraction")

    damage, traces, channel = resolve(
        ranged_defence=7, resistance=2,
        modifiers=[numeric_modifier(0x3C, 3)],
        target_modifiers=negative_provider)
    # Resolver: 20 - 7 = 13. Excess uses clamped 0: 3 - 0 = 3.
    assert (damage, channel) == (16, 1)
    excess_step = next(step for trace in traces for step in trace.steps
                       if step[0] == "modifier 0x3C excess over resistance")
    assert excess_step[3] == "max(0, 3 - 0)"


def test_frozen_ranged_damage_branches() -> None:
    cases = [
        # Ranged defence and resistance deliberately differ.
        ("ordinary ranged defence", 7, 2, [], 13, 1),
        ("0x1C resistance channel", 2, 4,
         [numeric_modifier(0x1C)], 16, 2),
        ("0x1C plus 0x5F", 2, 7,
         [numeric_modifier(0x1C), numeric_modifier(0x5F, 3)], 16, 2),
        ("0x11 before 0x4D", 9, 20,
         [numeric_modifier(0x11), numeric_modifier(0x4D, 3)], 19, 1),
        ("0x4D without 0x11", 9, 20,
         [numeric_modifier(0x4D, 3)], 14, 1),
        ("0x3C positive excess", 7, 3,
         [numeric_modifier(0x3C, 8)], 18, 1),
        ("0x3C no excess control", 7, 3,
         [numeric_modifier(0x3C, 3)], 13, 1),
        ("0x1C returns before non-resistance tail", 12, 3, [
            numeric_modifier(0x1C), numeric_modifier(0x11),
            numeric_modifier(0x4D, 9), numeric_modifier(0x3C, 8),
        ], 17, 2),
    ]
    for label, ranged_defence, resistance, modifiers, expected, channel in cases:
        damage, traces, got_channel = resolve(
            ranged_defence=ranged_defence, resistance=resistance,
            modifiers=modifiers)
        assert (damage, got_channel) == (expected, channel), label


def test_frozen_ranged_damage_stage_controls() -> None:
    damage, traces, channel = resolve(
        ranged_defence=9, resistance=20,
        modifiers=[numeric_modifier(0x11), numeric_modifier(0x4D, 3)])
    ordered = sources(traces)
    assert damage == 19 and channel == 1
    assert ordered.index("modifier 0x11 ranged-defence halving") < ordered.index(
        "modifier 0x4D ranged-defence subtraction") < ordered.index(
        "defence subtraction")

    damage, traces, channel = resolve(
        ranged_defence=12, resistance=3,
        modifiers=[numeric_modifier(0x1C), numeric_modifier(0x11),
                   numeric_modifier(0x4D, 9), numeric_modifier(0x3C, 8)])
    assert (damage, channel) == (17, 2)
    assert "modifier 0x11 ranged-defence halving" not in sources(traces)
    assert "modifier 0x4D ranged-defence subtraction" not in sources(traces)
    assert "modifier 0x3C excess over resistance" not in sources(traces)


def test_zero_valued_0x1c_does_not_select_resistance() -> None:
    damage, _traces, channel = resolve(
        ranged_defence=7, resistance=2,
        modifiers=[numeric_modifier(0x1C, 0)])
    assert (damage, channel) == (13, 1)


def test_signed_half_is_truncating_not_flooring() -> None:
    assert trunc0_half(5) == 2
    assert trunc0_half(-5) == -2
    assert trunc0_half(9_007_199_254_740_995) == 4_503_599_627_370_497
    assert trunc0_half(-9_007_199_254_740_995) == -4_503_599_627_370_497
