"""Closed EGO-owned passive-modifier semantic query vocabulary."""

from __future__ import annotations

from enum import IntEnum


class Query(IntEnum):
    STAMINA_MUTATION_SUPPRESSED = 0
    MELEE_EXCHANGE_SUPPRESSED = 1
    MORALE_UNDERFLOW_SUPPRESSED = 2


_NAMES = {
    Query.STAMINA_MUTATION_SUPPRESSED: "stamina.mutation_suppressed",
    Query.MELEE_EXCHANGE_SUPPRESSED: "combat.melee_exchange_suppressed",
    Query.MORALE_UNDERFLOW_SUPPRESSED: "morale.underflow_suppressed",
}
_BY_NAME = {name: query for query, name in _NAMES.items()}


def normalize(values=()) -> tuple[Query, ...]:
    """Validate, deduplicate, and return canonical enum order."""
    if values is None:
        values = ()
    if not isinstance(values, (list, tuple, set, frozenset)):
        raise ValueError("modifier semantics must be an array")
    parsed = set()
    for raw in values:
        if isinstance(raw, Query):
            parsed.add(raw)
            continue
        if not isinstance(raw, str):
            raise ValueError("modifier semantic values must be names")
        name = raw.strip().lower()
        try:
            parsed.add(_BY_NAME[name])
        except KeyError as exc:
            raise ValueError("unknown modifier semantic %r" % name) from exc
    return tuple(query for query in Query if query in parsed)


def names(values=()) -> list[str]:
    return [_NAMES[query] for query in normalize(values)]


def name(query: Query) -> str:
    try:
        return _NAMES[Query(query)]
    except (KeyError, ValueError) as exc:
        raise ValueError("unknown modifier semantic query %r" % query) from exc
