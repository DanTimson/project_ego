# Content reference and normalization model

This document separates the original `.var` reference conventions from Project
EGO's normalized rules model.

The source format must be parsed exactly. Its record organization and display
names do not have to become the engine architecture.

## Proven source namespaces

R2 establishes:

| source field | raw value means |
|---|---|
| `unit.var Abilityes[*]` | record index in `unit_upg.var` |
| `item.var Effects[*]` | direct modifier opcode |
| `medal.var Effects[*]` | direct modifier opcode |
| `spell.var Effects[*]` | direct action-effect opcode |

The direct opcodes use the numeric namespace described by
`ability_num.Number`. The executable normally compares or dispatches the stored
integer directly; `ability_num.var` is useful as an opcode descriptor catalog,
not as a required runtime lookup layer.

Special spell values above 1000 are separately encoded unit-definition
references interpreted by the action dispatcher. They must not be treated as
ordinary `ability_num` records.

## Import boundary

Import must retain the original reference type long enough to validate it:

```text
raw unit ability index
    -> resolve unit_upg record by index
    -> preserve upgrade identity and selection metadata
    -> normalize its mechanical clauses

raw item/medal/spell effect number
    -> validate against the appropriate opcode dictionary/dispatcher rules
    -> normalize the explicit effect fields directly
```

A source upgrade remains a content object when its identity matters for
prerequisites, conflicts, weighting, level-up history, localization or
provenance. Its mechanics should nevertheless be represented as explicit
effect clauses rather than as a class named after its display label.

## Conceptual normalized clause

The exact engine type is owned by the implementation side. Binary and content
documentation require it to preserve at least the following concepts:

```text
effect_id or stable handler identity
magnitude
duration / stack value when present
area or scope when present
source kind
source record ID
raw source opcode/index
```

An upgrade such as:

```text
unit_upg record 2
Name: Жизнь +2
Upg Type: 1
Quantity: 2
```

should therefore remain identifiable as source upgrade 2, but its mechanic is
conceptually:

```text
effect_id: 1        # Life
magnitude: 2
source_kind: unit_upgrade
source_record_id: 2
```

`Жизнь +2` is localization or source metadata. It is not a dispatch key, a
runtime class, or the canonical identity of the mechanic.

## Why upgrade identity is still retained

Flattening every source record into anonymous effect clauses would lose
information needed by the original progression system:

- prerequisite upgrade IDs;
- one-time restrictions;
- weighted candidate selection;
- conflicts and repeated-choice behaviour;
- the selected-upgrade history stored on the unit;
- special transformation behaviour.

The intended model is therefore:

```text
UpgradeDefinition
    identity and progression metadata
    list of normalized effect clauses
```

not either of these extremes:

```text
named class LifePlusTwo
```

or:

```text
untraceable anonymous +2 applied during import
```

## Validation rules

Import and cross-reference tooling should enforce namespace explicitly:

1. Never infer reference type merely because an integer resolves in a dense
   table.
2. Parse `unit.var` positionally; metadata fields such as `Race` and `UnitKind`
   are not ability references.
3. Resolve `Abilityes` only against `unit_upg` by record index.
4. Treat item, medal and spell `Effects` as direct opcodes.
5. Do not use localized names to resolve mechanics.
6. Preserve raw source identifiers for diagnostics and round-trip reports.
7. Report an unknown opcode explicitly; never fall through to a plausible
   `unit_upg` record.
8. Keep source parsing, normalization and runtime dispatch as separate stages.

## Current schema naming

The schema-14 runtime header calls the three persistent fields at
`+0x94..+0x9F` `attachment_ids`. R2 proves that they index `medal.var`.
Documentation uses `medal_ids`; the header rename is deferred to the next schema
checkpoint so Ghidra imports are not churned for a name-only change.
