extends SceneTree

## Portable canonical-definition scenarios using project-authored synthetic data.
## Run: godot --headless --script tests/test_scenario_content.gd

const FIXTURE := "res://tests/fixtures/scenario_content_fixture.json"
var failures := 0


class CountingProvider:
	extends RefCounted
	var calls := 0

	func content_provenance() -> Dictionary:
		calls += 1
		return {"pack": "unused", "version": "unused"}

	func resolve_definition(_content_id: String) -> Variant:
		calls += 1
		return null


class MalformedProvider:
	extends RefCounted
	func content_provenance() -> Variant:
		return "not an object"

	func resolve_definition(_content_id: String) -> Variant:
		return null

	func compose_actions(_profile: String, _mode: String) -> Dictionary:
		return ActionDefinitionComposer.empty_result(_profile, _mode)


func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		(" — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1


func _provider(fx: Dictionary) -> ScenarioContentProvider:
	var p: Dictionary = fx["provider"]
	return ScenarioContentProvider.new(
		String(p["pack"]), p["definitions"], String(p["version"]),
		String(p["build"]))


func _fingerprint_pack() -> ContentPack:
	var pack := ContentPack.new("synthetic")
	pack.version = "v1"
	pack.build = "build-1"
	var binding := ContentPack.Binding.new()
	binding.opcode = 7
	binding.name = "Synthetic"
	binding.hook = "STAT_PASSIVE"
	binding.handler = &"stat_delta"
	binding.params = {"stat": "attack"}
	binding.uses = 1
	pack.bindings[7] = binding
	pack.tables = {"unit": {1: {"Name": "Before", "Attack": 1}}}
	pack.declared_fingerprint = ScenarioContentProvider.canonical_fingerprint(
		pack.snapshot_payload())
	return pack


func _error(spec: Dictionary, provider: Variant) -> String:
	return String(Scenario.prepare_content(spec, provider)["error"])


func _inline_construction_spec() -> Dictionary:
	return {
		"name": "IR-1 inline construction", "profile": "native", "seed": 1,
		"battlefield": {"width": 2, "height": 2, "tiles": []},
		"sides": [
			{"id": 0, "units": [{"id": "one", "name": "One", "at": [0, 0]}]},
			{"id": 1, "units": [{"id": "two", "name": "Two", "at": [1, 1]}]},
		],
		"commands": [],
	}


func _check_failed_construction(built: Scenario, fragment: String,
		what: String) -> void:
	_check(fragment in built.construction_error
			and built.units.is_empty()
			and built.field == null
			and built.state == null
			and built.auras_by_source.is_empty(),
		what + " fails closed without a usable partial Scenario",
		built.construction_error)


func _test_inline_construction_fail_closed() -> void:
	print("\n[IR-1] inline Scenario construction fails closed")
	var duplicate := _inline_construction_spec()
	duplicate["sides"][1]["units"][0]["id"] = "one"
	_check_failed_construction(Scenario.new(duplicate),
		"duplicate unit instance id", "duplicate inline instance ID")

	var occupied := _inline_construction_spec()
	occupied["sides"][1]["units"][0]["at"] = [0, 0]
	_check_failed_construction(Scenario.new(occupied),
		"cannot place unit", "occupied-tile placement")

	var out_of_bounds := _inline_construction_spec()
	out_of_bounds["sides"][1]["units"][0]["at"] = [4, 4]
	_check_failed_construction(Scenario.new(out_of_bounds),
		"cannot place unit", "out-of-bounds placement")

	var valid := Scenario.new(_inline_construction_spec())
	_check(valid.construction_error == "" and valid.field != null
			and valid.state != null and valid.state.sides.size() == 2
			and valid.units.size() == 2
			and valid.field.has_unit(valid.units["one"])
			and valid.field.has_unit(valid.units["two"]),
		"valid inline construction remains usable")


func _test_aura_construction_fail_closed() -> void:
	print("\n[CX-018 A] invalid aura construction fails closed")
	var invalid := _inline_construction_spec()
	invalid["sides"][0]["units"][0]["auras"] = [{
		"id": "invalid-semantic", "scope": "SELF", "affects": "ALLY",
		"modifiers": [{"handler": "stat_delta", "semantics": ["unknown.semantic"]}],
	}]
	var built := Scenario.new(invalid)
	_check_failed_construction(built, "invalid modifier in aura",
		"invalid aura semantic")
	var session := ManualBattleSession.new(built)
	var begun := session.begin()
	_check(not bool(begun["ok"]) and not session.started
			and "construction failed" in String(begun["message"]),
		"manual session refuses an aura-invalid Scenario",
		String(begun["message"]))

	var valid := _inline_construction_spec()
	valid["sides"][0]["units"][0]["auras"] = [{
		"id": "valid-aura", "scope": "SELF", "affects": "ALLY",
		"modifiers": [{"handler": "stat_delta", "power": 2,
			"params": {"stat": "attack"}}],
	}]
	var valid_built := Scenario.new(valid)
	_check(valid_built.construction_error == ""
			and valid_built.auras_by_source.has(valid_built.units["one"])
			and valid_built.auras_by_source[valid_built.units["one"]].size() == 1,
		"valid aura construction remains unchanged")


func _init() -> void:
	var file := FileAccess.open(FIXTURE, FileAccess.READ)
	if file == null:
		push_error("fixture not found: %s" % FIXTURE)
		quit(1)
		return
	# Godot 4.3 compares nested Dictionary/Array numbers by Variant type. Match
	# Python's JSON integer semantics before direct fixture equality checks.
	var fx: Dictionary = ScenarioContentProvider._canonical_json_value(
		JSON.parse_string(file.get_as_text())) as Dictionary
	file.close()
	_test_inline_construction_fail_closed()
	_test_aura_construction_fail_closed()
	var provider := _provider(fx)
	_check(provider.fingerprint == fx["provider"]["fingerprint"],
		"canonical fingerprint matches the Python oracle", provider.fingerprint)

	var ordered_a := {"z": [3, {"b": 2, "a": 1}], "a": "value"}
	var ordered_b := {"a": "value", "z": [3.0, {"a": 1.0, "b": 2.0}]}
	_check(ScenarioContentProvider.canonical_fingerprint(ordered_a)
			== ScenarioContentProvider.canonical_fingerprint(ordered_b),
		"fingerprints normalize dictionary order and integral JSON numbers")

	var changing := ScenarioContentProvider.new(
		"synthetic", {"synthetic:unit/1": {"name": "Before", "attack": 1}},
		"v1")
	var old_fingerprint := String(changing.content_provenance()["fingerprint"])
	changing._definitions["synthetic:unit/1"]["attack"] = 2
	var changed_fingerprint := String(changing.content_provenance()["fingerprint"])
	_check(changed_fingerprint != old_fingerprint,
		"changing synthetic definitions changes observed fingerprint")
	var stale_provider := ScenarioContentProvider.new(
		"synthetic", {"synthetic:unit/1": {"name": "Before", "attack": 2}},
		"v1", "", old_fingerprint)
	var stale_provenance := stale_provider.content_provenance()
	_check(stale_provenance["fingerprint"] == changed_fingerprint
			and "fingerprint assertion mismatch" in stale_provenance.get("error", ""),
		"a stale supplied fingerprint cannot authenticate changed definitions",
		String(stale_provenance.get("error", "")))

	for changed_part in ["table", "binding"]:
		var declared_pack := _fingerprint_pack()
		var declared := declared_pack.declared_fingerprint
		_check(declared_pack.provenance()["fingerprint"] == declared,
			"matching declared %s snapshot fingerprint is accepted" % changed_part)
		if changed_part == "table":
			declared_pack.tables["unit"][1]["Attack"] = 2
		else:
			(declared_pack.bindings[7] as ContentPack.Binding).uses = 2
		var changed_pack_provenance := declared_pack.provenance()
		_check(changed_pack_provenance["fingerprint"] != declared
				and "pack fingerprint assertion mismatch"
				in changed_pack_provenance.get("error", ""),
			"stale declared fingerprint cannot authenticate changed %s" % changed_part,
			String(changed_pack_provenance.get("error", "")))

	var canonical_spec: Dictionary = fx["canonical_spec"].duplicate(true)
	var canonical := Scenario.new(canonical_spec, null, provider)
	var inline := Scenario.new((fx["inline_spec"] as Dictionary).duplicate(true))
	var unit: Combatant = canonical.units["attacker-1"]
	var inline_unit: Combatant = inline.units["attacker-1"]
	_check(unit.content_id == "synthetic:unit/5", "content identity is canonical")
	_check(unit.instance_id == "attacker-1", "instance identity is scenario-owned")
	_check(unit.name == "Synthetic vanguard", "display name remains separate")
	_check(inline_unit.content_id == "", "equivalent inline unit remains pack-free")
	_check(inline_unit.instance_id == "attacker-1",
		"provider-free inline instance identity comes from id")
	_check(unit.stamina == 4 and unit.stamina_base == 4,
		"overrides precede base-value defaults")
	_check(unit.life == 15 and unit.life_base == 15
			and unit.morale == 10 and unit.morale_base == 10,
		"canonical defaults match inline defaults")
	_check(unit.flags.has(&"synthetic_flag")
			and unit.subtypes.has(&"synthetic_subtype"),
		"flags and subtypes resolve")
	_check(unit.modifiers.size() == 1
			and unit.modifiers[0].params == inline_unit.modifiers[0].params,
		"modifiers and nested parameters match inline construction")
	_check(canonical.auras_by_source[unit].size() == 1,
		"auras resolve from the canonical definition")

	var canonical_result := canonical.run()
	var inline_result := inline.run()
	_check(canonical_result["log"] == fx["expected"]["log"],
		"canonical log matches the Python fixture")
	_check(canonical_result["final"] == fx["expected"]["final"],
		"canonical final state matches the Python fixture")
	_check(canonical_result["log"] == inline_result["log"]
			and canonical_result["final"] == inline_result["final"],
		"equivalent inline and canonical scenarios are behaviorally identical")
	var unused_provider := CountingProvider.new()
	var inline_with_provider := Scenario.new(
		(fx["inline_spec"] as Dictionary).duplicate(true), null, unused_provider)
	_check(unused_provider.calls == 0 and inline_with_provider.run() == inline_result,
		"inline scenarios never consult an injected content provider")

	# Every resolution and every instance owns nested mutable values.
	var before: Dictionary = provider.resolve_definition("synthetic:unit/5")
	unit.modifiers[0].params["nested"]["order"].append(99)
	unit.set_flag(&"battle-only")
	_check(provider.resolve_definition("synthetic:unit/5") == before,
		"battle mutation cannot reach the provider definition")
	var shared_spec: Dictionary = fx["canonical_spec"].duplicate(true)
	var second: Dictionary = shared_spec["sides"][0]["units"][0].duplicate(true)
	second["id"] = "attacker-2"
	second["at"] = [0, 1]
	shared_spec["sides"][0]["units"].append(second)
	var shared := Scenario.new(shared_spec, null, provider)
	var one: Combatant = shared.units["attacker-1"]
	var two: Combatant = shared.units["attacker-2"]
	one.modifiers[0].params["nested"]["order"].append(88)
	_check(one != two and one.content_id == two.content_id
			and one.instance_id != two.instance_id and one.name == two.name,
		"two instances may share one content definition")
	_check(two.modifiers[0].params["nested"]["order"] == [2, 1],
		"shared definitions do not alias between instances")

	var missing_provider := _error(fx["canonical_spec"].duplicate(true), null)
	_check("injected content provider" in missing_provider,
		"missing provider fails clearly", missing_provider)
	var missing_definition: Dictionary = fx["canonical_spec"].duplicate(true)
	missing_definition["sides"][0]["units"][0]["def"] = "synthetic:unit/999"
	_check("was not found" in _error(missing_definition, provider),
		"missing definition fails clearly")
	var namespace_spec: Dictionary = fx["canonical_spec"].duplicate(true)
	namespace_spec["sides"][0]["units"][0]["def"] = "other:unit/5"
	_check("namespace mismatch" in _error(namespace_spec, provider),
		"pack namespace mismatch fails clearly")

	for key in ["pack", "version", "build", "fingerprint"]:
		var mismatch: Dictionary = fx["canonical_spec"].duplicate(true)
		mismatch["content"][key] = "sha256:" + "0".repeat(64) \
			if key == "fingerprint" else "wrong"
		var mismatch_error := _error(mismatch, provider)
		_check("mismatch for %s" % key in mismatch_error
				and "expected" in mismatch_error and "observed" in mismatch_error,
			"%s mismatch reports expected and observed" % key, mismatch_error)

	var malformed: Dictionary = fx["canonical_spec"].duplicate(true)
	malformed["content"] = {"pack": "synthetic"}
	_check("requires version" in _error(malformed, provider),
		"malformed provenance lacks a discriminator")
	malformed = fx["canonical_spec"].duplicate(true)
	malformed["content"]["fingerprint"] = "sha256:nope"
	_check("64 lowercase" in _error(malformed, provider),
		"malformed fingerprint is rejected")
	malformed = fx["canonical_spec"].duplicate(true)
	malformed["content"].erase("pack")
	_check("requires non-empty" in _error(malformed, provider),
		"content provenance requires a pack identity")
	malformed = fx["canonical_spec"].duplicate(true)
	malformed["content"]["timestamp"] = "today"
	_check("unknown scenario content provenance" in _error(malformed, provider),
		"undeclared provenance fields are rejected")
	_check("malformed provenance" in _error(
		fx["canonical_spec"].duplicate(true), MalformedProvider.new()),
		"malformed provider provenance is rejected")

	for identity_field in [
			"content_id", "instance_id", "__scenario_resolved_content_id"]:
		var spoofed_inline: Dictionary = fx["inline_spec"].duplicate(true)
		spoofed_inline["sides"][0]["units"][0][identity_field] = "spoofed"
		_check("inline unit" in _error(spoofed_inline, null)
				and "serialized identity field" in _error(spoofed_inline, null),
			"inline %s is rejected" % identity_field)

	var duplicate: Dictionary = fx["canonical_spec"].duplicate(true)
	var repeated: Dictionary = duplicate["sides"][0]["units"][0].duplicate(true)
	repeated["at"] = [0, 1]
	duplicate["sides"][0]["units"].append(repeated)
	_check("duplicate unit instance id" in _error(duplicate, provider),
		"duplicate canonical battle-instance identities are rejected")

	for field in ["id", "def", "at", "content_id", "instance_id", "pack"]:
		var forbidden: Dictionary = fx["canonical_spec"].duplicate(true)
		forbidden["sides"][0]["units"][0]["overrides"][field] = "hidden"
		_check("forbidden field" in _error(forbidden, provider),
			"override cannot replace %s" % field)
	var unknown: Dictionary = fx["canonical_spec"].duplicate(true)
	unknown["sides"][0]["units"][0]["overrides"]["mystery_stat"] = 9
	_check("unknown or non-settable" in _error(unknown, provider),
		"unknown override is rejected")
	var mixed: Dictionary = fx["canonical_spec"].duplicate(true)
	mixed["sides"][0]["units"][0]["attack"] = 99
	_check("mixes undeclared inline field" in _error(mixed, provider),
		"canonical sibling combat fields are not silent overrides")


	var lifecycle_inline: Dictionary = fx["inline_spec"].duplicate(true)
	var lifecycle_unit: Dictionary = lifecycle_inline["sides"][0]["units"][0]
	lifecycle_unit.merge({
		"ammo_base": 7, "tier": 3, "definition_id": 900,
		"morale_break_accumulator": 20, "damage_received": [1, 2, 3, 4],
		"original_definition": {
			"name": "original", "definition_id": 5, "tier": 2, "ammo_base": 4,
		},
		"battle_owned": true, "discarded": true,
	}, true)
	var lifecycle_built: Combatant = Scenario.new(lifecycle_inline).units["attacker-1"]
	_check(lifecycle_built.ammo_base == 7 and lifecycle_built.tier == 3
		and lifecycle_built.definition_id == 900
		and lifecycle_built.morale_break_accumulator == 20
		and lifecycle_built.damage_received == [1, 2, 3, 4]
		and lifecycle_built.original_definition["definition_id"] == 5
		and lifecycle_built.battle_owned and lifecycle_built.discarded,
		"inline synthetic lifecycle instance state remains accepted",
		str([lifecycle_built.ammo_base, lifecycle_built.tier,
			lifecycle_built.definition_id, lifecycle_built.morale_break_accumulator,
			lifecycle_built.damage_received, lifecycle_built.original_definition,
			lifecycle_built.battle_owned, lifecycle_built.discarded]))

	var runtime_values := {
		"morale_break_accumulator": 10,
		"damage_received": [1, 0, 0, 0],
		"original_definition": {},
		"battle_owned": true,
		"discarded": true,
		"last_position": [0, 0],
	}
	for runtime_field in runtime_values:
		var changed: Dictionary = fx.duplicate(true)
		changed["provider"]["definitions"]["synthetic:unit/5"][runtime_field] = \
			runtime_values[runtime_field]
		var changed_provider := _provider(changed)
		var changed_spec: Dictionary = changed["canonical_spec"].duplicate(true)
		changed_spec["content"] = changed_provider.content_provenance()
		_check("unknown construction field" in _error(changed_spec, changed_provider),
			"canonical definition rejects runtime field %s" % runtime_field)

		var runtime_override: Dictionary = fx["canonical_spec"].duplicate(true)
		runtime_override["sides"][0]["units"][0]["overrides"][runtime_field] = \
			runtime_values[runtime_field]
		_check("unknown or non-settable" in _error(runtime_override, provider),
			"canonical override rejects runtime field %s" % runtime_field)

	var spoofed_definition_id: Dictionary = fx["canonical_spec"].duplicate(true)
	spoofed_definition_id["sides"][0]["units"][0]["overrides"]["definition_id"] = 999
	_check("forbidden field: definition_id" in _error(spoofed_definition_id, provider),
		"canonical override cannot spoof internal definition identity")
	var changed_identity: Dictionary = fx.duplicate(true)
	changed_identity["provider"]["definitions"]["synthetic:unit/5"]["definition_id"] = 999
	var identity_provider := _provider(changed_identity)
	var identity_spec: Dictionary = changed_identity["canonical_spec"].duplicate(true)
	identity_spec["content"] = identity_provider.content_provenance()
	_check("scenario-owned field: definition_id" in _error(identity_spec, identity_provider),
		"canonical definition cannot compete with canonical content identity")

	var static_override: Dictionary = fx["canonical_spec"].duplicate(true)
	static_override["sides"][0]["units"][0]["overrides"].merge(
		{"ammo_base": 6, "tier": 3}, true)
	var static_unit: Combatant = Scenario.new(
		static_override, null, provider).units["attacker-1"]
	_check(static_unit.ammo_base == 6 and static_unit.tier == 3,
		"ammo_base and tier remain legitimate canonical static fields")

	print("\n%s" % ["ALL PASS" if failures == 0 else "%d FAILURES" % failures])
	quit(1 if failures else 0)
