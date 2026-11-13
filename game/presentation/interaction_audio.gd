class_name InteractionAudio
extends Node

const FREQUENCIES := {"select": 520.0, "confirm": 740.0, "refuse": 155.0,
	"movement": 310.0, "impact": 95.0, "capture": 990.0}

## Project-authored PCM tones; never loads or distributes private samples.
static var muted := false
static var volume := 0.35
var last_cue := ""
var player: AudioStreamPlayer


func _ready() -> void:
	player = AudioStreamPlayer.new()
	add_child(player)

func cue(id: String) -> void:
	last_cue = id
	if muted or volume <= 0 or player == null:
		return
	var pcm := PackedByteArray()
	var frequency: float = FREQUENCIES.get(id, 520.0)
	for index in 5292:
		var t := float(index) / 22050.0
		var envelope := minf(t * 160, 1.0) * pow(1.0 - index / 5292.0, 2)
		var wave := sin(TAU * frequency * t) + 0.3 * sin(TAU * frequency * 1.5 * t)
		var value := int(clampf(wave * envelope * 12000, -32767, 32767))
		pcm.append(value & 255)
		pcm.append((value >> 8) & 255)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = pcm
	player.stream = stream
	player.volume_db = linear_to_db(clampf(volume, 0.0001, 1.0))
	player.play()

static func controls(parent: Node) -> InteractionAudio:
	var sound := InteractionAudio.new()
	parent.add_child(sound)
	var row := HBoxContainer.new()
	var mute := CheckButton.new()
	mute.text = "Mute"
	mute.button_pressed = sound.muted
	mute.toggled.connect(func(value: bool) -> void:
		sound.muted = value
		if value:
			sound.player.stop())
	row.add_child(mute)
	var volume_slider := HSlider.new()
	volume_slider.custom_minimum_size.x = 90
	volume_slider.min_value = 0
	volume_slider.max_value = 1
	volume_slider.step = 0.05
	volume_slider.value = sound.volume
	volume_slider.tooltip_text = "Sound volume"
	volume_slider.value_changed.connect(func(value: float) -> void: sound.volume = value)
	row.add_child(volume_slider)
	parent.add_child(row)
	return sound


func _exit_tree() -> void:
	if player != null:
		player.stop()
		player.stream = null
