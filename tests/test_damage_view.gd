## Tests: Schadensansicht zum Lecksuchen (Ostranauts Ideal Atmosphere 2, Taste X)
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
	_check("Neues Schiff: nichts beschädigt, keine Lecks", m.damaged.is_empty() and m.leaks.is_empty())

	# Beschädigte Wand und Gerät
	var wall := -1
	# Außenwand mit Boden auf der einen und All auf der anderen Seite
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
	_check("Wand 40 % und Bett 70 % markiert", m.damaged.get(wall, -1.0) == 40.0 and m.damaged.get(g.idx(dev.pos), -1.0) == 70.0 and m.damaged.size() == 2)
	dev.broken = true
	m = view.damage_marks(g, 0, 0, W, H)
	_check("Kaputtes Gerät zählt als 0 %", m.damaged.get(g.idx(dev.pos), -1.0) == 0.0)

	# Loch in der Außenwand: Bodenfeld daneben ist ein Leck
	var p: Vector2i = g.pos(wall)
	g.tiles[wall] = ShipGrid.Tile.SPACE
	m = view.damage_marks(g, 0, 0, W, H)
	var leak_next := false
	for i in m.leaks:
		if g.pos(i).distance_to(p) <= 1.0:
			leak_next = true
	_check("Loch: Nachbarfeld als Leck markiert (%d Leckfelder)" % m.leaks.size(), leak_next)

	# Umschalten
	gs.view = "normal"
	var ev := InputEventKey.new()
	ev.keycode = KEY_X
	ev.pressed = true
	main._key(ev)
	_check("Taste X: Schadensansicht an", gs.view == "damage")
	main._key(ev)
	_check("Nochmal X: aus", gs.view == "normal")

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
