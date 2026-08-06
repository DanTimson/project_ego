#!/usr/bin/env python3
"""
Project EGO extended governance/evidence checkpoint.

This documentation-only updater performs four independent tasks:

1. accepts CX-001 only after its frozen validation commands pass;
2. classifies the new validator and its synthetic tests for public-lineage transfer;
3. installs the R14 large-unit-footprint controlled-observation protocol;
4. defers R15 all-zero/underfull level-up behaviour until an executable consumer
   and synthetic fixture exist;
5. reconciles stale broad ACTION-DISPATCH / MELEE-SECONDARY matrix rows with the
   accepted public-source reductions.

Run from the project_ego repository root:

    python3 /path/to/project_ego_overnight_governance_and_observation_update.py --check
    python3 /path/to/project_ego_overnight_governance_and_observation_update.py --apply

The updater is anchor-checked and idempotent. --apply restores all changed files
if post-write validation fails.
"""

from __future__ import annotations

import argparse
import csv
import io
import re
import subprocess
import sys
from pathlib import Path
from typing import Callable

ROOT = Path(".")
DOCS = ROOT / "docs"

EXPECTED_FILES = (
    "CODEX_WORK_QUEUE.md",
    "codex/tasks/CX-001.md",
    "PUBLIC_LINEAGE_TRANSFER.csv",
    "PUBLIC_TEST_TRANSFER.csv",
    "BINARY_REQUESTS.md",
    "OPEN_QUESTIONS.md",
    "PUBLIC_LINEAGE_AUDIT.md",
    "COMPATIBILITY_TEST_MATRIX.md",
    "STATUS.md",
    "observations/README.md",
)

CX_REVIEW = """## Review result

- **Decision:** accepted
- **Reviewed:** 2026-08-06
- **Reviewer:** binary/governance
- **Queue result:** `DONE`
- **Runtime behaviour changed:** no

The implementation matches the frozen `NON_SEMANTIC_TOOLING` contract:

- exact registry headers and known `N*`/`T*` classes are checked;
- malformed widths, duplicate exact artifact/scope rows and missing literal paths
  are rejected;
- literal, semicolon-group, glob and explicit aggregate forms are distinguished;
- unclassified rows remain notices rather than structural errors;
- output and exit status are deterministic;
- the tests use only standard-library temporary fixtures.

Intentional limits are accepted rather than expanded after implementation:

- a glob is a declared optional/pattern form and is not required to match;
- the tool validates structure, not classification completeness or legal
  sufficiency;
- descriptive aggregates remain an explicit allowlist.

The acceptance updater refuses to mark this task `DONE` unless the synthetic
tests, real-registry validation and deliberation checker all pass.
"""

R14_PROTOCOL = """# OBS-R14 — large-unit tactical footprint

Status: **ready for controlled observation**  
Request: R14  
Public source: `DOC-EADOROPEDIA-NH-26.0620-F01`  
Binary extraction authorized: **no**

## 1. Question

Does a unit presented as a giant occupy one logical tactical cell or several?

This is a high-blast-radius but cheap observation. A multi-cell result would
affect placement, path blocking, adjacency, melee legality, area effects and
auras. A single-cell result closes the footprint question without any binary
work.

## 2. Public test subject

For New Horizons 26.0620.f01 use unit `/66 Гигант` at level zero. The supplied
Eadoropedia snapshot identifies it as:

- rank 4;
- class `Гигант`;
- type `Смертный, Великан`;
- speed 2.

Those facts identify a convenient subject. They do not imply any footprint.

For Genesis use a visibly giant-class unit available in that build and record
its displayed name. Do not assume NH numeric IDs carry over.

Use one ordinary one-cell creature as a control.

## 3. Setup

Create or load a battle with:

- an open area free of obstacles and battlefield objects;
- the giant subject;
- at least six ordinary friendly or enemy units;
- one ordinary control subject;
- no teleport, push, immobilization or terrain effect altering occupancy.

Label the giant's apparent center tile `G` and its six standard odd-row hex
neighbours `N0..N5`. Save or screenshot the labelled setup.

## 4. Cases

### R14-A — selection and hover footprint

Select and hover the ordinary control, then the giant.

Record every tile that receives:

- occupied/selected highlighting;
- cursor blocking;
- unit-details association;
- attack-target association.

A large sprite covering several hexes is not evidence of multi-cell occupancy
unless more than one logical tile participates.

### R14-B — neighbour occupancy

Attempt to place or move an ordinary unit onto each of `N0..N5`.

Record which neighbours are legal final positions. Repeat with the ordinary
control at `G`.

Interpretation:

- all six neighbours behave normally: supports one logical cell;
- a stable subset is blocked only around the giant: possible multi-cell
  footprint; record exact odd-row shape;
- inconsistent blocking: inspect terrain/object interference and rerun.

### R14-C — pathing through visual overlap

Choose paths that pass immediately beside the giant and, where its sprite
visually overlaps a neighbouring hex, through that apparent overlap.

Record the path preview and final movement. The relevant result is logical
blocking, not sprite overlap.

### R14-D — melee adjacency

From each legal neighbour, attempt an ordinary melee attack on the giant.

Record whether the standard six neighbours exhaust the legal melee-adjacent
positions or whether attacks target additional occupied cells.

### R14-E — movement and area effects

Move the giant exactly one legal hex and record:

- old and new logical center;
- vacated and newly blocked cells;
- whether surrounding units are displaced.

If an available radius-one area preview can be used without changing the setup,
record which cells are included when centered on the giant and on an adjacent
tile.

## 5. Interpretation

| observation | conclusion |
|---|---|
| one selected/occupied tile; all six neighbours normal; one center moves by one hex | single-cell tactical unit |
| multiple stable highlighted or blocked tiles moving as one shape | multi-cell unit; record footprint for even and odd rows |
| only sprite overlap extends beyond `G` | presentation-only size; still single-cell |
| result differs by build or unit | profile/content-specific footprint; record each separately |

## 6. Closure condition

R14 closes when one build has:

- one selection/hover record;
- all six neighbour checks;
- one pathing check;
- one movement check;
- a screenshot or sufficiently precise tile record.

A multi-cell result requires the exact footprint shape. A single-cell result
requires only the completed sheet. Binary inspection is justified only if the
UI and movement results contradict each other.
"""

R14_CSV = """build,content_version,case_id,subject,subject_id_or_name,subject_class,center_tile,control_subject,highlighted_or_associated_tiles,legal_neighbor_tiles,blocked_neighbor_tiles,path_preview_or_result,melee_target_tiles,area_preview_tiles,move_old_center,move_new_center,displaced_units,video_or_screenshot,interpretation,notes
,,R14-A,/66 Гигант,/66,Гигант,G,,,,,,,,,,,,,
,,R14-B,/66 Гигант,/66,Гигант,G,,,,,,,,,,,,,
,,R14-C,/66 Гигант,/66,Гигант,G,,,,,,,,,,,,,
,,R14-D,/66 Гигант,/66,Гигант,G,,,,,,,,,,,,,
,,R14-E,/66 Гигант,/66,Гигант,G,,,,,,,,,,,,,
"""

LEVEL_UP_AUDIT = """# Level-up exhausted-pool necessity audit

Status: **deferred until an executable consumer exists**  
Request: R15  
Questions: OPEN_QUESTIONS 6 and 6b  
Binary extraction authorized: **no**

## 1. Separated questions

R15 previously combined two different layers:

1. **weighted primitive:** what a legacy weighted roll does when total weight is
   zero;
2. **level-up caller policy:** what the option-selection flow does when filtering
   leaves fewer candidates than requested, no candidates, or only zero-weight
   candidates.

The first may be unreachable by contract. The second is player-visible only when
a level-up option consumer actually invokes it.

## 2. Current reachability

The ordinary candidate collection, prerequisites, weighting and selected-value
removal are already recovered.

The edge does not currently unblock a runnable parity path:

- `core/model/option.gd` is empty;
- `tests/test_options.gd` is empty;
- the compatibility matrix has no executable underfull/all-zero level-up fixture;
- `LegacyRng` deliberately raises on a zero total so the prototype does not
  invent an undocumented fallback.

This does not prove the edge is impossible in Genesis or NH. It means new binary
work presently has no implementation consumer and fails the DELIB-0002
material-reachability gate.

## 3. Behaviour not to invent

Until a profile decision or evidence exists, do not silently choose among:

- return the first entry;
- return a sentinel;
- skip the draw;
- expose fewer choices;
- duplicate a choice;
- refill from rejected candidates;
- treat zero weights as uniform;
- abort the level-up operation.

The current explicit exception is preferable to an accidental compatibility
claim.

## 4. Reactivation trigger

R15 becomes active only after all of the following exist:

1. an implemented level-up option consumer;
2. synthetic fixtures for:
   - empty candidate pool;
   - one positive candidate when several choices are requested;
   - fewer positive candidates than requested;
   - all surviving weights zero;
   - mixed zero and positive weights;
   - duplicate values plus removal-by-selected-value;
3. a stated Genesis/NH/native profile need;
4. a public/data search and controlled observation attempt, or a recorded reason
   those cannot reach the state.

Only the still-material unresolved branch may then generate a binary request.

## 5. Future neutral fixture

The future fixture should record, without binary addresses:

```text
input candidates
prerequisite-filtered candidates
weights
requested choice count
RNG seed/profile
selected sequence
remaining candidates after each selection
caller result or explicit error
```

The weighted primitive and the caller policy must be tested separately. A caller
guard that guarantees positive totals would close 6b as unreachable while
leaving the underfull-choice policy independently testable.

## 6. Classification

- ordinary level-up selection: existing recovered specification;
- zero-total primitive: `N3_INTERNAL` unless a reachable caller is demonstrated;
- underfull/exhausted user-facing choice flow: conditional `N2_EXACT_EDGE`;
- current action: `DEFERRED_UNTIL_CONSUMER`;
- transfer consequence: neutral fixtures may transfer; raw roller/caller control
  flow remains research evidence.
"""

LINEAGE_ROWS = (
    {
        "artifact": "tools/check_public_lineage.py",
        "symbol_or_scope": "public-lineage registry structural validator",
        "current_basis": "Project-authored governance tooling under CX-001",
        "necessity_class": "N0_PUBLIC",
        "transfer_class": "T0_RETAIN",
        "materiality": "repository governance",
        "public_basis": "DELIB-0002; WORK_ALLOCATION.md; registry schemas",
        "binary_basis": "None",
        "binary_basis_surface": "none",
        "public_basis_sufficient": "yes",
        "required_action": "Transfer with the governance seed and keep recognized schemas/classes synchronized",
        "owner": "binary/governance",
        "status": "accepted",
        "notes": "Structural validation only; globs need not match and policy completeness remains outside scope.",
    },
)

TEST_ROWS = (
    {
        "artifact_or_pattern": "tools/test_check_public_lineage.py",
        "area": "public-lineage registry governance",
        "basis": "project-authored synthetic structural fixtures",
        "necessity_class": "N0_PUBLIC",
        "transfer_class": "T0_RETAIN",
        "required_action": "Transfer with the validator; preserve dependency-free temporary-tree coverage",
        "status": "accepted",
        "notes": "Tests literal/group/glob/aggregate forms, notices, headers, widths, duplicates, missing literals and unknown classes.",
    },
)

R14_SECTION = """## R14 — OBSERVATION READY: does any unit occupy more than one tactical cell?

**Closes:** `OPEN_QUESTIONS` item 2 · matrix `FOOTPRINT-001`
**Method:** controlled observation
**Cost:** very small
**Public subject:** NH `/66 Гигант`
**Protocol:** `docs/observations/OBS-R14-LARGE-UNIT-PREFLIGHT.md`
**Results:** `docs/observations/OBS-R14-LARGE-UNIT.csv`
**New binary extraction:** none

The engine models every unit as single-cell. A wrong answer would affect
placement, adjacency, movement blocking, area effects and aura reach, but the
question is directly visible in play.

The preregistered protocol compares a normal unit and a giant-class unit across:

- selection/hover association;
- all six neighbour occupancy checks;
- pathing through visual sprite overlap;
- melee adjacency;
- one-hex movement and optional radius-one preview.

**Minimum sufficient answer.** One logical cell, or the exact multi-cell
footprint shape for even and odd rows. Sprite size alone does not count.

Binary work is authorized only if selection, pathing and occupancy observations
contradict one another.

"""

R15_SECTION = """## R15 — DEFERRED UNTIL CONSUMER: all-zero weighted table and exhausted level-up pools

**Questions:** `OPEN_QUESTIONS` items 6 and 6b
**Ledger:** weighted roller `00454E80`
**Audit:** `docs/LEVEL_UP_EDGE_AUDIT.md`
**Disposition:** `DEFERRED_UNTIL_CONSUMER`
**New binary extraction:** none

R15 combines a possibly internal weighted-primitive edge with a player-facing
caller policy. The ordinary candidate collection, prerequisites, weighting and
selected-value removal are recovered, but the edge has no current executable
parity consumer:

- `core/model/option.gd` is empty;
- `tests/test_options.gd` is empty;
- no underfull/all-zero level-up fixture reaches the caller;
- `LegacyRng` deliberately raises on zero total rather than inventing a fallback.

The current state therefore fails the DELIB-0002 material-reachability gate. A
small binary question is still unnecessary when nothing consumes the answer.

R15 reactivates only after an option consumer and synthetic empty/underfull/zero
weight fixtures exist, a profile needs exact behaviour, and public or black-box
evidence cannot settle the remaining branch.

Do not generalize an eventual primitive result into caller policy: a caller guard
may make zero-total rolling unreachable while still returning fewer choices or an
explicit exhausted state.

"""

DEFERRED_OPEN_SECTION = """## Deferred until an executable consumer exists

| ID | Question | Why deferred | Reactivation trigger |
|---|---|---|---|
| 6 | **Exhausted level-up pools.** | Ordinary candidate collection is recovered, but `core/model/option.gd` and `tests/test_options.gd` are empty and no parity fixture reaches an underfull caller. Choosing a fallback now would create an unsupported gameplay rule. | Implement the option consumer and synthetic empty/one/fewer-than-requested fixtures; state the target profile; attempt public/black-box evidence before binary work. |
| 6b | **All-zero weighted roller behaviour.** | The normal path assumes a positive total and `LegacyRng` deliberately raises. The primitive may be unreachable if the future caller guards positive totals. | Demonstrate a reachable all-zero caller after filtering, or prove the caller guard; then ask only for the remaining observable branch. |

See `LEVEL_UP_EDGE_AUDIT.md`.

"""

AUDIT_SUBSECTION = """### 5.10 Governance validator, R14 and R15 checkpoint

CX-001 is accepted as `N0_PUBLIC / T0_RETAIN` governance tooling. Its validator
checks registry structure and literal paths but deliberately does not claim
classification completeness or require optional globs to match.

R14 passes the necessity gate as `N1_BLACKBOX`: footprint is directly observable,
cheap to test and has a large architectural blast radius. The `/66 Гигант`
protocol is ready; no binary packet is justified before observation.

R15 is conditionally material but currently fails reachability. The named
GDScript option model and test are empty and no parity fixture reaches an
underfull/all-zero caller. It is deferred until an executable consumer exists.
The zero-total primitive remains `N3_INTERNAL` unless reachability is
demonstrated; the player-facing underfull policy may later become
`N2_EXACT_EDGE`.

"""

FOOTPRINT_ROW = (
    "| FOOTPRINT-001 | battlefield | NH `/66 Гигант` versus ordinary control: "
    "selection association, six-neighbour occupancy, pathing, melee adjacency "
    "and one-hex movement | `DOC-EADOROPEDIA-NH-26.0620-F01`; "
    "`docs/observations/OBS-R14-LARGE-UNIT-PREFLIGHT.md` | record one logical "
    "cell or exact multi-cell shape; distinguish sprite overlap from occupancy | "
    "OBSERVATION READY |"
)

LEVELUP_EDGE_ROW = (
    "| LEVELUP-EDGE-001 | progression | empty, one-candidate, "
    "fewer-than-requested, all-zero, mixed-zero and duplicate-value pools | "
    "`docs/LEVEL_UP_EDGE_AUDIT.md`; future option consumer | weighted primitive "
    "and caller result recorded separately; no invented fallback | DEFERRED — "
    "executable consumer and fixture absent |"
)

ACTION_ROW = (
    "| ACTION-DISPATCH-001 | battle actions | public/data action-family coverage "
    "and only implemented content-record mappings | "
    "`docs/ACTION_SEMANTICS_AUDIT.md`; "
    "`docs/BATTLE_ACTION_FAMILY_COVERAGE.csv`; public content descriptions | "
    "target legality, effect-family inputs/outputs and only materially "
    "non-commutative order; original eight-clause structure is not required | "
    "PARTIAL — public family matrix complete; generic execution and "
    "consumer-triggered opcode mappings remain |"
)

MELEE_ROW = (
    "| MELEE-SECONDARY-001 | combat | finite zero-damage, threshold, "
    "retaliation, follow-up, component-damage, trample and instant-death cases | "
    "`docs/MELEE_SECONDARY_COVERAGE.csv`; "
    "`docs/observations/OBS-R17-MELEE-SECONDARY-PREFLIGHT.md`; archived "
    "`004D9800` evidence | record only observable trigger/order outcomes; do not "
    "reconstruct the monolithic processor | OBSERVATION READY |"
)


class UpdateError(RuntimeError):
    pass


def read_text(relative: str) -> str:
    path = DOCS / relative
    if not path.is_file():
        raise UpdateError(f"missing required file: {path}")
    return path.read_text(encoding="utf-8")


def run_command(command: list[str], label: str) -> None:
    result = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode != 0:
        raise UpdateError(f"{label} failed with exit code {result.returncode}")


def validate_codex_001() -> None:
    required = (
        ROOT / "tools/check_public_lineage.py",
        ROOT / "tools/test_check_public_lineage.py",
        ROOT / "tools/check_deliberations.py",
    )
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise UpdateError("CX-001 acceptance inputs missing: " + ", ".join(missing))

    run_command(
        [sys.executable, "tools/test_check_public_lineage.py"],
        "CX-001 synthetic tests",
    )
    run_command(
        [sys.executable, "tools/check_public_lineage.py"],
        "CX-001 real-registry validation",
    )
    run_command(
        [sys.executable, "tools/check_deliberations.py"],
        "deliberation validation",
    )


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise UpdateError(f"{label}: expected one exact anchor, found {count}")
    return text.replace(old, new, 1)


def regex_replace_once(
    text: str, pattern: str, replacement: str, label: str
) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.M | re.S)
    if count != 1:
        raise UpdateError(f"{label}: expected one regex anchor, found {count}")
    return updated


def update_queue(text: str) -> str:
    text = text.replace(
        "| CX-001 | `NON_SEMANTIC_TOOLING` | validate public-lineage registries | binary/governance | `REVIEW` | none |",
        "| CX-001 | `NON_SEMANTIC_TOOLING` | validate public-lineage registries | binary/governance | `DONE` | none |",
        1,
    )
    text = text.replace(
        (
            "The first assignment should be CX-001. CX-002 through CX-004 may "
            "proceed in\nparallel only when each receives a separate worktree or "
            "branch and returns an\nindependent patch."
        ),
        (
            "CX-001 is accepted. CX-002 through CX-004 may proceed in parallel "
            "only when\neach receives a separate worktree or branch and returns "
            "an independent patch."
        ),
        1,
    )
    if "| CX-001 |" not in text or "`DONE`" not in text:
        raise UpdateError("CODEX_WORK_QUEUE: CX-001 DONE row not established")
    return text


def update_cx_task(text: str) -> str:
    text = text.replace("- **State:** `REVIEW`", "- **State:** `DONE`", 1)
    if "## Review result" not in text:
        text = text.rstrip() + "\n\n" + CX_REVIEW
    return text


def append_dict_rows(
    text: str,
    rows_to_add: tuple[dict[str, str], ...],
    key_fields: tuple[str, ...],
    label: str,
) -> str:
    reader = csv.DictReader(io.StringIO(text))
    fields = reader.fieldnames
    if not fields:
        raise UpdateError(f"{label}: empty CSV")
    rows = list(reader)

    for new_row in rows_to_add:
        missing = set(fields).difference(new_row)
        extra = set(new_row).difference(fields)
        if missing or extra:
            raise UpdateError(
                f"{label}: row schema mismatch; missing={sorted(missing)}, "
                f"extra={sorted(extra)}"
            )
        key = tuple(new_row[field] for field in key_fields)
        if not any(tuple(row[field] for field in key_fields) == key for row in rows):
            rows.append(new_row)

    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return output.getvalue()


def update_binary_requests(text: str) -> str:
    text = text.replace(
        (
            "**Current binary extraction:** none. R1–R11 are closed. R12, R13, "
            "R15 and the\nreduced R17 questions must pass the DELIB-0002 "
            "necessity gate before a new\nextraction packet is issued. R16 is "
            "retired as structural reconstruction."
        ),
        (
            "**Current binary extraction:** none. R1–R11 are closed. R12, R13 "
            "and the\nreduced R17 questions remain black-box/necessity-gated. "
            "R14 is observation-ready,\nR15 is deferred until a consumer exists, "
            "and R16 is retired."
        ),
        1,
    )

    if "## R14 — OBSERVATION READY:" not in text:
        text = regex_replace_once(
            text,
            r"^## R14 — .*?(?=^---\n\n## R15\b)",
            R14_SECTION,
            "BINARY_REQUESTS R14 section",
        )

    if "## R15 — DEFERRED UNTIL CONSUMER:" not in text:
        text = regex_replace_once(
            text,
            r"^## R15 — .*?(?=^---\n\n## R16\b)",
            R15_SECTION,
            "BINARY_REQUESTS R15 section",
        )

    text = text.replace(
        (
            "**Consumer-triggered only.** R15 when level-up implementation reaches "
            "a\nzero-total or exhausted-pool state."
        ),
        (
            "**Deferred until consumer.** R15 is inactive until the option model "
            "and synthetic\nunderfull/all-zero fixtures reach a real caller."
        ),
        1,
    )
    return text


def update_open_questions(text: str) -> str:
    if "## Deferred until an executable consumer exists" not in text:
        lines = text.splitlines()
        remove_prefixes = (
            "| 6 | **Exhausted level-up pools.**",
            "| 6b | **All-zero weighted roller behaviour.**",
        )
        lines = [
            line for line in lines
            if not any(line.startswith(prefix) for prefix in remove_prefixes)
        ]
        text = "\n".join(lines) + "\n"

    old_item2_pattern = (
        r"^\| 2 \| \*\*Large-unit battlefield footprint\.\*\* \|.*?\|$"
    )
    new_item2 = (
        "| 2 | **Large-unit battlefield footprint.** | Public NH data identifies "
        "`/66 Гигант` as a level-zero giant-class test subject. The logical "
        "footprint remains unknown; sprite size is not occupancy evidence. | Run "
        "`docs/observations/OBS-R14-LARGE-UNIT-PREFLIGHT.md` and submit "
        "`OBS-R14-LARGE-UNIT.csv`; use binary evidence only if UI, pathing and "
        "occupancy contradict one another. |"
    )
    text = regex_replace_once(
        text, old_item2_pattern, new_item2, "OPEN_QUESTIONS item 2"
    )

    if "## Deferred until an executable consumer exists" not in text:
        marker = "## Current-model versus binary conflicts"
        pos = text.find(marker)
        if pos < 0:
            raise UpdateError("OPEN_QUESTIONS: current-conflicts anchor missing")
        text = text[:pos] + DEFERRED_OPEN_SECTION + text[pos:]

    text = text.replace(
        (
            "| D2 | **Battle-action effect-type dictionary.** | All eight-clause "
            "dispatcher cases, field use, resistance rule, immediate/runtime "
            "behaviour and damage channel. |"
        ),
        (
            "| D2 | **Battle-action effect-type dictionary.** | Map only "
            "implemented/reachable content opcodes to the public effect families, "
            "fields, resistance rule and observable result. The original "
            "eight-clause dispatcher structure is not a requirement. |"
        ),
        1,
    )
    return text


def update_matrix(text: str) -> str:
    if "- **DEFERRED**" not in text:
        anchor = (
            "- **OBSERVATION READY** — a preregistered black-box protocol exists; "
            "the build result has not yet been recorded.\n"
        )
        text = replace_once(
            text,
            anchor,
            anchor
            + "- **DEFERRED** — the edge is recorded but no current executable "
              "consumer justifies evidence work.\n",
            "matrix DEFERRED status",
        )

    text = regex_replace_once(
        text,
        r"^\| RNG-WEIGHT-002 \|.*?$",
        (
            "| RNG-WEIGHT-002 | RNG | total weight zero | "
            "`docs/LEVEL_UP_EDGE_AUDIT.md`; future reachable caller | keep "
            "primitive error/sentinel/guard distinct from level-up caller policy | "
            "DEFERRED — reachability and consumer fixture absent |"
        ),
        "matrix RNG-WEIGHT-002",
    )

    if "| LEVELUP-EDGE-001 |" not in text:
        anchor = "| LEVELUP-SELECT-001 |"
        pos = text.find(anchor)
        if pos < 0:
            raise UpdateError("matrix LEVELUP-SELECT-001 missing")
        end = text.find("\n", pos)
        text = text[: end + 1] + LEVELUP_EDGE_ROW + "\n" + text[end + 1 :]

    if "| FOOTPRINT-001 |" not in text:
        anchor = "| GRID-ADJ-001 |"
        pos = text.find(anchor)
        if pos < 0:
            raise UpdateError("matrix GRID-ADJ-001 missing")
        end = text.find("\n", pos)
        text = text[: end + 1] + FOOTPRINT_ROW + "\n" + text[end + 1 :]

    text = regex_replace_once(
        text,
        r"^\| ACTION-DISPATCH-001 \|.*?$",
        ACTION_ROW,
        "matrix ACTION-DISPATCH-001",
    )
    text = regex_replace_once(
        text,
        r"^\| MELEE-SECONDARY-001 \|.*?$",
        MELEE_ROW,
        "matrix MELEE-SECONDARY-001",
    )
    return text


def update_audit(text: str) -> str:
    if "### 5.10 Governance validator, R14 and R15 checkpoint" not in text:
        marker = "## 6. Remaining binary queue after the audit"
        pos = text.find(marker)
        if pos < 0:
            raise UpdateError("PUBLIC_LINEAGE_AUDIT queue anchor missing")
        text = text[:pos] + AUDIT_SUBSECTION + text[pos:]

    table_anchor = (
        "| R13 start-of-turn lifecycle | `N1_BLACKBOX` and high materiality | "
    )
    if "| R14 large-unit footprint |" not in text:
        pos = text.find(table_anchor)
        if pos < 0:
            raise UpdateError("PUBLIC_LINEAGE_AUDIT R13 row missing")
        end = text.find("\n", pos)
        rows = (
            "| R14 large-unit footprint | `N1_BLACKBOX`, cheap/high blast radius | "
            "Observation protocol ready with NH `/66 Гигант`; close from logical "
            "selection/occupancy/pathing results before binary work. |\n"
            "| R15 all-zero/underfull level-up edge | conditional "
            "`N2_EXACT_EDGE`; zero-total primitive may be `N3_INTERNAL` | Deferred "
            "until an executable option consumer and synthetic edge fixtures "
            "exist; do not invent fallback behaviour. |\n"
        )
        text = text[: end + 1] + rows + text[end + 1 :]

    text = text.replace(
        (
            "| R16 action dispatcher | mostly `N3_INTERNAL` | Retire as "
            "whole-function reconstruction. Replace with player-facing "
            "action-semantics coverage matrix. |"
        ),
        (
            "| R16 action dispatcher | `N3_INTERNAL / RETIRED` | Public "
            "effect-family coverage exists; implement only consumer-triggered "
            "observable mappings, not original dispatcher structure. |"
        ),
        1,
    )
    text = text.replace(
        (
            "| R17 melee secondary effects | selective `N2_EXACT_EDGE` | Replace "
            "with finite trigger/order matrix; inspect only unresolved material "
            "cells. |"
        ),
        (
            "| R17 melee secondary effects | selective `N2_EXACT_EDGE` | Public "
            "trigger matrix and controlled-observation packet are ready; inspect "
            "only a surviving inaccessible non-commutative cell. |"
        ),
        1,
    )
    text = text.replace(
        "Broad binary progression should pause until this triage is accepted or amended.",
        (
            "No binary packet is active. R12, R13, R14 and R17 are observation-first; "
            "R15 is consumer-deferred."
        ),
        1,
    )
    return text


def update_status(text: str) -> str:
    text = text.replace(
        (
            "| activated actions | docs, data, binary dispatcher | implemented | "
            "`Action` implemented | effect dictionary incomplete |"
        ),
        (
            "| activated actions | public/data families + selective binary edges | "
            "implemented | `Action` catalogue implemented | fourteen explicit NH "
            "unit actions and public effect-family matrix catalogued; battlefield "
            "execution and consumer-triggered opcode mappings incomplete |"
        ),
        1,
    )
    text = text.replace(
        (
            "| level-up selection | data + binary | implemented in part | options "
            "implemented | legacy RNG/underfull cases open |"
        ),
        (
            "| level-up selection | data + binary | implemented in part | "
            "`core/model/option.gd` and `tests/test_options.gd` empty | ordinary "
            "selection is specified; R15 zero-total/underfull edge deferred until "
            "an executable consumer and fixture exist |"
        ),
        1,
    )
    text = text.replace(
        (
            "| battlefield coordinates and adjacency | binary | implemented | "
            "implemented | adjacency recovered |"
        ),
        (
            "| battlefield coordinates and adjacency | binary + controlled "
            "observation | implemented | implemented | adjacency recovered; R14 "
            "large-unit logical-footprint protocol ready |"
        ),
        1,
    )
    text = text.replace(
        (
            "opens seven non-semantic repository-conformance tasks; CX-001 through "
            "CX-004 are\nready, while aggregate preflight, export and CI work "
            "remain dependency-blocked."
        ),
        (
            "opens seven non-semantic repository-conformance tasks; CX-001 is "
            "accepted,\nCX-002 through CX-004 are ready, and aggregate preflight, "
            "export and CI work\nremain dependency-blocked."
        ),
        1,
    )

    note = (
        "CX-001 passed governance review and is classified `N0_PUBLIC / "
        "T0_RETAIN`. R14 now has a five-case giant-footprint observation packet. "
        "R15 is formally deferred until a level-up option consumer and synthetic "
        "underfull/all-zero fixtures exist. The stale broad dispatcher and melee "
        "matrix rows are reconciled with the public-family and finite-observation "
        "reductions.\n\n"
    )
    if note not in text:
        marker = "When a new checkpoint is produced, update together:"
        pos = text.find(marker)
        if pos < 0:
            raise UpdateError("STATUS checkpoint anchor missing")
        text = text[:pos] + note + text[pos:]
    return text


def update_observation_readme(text: str) -> str:
    desired = """Current packets:

- `OBS-R12-R13-PREFLIGHT.md`
- `OBS-R12-HIT-RETURN.csv`
- `OBS-R13-START-EFFECT.csv`
- `OBS-R14-LARGE-UNIT-PREFLIGHT.md`
- `OBS-R14-LARGE-UNIT.csv`
- `OBS-R17-MELEE-SECONDARY-PREFLIGHT.md`
- `OBS-R17-MELEE-SECONDARY.csv`
"""
    text = re.sub(
        r"Current packet[s]?:\n(?:\n- .*\n?)+$",
        desired,
        text.rstrip(),
        flags=re.M,
    )
    return text.rstrip() + "\n"


UPDATERS: dict[str, Callable[[str], str]] = {
    "CODEX_WORK_QUEUE.md": update_queue,
    "codex/tasks/CX-001.md": update_cx_task,
    "PUBLIC_LINEAGE_TRANSFER.csv": lambda text: append_dict_rows(
        text, LINEAGE_ROWS, ("artifact", "symbol_or_scope"),
        "PUBLIC_LINEAGE_TRANSFER.csv"
    ),
    "PUBLIC_TEST_TRANSFER.csv": lambda text: append_dict_rows(
        text, TEST_ROWS, ("artifact_or_pattern", "area"),
        "PUBLIC_TEST_TRANSFER.csv"
    ),
    "BINARY_REQUESTS.md": update_binary_requests,
    "OPEN_QUESTIONS.md": update_open_questions,
    "PUBLIC_LINEAGE_AUDIT.md": update_audit,
    "COMPATIBILITY_TEST_MATRIX.md": update_matrix,
    "STATUS.md": update_status,
    "observations/README.md": update_observation_readme,
}

NEW_FILES = {
    "observations/OBS-R14-LARGE-UNIT-PREFLIGHT.md": R14_PROTOCOL,
    "observations/OBS-R14-LARGE-UNIT.csv": R14_CSV,
    "LEVEL_UP_EDGE_AUDIT.md": LEVEL_UP_AUDIT,
}


def validate_csv_text(label: str, text: str) -> None:
    rows = list(csv.reader(io.StringIO(text)))
    if not rows:
        raise UpdateError(f"{label}: empty CSV")
    width = len(rows[0])
    bad = [
        (index + 1, len(row))
        for index, row in enumerate(rows)
        if len(row) != width
    ]
    if bad:
        raise UpdateError(f"{label}: malformed row widths: {bad}")


def validate(contents: dict[str, str]) -> None:
    checks = {
        "CX task done": "- **State:** `DONE`"
        in contents["codex/tasks/CX-001.md"],
        "CX review": "## Review result"
        in contents["codex/tasks/CX-001.md"],
        "queue done": "| CX-001 |" in contents["CODEX_WORK_QUEUE.md"]
        and "`DONE`" in contents["CODEX_WORK_QUEUE.md"],
        "validator classified": "tools/check_public_lineage.py"
        in contents["PUBLIC_LINEAGE_TRANSFER.csv"],
        "validator test classified": "tools/test_check_public_lineage.py"
        in contents["PUBLIC_TEST_TRANSFER.csv"],
        "R14 ready": "## R14 — OBSERVATION READY:"
        in contents["BINARY_REQUESTS.md"],
        "R15 deferred": "## R15 — DEFERRED UNTIL CONSUMER:"
        in contents["BINARY_REQUESTS.md"],
        "deferred questions": "## Deferred until an executable consumer exists"
        in contents["OPEN_QUESTIONS.md"],
        "footprint matrix": "| FOOTPRINT-001 |"
        in contents["COMPATIBILITY_TEST_MATRIX.md"],
        "levelup edge matrix": "| LEVELUP-EDGE-001 |"
        in contents["COMPATIBILITY_TEST_MATRIX.md"],
        "dispatcher reduced": "PARTIAL — public family matrix complete"
        in contents["COMPATIBILITY_TEST_MATRIX.md"],
        "melee observation": "| MELEE-SECONDARY-001 |"
        in contents["COMPATIBILITY_TEST_MATRIX.md"]
        and "OBSERVATION READY" in contents["COMPATIBILITY_TEST_MATRIX.md"],
        "audit checkpoint": "### 5.10 Governance validator, R14 and R15 checkpoint"
        in contents["PUBLIC_LINEAGE_AUDIT.md"],
        "status checkpoint": "CX-001 passed governance review"
        in contents["STATUS.md"],
        "observation index": "OBS-R14-LARGE-UNIT-PREFLIGHT.md"
        in contents["observations/README.md"],
    }
    failed = [name for name, ok in checks.items() if not ok]
    if failed:
        raise UpdateError("post-update invariant failure: " + ", ".join(failed))

    validate_csv_text(
        "PUBLIC_LINEAGE_TRANSFER.csv",
        contents["PUBLIC_LINEAGE_TRANSFER.csv"],
    )
    validate_csv_text(
        "PUBLIC_TEST_TRANSFER.csv",
        contents["PUBLIC_TEST_TRANSFER.csv"],
    )
    validate_csv_text("OBS-R14-LARGE-UNIT.csv", R14_CSV)

    if contents["OPEN_QUESTIONS.md"].count("| 6 | **Exhausted") != 1:
        raise UpdateError("OPEN_QUESTIONS: expected one deferred item 6 row")
    if contents["OPEN_QUESTIONS.md"].count("| 6b | **All-zero") != 1:
        raise UpdateError("OPEN_QUESTIONS: expected one deferred item 6b row")


def install_new_files(apply: bool) -> list[str]:
    additions: list[str] = []
    for relative, content in NEW_FILES.items():
        path = DOCS / relative
        if path.exists():
            existing = path.read_text(encoding="utf-8")
            if existing != content:
                raise UpdateError(f"{path}: exists with different content")
        else:
            additions.append(f"docs/{relative}")
            if apply:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8", newline="\n")
    return additions


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    if not DOCS.is_dir():
        raise UpdateError("run from the project_ego repository root; docs/ missing")

    missing = [
        relative for relative in EXPECTED_FILES
        if not (DOCS / relative).is_file()
    ]
    if missing:
        raise UpdateError("missing required docs: " + ", ".join(missing))

    print("Validating CX-001 frozen acceptance commands...")
    validate_codex_001()

    before = {relative: read_text(relative) for relative in EXPECTED_FILES}
    after: dict[str, str] = {}
    changed: list[str] = []

    for relative in EXPECTED_FILES:
        updated = UPDATERS[relative](before[relative])
        after[relative] = updated
        if updated != before[relative]:
            changed.append(f"docs/{relative}")

    validate(after)
    additions = install_new_files(apply=False)

    if args.check:
        print("Extended checkpoint anchors and invariants: OK")
        print("Files that would change or be added:")
        for path in changed + additions:
            print(f"  {path}")
        return 0

    backups: dict[Path, str | None] = {}
    try:
        for relative in EXPECTED_FILES:
            path = DOCS / relative
            if after[relative] != before[relative]:
                backups[path] = before[relative]
                path.write_text(after[relative], encoding="utf-8", newline="\n")

        for relative, content in NEW_FILES.items():
            path = DOCS / relative
            if not path.exists():
                backups[path] = None
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8", newline="\n")

        print("Re-running CX-001 against the updated registries...")
        validate_codex_001()
    except Exception:
        for path, original in reversed(list(backups.items())):
            if original is None:
                if path.exists():
                    path.unlink()
            else:
                path.write_text(original, encoding="utf-8", newline="\n")
        raise

    print("Extended governance/evidence checkpoint applied.")
    print("Changed or added files:")
    for path in changed + additions:
        print(f"  {path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except UpdateError as exc:
        print(f"Extended checkpoint refused: {exc}", file=sys.stderr)
        raise SystemExit(2)
