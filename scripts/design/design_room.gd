@tool
extends Node2D
## Station service areas, in tiles relative to this movable node.
@export_enum("market", "bar", "board", "hiring", "claims", "bank", "shipyard") var kind := "market"
@export var inner := Rect2i(0, 0, 9, 18):
	set(value):
		inner = value
		queue_redraw()
@export var front := Rect2i(0, 0, 9, 10)
@export var behind := Rect2i(0, 14, 9, 4)
@export var desk := Vector2i(4, 12)
@export var door := Vector2i(4, -1)

func _draw() -> void:
	draw_rect(Rect2(Vector2(inner.position) * 16, Vector2(inner.size) * 16), Color(0.3, 0.9, 0.6, 0.6), false, 1)
	draw_string(ThemeDB.fallback_font, Vector2(inner.position) * 16 + Vector2(2, 13), kind, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
