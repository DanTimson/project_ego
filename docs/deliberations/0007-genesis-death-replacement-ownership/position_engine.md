# Engine position — DELIB-0007

## Current repository facts

**The hard-coded generic map.** `DeathLifecycle.REPLACEMENT_BY_TIER`
(`core/rules/death_lifecycle.gd:10`) is a `const` on the address-free,
pack-agnostic tactical death lifecycle class:
`{1: 21, 2: 37, 3: 56, 4: 65}`, read by
`replacement_id_for_tier(tier)` (`death_lifecycle.gd:13`), which asserts
`tier` is `1..4` and returns the raw int. This is generic lifecycle code
(CX-011's "authoritative address-free tactical death lifecycle," per the file
header) directly embedding Genesis-only source-record numbers — precisely
the "keep generic death lifecycle code free of universal hard-coded source
IDs where practical" criterion this deliberation must fix.

**The unsafe interpolation.** `DeathLifecycle._replacement_definition`
(`death_lifecycle.gd:69`) is the function actually reached at runtime (via
`resolve_for_scenario` -> `resolve`'s `replace_status` branch,
`death_lifecycle.gd:238-261`):

```gdscript
var source_id := String(unit.original_definition.get("content_id", unit.content_id))
var marker := ":unit/"
...
var canonical_id := source_id.split(marker)[0] + marker + str(definition_id)
var definition_v: Variant = content_provider.call("resolve_definition", canonical_id)
```

It takes the **victim's own current content id's pack prefix** — whatever
that pack happens to be — and substitutes in the raw Genesis tier number
(21/37/56/65) as if that number means the same thing in that pack. This is
exactly the "interpolation through the victim's current pack is unsafe as a
general rule" fact the brief already records as accepted, now traced to the
precise three lines that do it. A non-Genesis pack that happens to define a
`unit/21` record (an unrelated unit, by construction — the brief's accepted
fact: "those numbers are Genesis source-record identities, not
pack-independent canonical identities") would silently receive that
unrelated record as a "death replacement," with no error, because nothing
here checks pack *compatibility*, only pack *identity string equality by
construction* (whatever `source_id`'s prefix already was).

**Pack identity and rules-profile identity are two separate, currently
unlinked spaces.** `Scenario.profile` (`"genesis" | "new_horizons" |
"native"`, `scenario.gd:22-24`, validated by `profile_configuration`) governs
RNG selection and R3 charge policy. `ContentPack.id` (set at
`ContentDb.load_pack(pack_id, pack_dir, ...)`) is a wholly independent string
supplied by whoever loads the pack — test fixtures happen to load a pack
literally named `"genesis"` (`tests/test_scenario_requires_pack.gd:15`,
`ContentDb.load_pack("genesis", ...)`), but nothing in `Scenario`, `ContentDb`,
or `ContentPack` asserts any relationship between `Scenario.profile ==
PROFILE_GENESIS` and the loaded pack's `id` or its actual data. A modded pack
could load under `pack_id = "genesis"` with `profile = "genesis"` while
containing arbitrarily altered `.var` data (explicitly legitimate per this
deliberation's human policy constraints), or a pack could load under any
other `pack_id` while `profile = "genesis"`. There is currently **no explicit
Genesis-compatibility declaration anywhere in the pack format** — only the
bare `pack`/`version`/`build`/`fingerprint` provenance fields
`ContentPack.load_bindings`/`provenance()` already parse and verify
(`content_pack.gd:100-107`, `190-202`). This is the gap this deliberation's
"Genesis-compatible-profile-qualified" requirement must fill.

**The existing content-provider seam, already reused twice.** Both
`Scenario.prepare_content` (canonical unit construction) and
`DeathLifecycle._replacement_definition` (death replacement) already resolve
canonical definitions through the same minimal two-method provider protocol —
`provider.has_method("content_provenance")` and `resolve_definition(content_id)`
— implemented identically by `ContentDb` (`content_db.gd:43-92`) and
`ScenarioContentProvider` (`scenario_content_provider.gd:70-88`). This is
already the shared seam between ordinary unit construction and death
replacement; DELIB-0004 (if it introduces an `ActionCatalog`) is expected to
reuse the *same* two-method shape for action definitions rather than invent a
third. This deliberation can therefore share the seam **structurally**
(same provider protocol) without depending on any AD-3 decision specifics —
satisfying the brief's "remain compatible with, but not dependent on,
whatever AD-3 decides" criterion.

**Tier and status wiring.** `unit.tier` (read via
`unit.original_definition.get("tier", unit.tier)`, `death_lifecycle.gd:240`)
selects which of the four tiers applies; the `REPLACE` runtime marker
(`0x5B`, `_runtime_marker(unit, REPLACE)`) is what routes a fatal event into
the `replaced` branch at all. `CANONICAL_UNIT_KEYS`/normal unit construction
elsewhere in `Scenario` already treats `content_id` as pack-qualified
(`cid.pack != pack` is a hard construction error in `prepare_content`,
`scenario.gd:199-202`) — i.e., the rest of the codebase already refuses to
silently cross pack boundaries for ordinary unit definitions. Death
replacement is the one place that doesn't yet apply the same discipline.

**RS-1 (NH modifier `0x5B` equivalence) is explicitly out of scope** per the
brief; nothing here assumes or infers NH behavior.

## Architectural options

**A. Keep interpolating through the victim's current pack, but add a
pack-id string check (`source_id`'s pack must literally equal `"genesis"`).**
Rejected. This is exactly the "modded Genesis pack must be byte-identical /
literally the stock pack" model the human policy constraints explicitly
reject: "Genesis replacement semantics must be qualified by a
Genesis-compatible rules/profile contract, not by a requirement that the
content pack literally be the stock `genesis` pack." A pack id string match
also isn't even the right check today, since nothing enforces that
`Scenario.profile` and a pack's `id` agree in the first place.

**B. Move the tier map into `Scenario` (the composition root) as a
profile-conditional literal, passed into `DeathLifecycle.resolve` as data.**
Partially right (moves the hard-coded numbers out of generic lifecycle code,
satisfying criterion #5) but incomplete: it still leaves "is this pack
actually Genesis-compatible" as an unanswered question — `Scenario.profile ==
"genesis"` alone doesn't establish that the loaded pack's data can honor the
mapping (records 21/37/56/65 might not exist, or might be redefined) at
tier-resolution time, only that the RNG/charge rules "genesis" branch was
selected. Superseded by C, which subsumes this.

**C. A dedicated Genesis-compatible-profile-qualified resolver, owned outside
`DeathLifecycle`, consulted through the existing provider-injection pattern
`DeathLifecycle.resolve` already uses for `definition_resolver`/`event_sink`;
compatibility asserted via an explicit pack-declared contract, not string
identity.** Recommended.

## Recommended position

**1. Owner: a new `GenesisDeathReplacement` resolver (illustrative name;
`core/content/` alongside `ContentDb`/`Roster`, since it is content-layer
policy, not battle-mechanics policy), not `DeathLifecycle` itself.**
`DeathLifecycle` stays pack-agnostic per its own charter (CX-011,
"address-free"); it must not itself know the numbers 21/37/56/65. The new
resolver's contract:

```gdscript
class_name GenesisDeathReplacement
extends RefCounted

## tier (1..4) -> resolved canonical replacement definition, for a pack whose
## bindings manifest declares Genesis compatibility. Returns null (strict
## mode: construction/load error; permissive mode: explicit runtime refusal
## at the point of use) when the pack does not declare compatibility, or when
## a declared record is missing/malformed.
static func resolve(tier: int, content_provider: Variant,
        compatibility: Dictionary) -> Variant:
    ...
```

**2. Compatibility is an explicit pack-declared contract, not a pack-id
string match or a `Scenario.profile` inference.** Extend the bindings
manifest (`bindings.json`, same file `ContentPack.load_bindings` already
parses) with an explicit field, e.g.:

```jsonc
{
  "pack": "my_modded_genesis",
  "version": "1.2",
  "genesis_compatible": true,
  "genesis_death_replacement": {
    "1": 21, "2": 37, "3": 56, "4": 65
  },
  ...
}
```

`genesis_compatible: true` is the actual compatibility assertion (a pack
author's explicit claim, checkable independently of the pack's `id` string).
`genesis_death_replacement` lets a Genesis-compatible mod that renumbers or
retargets tiers still declare its own mapping explicitly, while defaulting
to the stock `{1:21, 2:37, 3:56, 4:65}` when `genesis_compatible: true` is
set and this key is omitted — satisfying "a modified content pack may
therefore remain Genesis-compatible even when its data is not byte-identical
to the stock game" without forcing every Genesis-compatible mod to
re-declare the stock numbers verbatim. This mirrors the existing
`ContentPack.declared_fingerprint`/`provenance()` pattern: the manifest is
already the place pack-level assertions about content identity live; this is
one more assertion of the same kind, not a new mechanism.

**3. `Scenario.profile == "genesis"` and pack `genesis_compatible: true` are
two independent, both-required gates**, not one inferred from the other. A
pack claiming `genesis_compatible: true` while `Scenario.profile !=
"genesis"` (or vice versa) is a configuration the resolver should refuse to
honor — the death-replacement rule is specifically a Genesis-profile rule
(per the brief's frozen fact), so both the rules-profile selection *and* the
content declaration must agree before the tier map applies. This closes the
gap identified above where the two identity spaces currently have no
enforced relationship at all.

**4. Non-Genesis-compatible pack: no rule, not a degraded rule.** If
`genesis_compatible` is absent/false, `GenesisDeathReplacement.resolve` is
simply not applicable — a `REPLACE`-marked unit's death in such a
pack/profile is a **construction-time configuration error** if the scenario
setup ever attempts to grant a `REPLACE` status under a non-Genesis-compatible
pack (this should be validated as early as possible, ideally when the status
is applied, not deferred to the death event), rather than silently falling
back to any interpolation. Per accepted fact: "A non-Genesis-compatible
profile must never inherit the Genesis mapping merely because it contains the
same numeric source records" — there is no fallback path to design here, only
a refusal.

**5. Genesis-compatible pack with missing/mismatched binding — strict vs.
permissive, exactly per the brief's required split:**
- **Strict (default) load-time validation:** when a pack declares
  `genesis_compatible: true`, pack loading should attempt to resolve all four
  tier targets (`resolve_definition("<pack>:unit/<n>")` for each declared
  tier number) and record failures in the pack's existing `LoadReport`-shaped
  diagnostics (new fields alongside `unbound`/`missing`/`orphaned`, or a
  dedicated small report from the new resolver — shape parity with
  `ContentPack.LoadReport` is preferred for consistency, not because the
  types must literally merge). A missing/malformed tier target is a load
  failure in strict mode, matching how `ContentDb.resolve_definition` already
  `push_error`s and returns `null` on an incomplete unit build
  (`content_db.gd:55`) — this is the same "fail loud at load time" posture
  already used for ordinary unit resolution, extended to this mapping.
- **Explicit permissive/unsafe mode:** loading proceeds despite the
  diagnostic; `GenesisDeathReplacement.resolve` returns `null` for the
  specific unresolved tier; `DeathLifecycle.resolve`'s `replaced` branch must
  then produce an **explicit runtime failure at the point the death-replacement
  path is actually reached** — the existing `assert(typeof(definition_v) ==
  TYPE_DICTIONARY, ...)` plus its explicit `{"branch": "invalid_replacement",
  ...}` early-return (`death_lifecycle.gd:245-250`) **already implements
  exactly this fail-explicitly-at-point-of-use behavior** for a null
  definition; no change to that guard is needed, only to what feeds it.
  Unrelated runtime paths (any unit not hitting a `REPLACE` death this
  battle) are unaffected, matching the human policy constraint verbatim.

**6. Death lifecycle should consume a resolved canonical target, not a raw
source-record id.** Change `DeathLifecycle.resolve`'s `replaced` branch to
receive an already-resolved `{definition, canonical_id}` (or just the
resolved definition dictionary, which already carries its own `content_id`
once resolved — see `_replacement_definition`'s existing
`definition["content_id"] = canonical_id` line) from the injected resolver,
rather than computing `replacement_id_for_tier(tier)` internally and building
the canonical id by string interpolation itself. Concretely,
`DeathLifecycle.resolve`'s `definition_resolver: Callable` parameter (already
present, already injected by `Scenario.resolve_for_scenario`) simply gets
bound to `GenesisDeathReplacement.resolve` (wrapped to match the existing
`Callable(unit, tier) -> Dictionary` shape `_replacement_definition` already
presents) instead of to `_replacement_definition`. **No change to
`DeathLifecycle.resolve`'s own signature or control flow is required** — the
existing injection seam already has the right shape; only what's bound to it
changes. This satisfies "keep generic death lifecycle code free of universal
hard-coded source IDs" precisely: `REPLACEMENT_BY_TIER`,
`replacement_id_for_tier`, and `_replacement_definition`'s pack-interpolation
logic all move out of `death_lifecycle.gd` entirely, replaced by whatever
`Callable` `Scenario` binds — Genesis-compatible resolution for a
Genesis-compatible pack, or (per point 4) no binding/an always-refusing
binding for a non-Genesis-compatible one.

## Implementation consequences

- `DeathLifecycle.REPLACEMENT_BY_TIER`, `replacement_id_for_tier`, and
  `_replacement_definition`'s pack-string-splicing logic are removed from
  `core/rules/death_lifecycle.gd`.
- New `core/content/genesis_death_replacement.gd` (illustrative path) owns
  the tier map default, the `genesis_compatible`/`genesis_death_replacement`
  manifest fields, and the resolve/validate logic.
- `ContentPack.load_bindings`/`provenance()` gain parsing (not necessarily
  strict validation there — validation of the *resolved* targets needs a
  loaded `ContentDb`/`Roster`, which `ContentPack` alone doesn't have) for
  the two new manifest keys.
- `Scenario.resolve_for_scenario`/`_replacement_definition`'s binding line
  (`scenario.gd:788-120`ish) changes to bind
  `GenesisDeathReplacement.resolve` (with `Scenario.profile` and the pack's
  parsed compatibility declaration closed over) instead of
  `DeathLifecycle._replacement_definition`.
- A scenario/pack combination where `profile != "genesis"` (or the pack
  doesn't declare `genesis_compatible`) must never reach a working `REPLACE`
  resolution — enforced by binding no resolver (or an always-`null`
  resolver) in that configuration, relying on the already-existing
  `invalid_replacement` guard to fail loudly if a `REPLACE` status is
  ever actually applied in that configuration (a scenario-authoring error,
  not a silent behavior).

## Verification required if accepted

- A test that a pack declaring `genesis_compatible: true` with the default
  tier map resolves tiers 1..4 to `<pack>:unit/21|37|56|65` exactly as today
  (no behavior change for the existing Genesis fixture).
- A test that a **different** pack containing an unrelated `unit/21` record,
  with **no** `genesis_compatible` declaration, never has that record
  selected as a tier-1 replacement — i.e., the accepted fact "equal numeric
  IDs in another pack must not be selected accidentally" is exercised
  concretely, not just asserted in prose.
- A test that a `genesis_compatible: true` pack missing one of the four
  target records fails pack loading in strict (default) mode, and in
  permissive mode loads successfully but produces the existing
  `invalid_replacement` branch/assertion only if and when a unit of that
  tier actually dies with `REPLACE` active — with an explicit assertion that
  an unrelated unit's ordinary death in the same battle is unaffected.
- A test that `profile = "genesis"` with a pack that does **not** declare
  `genesis_compatible` is treated as no-rule (construction-time refusal if a
  `REPLACE` status is ever granted), not silent fallback to the stock
  numbers.
- A test that a Genesis-compatible mod's custom
  `genesis_death_replacement` mapping (non-default tier numbers) is honored
  in place of the stock 21/37/56/65 map.

## Risks / rejected shortcuts

- **Rejected:** inferring `genesis_compatible` from `Scenario.profile ==
  "genesis"` alone (i.e., treating rules-profile selection as sufficient
  proof of content compatibility). Profile selects RNG/charge rules; it says
  nothing about whether the *loaded content pack's data* actually has valid
  records at the expected tier positions, which is exactly the case the
  brief's "missing/mismatched binding" failure mode describes.
- **Rejected:** validating tier targets lazily, only at the moment of first
  death-replacement, even in strict/default mode. The brief requires
  "validation should detect missing/mismatched required mappings at load
  time by default" — deferring all validation to first use would make strict
  mode behave like permissive mode for a condition (missing record) that is
  fully knowable at load time.
- **Risk carried forward:** the exact manifest field names
  (`genesis_compatible`, `genesis_death_replacement`) are this position's
  proposal, not settled project vocabulary — see remaining human choice.
  Also carried forward: whether a pack can declare `genesis_compatible: true`
  while `Scenario.profile` is `"native"` (an odd but not obviously invalid
  combination) — this position treats that as "no rule applies" (both gates
  required, point 3), but the product may want a load-time warning for that
  specific combination rather than silent inapplicability.

## Remaining human choice

- Exact manifest schema/field names for the Genesis-compatibility
  declaration and the (optional) custom tier map — a project data-format
  style choice.
- Whether a pack declaring `genesis_compatible: true` under a non-`"genesis"`
  `Scenario.profile` should warn at load time (currently proposed as silent
  inapplicability) — a diagnostics/UX policy choice, not an architecture
  question.
- Whether the default tier map (21/37/56/65) should be baked into the new
  `GenesisDeathReplacement` resolver as a fallback when
  `genesis_death_replacement` is omitted (this position's proposal), or
  whether every Genesis-compatible pack must always declare the map
  explicitly with no default — a strictness-tradeoff the project owner may
  prefer to set explicitly rather than have this position assume.
