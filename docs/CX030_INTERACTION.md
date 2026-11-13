# CX-030 interaction review

State: DONE. Reviewer: Daniel Timson. Base: `765e080930d26cd2c9d0cde2c5915a3b5f2d312d`.

The menu keeps the title and lower choices fixed while the panorama pans toward
the pointer, stops inside its center dead zone, and clamps to its available crop.
`PresentationLandscape.pan_speed` and `dead_zone` are exported native tuning
values. Missing button art uses authored states; focus has its own border.
Map landmarks show selection, travel and capture. Home services annotate changed
roster rows. Authored group frames avoid stretching private panel crops, duplicate
dossier values are removed, and transparent texture edges receive RGB bleeding
before filtering. Status descriptions support tooltip and keyboard inspection.

`BattleObservation` is an additive, detached presentation payload. Counterattack
captures life/stamina immediately before and after each actual strike; Scenario
uses `Exchange.order`, records movement, payment, resource effects and phase
boundaries, and retains existing text traces. Playback uses these observations,
never log parsing or gameplay RNG. Zero-damage or prevented blows receive no
impact beat. Normal/Fast/Instant share authoritative execution and command order.
Normal defaults are movement .32s, strike .24s, impact .15s, resource .24s,
effect/defeat .35s and phase .28s; Fast divides durations by three. These are
native tuning values in `BattlePlayback.timings`, not legacy timing claims.
Reduced motion replaces movement interpolation and rings with stationary text.
Headless scenes default to Instant so existing synchronous UI tests retain their
contract; new tests explicitly exercise all speeds.

Commands resolve once, including bounded Crimson policy execution, before their
detached observations are presented in order. During playback, battle input is
gated, final event text and values are withheld, and unit positions/life bars use
the observation snapshots. Skip drains only observations. Restart, abandon and
scene exit discard the presentation queue. Checkpoint schema, campaign content,
combat decisions and RNG paths are unchanged. No Python oracle expansion is
required under DELIB-0008.

Six distinct authored PCM cues cover select, confirm, refusal, movement, impact
and capture. Mute and volume are shared across scenes. Instant suppresses battle
cue bursts. Original audio is neither mapped nor packaged by this patch.

## Validation in the restricted workspace

- `python3 tools/run_godot_tests.py`: attempted, including clean cache removal.
  Editor scanning is blocked by prohibited TCP listening (`_sock == -1`,
  `ERR_CANT_CREATE`); the runner correctly reports compile failure. No script
  parse/compiler errors were reported. Writable `XDG_CONFIG_HOME` and
  `XDG_DATA_HOME` under `/tmp` avoid unrelated config/log write failures.
- The same runner's discovery, process execution and error classification were
  used to execute standalone scripts after scanning: **40 passed, one expected
  missing-pack skip, zero failed**. This supplements, and does not replace, the
  host clean-runner gate. Includes both CX-028 routes, checkpoint save/resume,
  abandon/retry and victory, plus all-size local/fallback/partial presentation.
- `python3 -m pytest -q`: **356 passed, nine skipped, four subtests passed**.
- `python3 oracle/test_fixtures_current.py`: all 14 fixture families match.
- `python3 tools/check_oracle_scope.py --base 765e080930d26cd2c9d0cde2c5915a3b5f2d312d --task docs/codex/tasks/CX-030.md`,
  deliberations, repository hygiene and `git diff --check`: passed.
- `gdlint` comparison against the identical frozen-base file set: **no new
  findings** (ten inherited Scenario findings on each side). New files pass.
- Capture choreography completed a headless rehearsal. Real display/audio
  acceptance was attempted but unavailable: `xdpyinfo` cannot open `:0`, and
  `ffmpeg`/`ffprobe` are absent. No recording is claimed.

New coverage checks ordered intermediate observations, ordinary melee, first
strike, lethal first-strike prevention, suppressed retaliation, command/state/RNG
identity across speeds, the full Ford/Home/Watchpost/Keep service route with
save/resume and retry at all three speeds, Crimson, repeated input, skip, restart, scene exit,
mute, pan direction, center stop and bounds. The existing Crimson replay test
now compares the new observations by value rather than object identity.

## Host closeout

- The clean WSL runner reported `compile=PASS pass=40 skip=1 fail=0`.
- Daniel observed normal operation live in all nine local/fallback/partial size
  combinations, and the screenshots recorded correctly. The desktop recorder
  produced black video in the submitted clip.
- The Godot Movie Maker replacement produced a 35.2-second local-artwork clip
  at 1152×648 and 30 FPS. Review confirmed rendered menu panning, map and Home
  screens, ordered tactical playback through the Crimson response, and a
  non-silent game audio track with cue bursts. The remaining combinations
  were accepted from the live review without repeating their recordings.
- Follow-up fixes prevent capture cues after defeat, silence skipped playback
  cues, and reject predominantly black video or silent audio in capture checks.

## Exact normal-WSL host capture command

Prerequisites: native Godot 4.3, a working WSLg X11 display, and installed
`ffmpeg`/`ffprobe` with libx264 support.
Run from this checkout, after the clean runner passes on the host:

```bash
python3 tools/capture_interaction_review.py \
  --godot /home/dantimson/.local/opt/godot-4.3/Godot_v4.3-stable_linux.x86_64 \
  --asset-root /home/dantimson/project_ego/.local/eador-art-review.TxEjLB
```

Godot Movie Maker records viewport frames and mixed game audio at a fixed 30 FPS.
The harness checks resolution, rejects predominantly black video and silent audio,
and writes `capture-results.json`. Use `--mode local --size 1152x648` for a
single smoke recording. Local, fallback and partial modes each cover 960×540, 1152×648 and 1440×810. Each clip
shows menu right/left/center, Ford capture, Home recovery/recruitment, a complete
exchange and Crimson response. PNG layout supplements and logs accompany clips.
It never writes a checkpoint or changes VCS state. Media stays under the private
root's `captures/cx030/<mode>-<width>x<height>/interaction.mkv`. Existing static
CX-029 capture tooling remains available. Review cue onset, focus/readability and
reduced-motion behavior interactively; automated stream checks cannot approve
sound identity or visual quality.

Headless choreography rehearsal (no images or audio acceptance):

```bash
XDG_DATA_HOME=/tmp/cx030-data XDG_CONFIG_HOME=/tmp/cx030-config \
  "$GODOT_BIN" --headless --path . --script tools/capture_interaction.gd \
  -- /tmp/cx030-rehearsal --rehearse
```

## Local sound investigation

Read-only inventory of the supplied `unit_sound.dat` and `spell_sound.dat` with
`eador_dat list` identified OGG entries. Local extraction of unit sounds produced
170 assets under the private root's `cx030-sound/`; raw payloads were inspected,
not assumed playable. `S000.OGG .bin` begins with OggS and Godot's Vorbis loader
successfully decoded it with duration 0.4268027 seconds. It has not been auditioned
on an available audio device, so it has no cue assignment. This is an audition
platform gap, not an unsupported-decoder claim. Authored cues provide the public
fallback. Inventory, extracted samples and all capture/validation logs remain
private; the existing image-only private distribution closure is unchanged.
Final logs and the changed-file inventory are under the private root at
`captures/cx030/validation/validation-results.json`.

For future automated review, keep the authored tones selectable as diagnostic
cues alongside mapped sounds. Keep the real-time review clip for checking
onsets and overlaps. For quick review, shorten scripted pauses or speed up the
finished clip with pitch-preserving audio. Accelerated presentation must retain
command ordering and must leave enough rendered frames to show short beats.
Treat descriptive names and VAR references as mapping evidence and audition
the decoded sample before assigning a production cue.
