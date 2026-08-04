"""Genesis legacy RNG — MSVC CRT compatibility generator.

Specification and golden vectors: docs/LEGACY_RNG.md (EXP-R4A-001, EXP-R4B-001).
Binding scope: legacy_behavior. Genesis compatibility mode must reproduce the
global call ordering and use ONE shared instance.

This is not a better random number generator and is not meant to be. It is the
Microsoft CRT `rand()` paired with `_holdrand`, plus the decimal-extension
bounded adapter at `00454C70` and the weighted roller at `00454E80`.

Why one shared state matters
----------------------------
Every ordinary consumer on the main game thread advances the same state: direct
`_rand()`, the bounded adapter, the weighted roller, and everything reaching
either. Adding or removing a single random call in one subsystem therefore
changes later outcomes in every other subsystem until the next explicit reseed.

That is the one recovered fact with a global rather than local consequence, and
it is why the randomness boundary exists: `Rng` (named streams, isolated per
subsystem) is correct for native mode and for differential tests, and cannot
reproduce Genesis. `LegacyRng` reproduces Genesis and deliberately gives up
stream isolation. Both satisfy the same tiny contract:

    roll(x, stream=None) -> int in [0, x-1]

`stream` is accepted and ignored here; it exists so native-mode callers keep
working unchanged.

Trap worth naming
-----------------
`Rng.roll` returns 0 for x <= 1 WITHOUT consuming a value. The original does not
work that way: bound 0 consumes nothing, but bound 1 consumes one value and
returns 0. Short-circuiting bound 1 silently shifts every subsequent result.
"""

from __future__ import annotations

MASK32 = 0xFFFFFFFF


class LegacyRng:
    """One mutable CRT state per emulated game thread/session."""

    def __init__(self, seed: int = 1):
        self.state = seed & MASK32
        self.calls = 0            # CRT advances, for trace assertions
        self.epoch = "unseeded"
        self.trace: list = []     # optional; see enable_trace()
        self._tracing = False

    # -- core generator -----------------------------------------------------

    def seed(self, value: int, epoch: str = "") -> None:
        self.state = value & MASK32
        if epoch:
            self.epoch = epoch

    def next_u15(self) -> int:
        """Advances BEFORE returning, then takes bits 16..30."""
        self.state = (self.state * 214013 + 2531011) & MASK32
        self.calls += 1
        return (self.state >> 16) & 0x7FFF

    def below(self, bound: int) -> int:
        """Bounded adapter at `00454C70`.

        Extends precision by appending decimal digits when the bound exceeds
        30000. The loop condition is strictly `> 30000`; the reduced bound only
        controls how many digits are appended; the final modulo uses the
        ORIGINAL bound, so the modulo bias is preserved deliberately.
        """
        if bound == 0:
            return 0                      # consumes nothing
        before, before_calls = self.state, self.calls
        value = self.next_u15()
        reduced = bound
        while reduced > 30000:
            reduced //= 10
            value = (value * 10 + self.next_u15() % 10) & MASK32
        result = value % bound
        if self._tracing:
            self.trace.append({
                "epoch": self.epoch, "consumer": "below", "bound": bound,
                "state_before": before, "state_after": self.state,
                "advances": self.calls - before_calls, "value": result,
            })
        return result

    # -- native-mode-compatible surface -------------------------------------

    def roll(self, x: int, stream: str | None = None) -> int:
        """Drop-in for `Rng.roll`. `stream` is accepted and ignored.

        Note the deliberate difference from `Rng.roll`: x == 1 consumes a value
        here, because the original does.
        """
        if x <= 0:
            return 0
        return self.below(x)

    # -- weighted roller ----------------------------------------------------

    def weighted(self, values: list, weights: list, remove_selected: bool = False):
        """Weighted selection at `00454E80`.

        Removal is BY SELECTED VALUE, not by selected index: duplicate values
        all drop to weight zero. Returns (selected_value, weights_after).

        Total weight zero is open question 6b — the original's behaviour is not
        established, so this raises rather than inventing a silent fallback.
        """
        if len(values) != len(weights):
            raise ValueError("values and weights must be parallel")
        total = sum(weights)
        if total <= 0:
            raise ValueError(
                "total weight is zero — behaviour unrecovered (OPEN_QUESTIONS 6b); "
                "compatibility code must not invent a fallback")
        roll = self.below(total)
        cumulative = 0
        selected = None
        for value, weight in zip(values, weights):
            cumulative += weight
            if cumulative > roll:
                selected = value
                break
        out = list(weights)
        if remove_selected and selected is not None:
            for i, value in enumerate(values):
                if value == selected:
                    out[i] = 0
        return selected, out

    # -- recovered reseed epochs -------------------------------------------

    def seed_map_generation(self, map_seed: int) -> int:
        """`if map_seed == 0: map_seed = 111` then `crt_srand(map_seed)`.

        Returns the effective map seed, because the zero substitution is
        observable downstream.
        """
        effective = 111 if map_seed == 0 else map_seed
        self.seed(effective, epoch="map_generation")
        return effective

    def seed_strategic_turn(self, map_seed: int, strategic_turn: int) -> None:
        """`crt_srand(map_seed + strategic_turn)`, uint32 arithmetic.

        A strategic turn therefore does NOT inherit the terminal state of the
        preceding turn, though call order within the turn is still binding.
        """
        self.seed((map_seed + strategic_turn) & MASK32,
                  epoch="strategic_turn/%d" % strategic_turn)

    # -- diagnostics --------------------------------------------------------

    def enable_trace(self, on: bool = True) -> None:
        self._tracing = on

    def snapshot(self) -> dict:
        return {"state": self.state, "calls": self.calls, "epoch": self.epoch}

    def restore(self, snap: dict) -> None:
        self.state = int(snap["state"]) & MASK32
        self.calls = int(snap.get("calls", 0))
        self.epoch = snap.get("epoch", self.epoch)
