# Fidelity, identity, and modifiability — binary-analysis view

**Status:** working architecture position, intended to be revised as implementation
probes produce evidence.

**Scope:** this file records the binary-analysis side of the Project EGO
faithfulness/modifiability discussion. It is not a replacement for recovered
mechanics documents and does not define a public mod API.

## Current conclusion

Project EGO should continue to pursue exact Genesis behaviour while preventing
facts about the original executable, source files, and runtime layouts from
silently becoming universal engine architecture.

The current codebase is already substantially pack-agnostic:

- Genesis and New Horizons are both data-driven profiles;
- rules do not branch on pack identity;
- raw `.var` indexes and numeric opcodes are resolved before they reach the
  rules layer;
- New Horizons already exercises the pipeline at nontrivial scale.

Therefore broad mod infrastructure should not be added now.

The immediate architecture work is narrower:

1. replace localized display-name identity with stable namespaced identity;
2. implement the recovered shared legacy RNG behind one injected randomness
   boundary;
3. treat the `.var` importer as a first-class, dialect-tolerant mod inlet;
4. defer other policy interfaces until a real altered rule, new action, or
   persistence case proves that they are needed.

## 1. Stable identity is the most urgent structural issue

Localized display names are currently load-bearing. Genesis and New Horizons
share many names while assigning different records and statistics to some of
them. A lookup such as:

```text
build("Мечник")
```

is therefore only safe while one roster encloses exactly one pack. It becomes
ambiguous as soon as a save, trace, comparison, override, or cross-pack tool
refers to content outside that local context.

A plausible wrong lookup is worse than an explicit failure.

### Recommended canonical form for `.var` content

Use the content-pack namespace, object kind, and source record ID:

```text
genesis:unit/1
new_horizons:unit/1
genesis:upgrade/76
new_horizons:spell/12
```

The source record ID is preferable to a transliterated display-name slug:

- it is language-independent;
- it is the source-native identity used by `.var` references;
- it does not change when localization or display spelling changes;
- it avoids collisions between records with the same visible name;
- it can be generated deterministically during import.

Display names remain localization and presentation fields:

```text
id: genesis:unit/1
display_name: Мечник
```

For readability, fixtures may include a non-binding label beside the ID, but
the label must not participate in resolution.

### Stability boundary

A source record ID is stable only within the identity and version of its content
pack. Future saves and replay metadata should therefore record at least:

```text
content_pack_id
content_pack_version or fingerprint
content_object_id
```

This is a persistence requirement, not a request to build a save system now.

Native non-`.var` content may later use author-supplied local IDs:

```text
my_campaign:unit/ash_golem
```

No separate native content format needs to be designed yet.

### Migration behaviour

During migration, name lookup may remain as an explicit compatibility helper,
but it should:

- be scoped to one pack;
- reject ambiguous matches;
- emit a deprecation warning;
- return the canonical ID;
- never be written into new fixtures or persistence artifacts.

Provenance should travel with imported definitions:

```text
source_format
source_pack
source_file
source_record_id
source_opcode, when applicable
```

## 2. The `.var` importer is a primary mod inlet

The importer should not be treated as a temporary Genesis compatibility corner.
The existing Eador modding ecosystem is `.var`-native, and New Horizons is
already a large real mod consumed through that route.

The correct boundary is:

```text
Eador .var dialects
        |
        v
dialect-aware parsing and reference resolution
        |
        v
normalized Project EGO definitions
        |
        v
pack-agnostic rules
```

The importer is allowed to understand source-specific conventions. The
normalized engine model should not inherit them unnecessarily.

### Importer obligations

The importer should be tested across known dialect differences rather than
assuming one canonical file shape. In particular:

- lexical parsing and record boundaries must remain separate from schema
  interpretation;
- metadata fields must not be mistaken for reference arrays;
- each reference field must declare its namespace explicitly;
- unknown or contradictory fields should produce diagnostics rather than a
  plausible cross-table lookup;
- imported definitions should retain source provenance;
- Genesis and New Horizons should remain paired regression profiles.

This is mod compatibility work and source fidelity work at the same time.

## 3. Only the RNG abstraction is justified now

Earlier proposals for separate morale, charge, counterattack, effect-dispatch,
and turn-structure policy interfaces were premature. They fail the project's own
test: no demonstrated second implementation currently requires those seams.

The RNG conflict is different. R4 proves that Genesis compatibility requires
one shared CRT sequence with explicit reseed epochs. A future native mode may
reasonably prefer isolated streams. This is a real, already-demonstrated
variation point, and retrofitting it after random calls spread further would be
costly.

### Minimal boundary

Rules should consume an injected randomness dependency. Mode and pack checks
must not appear inside rule functions.

Conceptually:

```text
RandomSource
    below(exclusive_bound)
```

The owning session or lifecycle layer may additionally seed or replace the
source.

Genesis compatibility supplies one shared `LegacyRng` instance implementing:

- the recovered MSVC CRT recurrence;
- the original bounded adapter and modulo bias;
- shared call ordering across ordinary consumers;
- recovered reseed epochs.

A later native mode may inject a different source or separate sources at
composition boundaries. The current interface should not include subsystem
names, plugin hooks, stream registries, or pack-specific branches.

Weighted selection remains an ordinary utility that consumes `below()`.

## 4. Recovered facts need an explicit binding scope

Binary analysis should continue recording maximum detail. The documentation
must also state where each fact constrains Project EGO.

A simple observable/internal split is helpful but incomplete: source reference
typing and original persistence layouts are binding somewhere even when they are
not gameplay observations.

Use these binding scopes:

| binding scope | Project EGO obligation |
|---|---|
| `legacy_behavior` | Genesis compatibility execution must reproduce the result and ordering |
| `eador_var_import` | the `.var` importer must parse or resolve the source convention exactly |
| `original_persistence` | required only for original save/runtime-layout compatibility |
| `diagnostic_only` | true of the executable, but not an engine implementation requirement |
| `unresolved` | evidence is insufficient to assign an obligation |

Each important claim should also include a one-sentence `engine_obligation`.

### Examples

| recovered fact | binding scope | engine obligation |
|---|---|---|
| morale truncation occurs before the final morale percentage | `legacy_behavior` | reproduce the truncation and application order |
| the original uses an internal ×100 temporary value | `diagnostic_only` | no fixed-point representation is required if outputs match |
| `unit.var Abilityes` uses `unit_upg` record IDs | `eador_var_import` | resolve against the correct table during import |
| item/medal/spell Effects use direct opcodes | `eador_var_import` | preserve the opcode namespace and normalize the effect |
| unit offsets `+0x94..+0x9C` hold medal IDs | `original_persistence` | honour only when decoding original-compatible structures |
| ordinary random calls share CRT state | `legacy_behavior` | use one shared `LegacyRng` in compatibility mode |
| `_holdrand` resides at CRT thread-data offset `+0x14` | `diagnostic_only` | emulate the sequence, not the physical CRT structure |
| Ghidra local/register names | `diagnostic_only` | none |

The evidence ledger can adopt `binding_scope` and `engine_obligation` when it is
next revised. This architecture note does not require an immediate ledger
migration.

## 5. Empirical extension probe

Do not design a broad mod API abstractly. New Horizons already proves:

- new and altered units;
- large alternative content sets;
- new effect combinations;
- pack-agnostic rules consumption.

The remaining useful probe is deliberately small:

1. one rule alteration that cannot be expressed as data;
2. one genuinely new action handled through the existing registry/handler path;
3. one save/load round trip using canonical namespaced IDs.

The implementation should first attempt these without adding general policy
interfaces. Any invasive edit identifies a real missing boundary. Only then
should the corresponding abstraction be introduced.

This probe is more informative than speculative `ChargePolicy`,
`MoralePolicy`, `TurnStructurePolicy`, or plugin APIs.

## 6. Deferred work

Continue to defer:

- public scripting APIs;
- plugin loading;
- hot reload;
- mod-management UI;
- graphical editors;
- generalized hook systems;
- arbitrary rule-policy interfaces;
- a second “proper mod format” designed without users;
- persistence implementation before the vertical slice requires it.

When persistence is implemented, it must be versioned and ID-based from its
first committed format.

## 7. Priority order

1. **Identity migration**
   - establish stable pack IDs;
   - generate canonical object IDs from `.var` record IDs;
   - add provenance;
   - migrate fixtures and scenario artifacts away from display-name references;
   - retain scoped name lookup only as a migration helper.

2. **Legacy RNG**
   - implement and test `LegacyRng` from `LEGACY_RNG.md`;
   - inject it through one randomness boundary;
   - preserve one shared compatibility instance and recovered reseed epochs.

3. **Importer dialect regression**
   - maintain paired Genesis/New Horizons tests;
   - add targeted fixtures for known schema differences and reference namespaces.

4. **Empirical extension probe**
   - one altered rule;
   - one new action;
   - one ID-based save/load round trip.

5. **Add only abstractions demanded by the probe.**

## Working decision rule

For every recovered or proposed feature, ask:

1. Is this a Genesis behaviour, a `.var` convention, an original persistence
   fact, or merely an executable implementation detail?
2. Where must Project EGO honour it?
3. Is the proposed abstraction required by a demonstrated second implementation?
4. Would deferring the decision make IDs, content, saves, or most call sites
   significantly harder to migrate?

This preserves exact reverse-engineering work without allowing the original
executable's incidental architecture to become Project EGO's universal model.
