# Ruleset profiles

## Status

Proposed — not binding until independent review, cross-review and human
acceptance.

## Context

DELIB-0002 separates provenance governance from ruleset policy. The engine still
needs explicit decisions about which observable Genesis behaviours are universal,
which are New Horizons-specific, and which may be corrected in a native profile.

## Considered options

### Option A — one universal compatibility mode

Use one ruleset and resolve every discovered difference in favour of whichever
behaviour appears most useful.

### Option B — independent feature flags

Expose charge, stamina-cost, RNG and other differences as unrelated switches.

### Option C — named coherent profiles

Define Genesis legacy, New Horizons and native/corrected profiles backed by an
explicit policy interface and profile-specific fixtures.

## Decision

Pending independent review and human acceptance.

The binary-side proposal is Option C.

## Consequences

### Positive

- Prevents silent mixtures of incompatible rules.
- Keeps engine architecture independent from Genesis implementation details.
- Makes exact-fidelity claims testable and scoped.
- Allows intentional NH/native corrections without rewriting history.

### Negative

- Expands the verification matrix.
- Requires profile serialization.
- Some NH rules remain unresolved.
- Feature combinations outside named profiles may still be requested later.

## Work allocation

- **Owner:** Human until decision.
- **Engine side:** profile API, migration cost and serialization.
- **Binary side:** Genesis evidence, neutral fixtures and necessity-gated gaps.
- **Shared:** NH black-box observations and scenario identity policy.

## Confirmation

- `python3 tools/check_deliberations.py`
- engine-side independent position;
- cross-review;
- human decision;
- profile names and API recorded;
- charge, restored-capacity attack cost and RNG fixtures assigned.

## Reconsideration triggers

- NH-specific source permission or decisive black-box evidence.
- Profile conditionals begin leaking outside the policy layer.
- Save/scenario compatibility requires finer-grained feature declarations.
