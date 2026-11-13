extends SceneTree

const Authored = preload("res://content/campaign/native_campaign.gd")
const LEGACY = "res://tests/fixtures/campaign/cx032_v1_home_guard.json"
var failures := 0


func check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _initialize() -> void:
	# Fixture produced by unmodified 34641e7 model + content: real Scout sacrifice,
	# Vanguard attack, apply Ford, return Home, recruit Home Guard, checkpoint().
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEGACY))
	check(JSON.stringify(Authored.baseline_v1()).sha256_text() == legacy.fingerprint,
		"shared baseline preserves authentic v1 fingerprint")
	var directory := "user://cx032-checkpoint-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(directory)
	var slot := directory.path_join("checkpoint.json")
	var file := FileAccess.open(slot, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var bytes := FileAccess.get_file_as_string(slot)
	var store := CampaignCheckpointStore.new(slot)
	var loaded := store.load_campaign(Authored.definition())
	check(loaded.ok, "authentic v1 checkpoint resumes")
	if not loaded.ok:
		quit(1)
		return
	var model: StrategicCampaign = loaded.campaign
	var state := model.snapshot()
	check(state.turn == 3 and state.gold == 23 and state.buildings.is_empty()
		and state.roster.entries["azure-vanguard"].life == 14
		and state.roster.entries["azure-scout"].life == 0
		and state.roster.entries["recruit-1"].def == "campaign:unit/3",
		"v1 restores exact position, wounds, casualty and Home Guard with zero buildings")
	check(FileAccess.get_file_as_string(slot) == bytes, "Resume does not rewrite v1 slot")
	check(store.save_campaign(model).ok, "explicit Save upgrades to v2")
	var upgraded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(slot))
	check(upgraded.version == 2 and store.load_campaign(Authored.definition()).ok,
		"published v2 upgrade passes full validation")
	var uninterrupted := StrategicCampaign.from_checkpoint(Authored.definition(), legacy)
	check(model.build("market") == uninterrupted.campaign.build("market")
		and model.checkpoint().data == uninterrupted.campaign.checkpoint().data,
		"next build after v1 upgrade equals uninterrupted legacy resume")
	for key in ["fingerprint", "content", "version"]:
		var bad := legacy.duplicate(true)
		bad[key] = "wrong"
		check(not StrategicCampaign.from_checkpoint(Authored.definition(), bad).ok,
			"reject mismatching v1 " + key)
	var bad := legacy.duplicate(true)
	bad.members[2].def = "campaign:unit/5"
	check(not StrategicCampaign.from_checkpoint(Authored.definition(), bad).ok,
		"v1 cannot contain new recruit types")
	bad = legacy.duplicate(true)
	bad.state["buildings"] = []
	check(not StrategicCampaign.from_checkpoint(Authored.definition(), bad).ok,
		"v1 rejects expanded state")
	bad = legacy.duplicate(true)
	bad.state.turn = 1
	check(not StrategicCampaign.from_checkpoint(Authored.definition(), bad).ok,
		"v1 validates original committed-action bounds")
	for source in [legacy, model.checkpoint().data]:
		for key in ["content", "fingerprint", "version", "state", "members"]:
			for value in [null, 42, "wrong", true, [], {}]:
				bad = source.duplicate(true)
				bad[key] = value
				check(not StrategicCampaign.from_checkpoint(Authored.definition(), bad).ok,
					"malformed envelope refuses %s %s" % [key, str(value)])
		for key in ["id", "def", "life"]:
			for value in [null, "wrong", true, [], {}]:
				bad = source.duplicate(true)
				bad.members[0][key] = value
				check(not StrategicCampaign.from_checkpoint(Authored.definition(), bad).ok,
					"malformed member refuses %s %s" % [key, str(value)])
	DirAccess.remove_absolute(slot)
	DirAccess.remove_absolute(directory)
	print("CASTLE CHECKPOINT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
