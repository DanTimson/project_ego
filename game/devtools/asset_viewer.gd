extends Control

const MANIFEST_PATH := "res://cache/root/manifest.json" # <-- change to your real path

@onready var assets: ItemList = %Assets
@onready var title_lbl: Label = %Title
@onready var image_view: TextureRect = %Image
@onready var audio_row: HBoxContainer = %AudioRow
@onready var audio: AudioStreamPlayer2D = %Audio
@onready var log_box: RichTextLabel = %Log

var _current_id := ""
var _current_type := ""
var _current_res := ""

func _ready() -> void:
	%LoadBtn.pressed.connect(_on_load_pressed)
	assets.item_selected.connect(_on_asset_selected)
	%Play.pressed.connect(_on_play)
	%Stop.pressed.connect(_on_stop)

	_reset_preview()
	_on_load_pressed() # auto-load on start

func _on_load_pressed() -> void:
	VFS.load_manifest(MANIFEST_PATH)

	assets.clear()
	for id in VFS.list_ids():
		assets.add_item(id)

	_log("Loaded %d assets from %s" % [assets.item_count, MANIFEST_PATH])

func _on_asset_selected(index: int) -> void:
	var id := assets.get_item_text(index)
	_current_id = id

	var a := VFS.get_asset(id)
	if a.is_empty():
		_log("Unknown asset: " + id)
		return

	_current_type = str(a.get("type", ""))
	_current_res  = str(a.get("res_path", ""))

	_preview_current()

func _preview_current() -> void:
	_reset_preview()
	title_lbl.text = "%s (%s)" % [_current_id, _current_type]

	if _current_res.is_empty():
		_log("No res_path for asset: " + _current_id)
		return

	# ResourceLoader.exists checks imported resources.
	if not ResourceLoader.exists(_current_res):
		_log("Missing resource (not imported?): " + _current_res)
		return

	match _current_type:
		"image":
			_preview_image(_current_res)
		"audio":
			_preview_audio(_current_res)
		_:
			_log("No preview for type: " + _current_type + " (" + _current_res + ")")

func _preview_image(res_path: String) -> void:
	var tex := load(res_path)
	if tex == null or not (tex is Texture2D):
		_log("Failed to load Texture2D: " + res_path)
		return

	image_view.texture = tex
	_log("Image OK: " + res_path)

func _preview_audio(res_path: String) -> void:
	var stream := load(res_path)
	if stream == null or not (stream is AudioStream):
		_log("Failed to load AudioStream: " + res_path)
		return

	audio.stream = stream
	audio_row.visible = true
	_log("Audio OK: " + res_path)

func _on_play() -> void:
	if audio.stream != null:
		audio.play()

func _on_stop() -> void:
	audio.stop()

func _reset_preview() -> void:
	title_lbl.text = "No selection"
	image_view.texture = null
	audio.stop()
	audio.stream = null
	audio_row.visible = false

func _log(s: String) -> void:
	log_box.append_text(s + "\n")
