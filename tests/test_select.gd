## Tests: right-click selection when removing – layers cable → device → floor on the same tile
## With real mouse events through the main scene (the menu stays open as in the game).
##   godot --headless --path . --script res://tests/boot.gd -- test_select
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var gs
var ui
var ship
var CS
var R
var main
var x0 := 0
var y0 := 0
var screen := Vector2.ZERO

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _until_done(p: Vector2i, max_s: int = 3600) -> bool:
	for k in max_s:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(ship.grid.idx(p)):
			return true
	return false

## Bring the tile under the mouse pointer (without a window the mouse stands still: move the camera)
func _aim(t: Vector2i) -> void:
	for k in 8:
		var got: Vector2i = main._tile_at_mouse()
		if got == t:
			return
		main.cam.position += Vector2(t - got) * Config.TILE_SIZE
		await process_frame

## A real right-click (press, release) on tile t
func _rclick(t: Vector2i) -> String:
	await _aim(t)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = pressed
		ev.position = screen
		ev.global_position = screen
		root.push_input(ev)
		await process_frame
	await process_frame
	return ui.sel_key

## Pick the menu entry "Uninstall" (like a click in the open menu)
func _uninstall_from_menu() -> bool:
	for k in ui.menu_actions.size():
		if ui.menu_actions[k].kind == "uninstall":
			var idx: int = ui.object_menu.get_item_index(k)
			if ui.object_menu.is_item_disabled(idx):
				print("        (locked: %s)" % ui.object_menu.get_item_text(idx))
				return false
			ui._on_object_menu(k)
			ui.object_menu.hide()
			return true
	return false

func _menu_head() -> String:
	for i in ui.object_menu.item_count:
		if ui.object_menu.is_item_separator(i) and ui.object_menu.get_item_text(i).begins_with("▶"):
			return ui.object_menu.get_item_text(i)
	return ""

func _find_tile(want: Array) -> Vector2i:
	var g = ship.grid
	for i in g.tiles.size():
		var p: Vector2i = g.pos(i)
		if g.zone[i] == 0 and R.layers_at(p) == want and not CS.jobs.has(i):
			return p
	return Vector2i(-1, -1)

func _initialize() -> void:
	await process_frame
	await process_frame
	root.get_node("SaveSystem").slot = 920
	gs = root.get_node("GameState")
	ui = root.get_node("UIManager")
	ship = root.get_node("ShipSystem")
	CS = root.get_node("ShipConstructionSystem")
	R = root.get_node("RemovalSystem")
	root.get_node("Settings").meteors = false
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.char_ui.creation.visible = false
	ui.close_help()
	var mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	var g = ship.grid
	x0 = (g.width / Config.GRID_SCALE - 16) / 2
	y0 = (g.height / Config.GRID_SCALE - 10) / 2
	# Click point in the middle of the ship view (not over a panel)
	screen = root.get_viewport().get_canvas_transform() * ((Vector2(C(x0 + 2, y0 + 5)) + Vector2(0.5, 0.5)) * Config.TILE_SIZE)
	await process_frame
	var bat := C(x0 + 2, y0 + 5)
	var gen := C(x0 + 1, y0 + 5)
	var bed := C(x0 + 1, y0 + 1)
	_check("Battery tile has cable, device and floor (%s)" % str(R.layers_at(bat)), R.layers_at(bat) == ["cable", "dev:battery", "tile:floor"])

	# 1) Right-click three times: cable, device, floor – then from the start again
	var s1: String = await _rclick(bat)
	var h1 := _menu_head()
	var s2: String = await _rclick(bat)
	var h2 := _menu_head()
	var s3: String = await _rclick(bat)
	var h3 := _menu_head()
	_check("1: Right-click 1 → cable (%s)" % h1, s1 == "cable" and "Selected: Cable" in h1 and ui.object_menu.visible)
	_check("1: Right-click 2 → device (%s)" % h2, s2 == "dev:battery" and "Selected: Ship Battery" in h2)
	_check("1: Right-click 3 → floor (%s)" % h3, s3 == "tile:floor" and "Selected: Floor" in h3)
	var s4: String = await _rclick(bat)
	_check("1: Right-click 4 → cable again", s4 == "cable")
	_check("1: Marking visible (selection valid: %s on %s)" % [ui.sel_key, str(ui.sel_tile)], ui.selection_valid() and ui.sel_tile == bat)

	# 4) Switch to another tile and back: start at the top each time
	await _rclick(gen)
	var g2: String = await _rclick(gen)
	_check("4: Generator tile: 2nd click → device", g2 == "dev:generator")
	var b1: String = await _rclick(bed)
	_check("4: Other tile (bed, no cable) → starts at the device", b1 == "dev:bed")
	var g3: String = await _rclick(gen)
	_check("4: Back to the generator → starts at the cable again", g3 == "cable")
	var b2: String = await _rclick(bed)
	_check("4: Back to the bed → at the device again", b2 == "dev:bed")

	# 3) A tile without a cable starts at the device, a tile with only a floor at the floor
	var floor_only := _find_tile(["tile:floor"])
	_check("3: Tile without a cable (bed): top = device", R.layers_at(bed)[0] == "dev:bed" and b1 == "dev:bed")
	var f1: String = await _rclick(floor_only)
	_check("3: Floor-only tile %s → floor" % str(floor_only), floor_only.x >= 0 and f1 == "tile:floor")
	var f2: String = await _rclick(floor_only)
	_check("3: … another click stays at the floor (the only layer)", f2 == "tile:floor")

	# 2) Uninstall the cable, then the device, then the floor – always on the same tile
	var k1: String = await _rclick(bat)
	_check("2: Cable selected", k1 == "cable")
	_check("2: “Uninstall” takes exactly the cable", _uninstall_from_menu() and CS.jobs.has(g.idx(bat)) and CS.jobs[g.idx(bat)].target == "cable")
	_until_done(bat)
	_check("2: Cable gone, battery and floor still there", g.cables[g.idx(bat)] == 0 and g.device_at(bat) != null and g.device_at(bat).type == "battery" and g.get_tile(bat) == ShipGrid.Tile.FLOOR)
	var k2: String = await _rclick(bat)
	_check("2: Next right-click → device (%s)" % _menu_head(), k2 == "dev:battery")
	_check("2: “Uninstall” takes exactly the battery", _uninstall_from_menu() and CS.jobs[g.idx(bat)].target == "dev:battery")
	_until_done(bat)
	_check("2: Battery uninstalled (lies as an item on the floor)", g.device_at(bat) == null and g.get_tile(bat) == ShipGrid.Tile.FLOOR and g.piles.has(g.idx(bat)) and g.piles[g.idx(bat)].count("pk_battery") == 1)
	var k3: String = await _rclick(bat)
	_check("2: Next right-click → floor (%s)" % _menu_head(), k3 == "tile:floor" and "Selected: Floor" in _menu_head())
	ui.object_menu.hide()

	# Multi-tile device: every occupied tile selects the same instance
	var inner := C(x0 + 1, y0 + 2)
	var thr = g.device_at(inner)
	await _rclick(C(x0 + 3, y0 + 2))     # another tile so every check starts at the top
	var m1: String = await _rclick(inner + Vector2i(-1, 0))
	var mid_dev = g.device_at(inner + Vector2i(-1, 0))
	await _rclick(C(x0 + 3, y0 + 2))
	var m2: String = await _rclick(inner + Vector2i(-2, 0))
	var out_dev = g.device_at(inner + Vector2i(-2, 0))
	_check("Thruster: wall tile and nozzle tile select the same device (%s, %s)" % [m1, m2], m1 == "dev:thruster" and m2 == "dev:thruster" and mid_dev == thr and out_dev == thr)
	var m3: String = await _rclick(inner)
	_check("Thruster: the inner tile starts at the cable, then the same device", m3 == "cable" and (await _rclick(inner)) == "dev:thruster" and g.device_at(ui.sel_tile) == thr)
	ui.object_menu.hide()

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
