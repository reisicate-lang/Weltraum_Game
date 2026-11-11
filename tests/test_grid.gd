## Tests: feineres Baufeld-Raster (16 px statt 32 px)
##   godot --headless --path . --script res://tests/boot.gd -- test_grid
## 1) Vier neue Felder in der Fläche eines alten Feldes einzeln anvisieren, bebauen, abbauen
## 2) Kabel → Gerät → Boden auf einem kleinen Feld
## 3) Laufen: gleiche sichtbare Strecke pro Spielzeit; Türdurchgang mit WASD
## 4) Älterer Spielstand (Testdatei aus der Version vor der Verfeinerung): laden, durch die
##    Luftschleuse gehen, Druckhülle, Ports und Andocken an der vorgesehenen Stelle
extends "res://tests/test_base.gd"

const OLD_SAVE := "res://tests/fixtures/old_save_coarse.json"
const SLOT := 922

var ok_count := 0
var fail_count := 0
var gs
var ui
var ship
var CS
var R
var P
var A
var save
var main
var x0 := 0
var y0 := 0
var screen := Vector2.ZERO
var toasts: Array[String] = []

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _secs(s: float) -> void:
	for k in int(s):
		gs.step(1.0 / 60.0)

func _until_done(p: Vector2i, max_s: int = 3600) -> bool:
	for k in max_s:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(ship.grid.idx(p)):
			return true
	return false

## Feld unter den Mauszeiger bringen (ohne Fenster steht die Maus still: Kamera verschieben)
func _aim(t: Vector2i) -> void:
	for k in 8:
		var got: Vector2i = main._tile_at_mouse()
		if got == t:
			break
		main.cam.position += Vector2(t - got) * Config.TILE_SIZE
		await process_frame
	main._process(0.0)          # Vorschau-Feld (view.hover) wie im Spiel aktualisieren

func _mouse(button: int, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = screen
	ev.global_position = screen
	root.push_input(ev)
	await process_frame

func _uninstall_from_menu() -> bool:
	for k in ui.menu_actions.size():
		if ui.menu_actions[k].kind == "uninstall":
			if ui.object_menu.is_item_disabled(ui.object_menu.get_item_index(k)):
				print("        (gesperrt: %s)" % ui.object_menu.get_item_text(ui.object_menu.get_item_index(k)))
				return false
			ui._on_object_menu(k)
			ui.object_menu.hide()
			return true
	return false

func _fresh() -> void:
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.char_ui.creation.visible = false
	ui.close_help()
	var m = root.get_node("CrewSystem").player()
	m.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	var g = ship.grid
	x0 = (g.width / Config.GRID_SCALE - 16) / 2
	y0 = (g.height / Config.GRID_SCALE - 10) / 2

func _initialize() -> void:
	await process_frame
	await process_frame
	save = root.get_node("SaveSystem")
	save.slot = SLOT
	gs = root.get_node("GameState")
	ui = root.get_node("UIManager")
	ship = root.get_node("ShipSystem")
	CS = root.get_node("ShipConstructionSystem")
	R = root.get_node("RemovalSystem")
	P = root.get_node("PhysicsSystem")
	A = root.get_node("AtmosphereSystem")
	root.get_node("Settings").meteors = false
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(String(t)))
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	_fresh()
	var g = ship.grid
	_check("Feldgröße halbiert (%d px, früher 32 px), Raster %d×%d" % [Config.TILE_SIZE, g.width, g.height], Config.TILE_SIZE == 16 and g.width == 128 and g.height == 88)
	_check("Figur bleibt gleich groß (%d px = 2 Felder), Kamera-Zoom unverändert (%.1f)" % [int(Config.CHAR_PX), main.cam.zoom.x], Config.CHAR_PX == 32.0 and absf(main.cam.zoom.x - 1.4) < 0.001)
	screen = root.get_viewport().get_canvas_transform() * ((Vector2(C(x0 + 2, y0 + 5)) + Vector2(0.5, 0.5)) * Config.TILE_SIZE)

	# ---------------- 1) Vier neue Felder in einem alten Feld ----------------
	var old := Vector2i(x0 + 4, y0 + 2)                  # freies Feld in der Wohnkabine (frühere Felder)
	var cells: Array[Vector2i] = []
	for sub in 4:
		cells.append(old * Config.GRID_SCALE + Vector2i(sub % 2, sub / 2))
	var free := true
	for c in cells:
		free = free and g.get_tile(c) == ShipGrid.Tile.FLOOR and not g.occupied(c) and g.cables[g.idx(c)] == 0
	_check("1: Die alte Fläche besteht aus 4 freien Bodenfeldern %s" % str(cells), free)
	for dv in g.devices.values():
		if dv.type == "crate" and g.zone[g.idx(dv.pos)] == 0:
			dv.inv.add("plate", 12, 90.0)
			break
	for c in cells:
		ui.set_tool("wall")
		await _aim(c)
		var hover_ok: bool = main.view.hover == c and main._tile_at_mouse() == c and CS.can_place("wall", c)
		var jobs_before: int = CS.jobs.size()
		await _mouse(MOUSE_BUTTON_LEFT, true)
		await _mouse(MOUSE_BUTTON_LEFT, false)
		var planned: bool = CS.jobs.has(g.idx(c)) and CS.jobs.size() == jobs_before + 1
		_check("1: Feld %s: Vorschau dort, Klick plant genau dieses Feld" % str(c), hover_ok and planned)
		_until_done(c)
		var only := true
		for o in cells:
			if o != c and g.get_tile(o) == ShipGrid.Tile.WALL and cells.find(o) > cells.find(c):
				only = false
		_check("1: … Wand steht genau auf %s (nicht auf den Nachbarfeldern)" % str(c), g.get_tile(c) == ShipGrid.Tile.WALL and only)
	ui.set_tool("select")
	for c in cells:
		await _aim(c)
		await _mouse(MOUSE_BUTTON_RIGHT, true)
		await _mouse(MOUSE_BUTTON_RIGHT, false)
		_check("1: Rechtsklick wählt genau %s (Wand)" % str(c), ui.sel_tile == c and ui.sel_key == "tile:wall")
		_check("1: … Abbauen geplant", _uninstall_from_menu() and CS.jobs.has(g.idx(c)))
		_until_done(c)
		_check("1: … abgebaut, wieder Boden", g.get_tile(c) == ShipGrid.Tile.FLOOR)

	# ---------------- 2) Kabel, Gerät, Boden auf einem kleinen Feld ----------------
	var bat := C(x0 + 2, y0 + 5)
	_check("2: Batterie belegt genau 1 kleines Feld mit Kabel und Boden (%s)" % str(R.layers_at(bat)), R.layers_at(bat) == ["cable", "dev:battery", "tile:floor"]
		and g.device_at(bat + Vector2i(1, 0)) != g.device_at(bat) and g.device_at(bat + Vector2i(0, 1)) != g.device_at(bat))
	var order: Array = []
	ui.clear_selection()
	for k in 4:
		await _aim(bat)
		await _mouse(MOUSE_BUTTON_RIGHT, true)
		await _mouse(MOUSE_BUTTON_RIGHT, false)
		order.append(ui.sel_key)
	ui.object_menu.hide()
	_check("2: Rechtsklicks: %s" % str(order), order == ["cable", "dev:battery", "tile:floor", "cable"])

	# ---------------- 3) Laufen und Türen ----------------
	var mira = root.get_node("CrewSystem").player()
	mira.auto_mode = false
	var start := C(x0 + 11, y0 + 6) + Vector2i(1, 1)
	mira.pos = Vector2(start) + Vector2(0.5, 0.5)
	mira.path.clear()
	_check("3: Laufziel geplant", mira.order_move(start + Vector2i(6, 0)))
	var p0: Vector2 = mira.pos
	_secs(1)
	var px_per_s: float = (mira.pos - p0).length() * Config.TILE_SIZE
	_check("3: Gleiche sichtbare Strecke pro Spielsekunde wie früher (%.1f px/s, früher 2,5 × 32 = 80)" % px_per_s, absf(px_per_s - 80.0) < 1.0)
	# WASD durch die Innentür der Luftschleuse, leicht neben der Türmitte
	var inner_door := C(x0, y0 + 7)
	_check("3: Innentür der Luftschleuse ist eine 1 Feld breite Tür", g.get_tile(inner_door) == ShipGrid.Tile.DOOR and g.wall_like(inner_door + Vector2i(0, -1)) and g.wall_like(inner_door + Vector2i(0, 1)))
	mira.pos = Vector2(inner_door + Vector2i(3, 0)) + Vector2(0.5, 0.78)
	for k in 120:
		mira.manual_move(Vector2(-1, 0), Config.WALK_SPEED / 60.0 / 60.0)
		gs.step(1.0 / 60.0 / 60.0)
	_check("3: Mit WASD durch die Tür in die Schleuse (Figur bei %s)" % str(mira.tile()), mira.tile().x < inner_door.x and g.walkable(mira.tile()))
	mira.auto_mode = true

	# ---------------- 4) Älterer Spielstand ----------------
	Config.ENABLE_STATION = true
	Config.ENABLE_WRECK = true
	var text := FileAccess.get_file_as_string(OLD_SAVE)
	var old_data: Dictionary = JSON.parse_string(text)
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	toasts.clear()
	_check("4: Alter Spielstand geladen (Felder %d×%d → fein)" % [int(old_data.ship.w), int(old_data.ship.h)], save.load_game(true) and ship.grid.width == 128 and ship.grid.migrated.refined)
	g = ship.grid
	# Geräte: dieselben, einzeln, mit Zustand und Inventar
	var old_types: Array = old_data.ship.devices.map(func(d): return String(d.type))
	var new_types: Array = g.devices.values().map(func(d): return d.type)
	old_types.sort()
	new_types.sort()
	# Die Station wird beim Laden frisch aufgebaut: ihre Tresen zählen beidseitig nicht
	old_types = old_types.filter(func(t): return not String(t).begins_with("st_"))
	new_types = new_types.filter(func(t): return not String(t).begins_with("st_"))
	_check("4: Alle Geräte als einzelne Instanzen erhalten (%d)" % new_types.size(), old_types == new_types)
	var crate42 := false
	var rations := 0
	for dv in g.devices.values():
		if dv.type == "crate" and absf(dv.cond - 42.0) < 0.01:
			crate42 = true
			rations = dv.inv.count("ration")
	_check("4: Zustand und Inventar erhalten (Kiste 42 %%, %d Rationen)" % rations, crate42 and rations == 10)
	var plates_pile := 0
	for i in g.piles:
		plates_pile += g.piles[i].count("plate")
	_check("4: Haufen erhalten (3 Platten)", plates_pile >= 3)
	# Druckhülle: alle eigenen Räume dicht
	A.topology()
	var own_rooms := 0
	var leaking := 0
	for r in A.rooms.size():
		if g.zone[A.rooms[r].cells[0]] == 0:
			own_rooms += 1
			if A.room_leak(r) != "":
				leaking += 1
	_check("4: Druckhülle dicht: %d eigene Räume, %d mit Leck" % [own_rooms, leaking], own_rooms >= 4 and leaking == 0)
	# Türen begehbar, Ports verbunden
	var doors_ok := true
	for i in g.tiles.size():
		if g.zone[i] == 0 and g.tiles[i] == ShipGrid.Tile.DOOR and not g.devices.has(i) and not g.walkable(g.pos(i)):
			doors_ok = false
	_check("4: Alle Türen des Schiffs begehbar", doors_ok)
	var st = root.get_node("StationSystem")
	var salv = root.get_node("SalvageSystem")
	var right_port := Vector2i(-1, -1)
	var down_port := Vector2i(-1, -1)
	for p in ship.ports():
		if p.dir == Vector2i(1, 0):
			right_port = p.pos
		if p.dir == Vector2i(0, 1):
			down_port = p.pos
	_check("4: Station hängt an derselben (rechten) Schleuse, Tür an Tür", st.active() and g.pos(st.hatch) == right_port and g.get_tile(right_port + Vector2i(1, 0)) == ShipGrid.Tile.DOOR and g.zone[g.idx(right_port + Vector2i(1, 0))] == 3)
	_check("4: Wrack hängt an derselben (unteren) Schleuse, Tür an Tür", g.pos(salv.port) == down_port and salv.entry == down_port + Vector2i(0, 1) and g.get_tile(salv.entry) == ShipGrid.Tile.DOOR and g.zone[g.idx(salv.entry)] == 1)
	_check("4: Durchgang Schiff → Station und Schiff → Wrack", not ship.find_path(right_port + Vector2i(-1, 0), right_port + Vector2i(2, 0)).is_empty() and not ship.find_path(down_port + Vector2i(0, -1), salv.entry + Vector2i(0, 1)).is_empty())
	# Durch die vorhandene Luftschleuse nach draußen: Boden direkt vor der Außentür bauen
	mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	var outer_door := Vector2i(-1, -1)
	for i in g.tiles.size():
		if g.zone[i] == 0 and g.tiles[i] == ShipGrid.Tile.DOOR and root.get_node("AirlockSystem").is_lock_door(i):
			var q: Vector2i = g.pos(i)
			if g.get_tile(q + Vector2i(-1, 0)) == ShipGrid.Tile.SPACE:
				outer_door = q
	_check("4: Außentür der Luftschleuse gefunden (%s)" % str(outer_door), outer_door.x >= 0)
	var steg := outer_door + Vector2i(-1, 0)
	CS.place("floor", steg)
	var saw_suit := false
	var saw_wait := false
	for k in 60 * 15:
		gs.step(1.0 / 60.0)
		saw_suit = saw_suit or mira.suit != null
		saw_wait = saw_wait or mira.waiting
		if g.get_tile(steg) == ShipGrid.Tile.FLOOR:
			break
	_check("4: Mira geht mit Raumanzug durch die Luftschleuse und baut draußen (Anzug %s, Schleuse %s)" % [saw_suit, saw_wait], saw_suit and saw_wait and g.get_tile(steg) == ShipGrid.Tile.FLOOR)
	_secs(120)
	A.topology()
	leaking = 0
	for r in A.rooms.size():
		var c0: int = A.rooms[r].cells[0]
		if g.zone[c0] == 0 and A.room_leak(r) != "" and g.tiles[c0] != ShipGrid.Tile.FLOOR:
			leaking += 1
	var cabin_p: float = g.pressure(g.idx(C(x0 + 4, y0 + 2)))
	_check("4: Danach Kabine weiter unter Druck (%.0f kPa)" % cabin_p, cabin_p > 90.0)
	# Abdocken und an der vorgesehenen Stelle wieder andocken
	var helm = P.ship_devices("helm")[0]
	P.helm_at = helm.pos
	for c in root.get_node("CrewSystem").crew:
		if g.zone[g.idx(c.tile())] != 0:
			c.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	salv.clear()
	_check("4: Abdocken von der Station", P.request_undock() and not st.active())
	_secs(20)
	var t0: Dictionary = P.loc_state(P.loc("tycho"), P.secs())
	P.vel = t0.vel
	P.pos = t0.pos + Vector2(0.05, 0)
	P.angle = P.dock_alignment("tycho").angle
	_check("4: Wieder angedockt (%s)" % P.dock_block_reason("tycho"), P.dock("tycho") and st.active())
	g = ship.grid
	_check("4: Station wieder Tür an Tür an einer Schiffsschleuse", st.hatch >= 0 and g.linked.has(st.hatch) and g.devices.has(st.hatch) and g.devices[st.hatch].type == "dockport")
	# Erneut speichern und laden: keine zweite Verfeinerung
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	_check("4: Erneut geladen: kein zweites Verfeinern, Größe bleibt", not ship.grid.migrated.refined and ship.grid.width == 128 and ship.ports().size() == 2)
	Config.ENABLE_STATION = false
	Config.ENABLE_WRECK = false

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
