## Tests: damage view for finding leaks (Ostranauts Ideal Atmosphere 2, key X)
##   godot --headless --path . --script res://tests/boot.gd -- test_damage_view
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _initialize() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	root.get_node("SaveSystem").slot = 955
	root.get_node("Settings").meteors = false
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var g = root.get_node("ShipSystem").grid
	var view = main.get_node("ShipView")
	var W: int = g.width - 1
	var H: int = g.height - 1

	var m: Dictionary = view.damage_marks(g, 0, 0, W, H)
	_check("New ship: nothing damaged, no leaks", m.damaged.is_empty() and m.leaks.is_empty())

	# Damaged wall and device
	var wall := -1
	# Outer wall with floor on one side and space on the other
	for i in g.tiles.size():
		if g.tiles[i] != ShipGrid.Tile.WALL or g.foreign(i) or g.device_at(g.pos(i)) != null:
			continue
		var q: Vector2i = g.pos(i)
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			if g.in_bounds(q - d) and g.in_bounds(q + d) and g.get_tile(q - d) == ShipGrid.Tile.FLOOR and g.get_tile(q + d) == ShipGrid.Tile.SPACE:
				wall = i
		if wall >= 0:
			break
	g.cond[wall] = 40.0
	var dev: Device = null
	for i in g.devices:
		if g.devices[i].type == "bed":
			dev = g.devices[i]
	dev.cond = 70.0
	m = view.damage_marks(g, 0, 0, W, H)
	_check("Wall 40 % and bed 70 % marked", m.damaged.get(wall, -1.0) == 40.0 and m.damaged.get(g.idx(dev.pos), -1.0) == 70.0 and m.damaged.size() == 2)
	dev.broken = true
	m = view.damage_marks(g, 0, 0, W, H)
	_check("A broken device counts as 0 %", m.damaged.get(g.idx(dev.pos), -1.0) == 0.0)

	# Hole in the outer wall: the floor tile next to it is a leak
	var p: Vector2i = g.pos(wall)
	g.tiles[wall] = ShipGrid.Tile.SPACE
	m = view.damage_marks(g, 0, 0, W, H)
	var leak_next := false
	for i in m.leaks:
		if g.pos(i).distance_to(p) <= 1.0:
			leak_next = true
	_check("Hole: neighbouring tile marked as a leak (%d leak tiles)" % m.leaks.size(), leak_next)

	# Umschalten
	gs.view = "normal"
	var ev := InputEventKey.new()
	ev.keycode = KEY_X
	ev.pressed = true
	main._key(ev)
	_check("Taste X: Schadensansicht an", gs.view == "damage")
	main._key(ev)
	_check("X again: off", gs.view == "normal")

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
