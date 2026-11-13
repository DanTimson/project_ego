# CX-030 interaction brief

Draft for the audiovisual milestone after CX-029. Timecodes refer to the
uploaded recordings, beginning at 00:00 in each file. Capture samples give
approximate times. They do not establish the engine's original timings.

## Reference observations

| Source and time | Observed | Project EGO requirement |
|---|---|---|
| Menu 00:02–00:08 | Panorama and centered title emerge above the fixed red-and-gold lower frame. Narrow parchment choices are stacked in the center of that lower area. | Recompose the title and choices around a moving upper viewport and fixed lower controls. Use Project EGO branding and its existing actions. Make the frame continuous across supported sizes. |
| Menu 00:08–00:22 | The visible island crop changes while frame, title, and controls stay fixed. The user confirms that scrolling follows the direction of the cursor offset from center. | Right of center advances the view right through the panorama, revealing artwork farther right; left advances left. Center stops motion. Clamp to available artwork and keep hitboxes stationary. Exact dead zone, speed, smoothing and vertical behavior are tuning choices. |
| Gameplay 00:12–00:40 | Terrain fills the scene, the active unit and landmarks sit in the landscape, and the framed information pane, bottom resource bar and dialogs remain visually distinct. | Compose around the terrain, one current-position marker, compact gold and turn readouts, and a contextual roster or province pane. Preserve the six-province graph. Keep labels and legal destinations readable without relying on color. |
| Gameplay around 00:44–00:46 | A book-like chooser overlays the field, and the selected item exposes a contextual description. | Use progressive disclosure for action and modifier descriptions. Keep current values in one place and make effects discoverable by pointer and keyboard. |
| Gameplay around 00:55 and 01:00–01:01 | Bright effects appear over affected hexes in distinct short bursts and then clear. The battlefield remains legible around them. | Bind effects to model-reported targets. Stage onset, impact and decay so the originating action and affected tiles are clear. Use a reduced-motion alternative. |

The longer gameplay recording has a silent audio track. The supplemental
combat clip (2026-11-13 04-29-06) has audible-level audio, but the clip does not
yet establish individual cue identities or their timing relative to actions.

### Supplemental combat clip

| Approximate clip time | Observed | CX-030 implication |
|---|---|---|
| 00:06–00:08 | A bright green effect stays anchored beside the shield-bearing figure, briefly clears, and reappears. Sprites and unit bars remain visible. | Keep effects localized and allow successive effect beats. Keep the affected unit and its bar legible. |
| 00:18–00:21 | The spellbook description gives way to a narrow targeting instruction in the right panel. The field remains visible. | Keep targeting instructions and cancellation within the HUD. Use this as a pattern for actions the current engine supports. |
| 00:25–00:27 | The shield-bearing figure ends up adjacent to a pale unit. The visible selection and effect change, but the clip does not resolve a clean pair of ordinary melee impacts. | Treat adjacency, approach and a resolved exchange as distinct. Require an ordinary melee exchange with retaliation in the Project EGO acceptance recording. |

Use configurable native defaults for wind-up, impact, reaction and the gap
before retaliation. Playback must follow the authoritative result ordering,
including first strike before the primary hit and no counter cue when the
result contains no counter. Do not derive combat steps from the reference
effect color, infer a hit from adjacency, or add spells or wider targeting
rules to match the footage.

## Implementation scope

- **Menu and controls.** Add the pointer-driven panorama, static chrome, and
  compact framed choices. Use normal, hover, pressed and disabled artwork
  when verified for the control, with a visible independent keyboard focus.
  Supply authored states where the local pack is missing or incomplete.
- **Map and Home.** Improve map composition and the feedback for selection,
  travel, capture, recovery and recruitment. Keep decisions and ownership
  authoritative in the existing model. Remove repeated HUD values, reduce
  color-key fringes and use panel cuts that respect the original borders.
- **Battle.** Stage movement, attack, impact, retaliation, resource and
  modifier feedback, and defeat in the order produced by accepted commands.
  Show Crimson actions in the same readable sequence. Use typed command
  results and state transitions. Add a narrowly scoped presentation payload
  if the existing results cannot distinguish the steps. Include Normal, Fast
  and Instant playback with one authoritative combat path. Define input and
  interruption behavior during playback so retry, abandon or scene exit
  cannot replay or double-apply a command.
- **Audio.** Inventory and audition candidate local cues before mapping them.
  Give selection, confirm, refusal, movement, impact and capture distinct
  authored fallback cues with mute and volume controls. Keep original audio
  local and treat any audio packaging changes as a separate explicit check.
  Verify sound onset against the displayed action using rendered clips.

## Acceptance

Deliver one review with short local and fallback recordings that demonstrate
the menu moving in both directions and stopping at center, map selection and
capture, Home service feedback, and a complete combat exchange with a response
from Crimson. Include a separate deterministic combat comparison across
playback speeds. Compare command ordering, final state and RNG consumption.
Verify keyboard focus, missing or partial artwork, muted audio, repeat input,
scene changes and existing campaign checkpoint compatibility. Use the host
capture path that worked for CX-029, with an actual audio capture path for
sound checks. Leave the contested campaign outside this milestone.
