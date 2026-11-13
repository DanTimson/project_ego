# CX-033 contested strategic engine — executor review handoff

State: **DONE**, against `58bf19f849b5fbd0c0277fd5336de1312e04a87e`.
Semantic owner/reviewer: Daniel Timson. The clean host check and interactive
defensive playthrough passed before closeout.
This is Project EGO native strategic design under CX-033, without Genesis/NH
strategic, AI, economy or original-save compatibility claims. Python is unchanged
under `PYTHON_ORACLE: NOT_REQUIRED` / DELIB-0008.

## Changed paths

- Content: `content/campaign/contested_campaign.gd`.
- Core: `core/campaign/contested_campaign.gd`, `contested_validation.gd`,
  `strategic_policy.gd`, `campaign_encounter.gd`, and `core/battle/ai/policy.gd`.
- Presentation/persistence: `game/campaign/contested_main.gd`, `contested_main.tscn`,
  `contested_map.gd`, `checkpoint_store.gd`, `strategic_battle.gd`, `strategic_main.gd`.
- Tests: `tests/test_contested_campaign.gd`, `test_contested_checkpoint.gd`,
  `test_contested_rules.gd`, `test_contested_presentation.gd`.
- Review tooling: `tools/capture_contested_review.gd`.
- Documentation: this handoff, `docs/ARCHITECTURE.md`, `STATUS.md`,
  `OPEN_QUESTIONS.md`, `FORMULAS.md`, `CODEX_WORK_QUEUE.md`, and
  `docs/codex/tasks/CX-033.md`.

## Model and balance decisions

`ContestedCampaign` is a separate injected, headless command authority beside
`StrategicCampaign`. The native campaign, its v1/v2 loader, slot and direct routes
remain available. `content/campaign/contested_campaign.gd` supplies a six-province
campaign and an independently authored five-province coast campaign. Neither core
rules nor the contested graph renderer contains province-ID routes or scripts.

A faction has a stable ID, Home reference, treasury and paid-service ledger. A
province has one owner (empty means neutral) and its own buildings. An army has a
stable ID, faction, position, formation round and remaining edge budget. A living
unit has its own ID, definition ID, faction, container, position, current life and
per-round movement flag. Casualties live in a separate collection and keep their
identity and definition. Army/unit locations must agree; checkpoint reconstruction
rejects disagreements rather than repairing them. UI inspection and selection are
presentation state and spend nothing.

The authored caps are two armies per faction, two living troops per army and two
per garrison. Four distinct deployment cells per side support every legal combined
defense; content with insufficient, overlapping or out-of-bounds deployment fails
before play. Deployment is stable unit-ID order, including both the defending
field army and garrison. Definitions and current life reach both tactical sides
through `CampaignRoster` validation and `CampaignEncounter.open_contest`.

Opening Azure has Vanguard (20 life, 30 attack) in `azure-first`, plus a Home Guard
(20 life, 18 attack) in the Home garrison. Crimson has two independent Raiders
(8 life, 3 attack), at Watchpost and Mill, and a Capital Guard (10 life, 3 attack)
at Keep. These are explicit contested campaign tuning. The six CX-032 buildings,
prices, prerequisites and recruit definitions are reused unchanged. Opening gold
is 12/0, round limit 12, recovery 8g/+6 life. The deliberately weak opening raiders
make both defensive play and rebuilding after losing the Vanguard viable. No
combat formula, existing native definition or old campaign balance was changed.

One edge per army per player round applies to travel and capture. Paid services
run at the faction's own controlled Home, independently of UI army selection;
recruitment feeds its garrison and targeted recovery accepts only wounded friendly
living troops there. One service per faction round is paid from current gold.
Transfers and formation are free. An emptied army disbands. Formation starts at
zero movement even with fresh troops. Troop movement flags survive transfers, and
receiving a spent troop also closes the receiving army's budget. Neither container
changes, UI selection nor disbanding can refresh travel or life.

## Exact phase and battle ordering

1. Player round N: services and each army's edge may be used in any legal order.
   New facilities record N. A service does not advance the round or pay income.
2. End Turn closes player commands and starts rival factions in sorted faction-ID
   order. Each rival chooses from the live board again after each action. The
   command counter increments **before** a battle opens, including a suspended
   defense. The authored bound is eight strategic commands per faction.
3. Rival player-facing attacks suspend the phase with its cursor and command count
   intact. Defend opens the actual retained tactical session. Azure stays side 0;
   the real attacker flag gives side 1 tie initiative for defense. The existing
   Crimson policy performs the initial attacking phase before Azure input.
4. Collect validates the completed detached session and every participant before
   publishing life/casualties, disbands, movement and control together. Exact bridge
   identity rejects old/retried results. Resume continues from the suspended cursor
   once, without replaying that attack or paying interim income.
5. After all rival phases, each faction receives its currently owned province
   income once, in sorted faction order. Only facilities built **before** N add
   income to this payout. Market built in round 1 first contributes to round 2's
   payout. Map cards show the actual upcoming payout separately from later
   effective income. Increment completed rounds once.
6. Check terminal state, then start N+1 and refresh all army budgets and troop
   movement flags. The service ledger's current-round marker now permits another
   paid service. Exhaustion after the last payout is defeat. Capturing the objective
   during the last playable player round wins immediately, before exhaustion.

Capturing an undefended hostile/neutral province spends the edge immediately.
Opening a defended player attack spends no edge yet. Abandon/retry changes only
attempt identity and trace; life, ownership, budgets, gold and round are preserved.
Retry uses fresh tactical IDs and the same deterministic round seed.

On attacker victory, its surviving army enters the captured province with spent
movement. Defeated defenders become casualties and empty armies disband. On a
defender victory, the defending army and garrison survivors retain their original
containers and province; any attacking survivors return to the origin with spent
movement. A draw leaves control unchanged. A completed tactical loss normally has
no living losing-side troops. Defense concession deliberately kills **all**
defending participants, preserves attackers' opening life and captures the province;
it resumes the rival phase and offers no cancel/retry. The loss of a field army
is survivable. Loss of Azure's Home immediately ends the run, even with another
Azure army alive. Buildings stay on their province through capture.

The rival policy first chooses legal travel: enemy/neutral weights 30/20, enemy
Home bonus 50, friendly progress weight 10, hold threshold 0. Ties use army then
province IDs. Friendly progress uses graph distance to visible nonfriendly land.
When travel is exhausted it reinforces a stationed army, forms from an available
garrison, invests in a legal income facility (sorted catalogue IDs), recovers,
or recruits, through the same query/execute guards. These are generic policy
choices, without lanes, turn events or province-ID branches. Choosing policy
commands consumes no tactical RNG. Encounter seed is authored seed plus completed
rounds, through Scenario's existing native seed boundary. NPC/NPC contests issue
real commands using the existing tactical policy with explicit side selection;
its old callers still default to Crimson. Automatic NPC combat has a 256-command
halt bound and never invents a winner.

## Checkpoint boundary

The distinct slot is `user://contested_campaign.json`; native still uses
`user://strategic_campaign.json`. Version 3 has explicit `mode: contested`, content
ID, observed full-definition SHA-256 and detached state. It saves map boundaries,
including inspectable terminal maps, and rejects pending tactical/rival resolution.
No tactical session, RNG state or UI selection is serialized.

Validation checks graph/Home/objective references, reciprocal connected edges,
opening ownership and identities, actual definitions, roster/field caps, living
and casualty identity coverage, locations, counters, per-troop and army budgets,
formation-round budgets, service chronology, building prerequisites, recruit
unlocks and payments, conservative treasury ceilings and terminal consistency.
JSON whole numbers are normalized before typed validation; fractions fail. A load
constructs a separate replacement and swaps only on success. The existing atomic
write/flush/verify/rename store is reused; failed publication preserves the prior
slot. Native and contested checkpoints cannot cross-load. Both graph definitions
have different fingerprints and deliberately share the contested slot: choose
the matching graph before Resume. New never overwrites a checkpoint.

## Exact interactive WSL routes

Run from a normal WSL shell with a working display, outside the executor sandbox:

```bash
cd /home/dantimson/ego-cx-033
export GODOT_BIN="$HOME/.local/opt/godot-4.3/Godot_v4.3-stable_linux.x86_64"
"$GODOT_BIN" --path . --audio-driver Dummy
```

Choose **Strategic Campaign → Campaign → Contested factions & armies**. The
contested scene starts a new six-province run without writing a save. It can also
be launched with `"$GODOT_BIN" --path . game/campaign/contested_main.tscn`.
Controls use pointer or Tab/Shift-Tab and Enter/Space. The right panel scrolls and
follows keyboard focus. Province buttons inspect; the army picker selects an army;
**Travel** is a separate guarded command. In the services dropdown choose a
building/recruit and press **Buy selected service**. Garrison checkboxes choose
formation members. Per-troop buttons station or withdraw that particular troop.
The last rival feedback lines remain visible in the side panel; the footer tooltip
contains more trace lines.

### Route A: build, recruit, form, station, defend, conquer

| Step | Exact action | Expected strategic result |
|---|---|---|
| Round 1 | At Home buy **Build Market • 8g**. | 4g, round 1, no income yet; next Home payout 3g, later effective 5g. |
| Round 1 | Select `azure-first`, inspect Ford, press Travel, then End Turn. | Azure captures undefended Ford; rival Raider attacks it. Save disabled. |
| Ford defense | Press Defend province. Crimson attacks automatically. Select Vanguard at offset cell (0,0), then melee Raider at (1,0). Apply defense result. | Vanguard 16/20; Raider casualty. Remaining rival moves to Quarry and forms `formed-1` at Keep. Round 2, Azure 11g. |
| Round 2 | Inspect Home. Buy **Recruit Home Guard • 10g**. | 1g; `recruited-1` joins Home garrison. |
| Round 2 | Check both `azure-guard` and `recruited-1`, Form army. Press **Station in garrison** for `azure-guard`. | Azure's second army `formed-2` contains `recruited-1`, has zero moves; Home garrison retains `azure-guard`. This uses a real station transfer. |
| Round 2 | Select `azure-first`, inspect Watchpost and Travel; press End Turn. | Watchpost captured. Crimson attacks Home first. |
| Home defense | Defend. Crimson attacks the original Home Guard. Select that guard at (0,0), melee Raider at (1,0), Apply. | Guard survives 17/20 in the garrison; `recruited-1` survives 20/20 in its army. Another defense prompt appears at Watchpost. |
| Watchpost defense | Defend. Select Vanguard (0,0), melee Capital Guard (1,0), Apply. | Vanguard 13/20. Capital Guard casualty. Crimson builds its Market at Keep. Round 3, Azure 15g, both Azure armies refreshed. |
| Round 3 | Select `formed-2`, inspect Quarry, Travel. Then select `azure-first`, inspect Keep, Travel. | Reclaim Quarry and capture now-undefended Keep. Victory in round 3, 15g; no unfinished-round payout. Keep's Market stays there. |

Each defensive win uses ordinary tactical melee and automated Crimson commands.
The Capital Guard chose a legal sortie, making the final capital capture
undefended. No province event or fabricated battle result produces this route.
Automated evidence is `test_contested_campaign.gd`; the presentation test exercises
actual keyboard/pointer formation, defense and saves at 960×540.

### Route B: lose Ford, save/resume, defend twice, reclaim

1. New six-province run; do **not** build. Travel `azure-first` to Ford and End Turn.
   At the Ford defense prompt press **Concede province and defenders**. Ford becomes
   Crimson; Vanguard becomes a casualty and `azure-first` disbands. Home Guard
   remains 20/20. Round 2, Azure 15g; the run stays active.
2. Save, start New (which leaves the slot untouched), then Resume contested with
   **Six provinces** selected. Check Ford's Crimson control, absent first army,
   persistent casualty and Home garrison. Inspection costs no action.
3. Inspect Home, check `azure-guard`, Form army (`formed-1`, zero moves), End Turn.
   Defend Home against the Ford Raider: after its automatic attack, select Guard
   (0,0), melee Raider (1,0), Apply. Defend again against the Quarry patrol in the
   same way and Apply. Guard survives both at **14/20** in `formed-1` at Home.
   Round 3, Azure **18g**. Crimson's original Raiders are casualties; its Capital
   Guard has formed another army at Keep.
4. Select `formed-1`, inspect Ford, Travel. Ford returns to Azure, Guard stays
   14/20, its budget becomes zero, gold stays 18, round stays 3, Vanguard remains
   a casualty. Save/Resume again to inspect these values. A fresh next-command
   replay is compared with uninterrupted execution in the model/checkpoint tests.

This route is a real defensive concession plus wins, rather than a cancelled
rival turn. There is no checkpoint while either Home defense is pending.

### Alternate graph and existing entry checks

Choose **Coast graph**, then New. Select `coast-company`, inspect Salt Flats,
Travel and End Turn. Defend Salt Flats: after the automatic Raider attack, select
Vanguard (0,0), melee Raider (1,0), Apply. The surviving Vanguard has 16/20 life;
the rival forms its Port guard into a field army. Round 2, Azure 17g. Inspect Port, Travel. In the attacking encounter
select Vanguard (0,0), melee Capital Guard (1,0), Apply. Port is Azure; victory
in round 2 with 17g. The graph has five provinces, a direct Salt–Port edge,
different Home/objective IDs and different opening armies, without engine edits.

Return to **Native campaign** and follow the accepted CX-032 Market/recovery/Home
Guard and Range/Archer routes in `CX032_HOME_CASTLE.md`. They still finish at
turns 8/7 and 70/53g; direct native routes finish at turn 3 and 51g. Main Menu →
Campaign Demo still runs Ford/Watchpost, and Play Demo still enters standalone
Azure versus automated Crimson. The full standalone suite exercises these entries,
the native v1/v2 checkpoint migration and retry behavior.

## Validation and host-only checks together

The executor ran native Godot 4.3. All **48** standalone scripts passed; one further
script has the expected missing-local-pack skip, zero failures. The four contested
scripts cover both graphs, full defense capacity, faction/army limits, transfer,
formation/disband, service ordering and catalogue effects, two-sided persistence,
actual wins/losses/concessions, stale/unfinished/halted outcomes, multi-action rival
suspension, a three-faction NPC battle, deterministic resume, capital loss and
last-round victory/exhaustion. The four new test scripts emit no engine errors or leak warnings.
Existing scripts retain their previously observed ObjectDB shutdown warnings.

| Gate | Executor result |
|---|---|
| Clean `python3 tools/run_godot_tests.py` | Attempted; editor socket creation is sandbox-blocked (`_sock == -1`, `ERR_CANT_CREATE`). Gate stops before standalone execution. No parser/compiler errors. |
| Executor standalone fallback | Reported 48 passed and one expected skip. The independent clean run below supersedes this count. |
| `python3 -m pytest -q` | 356 passed, 9 skipped, 4 subtests passed; one inherited pytest warning. |
| `python3 oracle/test_fixtures_current.py` | All 14 fixtures match. |
| Oracle scope against frozen base and CX-033 | PASS, 23 modules / one task declaration. |
| Deliberations / repository hygiene | PASS, eight deliberation packages; original-content checks pass. |
| gdlint on all touched/new GDScript | PASS, zero findings. |
| `git diff --check` | PASS. |
| Rendered minimum-size capture | Attempted; X11 and Wayland unavailable before scene startup. No screenshots claimed. |

The complete normal-WSL portable gate set, followed by fallback rendering capture:

```bash
cd /home/dantimson/ego-cx-033
export GODOT_BIN="$HOME/.local/opt/godot-4.3/Godot_v4.3-stable_linux.x86_64"
python3 tools/run_godot_tests.py
python3 -m pytest -q
python3 oracle/test_fixtures_current.py
python3 tools/check_oracle_scope.py --base 58bf19f849b5fbd0c0277fd5336de1312e04a87e --task docs/codex/tasks/CX-033.md
python3 tools/check_deliberations.py
python3 oracle/test_repository_hygiene.py
gdlint core/battle/ai/policy.gd core/campaign/campaign_encounter.gd core/campaign/contested_campaign.gd core/campaign/contested_validation.gd core/campaign/strategic_policy.gd content/campaign/contested_campaign.gd game/campaign/checkpoint_store.gd game/campaign/strategic_battle.gd game/campaign/strategic_main.gd game/campaign/contested_main.gd game/campaign/contested_map.gd tests/test_contested_campaign.gd tests/test_contested_checkpoint.gd tests/test_contested_rules.gd tests/test_contested_presentation.gd tools/capture_contested_review.gd
git diff --check
mkdir -p /tmp/cx033-review
EGO_ASSET_INDEX=/tmp/cx033-review/absent-index.json "$GODOT_BIN" --path . --audio-driver Dummy --script tools/capture_contested_review.gd -- /tmp/cx033-review
```

The capture command runs real commands in an isolated scene and never accesses a
checkpoint. It should produce five 960×540 PNGs with `error=0`: opening,
defense-prompt, interactive-defense, second-army-and-garrison and coast-graph.
Omit `EGO_ASSET_INDEX` to inspect locally configured optional map art too. Keep
private-art captures outside tracked content. Review the PNGs and the interactive
routes above on the host. Exported Windows DPI and packaged release checks remain
the existing release gate; this unstaged executor task creates no release artifact.


## Continuation closeout

After the usage-limit interruption, the executor re-read the task and inspected
all tracked/untracked changes and saved validation logs. The implementation was
preserved. The final casualty identity display passes the resumed presentation
check. The executor reported passing standalone scripts. Route checks covered
the coast route's 17g/16-life finish and a second save/resume after reclaiming Ford with its Guard's 14 life
and spent movement budget intact. The clean runner was reattempted and remains
blocked solely at editor socket creation, without parser/compiler findings.
Scope, deliberations, hygiene, lint and diff checks were rerun successfully.
No staged changes or VCS integration actions were introduced.

## Independent review follow-up

The submitted patch reproduced the host's 47 passes, one skip and one failure.
The one-army test reduced the shared per-faction cap while leaving two opening
Crimson armies. The validator rejected the fixture before its formation check.
The test now asserts that rejection, creates a legal one-army opening, moves
Azure's army out of Home and verifies the refusal to form another there.
The correction changes only test setup and review documentation.

The clean WSL suite passed after the fixture correction (48 passed, one
expected skip). The Ford defense input fix lets battlefield clicks pass
through the contested scene root and extends pointer selection to unit
sprites above their hexes. Daniel verified the interactive fix. Independent
review reproduced the reported Godot viewport error on the Contested button
inside the campaign popup. Deferring scene changes from that popup keeps its
viewport attached through input dispatch. The automated dialog and defense
pointer tests pass on Godot 4.3.

## Province and settlement reference

Observations from Daniel's 75-second capture of a fresh Eador game.
Timecodes are approximate. The visible UI establishes interactions and
field labels. Exact rules and numerical behavior need separate evidence.

| Time | Observed | Implication for Project EGO |
|---|---|---|
| 00:05–00:08 | Map shows irregular revealed terrain against unexplored space. Province card includes region, terrain, exploration percentage, income, resource discovery and local population/status. | Make province discovery, economy and local state visible on the map. The current province card can only show values the model represents. |
| 00:10–00:19 | Castle art remains visible beside a district-organized grid. Building details show cost, availability, a description, and recruit/building unlocks. | Group the existing catalogue visually by district and show cost and unlocks alongside the settlement when that interface is revisited. |
| 00:20–00:34 | Hero recruitment and a two-pane hero/army view show equipment and organized troop slots. | Hero recruitment, equipment and formation are distinct mechanics. Existing army/garrison transfers can support a richer roster view. |
| 00:44–00:50 | Illustrated encounter panel identifies the opposition and offers attack, retreat and negotiation before tactical entry. | Represent encounter choices before opening battle where the model supports them. Negotiation needs its own rules. |

The local DAT index has candidate frames `Interface:39LowPanel`,
`Interface:40InfoBar`, `Interface:90BuildScreen`, `Interface:03HeroScreen`
and `Interface:58HeroRecr`, plus district and facility imagery in
`Castle`. Inspect the actual frames and compare them with the recording
before choosing crops or assigning semantics. Keep the recording and original
assets outside tracked source.
