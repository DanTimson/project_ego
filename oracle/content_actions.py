"""Profile-aware action-definition composition for production providers.

Raw opcodes are interpreted only here. Runtime dispatch receives canonical IDs.
The sanitized stock layer deliberately contains only the two CX-013 actions with
accepted source bindings and recipes; the fourteen-entry evidence catalogue in
``actions.py`` is not consulted.
"""
from __future__ import annotations

import copy
from dataclasses import dataclass, field, replace

import actions
import declarative_action_recipe as dar

STRICT = "strict"
PERMISSIVE = "permissive"
MODES = {STRICT, PERMISSIVE}
GRANT_OVERRIDE_FIELDS = frozenset({"magnitude"})
SHARED_IDS = frozenset({"crushing_blow", "shield_bash"})

_DEFINITION_FIELDS = frozenset({
    "source_id", "shared_id", "canonical_id", "name", "target",
    "cost_stamina", "cost_ammo", "consumes_action", "attack_surcharge",
    "free_action_for", "magnitude", "is_attack", "damage_scale",
    "suppresses", "scales", "excluded_targets", "grants", "notes", "replace",
    "recipe",
})
_ARRAY_FIELDS = ("free_action_for", "suppresses", "scales", "excluded_targets", "grants")


def _definition_shape_error(entry: dict) -> str:
    unknown = sorted(set(entry) - _DEFINITION_FIELDS)
    if unknown:
        return "unknown fields: %s" % ", ".join(unknown)
    for key in _ARRAY_FIELDS:
        if key in entry and not isinstance(entry[key], (list, tuple)):
            return "%s must be a list" % key
    for pair in entry.get("scales", ()):
        if (not isinstance(pair, (list, tuple)) or len(pair) != 2
                or not isinstance(pair[1], (int, float))
                or isinstance(pair[1], bool)):
            return "scales entries must be [identity, numeric factor]"
    for key in ("cost_stamina", "cost_ammo", "magnitude"):
        if key in entry and (not isinstance(entry[key], int)
                             or isinstance(entry[key], bool)):
            return "%s must be an integer" % key
    for key in ("consumes_action", "attack_surcharge", "is_attack", "replace"):
        if key in entry and not isinstance(entry[key], bool):
            return "%s must be a boolean" % key
    if "damage_scale" in entry and (not isinstance(entry["damage_scale"], (int, float))
                                     or isinstance(entry["damage_scale"], bool)):
        return "damage_scale must be numeric"
    if "notes" in entry and not isinstance(entry["notes"], str):
        return "notes must be a string"
    return ""

# Repository-owned, sanitized compatibility defaults. These values are the
# already accepted CX-013 definition/recipe boundary, not extracted content.
_GENESIS_DEFAULTS = (
    {"source_id": 59, "shared_id": "crushing_blow", "name": "Crushing Blow",
     "target": "enemy_melee", "cost_stamina": 0, "attack_surcharge": True,
     "is_attack": True, "damage_scale": 1.5},
    {"source_id": 388, "shared_id": "shield_bash", "name": "Shield Bash",
     "target": "enemy_melee", "cost_stamina": 1, "attack_surcharge": True,
     "is_attack": True, "damage_scale": 0.0,
     "excluded_targets": ["Бестелесный"]},
)


class ActionCompositionError(ValueError):
    def __init__(self, diagnostics: list[dict]):
        self.diagnostics = copy.deepcopy(diagnostics)
        super().__init__("action composition failed: " + "; ".join(
            item["message"] for item in diagnostics))


@dataclass
class CompositionResult:
    pack: str
    profile: str
    mode: str
    definitions: dict[str, actions.Action] = field(default_factory=dict)
    source_map: dict[int, str] = field(default_factory=dict)
    grants: dict[str, list[dict]] = field(default_factory=dict)
    refusals: dict[str, dict[str, str]] = field(default_factory=dict)
    diagnostics: list[dict] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.diagnostics

    def definition_data(self) -> list[dict]:
        return [action_to_dict(value) for value in self.definitions.values()]


def action_to_dict(action: actions.Action) -> dict:
    data = {
        "id": action.id, "name": action.name, "source_id": action.source_id,
        "target": action.target.value,
        "cost_stamina": action.cost.stamina, "cost_ammo": action.cost.ammo,
        "consumes_action": action.cost.consumes_action,
        "attack_surcharge": action.cost.attack_surcharge,
        "free_action_for": list(action.cost.free_action_for),
        "magnitude": action.magnitude, "is_attack": action.is_attack,
        "damage_scale": action.damage_scale,
        "suppresses": list(action.suppresses),
        "scales": [list(value) for value in action.scales],
        "excluded_targets": list(action.excluded_targets),
        "grants": [list(value) for value in action.grants],
        "notes": action.notes,
    }
    if isinstance(action.declarative_recipe, dar.DeclarativeRecipe):
        data["recipe"] = dar.authored_dict(action.declarative_recipe)
    return data


def namespace_id(pack: str, source_id: int) -> str:
    return "%s:action/%d" % (pack, source_id)


def _diagnostic(out: CompositionResult, code: str, message: str, **context) -> None:
    item = {"code": code, "message": message}
    item.update(context)
    out.diagnostics.append(item)


def _canonical_id(pack: str, entry: dict, source_id: int) -> str | None:
    shared = entry.get("shared_id")
    if shared is not None:
        if not isinstance(shared, str) or shared not in SHARED_IDS:
            return None
        return shared
    supplied = entry.get("canonical_id")
    expected_prefix = "%s:action/" % pack
    if supplied is not None:
        if not isinstance(supplied, str) or not supplied.startswith(expected_prefix):
            return None
        return supplied
    return namespace_id(pack, source_id)


def compose(pack: str, profile: str, overlay: dict | None = None,
            mode: str = STRICT) -> CompositionResult:
    """Compose stock profile defaults and one optional pack overlay.

    Strict mode raises after collecting every diagnostic. Permissive mode returns
    the same durable diagnostics plus all unrelated valid definitions/grants.
    """
    if mode not in MODES:
        raise ValueError("unknown action load mode %r" % mode)
    pack = str(pack)
    profile = str(profile)
    out = CompositionResult(pack=pack, profile=profile, mode=mode)
    overlay = copy.deepcopy(overlay or {})
    if not isinstance(overlay, dict):
        _diagnostic(out, "malformed_binding", "action overlay must be an object")
        overlay = {}
    raw_definitions = list(_GENESIS_DEFAULTS if profile == "genesis" else ())
    supplied_definitions = overlay.get("definitions", [])
    if not isinstance(supplied_definitions, list):
        _diagnostic(out, "malformed_binding", "action definitions must be a list")
        supplied_definitions = []
    raw_definitions += supplied_definitions

    owner_by_canonical: dict[str, int] = {}
    ambiguous_sources: set[int] = set()
    for position, raw in enumerate(raw_definitions):
        if not isinstance(raw, dict):
            _diagnostic(out, "malformed_binding",
                        "action definition %d must be an object" % position,
                        position=position)
            continue
        shape_error = _definition_shape_error(raw)
        if shape_error:
            _diagnostic(out, "malformed_binding",
                        "action definition %d is malformed: %s" % (position, shape_error),
                        position=position)
            continue
        source_id = raw.get("source_id")
        if not isinstance(source_id, int) or isinstance(source_id, bool) or source_id < 0:
            _diagnostic(out, "malformed_binding",
                        "action definition %d requires a non-negative integer source_id" % position,
                        position=position)
            continue
        canonical_id = _canonical_id(pack, raw, source_id)
        if canonical_id is None:
            _diagnostic(out, "malformed_binding",
                        "action source %d has an invalid shared or canonical identity" % source_id,
                        source_id=source_id)
            ambiguous_sources.add(source_id)
            continue
        name = raw.get("name")
        if not isinstance(name, str) or not name:
            _diagnostic(out, "malformed_binding",
                        "action source %d requires a non-empty name" % source_id,
                        source_id=source_id)
            ambiguous_sources.add(source_id)
            continue

        # Declarative data can never replace an engine-owned shared recipe.  In
        # permissive Genesis composition, retain the default definition already
        # installed rather than letting collision/replacement remove it.
        raw_for_action = raw
        if canonical_id in SHARED_IDS and "recipe" in raw:
            _diagnostic(out, "shared_recipe_override",
                        "action %r cannot attach or replace its engine-owned recipe"
                        % canonical_id,
                        source_id=source_id, canonical_id=canonical_id)
            if canonical_id in owner_by_canonical:
                continue
            raw_for_action = copy.deepcopy(raw)
            raw_for_action.pop("recipe", None)

        if source_id in out.source_map:
            old_canonical = out.source_map[source_id]
            if raw_for_action.get("replace") is True:
                out.definitions.pop(old_canonical, None)
                owner_by_canonical.pop(old_canonical, None)
                out.source_map.pop(source_id, None)
            else:
                _diagnostic(out, "identity_collision",
                            "source action %d is bound more than once" % source_id,
                            source_id=source_id)
                out.definitions.pop(old_canonical, None)
                owner_by_canonical.pop(old_canonical, None)
                out.source_map.pop(source_id, None)
                ambiguous_sources.add(source_id)
                continue
        if canonical_id in owner_by_canonical:
            other = owner_by_canonical.pop(canonical_id)
            _diagnostic(out, "identity_collision",
                        "canonical action %r is claimed by source %d and %d"
                        % (canonical_id, other, source_id),
                        canonical_id=canonical_id, source_ids=[other, source_id])
            out.definitions.pop(canonical_id, None)
            out.source_map.pop(other, None)
            ambiguous_sources.update((other, source_id))
            continue
        recipe_input = raw_for_action.get("recipe") if "recipe" in raw_for_action else None
        try:
            data = copy.deepcopy(raw_for_action)
            for metadata in ("shared_id", "canonical_id", "replace", "recipe"):
                data.pop(metadata, None)
            data["id"] = canonical_id
            action = actions.action_from_dict(data)
        except (TypeError, ValueError, IndexError) as exc:
            _diagnostic(out, "malformed_binding",
                        "action source %d is malformed: %s" % (source_id, exc),
                        source_id=source_id)
            ambiguous_sources.add(source_id)
            continue
        if "recipe" in raw_for_action:
            validated = dar.validate_recipe(recipe_input,
                                            action_magnitude=action.magnitude)
            if validated.ok:
                action = replace(action, declarative_recipe=validated.recipe)
            else:
                message = "action %r has invalid declarative recipe: %s" % (
                    canonical_id, validated.error)
                _diagnostic(out, "invalid_declarative_recipe", message,
                            source_id=source_id, canonical_id=canonical_id)
                action = replace(action, declarative_recipe_error=validated.error)
        out.definitions[canonical_id] = action
        out.source_map[source_id] = canonical_id
        owner_by_canonical[canonical_id] = source_id

    required = overlay.get("required_source_ids", [])
    if not isinstance(required, list):
        _diagnostic(out, "malformed_binding", "required_source_ids must be a list")
        required = []
    for source_id in required:
        if not isinstance(source_id, int) or isinstance(source_id, bool):
            _diagnostic(out, "malformed_binding",
                        "required action source identity must be an integer")
        elif source_id not in out.source_map:
            _diagnostic(out, "missing_binding",
                        "required action source %d has no unambiguous binding" % source_id,
                        source_id=source_id)

    grants = overlay.get("grants", {})
    if not isinstance(grants, dict):
        _diagnostic(out, "malformed_binding", "action grants must be an object")
        grants = {}
    for unit_id, raw_grants in grants.items():
        unit_id = str(unit_id)
        if not unit_id.startswith(pack + ":unit/"):
            _diagnostic(out, "malformed_binding",
                        "action grant unit %r is outside pack %r" % (unit_id, pack),
                        unit=unit_id)
            continue
        if not isinstance(raw_grants, list):
            _diagnostic(out, "malformed_binding",
                        "action grants for %r must be a list" % unit_id,
                        unit=unit_id)
            continue
        for position, grant in enumerate(raw_grants):
            if not isinstance(grant, dict):
                _diagnostic(out, "malformed_binding",
                            "action grant %d for %r must be an object" % (position, unit_id),
                            unit=unit_id, position=position)
                continue
            source_id = grant.get("source_id")
            if not isinstance(source_id, int) or isinstance(source_id, bool) or source_id < 0:
                _diagnostic(out, "malformed_binding",
                            "action grant %d for %r requires an integer source_id"
                            % (position, unit_id), unit=unit_id, position=position)
                continue
            overrides = grant.get("overrides", {})
            if not isinstance(overrides, dict):
                _diagnostic(out, "malformed_binding",
                            "action grant for %r source %d has malformed overrides"
                            % (unit_id, source_id), unit=unit_id, source_id=source_id)
                continue
            forbidden = sorted(set(overrides) - GRANT_OVERRIDE_FIELDS)
            if forbidden:
                _diagnostic(out, "forbidden_override",
                            "action grant for %r source %d overrides forbidden fields: %s"
                            % (unit_id, source_id, ", ".join(forbidden)),
                            unit=unit_id, source_id=source_id, fields=forbidden)
                continue
            if "magnitude" in overrides and (not isinstance(overrides["magnitude"], int)
                                               or isinstance(overrides["magnitude"], bool)):
                _diagnostic(out, "malformed_binding",
                            "action grant magnitude for %r source %d must be an integer"
                            % (unit_id, source_id), unit=unit_id, source_id=source_id)
                continue
            canonical_id = out.source_map.get(source_id)
            if canonical_id is None:
                candidate = namespace_id(pack, source_id)
                message = "unit %r has unresolved required action grant source %d" % (
                    unit_id, source_id)
                _diagnostic(out, "unresolved_grant", message,
                            unit=unit_id, source_id=source_id,
                            canonical_id=candidate)
                out.refusals.setdefault(unit_id, {})[candidate] = message
                continue
            definition = out.definitions[canonical_id]
            resolved_magnitude = overrides.get("magnitude", definition.magnitude)
            if (dar.uses_action_magnitude(definition.declarative_recipe)
                    and resolved_magnitude < 0):
                message = ("action grant for %r source %d makes declarative "
                           "stamina delta positive" % (unit_id, source_id))
                _diagnostic(out, "invalid_declarative_recipe", message,
                            unit=unit_id, source_id=source_id,
                            canonical_id=canonical_id)
                out.refusals.setdefault(unit_id, {})[canonical_id] = message
                continue
            out.grants.setdefault(unit_id, []).append({
                "canonical_id": canonical_id,
                "overrides": copy.deepcopy(overrides),
            })

    if out.diagnostics and mode == STRICT:
        raise ActionCompositionError(out.diagnostics)
    return out


def resolve_grant(definition: actions.Action, overrides: dict) -> actions.Action:
    """Return one isolated per-unit action; never mutate the shared definition."""
    forbidden = set(overrides) - GRANT_OVERRIDE_FIELDS
    if forbidden:
        raise ValueError("forbidden action grant overrides: %s" % sorted(forbidden))
    return replace(definition, **copy.deepcopy(overrides))
