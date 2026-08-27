# DELIB-0007 — Genesis death-replacement content ownership

## Question

Which pack-qualified content resolver owns the recovered Genesis death-replacement
source records `21/37/56/65`, and what should happen when the active pack/profile
cannot resolve that Genesis mapping?

## Decision required

Define the content/engine boundary for the existing Genesis-only tier 1..4 death
replacement mapping without treating equal numeric indices in another pack as the
same units.

## Frozen base

`4e508b7ec42268d55df64199be1da414ea69c825`

## Accepted starting facts

- The tier mapping to source records `21/37/56/65` is BIN_PROVEN for Genesis.
- Those numbers are Genesis source-record identities, not pack-independent
  canonical identities.
- The current implementation's interpolation through the victim's current pack is
  unsafe as a general rule, even though no released Genesis fixture demonstrated
  a failure.
- Pack-qualified canonical identity and injected content providers already exist.
- NH modifier-`0x5B` equivalence remains deferred research (`RS-1`) and must not be
  inferred here.

## Human policy constraints

The project owner confirms that editing the original game's `.var` (and some
`.dat`) data is a legitimate modding method. A modified content pack may therefore
remain **Genesis-compatible** even when its data is not byte-identical to the
stock game.

Accordingly:
- Genesis replacement semantics must be qualified by a Genesis-compatible
  rules/profile contract, not by a requirement that the content pack literally be
  the stock `genesis` pack or match a stock file hash.
- A Genesis-compatible mod may supply altered content behind the required source
  bindings, provided the compatibility contract is satisfied.
- Validation should detect missing/mismatched required mappings at load time by
  default.
- An explicit permissive/unsafe override must allow the user to continue loading
  despite such diagnostics. In that mode, an unresolved replacement must fail
  explicitly if the affected death-replacement path is actually reached; unrelated
  runtime operation may continue normally.
- A non-Genesis-compatible profile must never inherit the Genesis mapping merely
  because it contains the same numeric source records.


## Decision criteria

The accepted design must:
1. keep `21/37/56/65` explicitly Genesis-rules-profile-qualified;
2. prevent equal numeric IDs in another pack from being selected accidentally;
3. identify the owner that converts a Genesis source record into a canonical
   resolved replacement definition;
4. define strict-default load validation plus explicit permissive-mode runtime behavior when the Genesis mapping is absent/mismatched/unresolvable;
5. keep generic death lifecycle code free of universal hard-coded source IDs where
   practical;
6. preserve tactical lifecycle ordering already accepted under CX-011;
7. remain compatible with, but not dependent on, whatever AD-3 decides unless the
   two decisions explicitly share a content-resolution seam.

## Non-goals

- Do not determine NH modifier-`0x5B` behavior.
- Do not assume Genesis and NH share numeric replacement IDs.
- Do not change strategic rewards/corpses/kill credit.
- Do not implement the resolver here.
- Do not reopen CX-011 tactical branch ordering.

## Questions for the binary/governance side

- Exactly what is proven about the Genesis mapping and what is not universal?
- What fail-closed behavior is necessary to avoid false cross-pack claims?
- Is there any evidence reason for generic death code to know raw source IDs?

## Questions for the engine side

- Which existing/new content resolver should own the pack-qualified mapping?
- Should non-Genesis profiles simply have no such rule, while Genesis resolution
  failure is an explicit construction/runtime error?
- Should death lifecycle consume a resolved canonical target rather than a source
  record ID?
- Does AD-3's composition seam offer useful reuse without coupling the decisions?

## Required output

An accepted decision must make the Genesis scope explicit enough that a later
implementation cannot silently reinterpret another pack's same-numbered record.
