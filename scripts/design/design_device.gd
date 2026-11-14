@tool
extends Node2D
## Move on the 16 px grid. Choose a component resource in the Inspector.
@export var component: DeviceData:
	set(value):
		component = value
		queue_redraw()
@export_range(0, 3) var direction := 0:
	set(value):
		direction = value
		queue_redraw()
@export var initial_state: Dictionary = {}

func _draw() -> void:
	if component == null:
		return
	var outward := -Vector2.RIGHT.rotated(direction * PI / 2)
	for index in maxi(1, component.length):
		draw_rect(Rect2(outward * index * 16 + Vector2(2, 2), Vector2(12, 12)), Color("609bb8"))
	draw_string(ThemeDB.fallback_font, Vector2(0, -3), component.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

func _get_configuration_warnings() -> PackedStringArray:
	return ["Choose a component from resources/components."] if component == null else []
