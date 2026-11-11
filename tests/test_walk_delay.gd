## Tests: Übergang von WASD zu einem Laufbefehl per Klick (Frist 0,5 echte Sekunden)
## Mit echten Tasten- und Mausereignissen über die Hauptszene, bei ×1 und ×16.
##   godot --headless --path . --script res://tests/boot.gd -- test_walk_delay
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var gs
var ui
var ship
var main
var mira
var screen := Vector2.ZERO

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

## Kachel unter den Mauszeiger bringen (ohne Fenster steht die Maus still: Kamera verschieben)
func _aim(t: Vector2i) -> void:
	for k in 8:
		var got: Vector2i = main._tile_at_mouse()
		if got == t:
			return
		main.cam.position += Vector2(t - got) * Config.TILE_SIZE
		await process_frame

func _click(button: MouseButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = screen
		ev.global_position = screen
		root.push_input(ev)
		await process_frame

## Mit WASD (D, sonst A) ein Stück laufen und loslassen; gibt die echte Zeit des Loslassens zurück
func _wasd() -> float:
	var start: Vector2 = mira.pos
	for code in [KEY_D, KEY_A]:
		_key(code, true)
		var t0 := _now()
		while _now() - t0 < 0.3:
			await process_frame
		_key(code, false)
		await process_frame
		if mira.pos.distance_to(start) > 0.2:
			break
	return _now()

## Erreichbares freies Bodenfeld 4–8 Felder entfernt
func _target() -> Vector2i:
	var g = ship.grid
	var from: Vector2i = mira.tile()
	for i in g.tiles.size():
		var p: Vector2i = g.pos(i)
		var d := absi(p.x - from.x) + absi(p.y - from.y)
		if d < 4 or d > 8 or g.zone[i] != 0 or g.tiles[i] != ShipGrid.Tile.FLOOR or g.devices.has(i) or g.piles.has(i):
			continue
		if not ship.find_path(from, p).is_empty():
			return p
	return Vector2i(-1, -1)

## Wartet, bis sich die Figur bewegt; gibt die echte Zeit zurück (oder -1)
func _wait_move(max_s: float) -> float:
	var p0: Vector2 = mira.pos
	var t0 := _now()
	while _now() - t0 < max_s:
		await process_frame
		if mira.pos.distance_to(p0) > 0.05:
			return _now()
	return -1.0

## Wartet, bis die Figur am Ziel steht
func _wait_arrive(t: Vector2i, max_s: float) -> bool:
	var t0 := _now()
	while _now() - t0 < max_s:
		await process_frame
		if mira.tile() == t and mira.order == null:
			return true
	return false

func _run(speed: int, label: String) -> void:
	root.get_node("TimeSystem").set_speed(speed)
	# 1) Loslassen und sofort klicken: vorgemerkt, Start nach etwa 0,5 s
	var released: float = await _wasd()
	_check("%s: WASD hat die Figur bewegt und die Handsteuerung gesetzt" % label, mira.is_manual() and not mira.walk_ready())
	var t := _target()
	await _aim(t)
	await _click(MOUSE_BUTTON_LEFT)
	var clicked := _now() - released
	_check("%s 1: Klick %.2f s nach dem Loslassen, Befehl vorgemerkt" % [label, clicked], clicked < 0.35 and mira.order == t)
	var moved: float = await _wait_move(3.0)
	var delay := moved - released
	_check("%s 1: Figur läuft %.2f s nach dem Loslassen los (erwartet ≈ 0,5 s)" % [label, delay], moved > 0.0 and delay >= 0.45 and delay <= 0.7)
	_check("%s 1: ohne zweiten Klick am Ziel" % label, await _wait_arrive(t, 30.0))

	# 2) Loslassen, länger warten, dann klicken: sofort los
	released = await _wasd()
	var t2 := _target()
	await _aim(t2)
	while _now() - released < 0.8:
		await process_frame
	await _click(MOUSE_BUTTON_LEFT)
	var at := _now()
	moved = await _wait_move(3.0)
	_check("%s 2: Klick nach %.2f s → Figur läuft %.2f s danach los (sofort)" % [label, at - released, moved - at], moved > 0.0 and moved - at <= 0.15)
	_check("%s 2: am Ziel" % label, await _wait_arrive(t2, 30.0))

func _initialize() -> void:
	await process_frame
	await process_frame
	root.get_node("SaveSystem").slot = 921
	gs = root.get_node("GameState")
	ui = root.get_node("UIManager")
	ship = root.get_node("ShipSystem")
	root.get_node("Settings").meteors = false
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.char_ui.creation.visible = false
	ui.close_help()
	ui.set_tool("select")
	mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	mira.auto_mode = false
	var g = ship.grid
	var x0: int = (g.width / Config.GRID_SCALE - 16) / 2
	var y0: int = (g.height / Config.GRID_SCALE - 10) / 2
	screen = root.get_viewport().get_canvas_transform() * ((Vector2(C(x0 + 2, y0 + 5)) + Vector2(0.5, 0.5)) * Config.TILE_SIZE)
	await process_frame
	_check("Frist ist 0,5 echte Sekunden", is_equal_approx(Config.MANUAL_WALK_DELAY, 0.5))

	await _run(1, "×1")
	await _run(5, "×16")

	# 3) Rechtsklick-Auswahl nach WASD unverändert: Kabel → Gerät → Boden
	root.get_node("TimeSystem").set_speed(1)
	await _wasd()
	var bat := C(x0 + 2, y0 + 5)
	var keys: Array = []
	for k in 4:
		await _aim(bat)
		await _click(MOUSE_BUTTON_RIGHT)
		await process_frame
		keys.append(ui.sel_key)
	ui.object_menu.hide()
	_check("3: Rechtsklicks auf dieselbe Kachel: %s" % str(keys), keys == ["cable", "dev:battery", "tile:floor", "cable"])
	_check("3: Rechtsklick gibt keinen Laufbefehl", mira.order == null)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
