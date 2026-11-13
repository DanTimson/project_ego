# CX-034 province campaign handoff

State: DONE. Reviewer/semantic owner: Daniel Timson. Frozen base:
`feb0b71484428b3cf3c887e1e04165d9c18ded9d`.
Runtime behavior changes only for definitions with `province_rules`, apart from
repairing the existing strategic tactical-policy fallback to issue `end_phase`
instead of unsupported `pass`. Existing CX-032/033 routes and save formats remain
regression gates. No original strategic compatibility or binary constant is claimed.

## Implementation and authored defaults

`ContestedCampaign.create` selects the province extension for an authored option.
The same production command/query, rival cursor, CampaignEncounter and tactical
UI serve the six-province and independently authored coast graphs. Province IDs
and narrative content stay in content definitions. No Python mirror is required
under the task's NOT_REQUIRED declaration and DELIB-0008.

| Area | Native CX-034 behavior |
|---|---|
| Knowledge | Each faction starts with its owned settlements revealed and their adjacent nodes as frontier. Successful arrival reveals the destination and frontier links. Current visibility follows control or a present army; remembered observations persist on departure/loss. Unknown/frontier views contain no terrain, money, guard or discovery data. Player UI and rival policy use the same `faction_view`. Omniscient snapshots remain internal to rules/checkpoint verification. |
| Movement | One army/troop budget shared by Travel, Explore and resolved encounters. Explore adds 50%, capped at 100; both authored discoveries trigger at 50. Refused complete exploration costs nothing. Formation, transfer, leader assignment and ordering never refresh spent movement. |
| Economy | Named integer gold/crystal balances, one ledger mutation path for payments, rewards and payouts. Discoveries are per faction; only the current owner's discovery contributes. Construction income activates when `build_round < payout_round`; discovery starts at the next eligible end-round. Pay after all rival defenses, using post-rival control and current stability, then recover stability. |
| Stability | Starting tier/stability are content fields. Capture subtracts 30 from the surviving value, stamps the capture round, and never resets stability. A full owned round restores 10 after payout. Gold and crystals each truncate after multiplying by 50%, 75% or 100% at thresholds 0, 50 and 80. Recapture restarts the wait and subtracts again. |
| Settlements | Capital districts retain the existing catalogue/chains. Woodland villages have Crystal farm (6g/1c, +3g/+1c) and a dependent Local mustering yard (8g/1c), unlocking Village Guard (6g/1c). Local prerequisites, terrain eligibility and garrison capacity apply. Facilities remain attached to captured provinces. Builds, recruitment, healing, hires and equipment share one faction service per round. |
| Heroes | Warden and Ranger have separate persistent identities and authored faction-specific canonical definitions. A hero occupies one ordinary deployment slot. One leader per army; unassigned heroes stay at owned settlements and participate in defense. Death persists; troops surviving a leader continue unled. Captured unassigned heroes become casualties. No command resurrects a hero identity. |
| Progress/equipment | Surviving victorious heroes gain 5 XP. Levels begin at 0/5/15 XP; each earned level adds 3 melee attack. Steel blade adds 4 attack in hand; Mail adds 2 defence in body. Each purchased item belongs to one hero, with a compatible slot; unequip before replacing. Ordinary tactical definition composition occurs when opening an encounter. Level/equipment operations preserve current life. |
| Sites | Guard arrays are distinct from province garrisons. Inspect opens a decision; Fight opens CampaignEncounter with persistent guard life and ordered army deployment. Withdraw/abandon preserves map life, rewards and budgets while attempts remain monotonic. A completed result applies once; losses preserve guard deaths/wounds; wins pay 12g/4c once. Site battles do not transfer province control. |
| Negotiation | Native deterministic tribute: site 3g/1c resolves access without reward/XP; eligible neutral garrison 5g/1c yields control, with capture stability. Both spend one move and pay once. Quotes bind position, unit/province state and funds; stale or unaffordable decisions refuse atomically. Rival-owned tactical defense remains intact. |
| Rivals | Stable weighted choice among legal site, explore, travel and construction commands, with the existing bound. New encounters use the same decision/tribute/battle path; hidden economic fields cannot alter opening policy choices. Real defenses suspend/resume the same round cursor. |

These are **Project EGO authored defaults**. The **STATED observations** in the
CX-033 province/settlement reference establish visible fields, district organization,
hero/equipment panes and encounter choices. They establish no values in this table.
The local DAT candidates were inspected: LowPanel 1024×106, InfoBar 312×470,
BuildScreen/HeroRecr 512×768 and HeroScreen 1024×768. Their fixed-size borders and
key-color backgrounds need explicit crop/mapping work. This patch uses the existing
private map resolver and native terrain/landmark fallbacks; no media or private
mapping is tracked.

## Checkpoint contract

Province mode uses its own `user://province_campaign.json`, version 4, mode
`province`, content ID and complete definition fingerprint. V1/v2 native and v3
contested save handling is unchanged. Save is restricted to the quiescent player
map, including terminal maps; open decisions, site battles and rival resolution
block it. New never overwrites the slot. The existing atomic disk publication
path is reused.

The checkpoint stores detached state and a bounded journal of accepted strategic
commands plus completed battle inputs. Loading creates a separate model, replays
all transitions through the production guards, and requires exact state/journal
agreement before publication. This verifies knowledge thresholds, balances and
payout timing, control/resource consistency, all guard life/definitions, one-time
outcomes, unique heroes/equipment, casualties, deployment capacity and formation
as one coupled state. Failed loads do not mutate the live model. Temporary tactical
objects, RNG/status state and unfinished battles are not serialized; completed
input transcripts reconstruct historical outcomes. Limits are 2,000 journal events,
2,048 commands per completed encounter, 32,000 tactical inputs total and
8 million characters in compact JSON. The same bounds apply before publication
and replay. An over-bound save leaves the prior slot intact.

The exact integrated routes and a checklist intended for separate printing are in
[CX034_PLAYTHROUGH.md](CX034_PLAYTHROUGH.md). Route A reaches victory in round 12
with 133g/34c, a level-3 equipped Warden, village construction and local recruitment.
Route B exercises neutral and site negotiation and subsequent revenue. Focused
fixtures additionally author capture/loss, guard loss and hero death situations;
these are native tests, not claimed observations of Genesis/NH.

## Exact host commands

Run outside the executor sandbox in a normal WSL shell. The clean gate performs
its own clean import. Keep optional private artwork and screenshots outside source.

```bash
cd /home/dantimson/ego-cx-034
export GODOT_BIN="$HOME/.local/opt/godot-4.3/Godot_v4.3-stable_linux.x86_64"
python3 tools/run_godot_tests.py
python3 -m pytest -q
python3 oracle/test_fixtures_current.py
python3 tools/check_oracle_scope.py --base feb0b71484428b3cf3c887e1e04165d9c18ded9d --task docs/codex/tasks/CX-034.md
python3 tools/check_deliberations.py
python3 oracle/test_repository_hygiene.py
gdlint core/battle/manual_battle_session.gd core/campaign/contested_campaign.gd core/campaign/strategic_policy.gd core/campaign/province_campaign.gd core/campaign/province_validation.gd core/campaign/province_checkpoint.gd content/campaign/province_campaign.gd game/campaign/contested_main.gd game/campaign/strategic_main.gd game/campaign/strategic_battle.gd game/campaign/province_main.gd game/campaign/exploration_map.gd tests/province_test_support.gd tests/test_province_campaign.gd tests/test_province_rules.gd tests/test_province_checkpoint.gd tests/test_province_presentation.gd tools/capture_province_review.gd
git diff --check
"$GODOT_BIN" --path . --audio-driver Dummy game/campaign/province_main.tscn
mkdir -p /tmp/cx034-review
EGO_ASSET_INDEX=/tmp/cx034-review/absent-index.json "$GODOT_BIN" --path . --audio-driver Dummy --script tools/capture_province_review.gd -- /tmp/cx034-review
```

The capture command executes a real route without touching a save slot and emits
six 960×540 PNGs: unknown/frontier, discoveries, encounter choices, site combat,
hero/equipment/formation and provincial districts. Inspect them on the host. Omit
the `EGO_ASSET_INDEX` override to repeat using locally configured assets. In headless
mode the capture driver checks its route and explicitly skips images.

Print the independent checklist, without test logs:

```bash
cat docs/CX034_PLAYTHROUGH.md
# If a WSL print queue is configured:
lp docs/CX034_PLAYTHROUGH.md
```

## Executor validation

Validation results are recorded below after the final gate run. The sandbox has
no usable X11/Wayland display and cannot create the editor's listening sockets.
These environment failures occur before rendered capture/clean-gate completion;
no rendered screenshots or successful clean editor gate are claimed. Standalone
headless runs use writable `XDG_DATA_HOME=/tmp/cx034-data` and
`XDG_CONFIG_HOME=/tmp/cx034-config` so Godot can write its logs.

| Gate | Executor result |
|---|---|
| Clean `tools/run_godot_tests.py` | Attempted twice with Godot 4.3; blocked at editor socket creation (`_sock == -1`, `ERR_CANT_CREATE`), before standalone execution. No parser/compiler findings. |
| Standalone scripts, same discovery/timeout/error-marker runner without editor import | 52 PASS, one expected missing-local-pack SKIP, zero failures. Includes all four new province scripts and the unchanged CX-032/033 routes/save tests. |
| `python3 -m pytest -q` | 356 passed, 9 skipped, 4 subtests passed; one inherited pytest return-value warning. |
| `python3 oracle/test_fixtures_current.py` | All 14 curated fixtures match. |
| Oracle scope, frozen base plus CX-034 task | PASS: 23 modules, one task declaration. |
| Deliberations / repository hygiene | PASS: eight packages; original-data/media restrictions pass. |
| gdlint, every touched/new GDScript | PASS: zero findings; no inherited-debt exception needed. |
| `git diff --check` / staged diff | PASS / empty staged diff. |
| Six-view capture driver, headless route check | PASS, `errors=0`; all six images explicitly skipped in headless mode. |
| Rendered capture at 960×540 | Attempted; blocked before scene startup by unavailable X11/Wayland display. Host image inspection remains required. |

The four new standalone scripts check the integrated round-12 victory, both
negotiation outcomes and currencies, threshold edges and optional resource/site
content, hidden-state-independent rival choices, transfers, repeated discovery,
loss/recapture/rediscovery, paid facility ownership, persistent site guard wounds,
abandon/retry/stale outcomes, hero death with surviving troops, unassigned hero
capture, slot/owner restrictions, two-pane keyboard input, actual tactical hero
stats and deployment, on-disk resume, next-transition identity and forged saves.

The exact sandbox standalone fallback used the existing runner's discovery,
timeouts and error detection, with no changes to the clean gate:

```bash
mkdir -p /tmp/cx034-data /tmp/cx034-config
XDG_DATA_HOME=/tmp/cx034-data XDG_CONFIG_HOME=/tmp/cx034-config EGO_ASSET_INDEX=/tmp/cx034-absent.json python3 - <<'PY'
from tools import run_godot_tests as r
scripts, _ = r.discover_standalone_scripts(r.REPOSITORY_ROOT)
counts = [0, 0, 0]
for script in scripts:
    result = r.run_process(
        [r.locate_godot(), '--headless', '--path', str(r.REPOSITORY_ROOT), '--script', str(script)],
        r.TEST_TIMEOUT_SECONDS,
    )
    reasons = r.failure_reasons(result)
    state = 'FAIL' if reasons else 'SKIP' if r.is_requires_pack_skip(script, result.stdout, result.stderr) else 'PASS'
    counts[['PASS', 'SKIP', 'FAIL'].index(state)] += 1
    print(state, script.name, ','.join(reasons), flush=True)
    if reasons:
        r.print_process_output(result)
print('STANDALONE pass=%d skip=%d fail=%d' % tuple(counts))
raise SystemExit(bool(counts[2]))
PY
```

Godot logs and executor output are temporary `/tmp/cx034-*.log` artifacts. The
printable checklist is maintained separately and does not require those logs.
The submitted patch passed the clean WSL suite with 52 passes and one expected
skip. Daniel reported a successful manual playthrough.

## File inventory for complete-diff review

| Files | Purpose |
|---|---|
| `content/campaign/province_campaign.gd` | Two authored province-enabled definitions and catalogues. |
| `core/campaign/province_campaign.gd` | Opt-in strategic commands, projections, services, encounters, progression, payouts and replay journal. |
| `core/campaign/province_validation.gd` | Authored content constraints, canonical hero definition uniqueness and thresholds. |
| `core/campaign/province_checkpoint.gd` | Detached v4 reconstruction and coupled-state validation. |
| `core/campaign/contested_campaign.gd` | Opt-in factory/load selection and tactical definition-composition hook. |
| `core/campaign/strategic_policy.gd` | Opt-in rival policy routing and supported tactical phase fallback. |
| `core/battle/manual_battle_session.gd` | Detached history of accepted tactical inputs. |
| `game/campaign/province_main.gd`, `game/campaign/province_main.tscn` | Integrated province, districts, hero/army and encounter screens; separate save slot. |
| `game/campaign/exploration_map.gd` | Faction-facing fog, frontier, remembered map and terrain/landmark fallbacks. |
| `game/campaign/contested_main.gd` | Reusable authored-definition selection hook; previous scene defaults retained. |
| `game/campaign/strategic_main.gd` | Menu entry. |
| `game/campaign/strategic_battle.gd` | Site/decision-aware retry through the same commands. |
| `tests/province_test_support.gd` | Shared real-command checks and tactical playthrough helpers. |
| `tests/test_province_campaign.gd` | Integrated construction/hire/equipment/recruitment/XP/save/victory route. |
| `tests/test_province_rules.gd` | Knowledge, movement, negotiation, loss, capture/rediscovery and malformed-input cases. |
| `tests/test_province_checkpoint.gd` | Hero casualties, gear, coupled corruption refusal, disk roundtrip and recapture clock. |
| `tests/test_province_presentation.gd` | Minimum-size pointer/keyboard discovery, decisions, battle, populated hero panes and resume. |
| `tools/capture_province_review.gd` | Six-view host capture with headless route fallback. |
| `docs/CX034_PROVINCE_CAMPAIGN.md`, `docs/CX034_PLAYTHROUGH.md` | Review handoff, exact commands and independent printable checklist. |
| `docs/FORMULAS.md`, `docs/STATUS.md` | Explicit native accounting/progression and implementation status. |
| `docs/CODEX_WORK_QUEUE.md`, `docs/codex/tasks/CX-034.md` | REVIEW handoff; existing task/queue edits preserved. |

## Independent review follow-up

The checkpoint writer originally enforced only the journal event count.
It now enforces the reader's per-battle, total transcript and compact-size
bounds before atomic publication. A regression starts from a readable slot,
attempts an oversized save and verifies the original bytes still load.
The focused checkpoint, campaign route and rule scripts passed on Godot 4.3.
The independent clean editor scan timed out; the WSL result above covers the
submitted patch.
