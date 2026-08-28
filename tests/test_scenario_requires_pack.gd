extends SceneTree

## Requires-pack tier. Fresh clones skip cleanly.
## Run: godot --headless --script tests/test_scenario_requires_pack.gd

func _init() -> void:
	var pack_dir := "res://packs/genesis"
	if not FileAccess.file_exists(pack_dir.path_join("data/unit.json")):
		print("SKIP requires-pack: packs/genesis/data is absent; generate it with "
			+ "python3 tools/extract/build_pack.py <path-to>/var genesis")
		quit(0)
		return
	var registry := AbilityRegistry.new()
	Handlers.register_all(registry)
	var db := ContentDb.load_pack("genesis", pack_dir, registry, {
		"unit": "unit.json", "unit_upg": "unit_upg.json",
		"ability_num": "ability_num.json",
	}, "genesis")
	var provenance := db.content_provenance()
	if db.content_compatibility() != {
			"identity": "genesis", "source": "legacy_profile"}:
		push_error("requires-pack loader did not inherit Genesis compatibility")
		quit(1)
		return
	if provenance.get("pack") != "genesis" \
			or not String(provenance.get("fingerprint", "")).begins_with("sha256:"):
		push_error("requires-pack provider did not report deterministic Genesis provenance")
		quit(1)
		return

	# Prefer a record without abilities so an intentionally empty committed
	# bindings skeleton does not turn this dependency/provenance tier into a bulk
	# handler-coverage test.
	var selected_id := ""
	for key in db.pack.tables.get("unit", {}):
		var record: Dictionary = db.pack.tables["unit"][key]
		var display := String(record.get("Name", ""))
		if display in ["", "Пусто"] or not (record.get("Abilityes", []) as Array).is_empty():
			continue
		selected_id = ContentId.make("genesis", "unit", int(key))
		break
	if selected_id == "":
		push_error("requires-pack: no complete no-ability unit definition found")
		quit(1)
		return

	var spec := {
		"name": "requires-pack dependency probe", "profile": "native", "seed": 1,
		"content": provenance,
		"battlefield": {"width": 3, "height": 3, "tiles": []},
		"sides": [
			{"id": 0, "is_attacker": true, "units": [
				{"id": "local-1", "def": selected_id, "at": [0, 0], "overrides": {}}]},
			{"id": 1, "units": [{
				"id": "portable-target", "name": "Portable target", "at": [2, 0],
				"life": 10, "stamina": 10, "morale": 10, "speed": 1,
			}]},
		],
		"commands": [],
	}
	var built := Scenario.new(spec, null, db)
	if built.construction_error != "" or not built.units.has("local-1"):
		push_error("requires-pack scenario construction failed: %s" % built.construction_error)
		quit(1)
		return
	var unit: Combatant = built.units["local-1"]
	if unit.content_id != selected_id or unit.instance_id != "local-1":
		push_error("requires-pack identity separation failed")
		quit(1)
		return
	print("PASS requires-pack dependency discovery and provenance: %s" % selected_id)
	quit(0)
