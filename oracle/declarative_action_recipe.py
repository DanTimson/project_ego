"""Validated declarative action recipes for the CX-014 v1 safe subset.

The authored schema is parsed only at content composition.  Normalized recipe
values are immutable data, and compilation produces the existing typed plan
operations; this module does not execute gameplay or interpret legacy opcodes.
"""
from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Any


@dataclass(frozen=True)
class AttackRecipeOp:
    scale_numerator: int
    scale_denominator: int


@dataclass(frozen=True)
class ResourceDeltaRecipeOp:
    fixed_amount: int | None = None
    negative_action_magnitude: bool = False


RecipeOp = AttackRecipeOp | ResourceDeltaRecipeOp


@dataclass(frozen=True)
class DeclarativeRecipe:
    operations: tuple[RecipeOp, ...]
    version: int = 1


@dataclass(frozen=True)
class RecipeValidation:
    recipe: DeclarativeRecipe | None
    error: str = ""

    @property
    def ok(self) -> bool:
        return self.recipe is not None and not self.error


def _is_int(value: Any) -> bool:
    # Godot's JSON parser represents every number as float. Accept only finite
    # integral values so the same authored JSON validates in both runtimes.
    return ((isinstance(value, int) and not isinstance(value, bool))
            or (isinstance(value, float) and math.isfinite(value)
                and value == math.floor(value)))


def _exact_keys(value: dict, expected: set[str], where: str) -> str:
    unknown = sorted(set(value) - expected)
    missing = sorted(expected - set(value))
    if unknown:
        return "%s has unknown fields: %s" % (where, ", ".join(unknown))
    if missing:
        return "%s is missing fields: %s" % (where, ", ".join(missing))
    return ""


def validate_recipe(raw: Any, *, action_magnitude: int) -> RecipeValidation:
    """Validate and normalize one complete authored recipe, fail-closed."""
    if not isinstance(raw, dict):
        return RecipeValidation(None, "recipe must be an object")
    error = _exact_keys(raw, {"version", "operations"}, "recipe")
    if error:
        return RecipeValidation(None, error)
    if not _is_int(raw["version"]) or raw["version"] != 1:
        return RecipeValidation(None, "recipe version must be integer 1")
    operations_raw = raw["operations"]
    if not isinstance(operations_raw, list):
        return RecipeValidation(None, "recipe operations must be a list")
    if not operations_raw:
        return RecipeValidation(None, "recipe operation list must not be empty")

    operations: list[RecipeOp] = []
    attack_seen = False
    for index, operation_raw in enumerate(operations_raw):
        where = "recipe operation %d" % index
        if not isinstance(operation_raw, dict):
            return RecipeValidation(None, "%s must be an object" % where)
        kind = operation_raw.get("kind")
        if kind == "attack":
            error = _exact_keys(operation_raw, {"kind", "mode", "scale"}, where)
            if error:
                return RecipeValidation(None, error)
            if attack_seen:
                return RecipeValidation(None, "recipe permits at most one attack operation")
            if index != len(operations_raw) - 1:
                return RecipeValidation(None, "attack operation must be final")
            if operation_raw["mode"] != "melee":
                return RecipeValidation(None, "%s supports melee mode only" % where)
            scale = operation_raw["scale"]
            if not isinstance(scale, dict):
                return RecipeValidation(None, "%s scale must be an object" % where)
            error = _exact_keys(scale, {"numerator", "denominator"}, "%s scale" % where)
            if error:
                return RecipeValidation(None, error)
            numerator, denominator = scale["numerator"], scale["denominator"]
            if (not _is_int(numerator) or not _is_int(denominator)
                    or numerator <= 0 or denominator <= 0):
                return RecipeValidation(
                    None, "%s scale numerator and denominator must be positive integers" % where)
            operations.append(AttackRecipeOp(int(numerator), int(denominator)))
            attack_seen = True
        elif kind == "resource_delta":
            error = _exact_keys(
                operation_raw, {"kind", "target", "resource", "amount"}, where)
            if error:
                return RecipeValidation(None, error)
            if attack_seen:
                return RecipeValidation(None, "operation after attack is not permitted")
            if operation_raw["target"] != "selected_enemy":
                return RecipeValidation(None, "%s supports selected_enemy only" % where)
            if operation_raw["resource"] != "stamina":
                return RecipeValidation(None, "%s supports stamina only" % where)
            amount = operation_raw["amount"]
            if _is_int(amount):
                if amount > 0:
                    return RecipeValidation(None, "%s amount must be non-positive" % where)
                operations.append(ResourceDeltaRecipeOp(fixed_amount=int(amount)))
            elif isinstance(amount, dict):
                error = _exact_keys(amount, {"source", "sign"}, "%s amount" % where)
                if error:
                    return RecipeValidation(None, error)
                if amount != {"source": "action_magnitude", "sign": "negative"}:
                    return RecipeValidation(
                        None, "%s amount must be negative action_magnitude" % where)
                if not _is_int(action_magnitude) or action_magnitude < 0:
                    return RecipeValidation(
                        None, "%s resolved action magnitude must be non-negative" % where)
                operations.append(ResourceDeltaRecipeOp(negative_action_magnitude=True))
            else:
                return RecipeValidation(
                    None, "%s amount must be a non-positive integer or negative action_magnitude" % where)
        else:
            return RecipeValidation(None, "%s has unknown operation kind %r" % (where, kind))
    return RecipeValidation(DeclarativeRecipe(tuple(operations)))


def uses_action_magnitude(recipe: DeclarativeRecipe | None) -> bool:
    return bool(recipe and any(isinstance(operation, ResourceDeltaRecipeOp)
                               and operation.negative_action_magnitude
                               for operation in recipe.operations))


def authored_dict(recipe: DeclarativeRecipe) -> dict:
    """Return an isolated plain-data representation for serialization/copying."""
    operations = []
    for operation in recipe.operations:
        if isinstance(operation, AttackRecipeOp):
            operations.append({
                "kind": "attack", "mode": "melee",
                "scale": {"numerator": operation.scale_numerator,
                          "denominator": operation.scale_denominator},
            })
        else:
            amount: Any = (operation.fixed_amount
                           if not operation.negative_action_magnitude else
                           {"source": "action_magnitude", "sign": "negative"})
            operations.append({
                "kind": "resource_delta", "target": "selected_enemy",
                "resource": "stamina", "amount": amount,
            })
    return {"version": recipe.version, "operations": operations}
