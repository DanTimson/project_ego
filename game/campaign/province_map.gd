extends Control

signal destination_chosen(id: String)

const LOCATIONS := {
	"home": Vector2(0.0, 0.5),
	"ford": Vector2(0.33, 0.15),
	"quarry": Vector2(0.33, 0.85),
	"watchpost": Vector2(0.67, 0.15),
	"mill": Vector2(0.67, 0.85),
	"keep": Vector2(1.0, 0.5),
}
var buttons: Dictionary = {}
var _content: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(580, 260)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	for id in LOCATIONS:
		var button := Button.new()
		button.name = id.capitalize()
		button.size = Vector2(112, 76)
		button.pressed.connect(func() -> void: destination_chosen.emit(id))
		add_child(button)
		buttons[id] = button
	resized.connect(_layout)
	_layout()


func display(campaign: StrategicCampaign) -> void:
	_content = campaign.content()
	var state := campaign.snapshot()
	for id in buttons:
		var province: Dictionary = _content.provinces[id]
		var owner := "Friendly" if id in state.owned else "Hostile"
		buttons[id].text = (
			"%s%s\n%s • +%d"
			% ["● " if id == state.position else "", province.name, owner, province.income]
		)
		buttons[id].modulate = (
			Color(0.65, 0.85, 1.0) if id in state.owned else Color(1.0, 0.8, 0.65)
		)
		var query := campaign.query("travel", id)
		buttons[id].disabled = not query.ok
		buttons[id].tooltip_text = (
			("Travel to " if id in state.owned else "Battle for ") + province.name
			if query.ok
			else query.reason
		)
	queue_redraw()


func _layout() -> void:
	for id in buttons:
		buttons[id].position = Vector2(4, 4) + LOCATIONS[id] * (size - Vector2(120, 84))
	queue_redraw()


func _draw() -> void:
	if _content.is_empty():
		return
	for id in buttons:
		for neighbor in _content.provinces[id].links:
			if id < neighbor:
				draw_line(
					buttons[id].position + buttons[id].size / 2,
					buttons[neighbor].position + buttons[neighbor].size / 2,
					Color(0.42, 0.51, 0.59),
					3.0,
					true
				)
