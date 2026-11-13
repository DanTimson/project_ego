class_name CampaignCheckpointStore
extends RefCounted

## One map-only local slot. The model validates plain values; only game/ touches disk.
var path: String


func _init(save_path: String = "user://strategic_campaign.json") -> void:
	path = save_path


func load_campaign(content: Dictionary, contested := false) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "No campaign checkpoint found."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"reason": "Cannot read checkpoint: " + error_string(FileAccess.get_open_error())
		}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK:
		return {"ok": false, "reason": "Malformed checkpoint JSON: " + parser.get_error_message()}
	if contested:
		return ContestedCampaign.from_checkpoint(content, parser.data)
	return StrategicCampaign.from_checkpoint(content, parser.data)


func save_campaign(campaign: RefCounted) -> Dictionary:
	var exported: Dictionary = campaign.checkpoint()
	if not exported.ok:
		return exported
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"reason":
			"Cannot write checkpoint replacement: " + error_string(FileAccess.get_open_error())
		}
	var serialized := JSON.stringify(exported.data, "\t")
	file.store_string(serialized)
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK and FileAccess.get_file_as_string(temporary) != serialized:
		error = ERR_FILE_CORRUPT
	if error == OK:
		error = _publish(temporary)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return {
			"ok": false,
			"reason":
			"Checkpoint replacement failed; previous slot preserved: " + error_string(error)
		}
	return {"ok": true, "reason": "Map checkpoint saved. Resume it from the campaign entry."}


func _publish(temporary: String) -> Error:
	# Same-directory rename publishes a fully written replacement. Never delete the slot first.
	return DirAccess.rename_absolute(temporary, path)
