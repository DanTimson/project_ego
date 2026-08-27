# REL-0.2 — Milestone 0.2 release hardening

Status: `RELEASED` — Milestone 0.2

Frozen implementation baseline:
`510ff0c585222aa152a50ec47420e992f8942daf`

This is a release/tooling tranche. It is not CX-014 and must not decide or
change gameplay semantics.

## 1. Goal

Turn the existing Milestone 0.1.1 release machinery into a trustworthy
Milestone 0.2 public/private release path without redesigning packaging.

The current builder is already the authoritative foundation. Preserve:

- tracked-only `git archive HEAD` source materialization;
- public package with authored/fallback presentation only;
- private package as the same EXE/PCK plus only the exact mapped local-image
  closure;
- fail-closed JSON/path/symlink/type validation;
- machine-path, DAT, extraction-manifest and EGOgrabber leak rejection;
- public/private EXE and PCK byte-identity checks;
- executable smoke;
- deterministic ZIP entry ordering and timestamps when a deterministic build
  epoch is selected;
- ignored `dist/`, `.release_staging/` and `.local/` boundaries.

Do not replace this with another packager.

## 2. Release identity and governance

Milestone label: `0.2`.

This is explicitly a **research/prototype milestone release**, not a stable
community implementation lineage and not a broad-adoption/stable API promise.
Do not trigger or mark G1+ in `PUBLIC_LINEAGE_GATE.md`. Do not rewrite lineage
history or provenance policy.

The public artifact contains no original Eador assets/data. The private
artifact may contain only the already-supported mapped local image closure and
remains private/local.

No original/NH bulk data, DAT files, localization corpora, generated populated
bindings, research evidence, binary packets or Ghidra material may enter either
artifact.

### Durable Milestone 0.2 release notes

Milestone 0.2 packages the current playable deterministic tactical vertical
slice with responsive UI and a complete project-authored fallback presentation.
It remains an incomplete hot-seat prototype, not a complete Eador battle or
strategy implementation. The rules surface includes explicit native and Genesis
profile routing, the currently supported legacy RNG generator/adapters, and
model-owned command/action terminality.

Since the 0.1/0.1.1 release machinery was introduced, the implemented tactical
boundary has gained centralized death, revival, rollback, replacement and side
transfer lifecycle handling; the currently fixture-covered one-shot ranged
branch parity; and the typed unit-action-plan foundation used by Crushing Blow and Shield Bash.
The optional private presentation tier still adds only the exact mapped local
image closure beside byte-identical public/private EXE and PCK payloads.

Important open systems remain explicit: the other twelve catalogued unit
actions, generic battle-action/effect families, automatic status lifecycle
boundaries, exact legacy RNG call/reseed parity beyond current isolated support,
large-unit footprint observation, tactical AI and strategy play, and broad
presentation/content parity. Milestone 0.2 remains the mixed
research/prototype lineage at G0. It is not a stable community API or a
community/public implementation-lineage release.

## 3. Allowed tracked surface

Expected release/tooling surface:

- `tools/build_demo.py`;
- `tools/test_build_demo.py`;
- one small generic release-pair/orchestration tool and its tests if useful;
- `docs/DEMO_RELEASE.md`;
- `docs/RELEASE_0_2.md` (this file, converted from contract to durable release
  record/notes while retaining an implementation/validation record);
- `README.md`;
- `docs/STATUS.md`;
- `docs/ARCHITECTURE.md`;
- `export_presets.cfg`;
- `game/demo/demo_main.gd`;
- `game/demo/demo_main.tscn`;
- `tests/test_demo_release.gd`.

A narrower surface is preferred.

Do not modify:

- `core/` combat/rules/model/content semantics;
- `oracle/` gameplay/reference semantics;
- tactical scenario fixtures or expected combat results;
- evidence ledgers/sources, binary requests, observation results;
- public-lineage transfer classifications;
- deliberation decisions;
- packs/bindings;
- third-party/local content.

If a release test exposes a pre-existing semantic defect, stop and report it;
do not repair it in this tranche.

## 4. Required hardening

### 4.1 Windows-backed export staging seam

Project EGO's current WSL setup has a demonstrated Godot false-failure mode
when Godot creates/uses project cache state on the canonical Linux/ext4
checkout. The accepted validation convention is to run Godot from `/mnt/d`.

Generalize `tools/build_demo.py` so the source/export staging directory can be
placed under a caller-selected parent outside the repository, for example:

```text
--staging-parent /mnt/d
```

Requirements:

- default behavior remains portable and does not hard-code `/mnt/d`;
- a CLI option (and optionally a clearly named environment fallback) chooses
  the parent;
- create a uniquely owned temporary release directory beneath that parent;
- clean only that owned temporary directory;
- never recursively remove the caller's parent;
- reject/handle unsafe or unusable staging parents clearly;
- the source stage is still materialized from exact tracked `HEAD`;
- staging location must not leak into package files/metadata;
- unit tests cover default and external staging selection/cleanup at the helper
  level without requiring a real Godot export.

Official WSL 0.2 commands/documentation must use a Windows-backed staging
parent. Other platforms may use the portable default.

### 4.2 First-class reproducible release epoch

The ZIP writer is already deterministic for a fixed build timestamp. Make the
official release path choose a deterministic epoch rather than wall-clock time.

Preferred rule:

```text
official/reproducible build epoch = exact released commit's Git commit timestamp
```

Allow explicit `SOURCE_DATE_EPOCH` to remain authoritative when supplied.

A clean CLI such as `--reproducible` is acceptable. Do not silently rewrite
ordinary ad-hoc build timestamps unless that is simpler and well documented.

Requirements:

- public/private official pair receives the same `built_at`;
- repeated official packaging from the same commit, Godot payload and private
  asset closure produces byte-identical ZIPs;
- tests distinguish fixed/reproducible timestamp from ordinary wall-clock mode;
- do not claim that arbitrary future Godot versions are bit-reproducible.
  Record the exact Godot version as today.

### 4.3 One pair-level release manifest

Add a small generic pair-level orchestration/verification path rather than
making the user manually compare console logs.

For an official pair it must validate and record at least:

- schema/version;
- project and milestone;
- exact Git commit;
- exact Godot version;
- deterministic build timestamp/epoch;
- public artifact relative/name, byte size and SHA-256;
- private artifact relative/name, byte size and SHA-256;
- public EXE SHA-256 and PCK SHA-256;
- private EXE SHA-256 and PCK SHA-256;
- explicit assertion/result that the EXE payloads match;
- explicit assertion/result that the PCK payloads match;
- public ZIP inventory;
- private ZIP inventory;
- public fallback/no-local-assets validation result;
- private exact mapping-reference-closure validation result;
- runtime-smoke result for each mode.

Use a generated ignored sidecar under `dist/`; do not embed a self-hash inside
the ZIP. A `SHA256SUMS` sidecar is optional if the JSON manifest already records
artifact hashes.

The pair tool must fail closed if only one half succeeds, identity differs,
metadata differs, or the private root is invalid. It need not atomically retain
no intermediate ZIP at all on failure, but it must never write a successful
pair manifest for an incomplete/mismatched pair.

Keep `tools/build_demo.py` usable for single-mode developer builds.

### 4.4 Fresh tracked-source / fresh-clone acceptance

The existing `git archive HEAD` build source is retained. Document why this
prevents ignored/local/worktree material from entering an official package.

Provide an acceptance procedure for a fresh clone at the release commit. It may
be a documented command sequence rather than another permanent tool.

For the final 0.2 release acceptance, the human/reviewer will perform a real
fresh-clone public build from a Windows-backed location. Do not fake that in a
unit test.

### 4.5 Branding/version staleness

Remove stale shipped `0.1` / `0.1.1` identity where it would make a 0.2 package
self-contradictory.

At minimum:

- Windows file/product version in `export_presets.cfg` becomes `0.2.0.0`;
- the demo shell must not display hard-coded `Milestone 0.1.1` in a 0.2 build.

Preferred demo-shell design: derive the visible milestone subtitle from
`BUILD.json`, using an explicit development fallback, so future release
milestones do not require editing the scene solely for the subtitle.

Tests must prove packaged metadata drives the visible milestone and development
mode remains sensible.

Do not turn milestone identity into gameplay state.

### 4.6 0.2 release notes / compatibility boundary

Convert this document into a durable Milestone 0.2 record containing a concise,
truthful release summary.

It should describe the actual repository state through `510ff0c`, including
the major changes since the 0.1/0.1.1 release machinery was introduced, without
claiming a complete Eador battle implementation.

At minimum call out:

- playable deterministic tactical vertical slice and responsive UI/fallback
  presentation;
- Genesis/native profile routing and legacy RNG support that currently exists;
- command/action terminality;
- implemented tactical death/revival/rollback/transfer lifecycle boundary;
- ranged branch parity currently implemented;
- typed unit-action plan foundation with Crushing Blow and Shield Bash;
- local/private mapped presentation tier;
- important unsupported/open systems: remaining twelve explicit unit actions,
  generic battle-action/effect families, status automatic lifecycle boundaries,
  exact legacy RNG call/reseed parity beyond current support, large-unit
  footprint observation, AI/strategy, broad presentation/content parity.

Use `STATUS.md`/matrix truth when wording. Do not turn research findings into
new compatibility claims.

State explicitly that Milestone 0.2 remains the mixed research/prototype
lineage at G0 and is not a stable community API/community-lineage release.

Update `DEMO_RELEASE.md`, README release references, STATUS and ARCHITECTURE only
as necessary to eliminate stale 0.1.1 release instructions and describe the
new reproducibility/manifest/staging path.

## 5. Public/private package invariants

Public:

- no `local_assets/`;
- no original-derived artwork/data;
- authored fallback path must initialize and executable smoke must report the
  fallback marker;
- no developer machine paths or usernames;
- no DAT/extraction/research material.

Private:

- identical EXE and PCK to public;
- adds only executable-adjacent `local_assets/`;
- local bundle is exactly mapping references, no unreferenced files;
- runtime smoke must report loaded local tactical mapping;
- no DAT/extraction-layout/research material.

Both:

- exact full commit ID;
- exact Godot version;
- same milestone and deterministic official timestamp;
- package README/build metadata agree with mode;
- ZIP inventory matches the validated package tree.

## 6. Tests

Add independent synthetic tests for the new release helpers/orchestrator.

Distinguishing coverage must include:

1. external staging parent versus default staging;
2. cleanup ownership (never delete the parent itself);
3. reproducible epoch derived from a supplied/mock commit timestamp and explicit
   `SOURCE_DATE_EPOCH` precedence;
4. two identical synthetic package runs produce byte-identical ZIPs at a fixed
   epoch;
5. pair manifest records exact artifact/runtime hashes and inventories;
6. pair verification rejects mismatched EXE or PCK;
7. pair verification rejects public local assets / invalid private closure
   through the existing validators, not a parallel policy;
8. pair manifest is not written on incomplete/mismatched pair;
9. demo milestone display is metadata-driven rather than hard-coded 0.1.1.

Do not use original assets in tests.

## 7. Validation

Run focused release tests first.

Then from the Windows-backed `/mnt/d` worktree run:

```bash
python3 tools/run_godot_tests.py
python3 -m pytest -q
python3 oracle/test_fixtures_current.py
python3 tools/check_deliberations.py
python3 oracle/test_repository_hygiene.py
python3 tools/check_public_lineage.py
git diff --check
```

Run gdlint comparison against frozen base for every touched GDScript file and
require zero new findings.

Do not treat a Godot run from canonical WSL/ext4 as authoritative.

Because the candidate is intentionally uncommitted during Prime work,
`build_demo.py` still archives frozen `HEAD`. Therefore do not claim a true
candidate 0.2 exported-build acceptance from this tranche. End-to-end public,
private, reproducibility and fresh-clone artifact acceptance occurs **after**
the reviewed release-tooling candidate is integrated and committed.

## 8. Handoff

Keep this release record at `REVIEW` when implementation is complete.

Report:

- exact frozen base;
- files changed/new;
- release architecture changes;
- focused tests;
- full gate results;
- gdlint base/current/delta;
- explicit confirmation that gameplay semantics were untouched;
- explicit confirmation that no dist/local/private artifacts were tracked;
- any blockers to the later private build (especially absence of a prepared
  local asset root);
- exact final `git status --short` and diff stat.

Do not commit, stage, reset, push, rebase, create/remove worktrees, change
dependencies/tool versions, inspect raw binary packets, or spawn child agents.


## 9. Implementation handoff (REVIEW)

Implemented from frozen base
`510ff0c585222aa152a50ec47420e992f8942daf` without gameplay-semantic changes.
The authoritative single-mode builder now supports uniquely owned temporary
staging below a safe caller-selected parent and reproducible commit epochs with
explicit `SOURCE_DATE_EPOCH` precedence. The thin official pair wrapper reuses
the existing package scanners, private closure validator and runtime identity
logic, and writes its ignored manifest only after both packages and smokes pass.
The demo milestone is driven by `BUILD.json`; Windows file/product versions are
`0.2.0.0`.

Changed release surface: `README.md`, `docs/ARCHITECTURE.md`,
`docs/DEMO_RELEASE.md`, `docs/RELEASE_0_2.md`, `docs/STATUS.md`,
`export_presets.cfg`, `game/demo/demo_main.gd`, `game/demo/demo_main.tscn`,
`tests/test_demo_release.gd`, `tools/build_demo.py`,
`tools/test_build_demo.py`, plus new `tools/build_release_pair.py` and
`tools/test_build_release_pair.py`.

Validation from the `/mnt/d` worktree:

- focused Python release tests: 27 passed;
- focused demo-shell GDScript test: all passed;
- Godot aggregate: compile passed; 23 tests passed, one local-pack test skipped,
  and two non-standalone scripts were compile-covered;
- full pytest: 277 passed, 9 skipped, 4 subtests passed; one inherited pytest
  return-value warning;
- fixture freshness: 14 generated fixtures matched;
- deliberations: 3 packages passed;
- repository hygiene: passed;
- public-lineage validator: passed with the existing two open-classification
  notices; G0/classifications unchanged;
- `git diff --check`: passed;
- touched GDScript gdlint at frozen base/current/delta: 0 / 0 / 0.

No core/oracle gameplay semantics, fixtures, packs/bindings, evidence,
observations, deliberation decisions, lineage classifications, dependencies or
tool versions were changed. No `dist/`, `.local/`, `local_assets/` or private
artifact is tracked. The prepared private root `.local/eador_assets` is absent,
so later real private-pair acceptance is blocked until a human supplies it.
No candidate end-to-end 0.2 export was claimed from this dirty worktree; real
pair/reproducibility/fresh-clone acceptance remains post-integration.

## 10. Independent review amendment — official orchestration acceptance seam

**Status remains `REVIEW`.** The complete 13-file candidate was independently
reviewed. The production release design is provisionally accepted: uniquely
owned staging, reproducible epoch selection with explicit
`SOURCE_DATE_EPOCH` precedence, reuse of the existing public/private scanners
and private closure validator, runtime EXE/PCK identity checks, metadata-driven
milestone display, 0.2 Windows version metadata, and the unchanged G0 lineage
boundary are all in the intended shape.

Two bounded corrections are required before acceptance.

### R1. Directly test the official `build_pair()` orchestration seam

The current new tests cover `verify_release_pair()` and
`write_pair_manifest()`, but do not call `build_pair()` itself. Add small
synthetic/mocked tests that distinguish the official orchestration contract
without invoking real Godot.

At minimum prove:

1. both delegated builds receive `reproducible=True`;
2. public receives no asset root while private receives the requested asset root;
3. both delegated builds receive the same milestone and requested staging parent;
4. an already-existing pair manifest is removed before a new official attempt,
   so a failed attempt cannot leave an older manifest looking current;
5. if the public half succeeds but the private delegated build raises
   `BuildError`, no pair manifest exists afterward;
6. on two successful delegated builds, the orchestrator passes both successful
   smoke results to the manifest writer.

Prefer monkeypatching `build_demo.build` and the manifest writer so these are
fast unit tests of orchestration rather than duplicate package-scanner tests.

Do not change production code merely to satisfy test shape. If the direct test
reveals a real failure of the existing orchestration contract, make only the
smallest corresponding correction in `tools/build_release_pair.py`.

### R2. Decouple required fresh-clone public acceptance from private assets

`docs/DEMO_RELEASE.md` currently shows only the pair command in the fresh-clone
acceptance section. The prepared private root is currently absent, while the
frozen contract explicitly requires a real fresh-clone **public** build after
integration.

Change that acceptance procedure so it clearly performs, from the
Windows-backed fresh clone and exact release commit, a public-only official
build first:

```bash
python3 tools/build_demo.py --mode public --milestone 0.2 \
    --reproducible --staging-parent /mnt/d
```

Then describe the pair build as the subsequent acceptance step once a valid
prepared private root is supplied:

```bash
python3 tools/build_release_pair.py --milestone 0.2 \
    --asset-root <prepared-private-root> --staging-parent /mnt/d
```

Make clear that:

- the public fresh-clone artifact can be accepted independently of local/private
  assets;
- final public/private pair acceptance still requires the private root and pair
  manifest;
- the private root remains outside tracked Git content.

Do not weaken any public/private scanner, smoke, identity or closure gate.

### File-mode note

The three new files appear as mode `100755` only because the candidate lives on
the Windows-backed `/mnt/d` worktree. Do not spend this correction changing
file modes. The independent reviewer will normalize these three new tracked
files to `100644` in the accepted integration patch, matching the existing
release-tooling/document convention.

### Validation

Run the focused release tests, then the full REL-0.2 gates from this `/mnt/d`
worktree:

```bash
python3 tools/run_godot_tests.py
python3 -m pytest -q
python3 oracle/test_fixtures_current.py
python3 tools/check_deliberations.py
python3 oracle/test_repository_hygiene.py
python3 tools/check_public_lineage.py
git diff --check
```

Recheck touched-GDScript gdlint against frozen base and require zero new
findings if any GDScript changed. It is expected that this amendment can be
satisfied without further GDScript changes.

Keep `Status: REVIEW`. Append a short correction-specific validation note.
Do not build real release artifacts from the dirty candidate, do not introduce
or copy private assets, and do not change gameplay semantics, evidence,
lineage classifications, dependencies, or tool versions.

## 11. Independent review correction validation (REVIEW)

R1 now directly exercises `build_pair()` with mocked delegated builds and
manifest writing, covering official argument/asset routing, pre-attempt stale
manifest removal, private-build failure after public success, and successful
smoke forwarding. R2 makes the fresh-clone reproducible public build independently
runnable before the private-root-dependent pair acceptance. Production code and
GDScript were unchanged by this correction.

Correction validation from the `/mnt/d` worktree:

- focused release tests: 29 passed;
- Godot aggregate: compile passed; 23 tests passed, one local-pack test skipped,
  and two non-standalone scripts were compile-covered;
- full pytest: 279 passed, 9 skipped, 4 subtests passed; one inherited pytest
  return-value warning;
- fixture freshness: 14 generated fixtures matched;
- deliberations: 3 packages passed;
- repository hygiene: passed;
- public-lineage validator: passed with the existing two open-classification
  notices; G0/classifications remain unchanged;
- `git diff --check`: passed.

No correction-specific GDScript change was made, so no new gdlint delta was
required. No real release artifacts or private assets were built or imported.
Status remains `REVIEW`; final pair acceptance remains blocked until a prepared
private root exists outside tracked Git content.

## 12. Independent review result

> **Historical pre-release record.** This section preserves the tooling-review
> state at that pass. It is superseded as current release authority by the
> accepted artifact record in section 13; its remaining steps are now a
> rebuild/reproducibility procedure, not pending original acceptance.

**Decision:** release tooling accepted; Milestone 0.2 artifacts are not yet
released.

The independent review covered the complete 13-file candidate and one bounded
correction pass. The accepted release architecture preserves
`tools/build_demo.py` as the authoritative packager and adds only the required
hardening:

- each build owns one unique temporary staging child under either the portable
  default or a caller-selected parent; the caller's parent is never recursively
  removed;
- official/reproducible builds derive their epoch from the exact released commit,
  while explicit `SOURCE_DATE_EPOCH` remains authoritative;
- `tools/build_release_pair.py` is a thin official orchestrator that delegates
  both modes to the existing builder, requires both runtime smokes, reopens both
  ZIPs through the existing scanners/closure checks, verifies byte-identical
  EXE/PCK payloads and writes its ignored pair manifest only after the complete
  pair passes;
- direct tests now cover the `build_pair()` delegation and stale-manifest failure
  seam itself, rather than only lower-level manifest helpers;
- the demo's visible milestone identity is driven by package metadata, with an
  explicit development fallback, and Windows file/product versions are
  `0.2.0.0`;
- fresh-clone public artifact acceptance is independently runnable without
  private assets; final pair acceptance remains separately dependent on a valid
  external prepared private root;
- Milestone 0.2 remains the mixed research/prototype lineage at G0. No public
  lineage migration, stable API promise or provenance rewrite is implied.

No gameplay/core/oracle semantics, combat fixtures, packs/bindings, evidence,
lineage classifications, deliberation decisions, dependencies or tool versions
were changed by REL-0.2.

Acceptance reran the focused release tests and the complete Godot, Python,
fixture-freshness, deliberation, repository-hygiene, public-lineage and
`git diff --check` gates from the established Windows-backed worktree.

### Artifact acceptance still required

This status accepts the tracked release tooling only. It does **not** assert that
Milestone 0.2 has been released. After integration and commit:

1. make a real fresh-clone reproducible public build from a Windows-backed
   location at the exact release commit and perform the documented public/DPI
   acceptance;
2. supply a valid prepared private asset root outside tracked Git content;
3. run the official public/private pair build and accept only if the pair
   manifest, identity, closure and both runtime-smoke gates pass;
4. record the resulting artifact and manifest hashes before marking the milestone
   released.

## 13. Milestone 0.2 artifact and manual acceptance

Milestone 0.2 is released from commit
`aa0de561f53889d2465fd75c80a3a3f40c986f0d`.

The authoritative public/private deliverables were produced together from one
fresh Windows-backed clone and one shared Godot export payload. Repeating the
official pair packaging from that payload produced byte-identical public ZIP,
private ZIP and pair manifest.

Authoritative release hashes:

- public ZIP:
  `d77446e8d56727cf0df0051c26ed9773159d0778a04087775f0df398621d1a4e`;
- private ZIP:
  `5f7457170db7e85258c64317076104faad9911318cb979c55f8f9f8a62853223`;
- pair manifest:
  `123ae7e858376b4911fe59c3eb6f133284b1fb415bbcc7cc0f5962853e282854`;
- shared executable payload:
  `66b26ad96df7458ea917b632a73ac7c88bb058db24dbd11a457fd50435ab7b13`.

The pair acceptance verified:

- fresh-clone source at the exact release commit;
- public/private EXE and PCK byte identity inside the authoritative pair;
- public fallback/no-local-assets boundary;
- private exact mapped-asset closure;
- public and private runtime smoke passes;
- pair-manifest integrity and ZIP CRCs;
- byte-identical repeat packaging of the same exported payload;
- clean tracked state after the release build.

Independent Godot export byte identity is **not** claimed. A separate
fresh-clone public-only acceptance probe produced the same executable but a
different compiled PCK. Inspection found the same PCK path set and ordering,
with differences concentrated in Godot-generated compiled GDScript and
exported-scene payloads and no developer-path leakage. The release guarantee is
therefore intentionally bounded to deterministic packaging of a fixed Godot
payload plus exact public/private runtime identity within the official pair.

### Manual Windows UI/DPI acceptance

The remaining human UI gate is accepted under the same criterion used for the
earlier 0.1/0.1.1 milestone deliverables.

The executable continues to ignore Windows display scaling rather than adapting
its logical UI geometry to 100%, 125%, 150% or 200% scaling. This is a known
pre-existing limitation and was not introduced by Milestone 0.2. It is recorded
as an accepted prototype limitation rather than a Milestone 0.2 release blocker.

Milestone 0.2 remains a mixed research/prototype G0 release. This release state
does not imply stable community API guarantees, broad presentation parity or a
public-lineage migration.
