# CX-034 printable playthrough

Print this file independently of the test log. Native Project EGO rules; the
CX-033 Eador recording supplies UI references, not these numerical mechanics.
Review date/name: ____________________   Result: ____________________

Launch from a normal WSL shell with a working display:

```bash
cd /home/dantimson/ego-cx-034
export GODOT_BIN="$HOME/.local/opt/godot-4.3/Godot_v4.3-stable_linux.x86_64"
"$GODOT_BIN" --path . --audio-driver Dummy game/campaign/province_main.tscn
```

The menu route is **Strategic Campaign → Campaign → Province exploration &
heroes**. Choose **Six provinces**, then **New**. Use pointer or Tab/Shift-Tab
and Enter/Space. The right rail and the settlement/hero pages scroll with focus.
Select a province to inspect it; **Travel** is a separate action. Explore and
Inspect discovered site target the selected army's current location.

When defending, press **Defend province**. Crimson acts automatically. Select
an Azure figure, then click an enemy for melee; select Melee if another action
is active. Finish each living Azure participant's action as needed, then press
**Apply result**. On an attacking site or Keep, use **Fight** first. The retained
battle uses the ordinary tactical controls. Do not concede in route A.

## A. Discover, invest, lead, save and win

- [ ] Opening: Home is visible, Ford/Quarry are Frontier, farther land is
      Unexplored space. Unknown cards disclose no terrain, income or defenders.
- [ ] Round 1: select `azure-first`, inspect Ford, Travel, End Turn.
- [ ] Round 2: Explore. Ford reaches 50%; Crystal seam and Old ruin appear.
      Travel is now unavailable. End Turn.
- [ ] Round 3: Inspect discovered site, Withdraw. Position, life and movement
      remain unchanged. Inspect again, Fight, win with Vanguard, Apply.
      The site becomes cleared and pays 12g/4c once; Ford stays Azure.
- [ ] Still round 3: inspect Ford, **Settlement districts → Crystal farm →
      Build** (6g/1c). End Turn. The construction-round payout excludes the farm.
- [ ] Round 4: **Hero and army → Hire Warden** at Ford (8g/2c), then **Assign
      selected army**. Move Warden to the first slot. End Turn. Defend Ford
      against the Raider, win and Apply. Warden earns level 2.
- [ ] Round 5: inspect Ford; **Hero and army → Buy Steel blade** (4g/1c), then
      **Equip Steel blade**. Check base attack 16, effective attack 23, level 2.
      Save. Start New, then Resume contested with Six provinces selected.
      Check the equipped blade, formation, hero life, cleared ruin and treasury.
      End Turn; compare the same payout with the uninterrupted route.
- [ ] Round 6: at Ford, **Settlement districts → Local mustering yard → Build**
      (8g/1c). End Turn.
- [ ] Round 7: Recruit Village Guard at Ford (6g/1c). Verify the local garrison
      gained the troop while the hero-led army kept its two ordered slots.
      Travel `azure-first` to Home. End Turn.
- [ ] Round 8: Explore at Home. End Turn; defend Home against the other Raider,
      win and Apply. Equipment and XP must not heal existing wounds.
- [ ] Round 9: Inspect Home's site, Fight, win and Apply. Check Warden level 3,
      effective attack 26, and **88g/22c**. Save/Resume again if desired.
- [ ] End Turn. Round 10: Travel to Ford, End Turn. Round 11: Travel to
      Watchpost, End Turn. Round 12: Travel to Keep, Fight its Capital Guard.
      Negotiation is absent for a rival faction's defense. In battle verify
      Warden occupies the first slot and has attack 26. Win and Apply.
- [ ] Victory: **round 12, 133g/34c**. No unfinished-round payout. Save/Resume
      the terminal map; site rewards and casualties must remain unchanged.

## B. Negotiate and inspect the revenue effect

- [ ] New Six provinces run. In round 1 inspect Quarry and Travel. Its defended
      frontier opens a decision panel. Negotiate costs exactly **5g/1c** and
      is unavailable with zero crystals. Inspecting and refusing spends nothing.
- [ ] Withdraw: army remains at Home with movement. End Turn: **15g/1c**.
- [ ] Round 2: Travel to Quarry, Negotiate. Check **10g/0c**, Azure control,
      army at Quarry with zero movement, stability 70 and effective income 3g.
      End Turn: **16g/1c**; stability remains 70 in the capture round.
- [ ] Round 3: Explore Quarry, End Turn. The seam and ruin are discovered;
      resource payout uses the current owner's discovery only.
- [ ] Round 4: Inspect site and Negotiate for **3g/1c**. The site becomes
      negotiated; there is no battle reward or XP. End Turn, defend if prompted,
      and Apply. The site cannot pay or negotiate again after Save/Resume.
- [ ] The focused checkpoint/rules tests additionally cover stale quotes after
      position/control/funds change, both insufficient currencies, guard wounds
      after a loss, hero casualties, facility ownership and recapture recovery.

## C. Minimum-size and regression review

- [ ] Resize to 960×540. Map, faction End Turn, army picker, garrison transfers,
      settlement catalogue, hero equipment and encounter decisions stay reachable.
- [ ] Repeat an inspection and an encounter choice by pointer and by keyboard.
      In unknown/remembered provinces, check the visibility labels and redaction.
- [ ] With fallback artwork, inspect the six captures generated by the command
      in `CX034_PROVINCE_CAMPAIGN.md`; repeat with local art if configured.
- [ ] Choose Coast graph, New. Home/objective/army IDs change without UI edits.
      Travel `coast-company` to Salt Flats and Explore on the next round.
- [ ] Check the accepted CX-033 routes in `CX033_CONTESTED_CAMPAIGN.md` and
      CX-032 routes in `CX032_HOME_CASTLE.md`. Their modes and save slots retain
      their earlier rules. Province mode uses `user://province_campaign.json`.
