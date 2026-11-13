# CX-032 Home castle review

State: DONE. Daniel Timson confirmed the corrected manual check. This is native Project EGO campaign tuning, with no
Genesis/New Horizons construction, economy or save-format parity claim.
The starting army, map, guards and twelve-turn limit use the frozen-base values. The Archer costs 12g; no tactical or baseline tuning was
needed to make its route playable.

## Delivered behavior

The injected catalogue owns each building's price, prerequisite list and bounded
income/recovery/recruit effect. Loading rejects absent/cyclic prerequisites and
invalid effect/unlock references. Catalogue previews and commands share the model
gate. All builds and recruits spend from the pre-income treasury and use one turn.
Construction credits current owned income once **before** activating its benefit.
Market and Workshop each add 2g to Home income; Granary adds two life to the
existing paid survivor recovery. Barracks, Range and Guard Tower unlock Spearman,
Home Archer and Veteran Guard. Home Guard stays independently available at 10g.

Home opens a separate two-column scrolling construction catalogue. Cost,
prerequisites, effect, status and model refusal are readable on every card.
Inspect stays focusable when Build disables; successful construction returns
focus to Inspect. The right rail retains recovery, all four recruits, their
unlocks and the roster. Footer Map/Home controls remain reachable. The map and
Home province card both show effective Home income. Built facilities appear in
the settlement with optional local sprites or authored buildings and labels.

Version 2 persists ordered `{id, turn}` construction records, recruit turn bounds,
and each roster member's actual definition. Validation rejects duplicate and
unknown facilities, missing/out-of-order prerequisites, overlapping or impossible
action turns, bad counters/identities/types, and recruitment preceding its unlock.
The conservative gold ceiling adds each income bonus only for turns **after** its
recorded build and subtracts known build/recruit costs. Map-only atomic publication
uses the existing store unchanged.

Version-1 content comes from the exact shared `baseline_v1()` constructor. Only
its matching fingerprint and original fully validated schema are accepted. Resume
restores wounds, casualties and Home Guards, adds no buildings and writes nothing.
Since v1 did not record recruit turns, upgrade assigns earliest conservative
bounds `1..N` for its always-available Guards; these are bounds, not observed
historical recruitment dates. The next explicit Save writes v2. A frozen-code
fixture at `tests/fixtures/campaign/cx032_v1_home_guard.json` was generated from
unmodified revision `34641e7d5dda67b3e8f4735be8cf1e2abaf4fc6e`: attack Ford
with Scout then Vanguard, apply, return Home, recruit Home Guard, checkpoint.
Its authored fingerprint is
`7b648ef86df82d427f38951d4ed7c6a5f5bcb584a3669ad9cfce2fdfb127743a`.

## Private reference inspection

Inspected the supplied private visual index and Castle sprites for all six
facilities, plus construction panels, selectors/masks, Castle framing and
Build/Castle button states in Interface/Buttons. There are 233 Castle images and
no InnerBld namespace in this index. The exact selected keys, dimensions,
contact sheets and optional `cx032-mapping.json` remain in the private asset root.
Original settlement placement coordinates are OPEN; the renderer uses authored
positions and never infers rules from art names. Provincial OutBld/OutBuild
improvements are not used for Home facilities.

No readable Genesis/NH building tables were found in the supplied private root,
the project's Genesis/NH pack directories (metadata only), the local extraction
repositories, or the searched Games/Steam installation roots. No original
prerequisites, costs, effects or profile/version can therefore be asserted from
this inspection. The authored six-building catalogue is the rule source.
Effects requiring shops, equipment, spells, resources, garrisons, province
improvements or strategic opponents remain outside this milestone. No original
files, extracted data, private mapping or images are added to the repository.

## Exact manual economy route

Launch `godot --path .`, choose **Strategic Campaign**, then **Campaign → New
Campaign**. At 960×540 use Tab/Shift-Tab, Enter/Space and the right-rail scrollbar;
Home → Castle construction may require scrolling down the rail. Map provinces
are inspected first; use the right-hand Travel/Battle button to commit travel.
In battle, coordinates below are model cells: Vanguard starts upper left `(0,0)`,
Scout one cell down/right `(1,1)`, enemy `(1,0)`. Click the friendly unit then the
enemy. Use **Apply result** after Azure wins. Do not End Phase for these fights.

| Step | Exact action | Turn | Gold |
|---|---|---:|---:|
| 0 | New Campaign | 0 | 12 |
| 1 | Home → Castle construction → Market → Build | 1 | 7 |
| 2 | Map → Ford → Battle. Scout attacks enemy first (Scout dies), then Vanguard attacks. Apply result. | 2 | 16 |
| 3 | Map → Home → Travel | 3 | 25 |
| 4 | Home → Recover +6 (8g) | 4 | 26 |
| 5 | Recruit Home Guard (10g) | 5 | 25 |
| 6 | Map → Ford → Travel | 6 | 34 |
| 7 | Watchpost → Battle. Vanguard attacks enemy. Apply result. | 7 | 48 |
| 8 | Keep → Battle. Vanguard attacks enemy. Apply result. | 8 | 70 |

Immediately after step 1, Home income is +5g and Guard purchase is refused before
income. After step 2 Vanguard is 14/20 and Scout is a casualty. Optional Campaign
→ Save, New, Resume restores that exact state, including Market; it uses no turn.
Step 4 heals Vanguard to 20/20 and keeps Scout dead. Victory keeps the final map
inspectable. Home Guard is deployed in the later battles.

For the visual review after step 3, open construction: Market is Built, Workshop
and Granary are Available, Guard Tower is Locked with “Requires Barracks.” Inspect
with keyboard and pointer; focus the last Range card to scroll, return to settlement
to see Market, then Map. Clicking a locked Inspect control spends no turn.

## Exact manual Archer route

Start a separate New Campaign. Preserve the checkpoint unless you explicitly Save.
Use the same click/Apply pattern; keep Scout out of the opening fight.

| Step | Exact action | Turn | Gold |
|---|---|---:|---:|
| 0 | New Campaign | 0 | 12 |
| 1 | Home → Castle construction → Archery Range → Build | 1 | 5 |
| 2 | Map → Quarry → Battle. Vanguard attacks enemy. Apply result. | 2 | 12 |
| 3 | Map → Home → Travel | 3 | 19 |
| 4 | Home → Recruit Home Archer (12g) | 4 | 14 |
| 5 | Map → Quarry → Travel | 5 | 21 |
| 6 | Mill → Battle. Select Archer at `(0,1)`, move one hex back to `(0,2)`, press **R** (or Ranged), and click enemy `(1,0)`. Apply result. | 6 | 33 |
| 7 | Keep → Battle. Select Vanguard `(0,0)`, attack enemy `(1,0)`. Apply result. | 7 | 53 |

After Range construction Archer is unlocked but unaffordable; the opening 5g
cannot borrow income. The Mill shot is accepted, reduces enemy life **8 → 0**,
and spends ammo **3 → 2**. The Archer's actual tactical stats are 12 life,
4 melee, 12 ranged, range 4, three ammo. Saving/resuming after recruitment preserves
its definition. Abandon/retry before the shot preserves buildings, treasury,
turn and roster and gives fresh encounter IDs. Both routes above are covered by
real-command automated playthroughs, not forced victory flags.

## Validation and host review

The clean `python3 tools/run_godot_tests.py` gate was attempted with writable
XDG directories. Editor import reaches class/resource discovery but the sandbox
blocks socket creation (`_sock == -1`, `ERR_CANT_CREATE`); it reports compile=FAIL
and runs no scripts. No parser/compiler errors remain. The runner's discovery,
timeout and failure-marker helpers were then used to run every standalone script:
**44 pass, one expected missing-pack skip, zero failures**. This includes both old
direct routes, short demo, standalone/hot-seat, the new real-command castle routes,
v1/v2 checkpoints, and minimum-window pointer/keyboard/focus/scroll checks.

Other gates: **pytest 356 passed, 9 skipped, 4 subtests**, one inherited warning;
all 14 oracle fixtures match; oracle scope, eight deliberations, repository hygiene,
touched-file GDScript lint and `git diff --check` pass. Existing standalone tests
emit some inherited ObjectDB leak warnings; no new persistent model leak or failing
script is accepted. The castle milestone uses native campaign orchestration.
The ranged-target follow-up updates the existing O2 scenario harness.

A rendered capture was attempted in local, fallback and partial-art modes. All
three are blocked before scene startup because X11 `:0` and Wayland cannot be
opened in the sandbox. Thus rendered inspection and one interactive WSL
playthrough remain reviewer checks; headless geometry is not a visual acceptance
claim. The host command below runs the normal clean gate and the prepared capture
in one invocation, without staging, committing or writing the player's save:

```bash
cd /home/dantimson/ego-cx-032
python3 tools/run_godot_tests.py && \
python3 tools/capture_castle_review.py \
  --asset-root /home/dantimson/project_ego/.local/eador-art-review.TxEjLB \
  --mapping-name cx032-mapping.json
```

`GODOT_BIN` must name the native Godot 4.3 executable (already set in this WSL
environment). Capture writes fifteen 960×540 images and logs under the private
root's `captures-cx032/`: Home opening, opening catalogue, mixed built/available/
locked catalogue, last-card scroll and built settlement, in each of three art
modes. Inspect the fallback images at minimum size and run either manual route
above. Exact private mapping is optional presentation; absent individual layers
fall back independently. Review the complete diff before accepting the task.

## Independent review follow-up

The normal-WSL clean suite passed (44 scripts, one expected skip), and the
capture runner reported PASS in local, fallback and partial-art modes.
Independent review checked the frozen v1 fingerprint, v2 history validation,
pre-income affordability and construction's post-income activation. Castle
cards now follow the authored catalogue order. Settlement slots are assigned
from the full catalogue so a new facility does not displace a built one.
Returning from construction restores focus to its Home entry. The Archer's
12g price is native tuning. Daniel confirmed the WSL playthrough and deferred
further castle UI polish.

## Ranged target correction

The Mill guard starts one axial hex from the Archer, even though both
coordinate components differ. Ordinary ranged shots now refuse that target.
Other enemies in range remain valid while the shooter has an adjacent enemy,
subject to the existing capability restrictions. The corrected route steps
back one hex before shooting and reaches the same campaign result.

The clean Godot suite passed after the ranged correction (44 passed, one
expected skip). The Python scenario suite and all 14 fixture checks passed.
Pytest was unavailable in the independent review environment. Daniel
confirmed the corrected manual check.
