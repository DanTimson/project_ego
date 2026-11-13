extends RefCounted

# A checkpoint is accepted only if legal production commands reproduce ALL state.
# This validates identity, economic chronology, wounds, capacity and one-time outcomes
# together, rather than guessing independent upper bounds for interacting systems.
# gdlint: disable=max-returns
const Validation = preload("res://core/campaign/contested_validation.gd")
const MAX_EVENTS := 2000
const MAX_BATTLE_COMMANDS := 2048
const MAX_TACTICAL_COMMANDS := 32000
const MAX_COMPACT_LENGTH := 8000000


static func replay_bounds_error(data: Dictionary) -> String:
	if data.journal.size() > MAX_EVENTS:
		return "Checkpoint command journal bound exceeded."
	var tactical_count := 0
	for event in data.journal:
		if event is Dictionary and event.get("op") == "finish":
			if not event.get("commands") is Array or event.commands.size() > MAX_BATTLE_COMMANDS:
				return "Invalid or oversized tactical transcript."
			tactical_count += event.commands.size()
			if tactical_count > MAX_TACTICAL_COMMANDS:
				return "Checkpoint transcript bound exceeded."
	if JSON.stringify(data).length() > MAX_COMPACT_LENGTH:
		return "Checkpoint size bound exceeded."
	return ""


static func restore(c: Dictionary, data: Variant) -> Dictionary:
	var d: Variant = Validation.normalize(data)
	if (
		not d is Dictionary
		or d.size() != 6
		or d.get("version") != 4
		or d.get("mode") != "province"
		or d.get("content") != c.id
		or d.get("fingerprint") != JSON.stringify(c).sha256_text()
		or not d.get("state") is Dictionary
		or not d.get("journal") is Array
		or not CampaignRoster.values_only(d)
	):
		return {"ok": false, "reason": "Malformed or cross-content province checkpoint."}
	var bounds := replay_bounds_error(d)
	if bounds != "":
		return {"ok": false, "reason": bounds}
	var model := ContestedCampaign.create(c)
	if model == null:
		return {"ok": false, "reason": "Invalid province definition."}
	for event in d.journal:
		if not event is Dictionary or not event.get("op") is String:
			return {"ok": false, "reason": "Invalid checkpoint event."}
		var result := {"ok": false}
		match event.op:
			"command":
				if event.size() == 2 and event.get("command") is Dictionary:
					result = model.execute(event.command)
			"finish":
				if (
					event.size() != 2
					or not event.get("commands") is Array
					or not model.in_battle()
				):
					return {"ok": false, "reason": "Invalid tactical transcript."}
				var encounter := model.pending_encounter()
				encounter.session.begin()
				for command in event.commands:
					if (
						not _tactical_shape(command)
						or not encounter.session.issue_command(command).accepted
					):
						return {"ok": false, "reason": "Illegal tactical transcript."}
				result = model.finish(encounter)
			"abandon":
				if event.size() == 1:
					result = model.abandon(model.pending_encounter())
			"concede":
				if event.size() == 1:
					result = model.concede()
		if not result.ok:
			return {"ok": false, "reason": "Checkpoint contains an illegal transition."}
	var exported := model.checkpoint()
	if not exported.ok or model.snapshot() != d.state or exported.data.journal != d.journal:
		return {"ok": false, "reason": "Checkpoint state disagrees with legal command replay."}
	return {"ok": true, "campaign": model}


static func _tactical_shape(command: Variant) -> bool:
	if not command is Dictionary or not command.get("op") is String:
		return false
	for key in command:
		if key == "to":
			if not command.to is Array or command.to.size() != 2:
				return false
			for coordinate in command.to:
				if not coordinate is int:
					return false
		elif key not in ["op", "unit", "target", "action"] or not command[key] is String:
			return false
	return true
