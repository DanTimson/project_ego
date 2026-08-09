# oracle/combat.py
"""
combat.py — executable reference implementation of the Eador attack pipeline.

Source: Eadoropedia "Игровая механика", sections «Расчёт урона при атаках»,
«Тяжёлые ранения», «Выносливость», «Боевой дух (мораль)».

This is Python, not GDScript, on purpose. It runs in CI today, its outputs are
diffable, and it is the ORACLE the Godot port gets checked against. Porting it
is mechanical; verifying it is not, so verification happens here first.

Every quantity carries a Trace. That is not a debug convenience — it is the
tooltip system, the combat log, and the diff target against the original, all
the same object.

MASTER FORMULA (documented verbatim):

    ТекущаяАтака = (БазоваяАтака + ПлюсуемыеБонусы) * StaminaMod * MoraleMod * WoundMod

then randomised, then reduced by defence, then the negative-damage rule.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from enum import Enum


# ---------------------------------------------------------------------------
# Deterministic RNG with named streams.
#
# Named streams so that adding a roll in one subsystem does not shift every
# other subsystem's sequence. Without this, any rules change invalidates every
# stored replay and differential testing becomes impossible.
#
# STATUS: the original generator is no longer unknown. It is the MSVC CRT
# recurrence, implemented in oracle/legacy_rng.py from docs/LEGACY_RNG.md.
#
# This class is NOT that, and is not a candidate for Genesis parity. Named
# streams are structurally incompatible with the original, which advances one
# shared CRT state across every consumer — see LegacyRng's header. Per
# LEGACY_RNG.md they remain available for isolated tests and for an explicitly
# Project-EGO-native deterministic mode, and must not be described as legacy
# parity.
#
# Which generator a battle uses is decided once, at Scenario construction; rules
# never choose and never branch on mode.
# ---------------------------------------------------------------------------

class Rng:
    """Integer rolls only. `roll(x)` returns a uniform integer in [0, x-1],
    matching the Eadoropedia's `Random(x)` convention exactly.

    PORTABILITY IS THE POINT. Stream seeding uses FNV-1a over the UTF-8 bytes
    of the stream name, NOT the host language's `hash()`. Python randomises
    string hashing per process (PYTHONHASHSEED), so an earlier version of this
    class produced a different sequence on every run — which silently defeats
    fixtures, replays, and any differential test against the original. The
    algorithm below is fully specified so the GDScript port produces bit-identical
    streams; see tests/test_rng.gd.

        FNV-1a 32-bit:  h = 2166136261;  for each byte: h ^= b; h *= 16777619
        stream seed  :  fnv1a(name) XOR (seed * 2654435761), forced odd-nonzero
        step         :  s = (1103515245 * s + 12345) mod 2^31
    """

    FNV_OFFSET = 2166136261
    FNV_PRIME = 16777619
    MASK32 = 0xFFFFFFFF
    MASK31 = 0x7FFFFFFF

    def __init__(self, seed: int):
        self._seed = seed & self.MASK32
        self._streams: dict[str, int] = {}
        self.calls: dict[str, int] = {}

    @classmethod
    def fnv1a(cls, text: str) -> int:
        h = cls.FNV_OFFSET
        for b in text.encode("utf-8"):
            h = ((h ^ b) * cls.FNV_PRIME) & cls.MASK32
        return h

    def _state(self, stream: str) -> int:
        if stream not in self._streams:
            mixed = (self._seed * 2654435761) & self.MASK32
            s = (self.fnv1a(stream) ^ mixed) & self.MASK31
            self._streams[stream] = s or 1
            self.calls[stream] = 0
        return self._streams[stream]

    def roll(self, x: int, stream: str = "combat") -> int:
        """Uniform integer in [0, x-1]. Returns 0 for x <= 1."""
        if x <= 1:
            return 0
        s = self._state(stream)
        s = (1103515245 * s + 12345) & self.MASK31
        self._streams[stream] = s
        self.calls[stream] += 1
        return s % x


# ---------------------------------------------------------------------------
# Trace
# ---------------------------------------------------------------------------

@dataclass
class Trace:
    label: str
    base: float = 0.0
    steps: list = field(default_factory=list)
    result: float = 0.0

    def step(self, source: str, before: float, after: float, note: str = "") -> None:
        if before != after or note:
            self.steps.append((source, before, after, note))

    def explain(self, indent: str = "") -> str:
        out = [f"{indent}{self.label}: base {_fmt(self.base)}"]
        for source, before, after, note in self.steps:
            tail = f"   # {note}" if note else ""
            out.append(f"{indent}  {source:<26} {_fmt(before)} -> {_fmt(after)}{tail}")
        out.append(f"{indent}  = {_fmt(self.result)}")
        return "\n".join(out)


def _fmt(v: float) -> str:
    return str(int(v)) if float(v).is_integer() else f"{v:.3f}"


# ---------------------------------------------------------------------------
# Combatant state
#
# Deliberately a plain dataclass with no engine types. `flags` is a set of
# ability names rather than an enum: which abilities exist is CONTENT and
# differs between the genesis and new_horizons packs, so it cannot be a
# compile-time enum. See the pack-bindings decision.
# ---------------------------------------------------------------------------

class AttackKind(Enum):
    MELEE = "melee"
    COUNTER = "counter"
    RANGED = "ranged"


# eq=False gives Combatant IDENTITY semantics: two units with identical stats are
# not the same unit, and `==` should say so. It also makes instances hashable,
# which auras need — an aura is keyed by the unit projecting it, and a dataclass
# with the default eq=True sets __hash__ to None.
@dataclass(eq=False)
class Combatant:
    name: str = "unit"
    # BATTLE-INSTANCE identity: the handle addressing this particular combatant
    # within one battle. Distinct from `name`, which is presentation, and from
    # `content_id`, which is the definition it came from. Three identities,
    # because an army can field several units of one type: they share a
    # content_id, they share a display name, and they must still be individually
    # addressable. DELIB-0001 decision item 6.
    #
    # Defaults to the display name, so a scenario that declares no explicit
    # instance id behaves exactly as before.
    instance_id: str = ""

    # The content DEFINITION this instance was built from, e.g.
    # "genesis:unit/5". Empty for inline synthetic units declared directly in a
    # scenario, which are battle-local and are NOT pack content — see
    # DELIB-0001 decision item 6, which keeps content identity, battle-instance
    # identity and display name distinct. `name` remains presentation only.
    content_id: str = ""
    # base (unmodified) stats
    attack: int = 0
    counter_attack: int = 0
    ranged_attack: int = 0
    shooting_range: int = 0
    defence: int = 0
    ranged_defence: int = 0
    resist: int = 0
    life_base: int = 1
    life: int = 1
    stamina_base: int = 10
    stamina: int = 10
    morale_base: int = 10
    morale: int = 10
    speed: int = 1
    # additive bonuses that ARE inside the multiplier chain
    # (commander auras, spell buffs — the ones visible in the unit panel)
    attack_bonus: int = 0
    defence_bonus: int = 0
    # already-applicable conditional attack contribution; R10 places modifier
    # 0x3D after effective-stat/selected-branch processing, before randomisation
    conditional_bonus: int = 0

    ## Unit-owned innate/content modifiers: the represented persistent-instance
    ## and intrinsic channel. Timed effects and environment/auras use the
    ## separate containers below. `attack_bonus` and `defence_bonus` remain
    ## shorthand for simple scenarios.
    modifiers: list = field(default_factory=list)

    ## Timed effects. They contribute Modifiers through the same pipeline as
    ## everything else, so a status never computes a number itself.
    statuses: list = field(default_factory=list)

    # Address-free definition identity/state needed by the tactical death
    # lifecycle. ``original_definition`` is a deliberately narrow static
    # definition snapshot, never a clone of mutable battle state.
    definition_id: int = 0
    tier: int = 1
    original_definition: dict = field(default_factory=dict)
    battle_owned: bool = False
    discarded: bool = False

    flags: set = field(default_factory=set)
    subtypes: set = field(default_factory=set)

    # --- resources and per-round state -------------------------------------
    ammo: int = 0
    ammo_base: int = 0
    morale_break_accumulator: int = 0
    damage_received: list[int] = field(default_factory=lambda: [0, 0, 0, 0])
    # Final death clears living occupancy but retains this neutral tactical
    # coordinate for deterministic traces and a future corpse layer.
    last_position: object | None = None
    ## Set when an action that consumes the activation has been used this round.
    ## Movement is tracked separately, since a unit may move, yield, and return.
    action_spent: bool = False
    ## Tiles still spendable this round. Reset at ROUND_START from effective
    ## speed, which already includes the stamina penalty.
    movement_remaining: int = 0
    ## Set when the unit hits 0 stamina; consumes the next round entirely.
    forced_rest: bool = False
    ## Rested this round, so it forgoes counterattacks.
    resting: bool = False
    ## Восстановление сил, added to the base +2 on rest.
    stamina_recovery: int = 0
    alive: bool = True
    ## Sources that have fired their «только один раз за ход» effect this round.
    ## Cleared by begin_round and by NOTHING else — an extra turn must not
    ## refill it, or Кровавое безумие would chain without bound.
    once_per_round: set = field(default_factory=set)
    ## Cumulative path length this round — NOT displacement. Retained as
    ## trace-visible movement history; Genesis charge and R8 stamina cost do not
    ## consume it.
    steps_this_round: int = 0

    _DEFINITION_FIELDS = (
        "name", "content_id", "definition_id", "tier", "attack",
        "counter_attack", "ranged_attack", "shooting_range", "defence",
        "ranged_defence", "resist", "life_base", "stamina_base",
        "morale_base", "speed", "ammo_base", "flags", "subtypes",
        "modifiers",
    )

    def definition_snapshot(self) -> dict:
        """Copy only static definition identity/stat providers.

        Current life/resources, position, activation state, runtime statuses and
        other mutable tactical fields are intentionally excluded.
        """
        import copy
        return {key: copy.deepcopy(getattr(self, key))
                for key in self._DEFINITION_FIELDS}

    def restore_definition(self, snapshot: dict) -> None:
        """Restore the accepted temporary-transformation identity surface."""
        import copy
        for key in self._DEFINITION_FIELDS:
            if key in snapshot:
                setattr(self, key, copy.deepcopy(snapshot[key]))

    def label(self) -> str:
        """Display text for logs and traces.

        The display name alone, unless an explicit battle-instance id was given
        — in which case the id is appended, because two units of one type share a
        name and a log line naming only «Мечник» would be ambiguous about which
        one acted.
        """
        if self.instance_id and self.instance_id != self.name:
            return "%s(%s)" % (self.name, self.instance_id)
        return self.name

    def has_flag(self, f: str) -> bool:
        """A flag is DERIVED, not stored.

        `self.flags` holds flags set directly — by a scenario, a test, or a
        rule. But a flag can also come from an ability, and abilities live in
        the modifier list; and a modifier can come from a status effect, which
        expires.

        Checking all three sources here means a spell granting Неутомимый for
        three rounds works with no extra machinery: the modifier appears when
        the status is applied and vanishes when it expires, and every existing
        `has_flag` call site — wounds, stamina, counterattack — follows along
        without knowing statuses exist.

        The alternative was to have the roster run grant_flag at build time and
        mutate `flags`. That works for innate abilities and silently fails for
        every temporary one.
        """
        if f in self.flags:
            return True
        for m in self.modifiers:
            if m.handler == "grant_flag" and m.params.get("flag") == f:
                return True
        for effect in self.statuses:
            for m in effect.modifiers:
                if m.handler == "grant_flag" and m.params.get("flag") == f:
                    return True
        return False

    def has_modifier_id(self, ability: int) -> bool:
        """Numeric modifier membership from the unit and active statuses.

        Environment providers remain battle-contextual and are added by
        ``has_effective_modifier`` at the combat seam.
        """
        if any(m.ability == ability for m in self.modifiers):
            return True
        return any(m.ability == ability
                   for effect in self.statuses for m in effect.modifiers)

    def all_flags(self) -> set:
        """Every flag from every source. For display and for the AI."""
        out = set(self.flags)
        for m in self.modifiers:
            if m.handler == "grant_flag" and m.params.get("flag"):
                out.add(m.params["flag"])
        for effect in self.statuses:
            for m in effect.modifiers:
                if m.handler == "grant_flag" and m.params.get("flag"):
                    out.add(m.params["flag"])
        return out

    def has_subtype(self, s: str) -> bool:
        return s in self.subtypes

    def moved_this_round(self) -> bool:
        return self.steps_this_round > 0

    def reset_round(self) -> None:
        self.action_spent = False
        self.steps_this_round = 0

    def base_attack_for(self, kind: AttackKind) -> int:
        return {
            AttackKind.MELEE: self.attack,
            AttackKind.COUNTER: self.counter_attack,
            AttackKind.RANGED: self.ranged_attack,
        }[kind]

    def base_defence_for(self, kind: AttackKind) -> int:
        return self.ranged_defence if kind is AttackKind.RANGED else self.defence


# ---------------------------------------------------------------------------
# The three multipliers
# ---------------------------------------------------------------------------

def wound_mod(u: Combatant) -> tuple[float, str]:
    """«Тяжёлые ранения»: below 50% life, 0.5 + current/base.

    Exceptions are documented explicitly: «Не чувствует боли» and the
    «Боевое безумие» effect both suppress the penalty entirely.
    """
    if u.has_flag("Не чувствует боли") or u.has_flag("Боевое безумие"):
        return 1.0, "immune to wound penalty"
    if u.life >= u.life_base * 0.5:
        return 1.0, ""
    return 0.5 + u.life / u.life_base, f"life {u.life}/{u.life_base}"


def stamina_mod(u: Combatant) -> tuple[float, str]:
    """«Усталость»: at stamina <= 5, 0.4 + 0.1 * stamina.

    Derived from the LIVE stamina value. Modifier 0x12 «Неутомимость» is not
    consulted: R11's write audit found that every recovered tactical stamina
    mutation queries 0x12, but no recovered effective-stat function does —
    effective attack, counterattack, ranged attack, speed and both defences all
    derive their penalties from the current value.

    The previous flag check was an inference ("such a unit never loses stamina,
    so it never reaches the penalty band"). That is false whenever stamina is set
    directly by a script, an import, malformed content or a mod, and it produced
    a unit that was simultaneously at low stamina and unpenalised. 0x12 is
    stamina-mutation immunity, not penalty immunity.
    """
    if u.stamina > 5:
        return 1.0, ""
    return 0.4 + 0.1 * u.stamina, f"stamina {u.stamina}"


# --- MoraleMod ------------------------------------------------------------
#
# Keyed on ABSOLUTE morale. morale_base does NOT enter the attack multiplier —
# the earlier delta-from-base form was a placeholder shape, not the rule.
#
#   morale 0..5   ->  0.4 + 0.1 * morale     (0 -> 0.4, and the unit panics)
#   morale 6..15  ->  1.0
#   morale >= 16  ->  1.0 + 0.05 * n, band n starting at 15 + n(n+1)/2
#                     16-17 = 1.05  18-20 = 1.10  21-24 = 1.15  25-29 = 1.20
#                     30-35 = 1.25  36-42 = 1.30  43-50 = 1.35  … («и так далее»)
#
# 0..15 is VERIFIED: the Genesis binary's «−10% per missing point below 6» and
# the published table's 0.4 + 0.1*morale are the same function at every point,
# across two independent sources and two builds. See docs/FORMULAS.md §1.4.
#
# >=16 is STRONG INFERENCE for Genesis: both sources agree the step is 5%, but
# the band widths come only from NH 26.0620.f01 documentation and the Genesis
# high-morale branch has not been read. OPEN_QUESTIONS item 1.
#
# Applies to the three ATTACK values only, never to defence.
#
# The band index is computed iteratively rather than by solving the quadratic
# with a float sqrt, so this and the GDScript port agree bit for bit.


def _trunc(x: float) -> int:
    """C integer division truncates toward zero, not toward negative infinity.
    Python's // floors, which diverges for the negative bonuses below morale 6.
    """
    return int(x)


def morale_band(morale: int) -> int:
    """Band index n for morale >= 16; multiplier is 1.0 + 0.05 * n."""
    n = 1
    while 15 + (n + 1) * (n + 2) // 2 <= morale:
        n += 1
    return n


def morale_percent(u: Combatant) -> tuple[int, str]:
    """Morale as the INTEGER percentage the binary actually applies.

    The executable does not multiply by a float. After the wound and stamina
    steps it converts the internal x100 value back to an integer and then adds
    a whole-percent bonus:

        pre_morale = scaled_attack / 100
        result     = pre_morale + bonus_percent * pre_morale / 100

    Both divisions are C integer divisions, truncating toward zero.
    See docs/FORMULAS.md 1.4 (source EXP-R1-001).
    """
    if u.has_flag("Боевое безумие"):
        return 0, "morale effects suppressed"
    m = u.morale
    if m <= 5:
        # -10 percentage points per point of morale missing below 6.
        return -10 * (6 - max(m, 0)), f"morale {m}"
    if m <= 15:
        return 0, ""
    return 5 * morale_band(m), f"morale {m}"


def morale_mod(u: Combatant) -> tuple[float, str]:
    """The documented multiplier view of the same curve.

    Kept for the published-table fixtures and for tracing. The attack pipeline
    uses morale_percent() instead, because a float multiplier cannot reproduce
    the binary: 1.15 is not exactly representable, so 100 * 1.15 truncates to
    114 where the executable returns 115.
    """
    pct, note = morale_percent(u)
    return 1.0 + pct / 100.0, note


# ---------------------------------------------------------------------------
# Attack value
# ---------------------------------------------------------------------------

# Set by rules.bind_pipeline(). None means "no content loaded" — the scalar
# attack_bonus/defence_bonus path still works, which is what keeps every
# pre-existing test and scenario valid.
_PIPELINE = None
_CONTEXT_EXTRA = {}


def bind_pipeline(pipeline) -> None:
    """Install the modifier pipeline. Called once, after content loads."""
    global _PIPELINE
    _PIPELINE = pipeline


## Supplies modifiers that come from the unit's SURROUNDINGS rather than from the
## unit — auras today, terrain later. Injected rather than imported, because those
## need the battlefield and the side layout, and combat must not depend on either.
_ENVIRONMENT = None


def bind_environment(provider) -> None:
    """`provider(unit) -> list[Modifier]`. Pass None to detach."""
    global _ENVIRONMENT
    _ENVIRONMENT = provider


def _later_modifiers(u) -> list:
    """Runtime/status and environment/aura providers already stored separately."""
    out = []
    for effect in u.statuses:
        out.extend(effect.modifiers)
    if _ENVIRONMENT is not None:
        out.extend(_ENVIRONMENT(u))
    return out


def effective_modifiers(u) -> list:
    """Every modifier acting on this unit, from every represented source."""
    return list(u.modifiers) + _later_modifiers(u)


def has_effective_modifier(u, ability: int) -> bool:
    """Numeric modifier membership across every available provider."""
    return any(m.ability == ability for m in effective_modifiers(u))


def effective_modifier_value(u, ability: int) -> int:
    """Signed numeric total for one modifier ID across represented providers."""
    return sum(int(m.power) for m in effective_modifiers(u)
               if m.ability == ability)


def _offensive_disabled(u) -> bool:
    return has_effective_modifier(u, 0x26) or u.has_flag("Не сражается")


def _run_hook_for(base, mods, hook, ctx, label):
    if _PIPELINE is None or not mods:
        return base, None
    return _PIPELINE.resolve(base, mods, hook, ctx, label)


def _run_hook(base, u, hook, ctx, label):
    return _run_hook_for(base, effective_modifiers(u), hook, ctx, label)


def _append_hook_steps(trace, resolved, before):
    value, subtrace = resolved
    if subtrace is not None and value != before:
        trace.steps.extend(subtrace.steps)
    return value


def current_attack(u: Combatant, kind: AttackKind) -> tuple[float, Trace]:
    """(base + additive) * StaminaMod * MoraleMod * WoundMod.

    Order is documented and not negotiable: «Сначала к Атаке применяются
    "плюсуемые" бонусы ... а потом уже "умножаемые"».
    """
    t = Trace(f"{u.name}.{kind.value}_attack")
    base = u.base_attack_for(kind)
    t.base = base
    value = float(base)

    # R6: the three effective-attack functions do NOT share entry semantics.
    #
    # Melee and counterattack test modifier 0x26
    # «Не сражается» first and return zero outright. The final minimum-one clamp
    # is never reached on that path.
    if kind in (AttackKind.MELEE, AttackKind.COUNTER) and _offensive_disabled(u):
        t.step("modifier 0x26 «Не сражается»", value, 0.0, "cannot attack")
        t.result = 0.0
        return 0.0, t

    from modifier import Hook
    ctx = {"stat": _STAT_FOR_KIND[kind], "unit": u, "kind": kind}
    if kind is AttackKind.RANGED:
        # Existing unit modifiers are the represented instance/intrinsic
        # channel. Resolve them before the separately stored status/environment
        # channels, which are later providers for the accepted R6 cutoff.
        early = _run_hook_for(value, u.modifiers, Hook.STAT_PASSIVE, ctx,
                              "early unit modifiers")
        value = _append_hook_steps(t, early, value)
        t.step("ranged early provider total", base, value,
               "definition plus unit modifiers; "
               "status/environment not consulted")
        if _trunc(value) == 0:
            t.step("ranged zero-sum early return", value, 0.0,
                   "before runtime/status/environment, state and clamp")
            t.result = 0.0
            return 0.0, t

        # The scalar shorthand is documented as battle-visible spell/aura input,
        # so it remains on the later side of the ranged cutoff.
        if u.attack_bonus:
            nv = value + u.attack_bonus
            t.step("later additive bonuses", value, nv)
            value = nv
        later = _run_hook_for(value, _later_modifiers(u), Hook.STAT_PASSIVE,
                              ctx, "status/environment modifiers")
        value = _append_hook_steps(t, later, value)
    else:
        # Preserve established melee/counter behavior: scalar and all modifier
        # sources still resolve as one combined additive stage.
        if u.attack_bonus:
            nv = value + u.attack_bonus
            t.step("additive bonuses", value, nv)
            value = nv
        passive = _run_hook(value, u, Hook.STAT_PASSIVE, ctx, "modifiers")
        value = _append_hook_steps(t, passive, value)

    # Stamina and wound act inside the x100 scaled domain; morale is applied
    # LAST, on an integer, as a whole-percent bonus. The order is the binary's,
    # not a rearrangement of the documented product: with truncation between
    # the steps the order is observable. docs/FORMULAS.md 1.4.
    for label, fn in (("StaminaMod", stamina_mod),
                      ("WoundMod", wound_mod)):
        m, note = fn(u)
        if m != 1.0 or note:
            nv = value * m
            t.step(f"{label} x{m:.2f}", value, nv, note)
            value = nv

    # result = max(1, pre_morale + trunc0(bonus_percent * pre_morale / 100))
    #
    # The clamp is the shared final tail of all three functions, but it is only
    # REACHED on the paths above: melee and counterattack skip it entirely under
    # modifier 0x26, and ranged attack skips it on a zero sum. A single
    # unconditional clamp for all three kinds is not Genesis-compatible (R6).
    # On the reached path it does apply at neutral morale.
    pct, note = morale_percent(u)
    pre = _trunc(value)
    raw = pre + _trunc(pct * pre / 100)
    nv = float(max(1, raw))
    if pct or note or nv != value:
        label = f"MoraleMod {pct:+d}%" if pct else "MoraleMod"
        if raw < 1:
            label += " (min-1 clamp)"
        t.step(label, value, nv, note)
    value = nv

    t.result = value
    return value, t


_STAT_FOR_KIND = {
    AttackKind.MELEE: "attack",
    AttackKind.COUNTER: "counter_attack",
    AttackKind.RANGED: "ranged_attack",
}


# ---------------------------------------------------------------------------
# Randomisation
# ---------------------------------------------------------------------------

def roll_attack(attack: int, rng: Rng, stream: str = "attack") -> tuple[int, str]:
    """«Расчёт урона при атаках», exact form.

        attack >= 5:  attack + attack/5 - Random(2*(attack/5) + 1)
        attack <  5:  attack + 1 - Random(3)

    All division is integer and floors. The result clamps to a minimum of 1.

    Equivalent closed form, which the page itself states as a cross-check:
    a uniform integer over [attack - attack//5, attack + attack//5] for
    attack >= 5, and over [attack - 1, attack + 1] below that.
    """
    if attack >= 5:
        k = attack // 5
        rolled = attack + k - rng.roll(2 * k + 1, stream)
        note = f"uniform [{attack - k}, {attack + k}]"
    else:
        rolled = attack + 1 - rng.roll(3, stream)
        note = f"uniform [{attack - 1}, {attack + 1}]"
    if rolled < 1:
        return 1, note + ", clamped to 1"
    return rolled, note


# ---------------------------------------------------------------------------
# Damage
# ---------------------------------------------------------------------------

def negative_damage_hits(damage: int, rng: Rng, stream: str = "chip") -> bool:
    """«"Отрицательный" урон»: when damage <= 0 but > -10, one point still
    lands if Random(20 + damage) >= 10. Probability 1 - 10/(20+damage).
    """
    if damage <= -10:
        return False
    return rng.roll(20 + damage, stream) >= 10


def attack_power_before_randomisation(
        attacker: Combatant, kind: AttackKind,
        selected_ordinary_1_5x: bool = False) -> tuple[int, Trace]:
    """Final attack power immediately before randomisation (R10).

    ``conditional_bonus`` is an already-resolved applicability/provider
    boundary: callers decide whether modifier 0x3D contributes. This function
    freezes only its numeric placement and does not infer a target class from a
    presentation name.
    """
    atk_value, atk_trace = current_attack(attacker, kind)

    if kind is AttackKind.MELEE and selected_ordinary_1_5x:
        branch_add = _trunc(atk_value / 2)
        branch_value = atk_value + branch_add
        atk_trace.step("selected ordinary 1.5x branch", atk_value, branch_value,
                       "after finalized effective attack")
        atk_value = branch_value

    if (kind in (AttackKind.MELEE, AttackKind.COUNTER)
            and attacker.conditional_bonus):
        nv = atk_value + attacker.conditional_bonus
        atk_trace.step("conditional attack contribution", atk_value, nv,
                       "already-applicable numeric input; after selected branch; "
                       "before randomisation")
        atk_value = nv

    atk_trace.result = atk_value
    return _trunc(atk_value), atk_trace


def _resolve_attack_against_defence(attack_int: int, atk_trace: Trace,
                                      attacker_name: str, defence_input: int,
                                      defence_trace: Trace, rng: Rng,
                                      defence_note: str = "effective defence") -> tuple[int, list]:
    """Existing randomized resolver with an already-selected defensive input."""
    rolled, roll_note = roll_attack(attack_int, rng)
    roll_trace = Trace(f"{attacker_name}.roll")
    roll_trace.base = attack_int
    roll_trace.step("attack randomisation", attack_int, rolled, roll_note)
    roll_trace.result = rolled

    damage = rolled - defence_input
    dmg_trace = Trace("damage")
    dmg_trace.base = rolled
    dmg_trace.step("defence subtraction", rolled, damage,
                   f"{defence_note} {defence_input}")
    if damage <= 0:
        if negative_damage_hits(damage, rng):
            dmg_trace.step("chip roll", damage, 1, "negative-damage rule succeeded")
            damage = 1
        else:
            dmg_trace.step("chip roll", damage, 0, "negative-damage rule failed")
            damage = 0
    dmg_trace.result = damage
    return damage, [atk_trace, roll_trace, defence_trace, dmg_trace]


def trunc0_half(value: int) -> int:
    """Exact signed division by two toward zero for the frozen damage branch."""
    value = int(value)
    half = value >> 1
    return half + 1 if value < 0 and (value & 1) else half


def resolve_ranged_attack(attacker: Combatant, defender: Combatant,
                          rng: Rng) -> tuple[int, list, int]:
    """Frozen DAMAGE-RANGED-001 calculator: damage, traces, sink channel."""
    attack_int, atk_trace = attack_power_before_randomisation(
        attacker, AttackKind.RANGED)
    modifier_0x1c = effective_modifier_value(attacker, 0x1C)
    channel = 2 if modifier_0x1c != 0 else 1
    if attack_int == 0:
        channel_trace = Trace("ranged channel")
        channel_trace.step("ranged received-damage channel", channel, channel,
                           "modifier 0x1C nonzero" if channel == 2
                           else "ordinary ranged branch")
        channel_trace.result = channel
        return 0, [atk_trace, channel_trace], channel

    if modifier_0x1c != 0:
        defence_input, defence_trace = current_resistance(defender)
        defence_trace.step("ranged resistance branch", defence_input, defence_input,
                           "effective modifier 0x1C is nonzero")
        modifier_0x5f = effective_modifier_value(attacker, 0x5F)
        reduced = defence_input - modifier_0x5f
        defence_trace.step("modifier 0x5F resistance subtraction",
                           defence_input, reduced,
                           "resistance branch before resolver")
        defence_input = reduced
        defence_trace.result = defence_input
        damage, traces = _resolve_attack_against_defence(
            attack_int, atk_trace, attacker.name, defence_input, defence_trace, rng,
            "selected defensive input")
        channel_trace = Trace("ranged channel")
        channel_trace.step("ranged received-damage channel", 2, 2,
                           "0x1C resistance branch returns before non-resistance tail")
        channel_trace.result = 2
        traces.append(channel_trace)
        return damage, traces, 2

    defence_input, defence_trace = current_defence(defender, AttackKind.RANGED)
    defence_trace.step("ordinary ranged-defence branch",
                       defence_input, defence_input,
                       "effective modifier 0x1C is zero")
    modifier_0x11 = effective_modifier_value(attacker, 0x11)
    if modifier_0x11 != 0:
        halved = trunc0_half(defence_input)
        defence_trace.step("modifier 0x11 ranged-defence halving",
                           defence_input, halved,
                           "signed truncation toward zero; before 0x4D")
        defence_input = halved
    modifier_0x4d = effective_modifier_value(attacker, 0x4D)
    reduced = defence_input - modifier_0x4d
    defence_trace.step("modifier 0x4D ranged-defence subtraction",
                       defence_input, reduced,
                       "non-resistance branch before resolver")
    defence_input = reduced
    defence_trace.result = defence_input
    damage, traces = _resolve_attack_against_defence(
        attack_int, atk_trace, attacker.name, defence_input, defence_trace, rng,
        "selected defensive input")

    modifier_0x3c = effective_modifier_value(attacker, 0x3C)
    target_resistance, _ = current_resistance(defender)
    excess = max(0, modifier_0x3c - target_resistance)
    post_trace = Trace("ranged post-resolver")
    post_trace.base = damage
    post_trace.step("modifier 0x3C excess over resistance",
                    damage, damage + excess,
                    f"max(0, {modifier_0x3c} - {target_resistance})")
    damage += excess
    post_trace.step("ranged received-damage channel", 1, 1,
                    "ordinary non-resistance branch")
    post_trace.result = damage
    traces.append(post_trace)
    return damage, traces, 1


def resolve_attack(attacker: Combatant, defender: Combatant,
                   kind: AttackKind, rng: Rng,
                   selected_ordinary_1_5x: bool = False) -> tuple[int, list]:
    """Full ordinary-damage pipeline. Returns (damage_dealt, [traces])."""
    if kind is AttackKind.RANGED:
        damage, traces, _channel = resolve_ranged_attack(attacker, defender, rng)
        return damage, traces

    attack_int, atk_trace = attack_power_before_randomisation(
        attacker, kind, selected_ordinary_1_5x)
    if _offensive_disabled(attacker):
        return 0, [atk_trace]
    defence_input, defence_trace = current_defence(defender, kind)
    return _resolve_attack_against_defence(
        attack_int, atk_trace, attacker.name, defence_input, defence_trace, rng)


def current_defence(u: Combatant, kind: AttackKind) -> tuple[int, Trace]:
    """Defence clamps to a minimum of 0. At stamina 0 both defence values are
    halved — «его Защита и Защита от выстрела уменьшаются в 2 раза»."""
    t = Trace(f"{u.name}.defence")
    base = u.base_defence_for(kind)
    t.base = base
    value = float(base)

    if u.defence_bonus:
        nv = value + u.defence_bonus
        t.step("additive bonuses", value, nv)
        value = nv

    from modifier import Hook
    ctx = {"stat": "ranged_defence" if kind is AttackKind.RANGED else "defence",
           "unit": u, "kind": kind}
    nv, sub = _run_hook(value, u, Hook.STAT_PASSIVE, ctx, "modifiers")
    if sub is not None and nv != value:
        for step in sub.steps:
            t.steps.append(step)
        value = nv

    # R9: the shared accepted final tail of ordinary and ranged defence is
    #
    #     if current_stamina == 0: value = trunc0(value / 2)
    #     return max(value, 0)
    #
    # Three details, each of which this engine previously had wrong:
    #
    #   - the stamina predicate is EQUALITY WITH ZERO, not `<= 0`. Negative
    #     stamina does not halve defence.
    #   - modifier 0x12 «Неутомимость» is NOT consulted by either function. The
    #     exemption belongs to stamina COSTS, not to the defence halving.
    #   - the signed divide is `CDQ; SUB EAX,EDX; SAR EAX,1`, which truncates
    #     toward zero. `floor` diverges for negative odd values; the clamp hides
    #     it here, but the trace should still read correctly.
    path_name = "ranged" if kind is AttackKind.RANGED else "ordinary"
    t.step("defence provider total", value, value,
           "%s providers complete before stamina handling" % path_name)
    if u.stamina == 0:
        nv = float(_trunc(value / 2))
        t.step("zero-stamina defence halving", value, nv,
               "signed truncation toward zero")
        value = nv

    final = max(0, _trunc(value))
    t.step("final defence clamp", value, final, "minimum 0")
    t.result = final
    return final, t


def current_resistance(u: Combatant) -> tuple[int, Trace]:
    """Represented effective resistance providers, without defence stamina rules."""
    t = Trace(f"{u.name}.resistance")
    t.base = u.resist
    value = float(u.resist)
    from modifier import Hook
    resolved = _run_hook(value, u, Hook.STAT_PASSIVE,
                         {"stat": "resist", "unit": u}, "modifiers")
    if resolved[1] is not None and resolved[0] != value:
        t.steps.extend(resolved[1].steps)
        value = resolved[0]
    provider_total = _trunc(value)
    t.step("resistance provider total", value, provider_total,
           "represented providers complete; signed integer truncation")
    final = max(0, provider_total)
    t.step("final resistance clamp", provider_total, final, "minimum 0")
    t.result = final
    return final, t


# ---------------------------------------------------------------------------
# Central received-damage sink (CX-011)
# ---------------------------------------------------------------------------

def adjust_morale(unit: Combatant, delta: int) -> bool:
    """Apply the recovered morale adjustment, including modifier 0x13.

    Returns False when immunity suppressed the adjustment. Morale underflow is
    converted into ten-point break-accumulator steps and current morale floors
    at zero; positive morale remains unbounded because high-morale bands exist.
    """
    if has_effective_modifier(unit, 0x13):
        return False
    after = unit.morale + int(delta)
    if after < 0:
        unit.morale_break_accumulator += -after * 10
        after = 0
    unit.morale = after
    return True


def apply_received_damage(unit: Combatant, amount: int, channel: int = 0,
                          death_resolver=None) -> dict:
    """Account damage, clear remove-on-damage statuses, subtract/cap life,
    then invoke exactly one contextual death resolver on a fatal event.

    ``fatal_event`` records that this hit reached zero and entered the lifecycle;
    it deliberately says nothing about permanent death, credit, rewards or R17.
    """
    import statuses as _statuses

    amount = max(0, int(amount))
    if channel < 0 or channel >= len(unit.damage_received):
        raise ValueError("received-damage channel must be 0..3")
    unit.damage_received[channel] += amount
    _statuses.remove_on_damage(unit)
    unit.life = max(0, unit.life - amount)
    fatal_event = bool(unit.alive and unit.life == 0)
    if fatal_event:
        if death_resolver is None:
            unit.alive = False
        else:
            death_resolver(unit)
    return {
        "fatal_event": fatal_event,
        "final_alive": bool(unit.alive and unit.life > 0),
        "final_death": bool(fatal_event and not (unit.alive and unit.life > 0)),
    }
