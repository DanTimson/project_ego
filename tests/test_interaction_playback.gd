extends SceneTree

var failures := 0

func check(ok: bool, label: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _initialize() -> void:
	_run.call_deferred()

func fighter(id: String, at: Array, flags: Array = []) -> Dictionary:
	return {"id": id, "name": id, "at": at, "attack": 8, "counter_attack": 6,
		"defence": 0, "life": 90, "stamina": 20, "stamina_base": 20,
		"morale": 10, "speed": 5, "flags": flags}

func spec(flags: Array = [], evasive := false) -> Dictionary:
	return {"name": "playback", "seed": 123, "profile": "genesis",
		"death_replacement_load_mode": "permissive",
		"battlefield": {"width": 4, "height": 3, "tiles": []},
		"sides": [{"id": 0, "is_attacker": true, "leader_initiative": 1,
			"units": [fighter("a", [0, 0], ["Ловкость"] if evasive else [])]},
			{"id": 1, "leader_initiative": 0, "units": [fighter("b", [1, 0], flags)]}],
		"commands": []}

func run_case(flags: Array, evasive: bool, speed: String) -> Dictionary:
	var battle := Scenario.new(spec(flags, evasive))
	var session := ManualBattleSession.new(battle)
	session.begin()
	var result := session.issue_command({"op": "attack", "unit": "a", "target": "b"})
	check(result.accepted, "melee accepted")
	var impacts: Array = []
	var impact_life: Array = []
	for observation in result.observations:
		if observation.kind == BattleObservation.Kind.IMPACT:
			impacts.append(observation.source)
			impact_life.append(observation.state.units[observation.target].life)
	check(impacts == (["a"] if evasive else ["b", "a"] if not flags.is_empty()
		else ["a", "b"]), "authoritative strike order and suppressed counter")
	check(impact_life.all(func(life: int) -> bool: return life == 90),
		"impact observations preserve pre-hit life for each actual recipient")
	var playback := BattlePlayback.new()
	root.add_child(playback)
	playback.speed = speed
	var beats: Array[BattleObservation] = []
	beats.assign(result.observations)
	playback.start(beats)
	while playback.busy:
		playback._process(10)
	var crimson := CrimsonPolicy.run_phase(session) if session.active_side_id() == 1 else {}
	var response_beats: Array[BattleObservation] = []
	for response in crimson.get("results", []):
		response_beats.append_array(response.get("observations", []))
	playback.start(response_beats)
	while playback.busy:
		playback._process(10)
	var outcome := {"state": battle.final_state(), "rng": battle.rng.snapshot(),
		"log": battle.log.duplicate(), "beats": playback.history.duplicate(),
		"commands": crimson.get("commands", [])}
	playback.free()
	return outcome

func test_prevented_primary() -> void:
	var configuration := spec(["Первый удар"])
	configuration.sides[0].units[0].life = 1
	configuration.sides[1].units[0].counter_attack = 100
	var battle := Scenario.new(configuration)
	var session := ManualBattleSession.new(battle)
	session.begin()
	var result := session.issue_command({"op": "attack", "unit": "a", "target": "b"})
	var sources: Array = []
	for observation in result.observations:
		if observation.kind == BattleObservation.Kind.IMPACT:
			sources.append(observation.source)
	check(sources == ["b"], "lethal first strike has no prevented primary impact")


func campaign_attack(screen: Control, member: String, speed: String) -> Dictionary:
	var battle: TacticalController = screen.battle
	battle.playback.speed = speed
	battle.select_unit(battle.encounter._mapping[member].instance_id)
	var result := battle.dispatch_melee(battle._unit_at(Vector2i(1, 0)).instance_id)
	while battle.playback.busy:
		battle.playback._process(10)
	return {"events": result.events, "rng": battle.scenario.rng.calls.duplicate(true)}


func campaign_route(speed: String) -> Dictionary:
	var screen := load("res://game/campaign/strategic_main.tscn").instantiate() as Control
	root.add_child(screen)
	screen.store.path = "user://cx030-route-" + speed + ".json"
	screen.new_campaign()
	var initial: Dictionary = screen.campaign.snapshot()
	screen.travel("ford")
	screen.battle.playback.speed = speed
	screen.battle.select_unit(screen.battle.encounter._mapping["azure-scout"].instance_id)
	screen.battle.dispatch_melee(screen.battle._unit_at(Vector2i(1, 0)).instance_id)
	check(screen.battle.restart_battle(), "retry interrupts playback: " + speed)
	var retried: Dictionary = screen.campaign.snapshot()
	# Retry allocates a fresh encounter serial under the existing CX-028 contract.
	initial.erase("battle_serial")
	retried.erase("battle_serial")
	check(retried == initial, "retry preserves roster, economy and map: " + speed)
	var history: Array = []
	history.append(campaign_attack(screen, "azure-scout", speed))
	history.append(campaign_attack(screen, "azure-vanguard", speed))
	check(screen.return_from_battle(true).ok, "Ford captured: " + speed)
	var checkpoint: Dictionary = screen.campaign.checkpoint().data
	check(screen.save_checkpoint().ok, "save map checkpoint: " + speed)
	screen.new_campaign()
	check(screen.resume_checkpoint().ok and screen.campaign.checkpoint().data == checkpoint,
		"checkpoint survives New/Resume: " + speed)
	screen.travel("home")
	check(screen.recover().ok and screen.recruit().ok, "Home services: " + speed)
	check(not screen.row_feedback.is_empty(), "service marks the roster row")
	screen.travel("ford")
	for province in ["watchpost", "keep"]:
		screen.travel(province)
		history.append(campaign_attack(screen, "azure-vanguard", speed))
		check(screen.return_from_battle(true).ok, "capture " + province + ": " + speed)
	var outcome := {"checkpoint": screen.campaign.checkpoint().data, "history": history}
	check(screen.campaign.snapshot().status == "victory", "campaign victory: " + speed)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(screen.store.path))
	screen.free()
	return outcome


func _run() -> void:
	test_prevented_primary()
	var route := campaign_route("Instant")
	for speed in ["Normal", "Fast"]:
		check(campaign_route(speed) == route,
			"campaign checkpoint, command events and RNG match: " + speed)
	for data in [[[], false], [["Первый удар"], false], [[], true]]:
		var baseline := run_case(data[0], data[1], "Instant")
		for speed in ["Normal", "Fast"]:
			check(run_case(data[0], data[1], speed) == baseline,
				"same command order, state, RNG and beats: " + speed)
	var panorama := PresentationLandscape.new()
	root.add_child(panorama)
	panorama.set_process(false)
	panorama.size = Vector2(960, 540)
	panorama.advance_pan(1, 900)
	check(panorama.pan_offset > 0.5, "right reveals artwork farther right")
	var offset := panorama.pan_offset
	panorama.advance_pan(1, 480)
	check(panorama.pan_offset == offset, "center stops drift")
	panorama.advance_pan(1, 0)
	check(panorama.pan_offset < offset, "left reveals artwork farther left")
	panorama.advance_pan(1000, 960)
	check(panorama.pan_offset == 1, "pan clamps to artwork bounds")
	panorama.free()
	var packed := load("res://game/tactical/tactical_vs_crimson.tscn") as PackedScene
	var controller := packed.instantiate() as TacticalController
	root.add_child(controller)
	controller.playback.speed = "Normal"
	var result := controller.pass_side()
	check(result.accepted and controller.playback.busy, "Crimson queues visible beats")
	var snapshot := controller.scenario.final_state()
	var rng: Variant = controller.scenario.rng.calls.duplicate(true)
	check(not controller.pass_side().accepted, "repeat input refused during playback")
	controller.sound.last_cue = ""
	controller.playback.skip()
	check(controller.sound.last_cue.is_empty(), "skip emits no queued audio cues")
	check(controller.scenario.final_state() == snapshot
		and controller.scenario.rng.calls == rng,
		"skip never resolves again")
	controller.pass_side()
	controller.restart_battle()
	check(not controller.playback.busy and controller.battlefield_view.visual_state.is_empty(),
		"restart cancels stale presentation")
	controller.sound.player.stop()
	controller.sound.muted = true
	controller.sound.cue("impact")
	check(not controller.sound.player.playing, "muted cue produces no playback")
	controller.playback.speed = "Normal"
	controller.pass_side()
	controller.queue_free()
	await process_frame
	check(not is_instance_valid(controller), "scene exit discards queued work")
	quit(0 if failures == 0 else 1)
