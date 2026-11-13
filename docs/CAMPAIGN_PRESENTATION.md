# Campaign presentation — CX-029

CX-029 is the completed campaign graphics milestone. Menu, map, Home and every tactical
entry share an earth-and-gold theme and authored fallback visuals. Contested
strategic opposition remains separate follow-up work. Campaign rules, authored
content, save format/fingerprint, tactical commands and Python oracle are unchanged.

The map draws the six-province adjacency graph beneath landmarks. Owner text and
shields identify allegiance; HERE and a separate ring identify the army. Buttons
retain guarded model queries and ordinary keyboard focus, while their hit regions
stay independent of image bounds. Home has a separate services view; its portrait
roster rows are inspectable, casualties remain visible, and service availability
and costs still come from the campaign. Save stays an explicit map action.

The tactical dossier uses the native 140-pixel panel's portrait and four value
cells. Stat, action and effect frames use separate inspected border crops. The
full panel is never stretched under unrelated controls. Full meanings remain in
text, including Tangled Bowstring and Stamina Drain. Feedback, events and overflow
remain scrollable. Mapped figures and shadows retain the existing cell transform,
side facing and pointer routing. Missing artwork uses authored scenery, landmarks,
shields, portraits, figures and ground shadows.

## Private selection workflow

Use an external ignored asset directory or the existing ignored local root.
Original images, DATs, extracted archives, generated indexes/mappings, inspection
sheets and captures must stay outside tracked source and the public package.

With the inspected `visual-index.json` and its underlying exports in that root:

```bash
export EGO_ASSET_INDEX=/path/to/private/visual-index.json
export EGO_ASSET_MAPPING=/path/to/private/cx029-mapping.json
python3 tools/map_campaign_art.py --index "$EGO_ASSET_INDEX" \
  --output "$EGO_ASSET_MAPPING"
```

`--merge OLD_MAPPING` preserves unrelated version-1/2 bindings while installing
the selected slots. No new mapping format is introduced. Canonical-content and
explicit instance bindings retain priority. Campaign opponents are assigned the
explicit `campaign_guard` presentation role by their entry point; its unit,
shadow and portrait images occupy named `ui` slots. No display-name or attempt-ID
parsing is used. Roles are view-owned and never enter a model or checkpoint.

To prepare an export source, add `--bundle NEW_DIRECTORY_BESIDE_INDEX`.
The existing strict packager validates and writes canonical `index.json` and
`mapping.json`, plus only the exact referenced images. Point the existing private
release builder's `--asset-root` at that new directory. The default packager
interface and public exclusions are unchanged. Real release export still requires
a clean committed revision and appropriate Godot export templates.

## Review and captures

The supplied private root contains `CX-029-review.md`: every exact asset ID,
slot, native dimension, crop, rejected alternative and source-inspection aid.
This private note is the selection record for this review, not a tracked asset
manifest or an original-game compatibility observation.

On a host with a working Godot rendering display:

```bash
python3 tools/capture_campaign_review.py \
  --asset-root "$(dirname "$EGO_ASSET_INDEX")"
```

The tool archives the frozen base temporarily without creating a checkout or
changing VCS state. It captures before/local, before/fallback, after/local,
after/fallback and after/partial. Each mode covers menu, map, Home and selected
battle at 960×540, 1152×648 and 1440×810. Files, logs and
`capture-results.json` go under the private root's `captures/`. Before means the
CX-029 frozen base, since release 0.2 predates Home and the strategic map. Source
comparison against aa0de56 confirmed that the Slice-3 battlefield renderer and
version-2 visual boundary remain the basis for restored tactical coverage.

All five host capture modes passed, and the interactive WSL playthrough
confirmed the campaign flow. Windows exported-build and DPI verification
remain separate platform checks. Use the CX-028 service route in
`DEMO_RELEASE.md` to repeat the interactive review.


## CX-030 interaction handoff

CX-030 adds menu panorama motion, landmark/service feedback, authored audio
and ordered battle playback. See [the interaction review](CX030_INTERACTION.md)
for host acceptance and the normal-WSL recording command. Playback timings are
native tuning values.
