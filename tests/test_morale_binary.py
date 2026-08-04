#!/usr/bin/env python3
"""Binary-derived fixtures for STATS-MORALE-001 and STATS-MORALE-002.

Sources:
- EXP-R1-001: Genesis 1.05.2 effective attack/counterattack/ranged functions.
- DOC-NH-MORALE: independently agreeing published NH morale table.

Run from the repository root:
    python3 oracle/test_morale_binary.py
"""

from __future__ import annotations

import math

from combat import AttackKind, Combatant, current_attack, morale_band, morale_mod


EXPECTED_MULTIPLIERS = {
    0: 0.40,
    1: 0.50,
    2: 0.60,
    3: 0.70,
    4: 0.80,
    5: 0.90,
    6: 1.00,
    15: 1.00,
    16: 1.05,
    17: 1.05,
    18: 1.10,
    20: 1.10,
    21: 1.15,
    24: 1.15,
    25: 1.20,
    29: 1.20,
    30: 1.25,
    35: 1.25,
    36: 1.30,
    42: 1.30,
    43: 1.35,
    50: 1.35,
    51: 1.40,
    59: 1.40,
    60: 1.45,
}

EXPECTED_BANDS = {
    16: 1,
    17: 1,
    18: 2,
    20: 2,
    21: 3,
    24: 3,
    25: 4,
    29: 4,
    30: 5,
    35: 5,
    36: 6,
    42: 6,
    43: 7,
    50: 7,
    51: 8,
    59: 8,
    60: 9,
}

# Explicit binary output vectors. These catch the integer truncation at the
# pre-morale stat, which a pure multiplier table cannot express.
TRUNCATION_VECTORS = [
    (19, 16, 19),
    (20, 16, 21),
    (19, 18, 20),
    (7, 21, 8),
]


def fail(message: str) -> None:
    raise AssertionError(message)


def resolved_stat(base: int, morale: int, kind: AttackKind) -> int:
    unit = Combatant(
        attack=base,
        counter_attack=base,
        ranged_attack=base,
        life_base=100,
        life=100,
        stamina_base=10,
        stamina=10,
        morale_base=999,  # proves the curve uses absolute morale
        morale=morale,
    )
    value, _trace = current_attack(unit, kind)
    return int(math.floor(value))


def test_multiplier_table() -> None:
    for morale, expected in EXPECTED_MULTIPLIERS.items():
        unit = Combatant(morale=morale, morale_base=999)
        got, _ = morale_mod(unit)
        if not math.isclose(got, expected, rel_tol=0.0, abs_tol=1e-12):
            fail(f"morale {morale}: multiplier {got}, expected {expected}")


def test_band_boundaries() -> None:
    for morale, expected in EXPECTED_BANDS.items():
        got = morale_band(morale)
        if got != expected:
            fail(f"morale {morale}: band {got}, expected {expected}")


def test_three_offensive_stats() -> None:
    expected = {
        15: 100,
        16: 105,
        17: 105,
        18: 110,
        20: 110,
        21: 115,
        24: 115,
        25: 120,
        30: 125,
        36: 130,
        43: 135,
        51: 140,
    }
    for kind in AttackKind:
        for morale, want in expected.items():
            got = resolved_stat(100, morale, kind)
            if got != want:
                fail(
                    f"{kind.value}, morale {morale}: stat {got}, expected {want}"
                )


def test_integer_truncation_vectors() -> None:
    for kind in AttackKind:
        for base, morale, want in TRUNCATION_VECTORS:
            got = resolved_stat(base, morale, kind)
            if got != want:
                fail(
                    f"{kind.value}, base {base}, morale {morale}: "
                    f"stat {got}, expected {want}"
                )


def main() -> None:
    test_multiplier_table()
    test_band_boundaries()
    test_three_offensive_stats()
    test_integer_truncation_vectors()
    print("PASS: STATS-MORALE-001 and STATS-MORALE-002")


if __name__ == "__main__":
    main()
