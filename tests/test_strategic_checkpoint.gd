extends SceneTree

const Authored = preload("res://content/campaign/native_campaign.gd")
const Store = preload("res://game/campaign/checkpoint_store.gd")
var failures := 0
var slot: String


class FailedPublish:
	extends CampaignCheckpointStore

	func _publish(_temporary: String) -> Error:
		return ERR_CANT_CREATE


func check(condition: bool, message: String) -> void:
	print("%s  %s" % ["PASS" if condition else "FAIL", message])
	if not condition:
		failures += 1


func write(data: Variant) -> void:
	var file := FileAccess.open(slot, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func invalid(data: Dictionary, message: String) -> void:
	var result := StrategicCampaign.from_checkpoint(Authored.definition(), data)
	check(not result.ok and not result.reason.is_empty(), message)


func _initialize() -> void:
	# Unique test slot: never touch the player's user://strategic_campaign.json.
	# user:// is portable on Windows too, and belongs to this test's unique directory.
	slot = "user://cx028-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(slot)
	var directory := slot
	slot = slot.path_join("checkpoint.json")
	var store := Store.new(slot)
	var model := StrategicCampaign.create(Authored.definition())
	check(not store.load_campaign(Authored.definition()).ok, "missing checkpoint readable refusal")
	var encounter: CampaignEncounter = model.travel("ford").encounter
	encounter.session.begin()
	encounter.session.issue_command(
		{
			"op": "attack",
			"unit": encounter._mapping["azure-vanguard"].instance_id,
			"target": encounter.session.living_units(1)[0].instance_id
		}
	)
	check(not store.save_campaign(model).ok, "completed but unapplied battle cannot save")
	model.finish(encounter)
	var before: Dictionary = model.checkpoint().data
	check(store.save_campaign(model).ok, "save complete map checkpoint")
	var original := FileAccess.get_file_as_string(slot)
	var resumed := store.load_campaign(Authored.definition())
	check(
		resumed.ok and resumed.campaign != model and resumed.campaign.checkpoint().data == before,
		"round trip into independent fresh model"
	)
	check(
		resumed.campaign.snapshot().roster.entries["azure-vanguard"].life == 13,
		"resume preserves wounds without healing"
	)
	model.travel("home")
	check(
		Store.new(slot).load_campaign(Authored.definition()).campaign.checkpoint().data == before,
		"restarting store reads prior slot after current run changes"
	)
	var failed := FailedPublish.new(slot)
	check(
		(
			not failed.save_campaign(model).ok
			and FileAccess.get_file_as_string(slot) == original
			and store.load_campaign(Authored.definition()).ok
		),
		"failed publication preserves complete prior valid slot"
	)
	check(not FileAccess.file_exists(slot + ".tmp"), "failed replacement temporary cleaned")
	DirAccess.make_dir_absolute(slot + ".tmp")
	check(
		not store.save_campaign(model).ok and FileAccess.get_file_as_string(slot) == original,
		"actual replacement write failure preserves previous valid slot"
	)
	DirAccess.remove_absolute(slot + ".tmp")
	check(
		(
			store.save_campaign(model).ok
			and store.load_campaign(Authored.definition()).campaign.snapshot().position == "home"
		),
		"successful replacement publishes newer complete state"
	)
	var file := FileAccess.open(slot, FileAccess.WRITE)
	file.store_string("{bad json")
	file.close()
	check(not store.load_campaign(Authored.definition()).ok, "corrupt JSON readable refusal")
	write([])
	check(not store.load_campaign(Authored.definition()).ok, "non-object checkpoint refusal")
	var data := before.duplicate(true)
	data.version = 99
	write(data)
	check(
		store.load_campaign(Authored.definition()).reason.contains("version"),
		"version mismatch reason"
	)
	data = before.duplicate(true)
	data.content = "other-campaign"
	write(data)
	check(
		store.load_campaign(Authored.definition()).reason.contains("content"),
		"content mismatch reason"
	)
	data = before.duplicate(true)
	data.fingerprint = "changed"
	invalid(data, "authored snapshot mismatch")
	for key in ["position", "owned", "status", "turn", "gold", "next_recruit", "battle_serial"]:
		data = before.duplicate(true)
		data.state[key] = null
		invalid(data, "missing or malformed " + key)
	for alteration in [
		{"position": "keep"},
		{"owned": ["home", "home"]},
		{"owned": ["home", "watchpost"]},
		{"owned": ["ford"]},
		{"turn": -1},
		{"turn": 1.5},
		{"turn": 13},
		{"gold": -1},
		{"gold": 1.1},
		{"gold": 1000001},
		{"status": "victory"},
		{"status": "unknown"},
		{"status": "active", "turn": 12},
		{"turn": 0},
		{"battle_serial": 0},
		{"next_recruit": 3},
	]:
		data = before.duplicate(true)
		data.state.merge(alteration, true)
		invalid(data, "reject impossible state " + str(alteration))
	for alteration in [
		{"id": "unknown"},
		{"id": "azure-scout"},
		{"def": "campaign:unit/3"},
		{"life": -1},
		{"life": 21},
		{"life": 1.5},
		{"life": "20"},
	]:
		data = before.duplicate(true)
		data.members[0].merge(alteration, true)
		invalid(data, "reject invalid roster " + str(alteration))
	data = before.duplicate(true)
	data.members.remove_at(0)
	invalid(data, "missing opening roster record")
	data = before.duplicate(true)
	for member in data.members:
		member.life = 0
	invalid(data, "active army with no living members")
	data.state.status = "defeat"
	data.state.battle_serial += 1
	invalid(data, "capture and battle defeat cannot occupy the same turn")
	var final_turn_content := Authored.definition()
	final_turn_content.turn_limit = 1
	data.fingerprint = JSON.stringify(final_turn_content).sha256_text()
	check(
		not StrategicCampaign.from_checkpoint(final_turn_content, data).ok,
		"turn exhaustion cannot account for an eliminated roster"
	)
	data.fingerprint = before.fingerprint
	data.state.turn = 2
	check(
		StrategicCampaign.from_checkpoint(Authored.definition(), data).ok,
		"battle defeat with a separate turn and attempt is valid"
	)
	data = before.duplicate(true)
	data.state.extra = "unknown"
	invalid(data, "unknown schema state field")
	var changed_content := Authored.definition()
	changed_content.recruit_cost += 1
	check(
		not StrategicCampaign.from_checkpoint(changed_content, before).ok,
		"same named content with changed authored balance rejected"
	)
	DirAccess.remove_absolute(slot)
	DirAccess.remove_absolute(directory)
	print("STRATEGIC CHECKPOINT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
