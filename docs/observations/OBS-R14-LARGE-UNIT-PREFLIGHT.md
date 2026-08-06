# OBS-R14 — large-unit tactical footprint

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
