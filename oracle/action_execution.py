"""Typed, engine-native execution plans for canonical unit actions.

The recipe boundary is intentionally small: content identity selects a frozen ordered
plan, and the executor delegates operations to battle-owned tactical primitives.  It
is not a legacy opcode interpreter or a user-authored action language.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Callable


class AttackMode(Enum):
    MELEE = "melee"


class Resource(Enum):
    STAMINA = "stamina"


class OperationTarget(Enum):
    SELECTED_ENEMY = "selected_enemy"


@dataclass(frozen=True)
class AttackOp:
    mode: AttackMode
    initiating_attack_scale_numerator: int = 1
    initiating_attack_scale_denominator: int = 1

    @property
    def kind(self) -> str:
        return "AttackOp"


@dataclass(frozen=True)
class ResourceDeltaOp:
    target: OperationTarget
    resource: Resource
    amount: int

    def __post_init__(self) -> None:
        if self.amount > 0:
            raise ValueError("CX-013 ResourceDeltaOp supports drains only")

    @property
    def kind(self) -> str:
        return "ResourceDeltaOp"


ActionOp = AttackOp | ResourceDeltaOp


@dataclass(frozen=True)
class ActionExecutionPlan:
    operations: tuple[ActionOp, ...]


@dataclass(frozen=True)
class RecipeResolution:
    supported: bool
    plan: ActionExecutionPlan | None = None
    reason: str = ""


class ActionRecipeResolver:
    """Resolve only semantics frozen for the canonical action identity."""

    @staticmethod
    def resolve(action) -> RecipeResolution:
        if action.id == "crushing_blow":
            return RecipeResolution(True, ActionExecutionPlan((AttackOp(
                mode=AttackMode.MELEE,
                initiating_attack_scale_numerator=3,
                initiating_attack_scale_denominator=2,
            ),)))
        if action.id == "shield_bash":
            return RecipeResolution(True, ActionExecutionPlan((ResourceDeltaOp(
                target=OperationTarget.SELECTED_ENEMY,
                resource=Resource.STAMINA,
                amount=-int(action.magnitude),
            ),)))
        return RecipeResolution(False, reason="known action has no frozen recipe")


class ActionPlanExecutor:
    """Execute a validated ordered plan through injected tactical primitives."""

    @staticmethod
    def execute(plan: ActionExecutionPlan, *,
                attack_primitive: Callable[[AttackOp], object],
                resource_delta_primitive: Callable[[ResourceDeltaOp], object]) -> tuple:
        results = []
        for operation in plan.operations:
            if isinstance(operation, AttackOp):
                results.append(attack_primitive(operation))
            elif isinstance(operation, ResourceDeltaOp):
                results.append(resource_delta_primitive(operation))
            else:
                raise TypeError("unsupported internal action operation %r" %
                                (type(operation).__name__,))
        return tuple(results)
