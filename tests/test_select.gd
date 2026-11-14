## Tests: Rechtsklick-Auswahl beim Abbau – Ebenen Kabel → Gerät → Boden auf derselben Kachel
## Mit echten Mausereignissen über die Hauptszene (das Menü bleibt dabei offen wie im Spiel).
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

## Kachel unter den Mauszeiger bringen (ohne Fenster steht die Maus still: Kamera verschieben)
func _aim(t: Vector2i) -> void:
	for k in 8:
		var got: Vector2i = main._tile_at_mouse()
		if got == t:
			return
		main.cam.position += Vector2(t - got) * Config.TILE_SIZE
		await process_frame

## Ein echter Rechtsklick (drücken, loslassen) auf Kachel t
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

## Den Menüeintrag „Abbauen“ wählen (wie ein Klick im offenen Menü)
func _uninstall_from_menu() -> bool:
	for k in ui.menu_actions.size():
		if ui.menu_actions[k].kind == "uninstall":
			var idx: int = ui.object_menu.get_item_index(k)
			if ui.object_menu.is_item_disabled(idx):
				print("        (gesperrt: %s)" % ui.object_menu.get_item_text(idx))
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
	# Klickpunkt mitten in der Schiffsansicht (nicht über einem Bedienfeld)
	screen = root.get_viewport().get_canvas_transform() * ((Vector2(C(x0 + 2, y0 + 5)) + Vector2(0.5, 0.5)) * Config.TILE_SIZE)
	await process_frame
	var bat := C(x0 + 2, y0 + 5)
	var gen := C(x0 + 1, y0 + 5)
	var bed := C(x0 + 1, y0 + 1)
	_check("Batterie-Kachel hat Kabel, Gerät und Boden (%s)" % str(R.layers_at(bat)), R.layers_at(bat) == ["cable", "dev:battery", "tile:floor"])

	# 1) Dreimal rechtsklicken: Kabel, Gerät, Boden – dann wieder von vorn
	var s1: String = await _rclick(bat)
	var h1 := _menu_head()
	var s2: String = await _rclick(bat)
	var h2 := _menu_head()
	var s3: String = await _rclick(bat)
	var h3 := _menu_head()
	_check("1: Rechtsklick 1 → Kabel (%s)" % h1, s1 == "cable" and "Selected: Cable" in h1 and ui.object_menu.visible)
	_check("1: Rechtsklick 2 → Gerät (%s)" % h2, s2 == "dev:battery" and "Selected: Ship Battery" in h2)
	_check("1: Rechtsklick 3 → Boden (%s)" % h3, s3 == "tile:floor" and "Selected: Floor" in h3)
	var s4: String = await _rclick(bat)
	_check("1: Rechtsklick 4 → wieder Kabel", s4 == "cable")
	_check("1: Markierung sichtbar (Auswahl gültig: %s auf %s)" % [ui.sel_key, str(ui.sel_tile)], ui.selection_valid() and ui.sel_tile == bat)

	# 4) Auf eine andere Kachel wechseln und zurück: jeweils oben beginnen
	await _rclick(gen)
	var g2: String = await _rclick(gen)
	_check("4: Generator-Kachel: 2. Klick → Gerät", g2 == "dev:generator")
	var b1: String = await _rclick(bed)
	_check("4: Andere Kachel (Bett, ohne Kabel) → beginnt beim Gerät", b1 == "dev:bed")
	var g3: String = await _rclick(gen)
	_check("4: Zurück zum Generator → beginnt wieder beim Kabel", g3 == "cable")
	var b2: String = await _rclick(bed)
	_check("4: Zurück zum Bett → wieder beim Gerät", b2 == "dev:bed")

	# 3) Kachel ohne Kabel beginnt beim Gerät, Kachel mit nur Boden beim Boden
	var floor_only := _find_tile(["tile:floor"])
	_check("3: Kachel ohne Kabel (Bett): oben = Gerät", R.layers_at(bed)[0] == "dev:bed" and b1 == "dev:bed")
	var f1: String = await _rclick(floor_only)
	_check("3: Nur-Boden-Kachel %s → Boden" % str(floor_only), floor_only.x >= 0 and f1 == "tile:floor")
	var f2: String = await _rclick(floor_only)
	_check("3: … erneuter Klick bleibt beim Boden (einzige Ebene)", f2 == "tile:floor")

	# 2) Kabel abbauen, dann Gerät, dann Boden – immer auf derselben Kachel
	var k1: String = await _rclick(bat)
	_check("2: Kabel ausgewählt", k1 == "cable")
	_check("2: „Abbauen“ nimmt genau das Kabel", _uninstall_from_menu() and CS.jobs.has(g.idx(bat)) and CS.jobs[g.idx(bat)].target == "cable")
	_until_done(bat)
	_check("2: Kabel weg, Batterie und Boden noch da", g.cables[g.idx(bat)] == 0 and g.device_at(bat) != null and g.device_at(bat).type == "battery" and g.get_tile(bat) == ShipGrid.Tile.FLOOR)
	var k2: String = await _rclick(bat)
	_check("2: Nächster Rechtsklick → Gerät (%s)" % _menu_head(), k2 == "dev:battery")
	_check("2: „Abbauen“ nimmt genau die Batterie", _uninstall_from_menu() and CS.jobs[g.idx(bat)].target == "dev:battery")
	_until_done(bat)
	_check("2: Batterie abgebaut (liegt als Gegenstand am Boden)", g.device_at(bat) == null and g.get_tile(bat) == ShipGrid.Tile.FLOOR and g.piles.has(g.idx(bat)) and g.piles[g.idx(bat)].count("pk_battery") == 1)
	var k3: String = await _rclick(bat)
	_check("2: Nächster Rechtsklick → Boden (%s)" % _menu_head(), k3 == "tile:floor" and "Selected: Floor" in _menu_head())
	ui.object_menu.hide()

	# Mehrfeld-Gerät: jede belegte Kachel wählt dieselbe Instanz
	var inner := C(x0 + 1, y0 + 2)
	var thr = g.device_at(inner)
	await _rclick(C(x0 + 3, y0 + 2))     # andere Kachel, damit jede Prüfung oben beginnt
	var m1: String = await _rclick(inner + Vector2i(-1, 0))
	var mid_dev = g.device_at(inner + Vector2i(-1, 0))
	await _rclick(C(x0 + 3, y0 + 2))
	var m2: String = await _rclick(inner + Vector2i(-2, 0))
	var out_dev = g.device_at(inner + Vector2i(-2, 0))
	_check("Triebwerk: Wandfeld und Düsenfeld wählen dasselbe Gerät (%s, %s)" % [m1, m2], m1 == "dev:thruster" and m2 == "dev:thruster" and mid_dev == thr and out_dev == thr)
	var m3: String = await _rclick(inner)
	_check("Triebwerk: Innenfeld beginnt beim Kabel, dann dasselbe Gerät", m3 == "cable" and (await _rclick(inner)) == "dev:thruster" and g.device_at(ui.sel_tile) == thr)
	ui.object_menu.hide()

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
