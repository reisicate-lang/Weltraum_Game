## Tests: Andockschleuse 5×2 (längs an der Außenwand, Durchgang ohne Pumpe)
##   godot --headless --path . --script res://tests/boot.gd -- test_dockport
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var gs
var ship
var CS
var R
var P
var A
var save
var x0 := 0
var y0 := 0
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

func _fresh() -> void:
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var m = root.get_node("CrewSystem").player()
	m.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	var g = ship.grid
	x0 = (g.width / Config.GRID_SCALE - 16) / 2
	y0 = (g.height / Config.GRID_SCALE - 10) / 2
	_secs(2)

## Aufbau einer Schleuse mit Außentür p und Richtung d prüfen
func _layout_ok(g, p: Vector2i, d: Vector2i) -> bool:
	var along := Vector2i(d.y, d.x)
	for u in range(-2, 3):
		var o: Vector2i = p + along * u
		var i: Vector2i = p - d + along * u
		if g.get_tile(o) != (ShipGrid.Tile.DOOR if u == 0 else ShipGrid.Tile.WALL):
			return false
		if g.get_tile(i) != (ShipGrid.Tile.DOOR if u == 0 else ShipGrid.Tile.WALL):
			return false
		if g.device_at(o) != g.device_at(p) or g.device_at(i) != g.device_at(p):
			return false
	return g.get_tile(p - d * 2) == ShipGrid.Tile.FLOOR

func _sealed() -> bool:
	A.topology()
	for r in A.rooms.size():
		if ship.grid.zone[A.rooms[r].cells[0]] == 0 and A.room_leak(r) != "":
			return false
	return true

func _initialize() -> void:
	await process_frame
	await process_frame
	save = root.get_node("SaveSystem")
	save.slot = 923
	gs = root.get_node("GameState")
	ship = root.get_node("ShipSystem")
	CS = root.get_node("ShipConstructionSystem")
	R = root.get_node("RemovalSystem")
	P = root.get_node("PhysicsSystem")
	A = root.get_node("AtmosphereSystem")
	root.get_node("Settings").meteors = false
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(String(t)))
	_fresh()
	var g = ship.grid

	# 1) Startschiff: zwei Andockschleusen 5×2, dicht
	var ports: Array = ship.ports()
	_check("Zwei Andockschleusen am Startschiff", ports.size() == 2)
	for p in ports:
		var dev = g.devices[p.i]
		_check("Schleuse %s: 5×2 = 10 Felder, ein Gerät, Außentür in der Wand" % str(p.dir), dev.cells().size() == 10 and _layout_ok(g, p.pos, p.dir) and g.get_tile(p.pos + p.dir) == ShipGrid.Tile.SPACE)
	var right: Dictionary = ports.filter(func(p): return p.dir == Vector2i(1, 0))[0]
	_check("Ungekoppelt: Außentür gesperrt, Innentür begehbar", not g.walkable(right.pos) and g.walkable(right.pos - right.dir))
	_check("Druckhülle dicht", _sealed())
	var inner_p: float = g.pressure(g.idx(right.pos - right.dir * 2))
	_secs(60)
	_check("… auch nach einer Minute (%.0f kPa)" % g.pressure(g.idx(right.pos - right.dir * 2)), absf(g.pressure(g.idx(right.pos - right.dir * 2)) - inner_p) < 1.0)

	# 2) Bauen: Vorschau 10 Felder, Abweisungen
	var top := C(x0 + 12, y0)                      # obere Außenwand im Cockpit
	_check("Bauplatz oben in der Außenwand gültig (%s)" % CS.place_reason("dev:dockport", top), CS.can_place("dev:dockport", top))
	var prev: Array = CS.cells_of("dockport", top, 0)
	_check("Vorschau zeigt alle 10 Felder", prev.size() == 10 and prev[0] == top)
	_check("Innenwand abgewiesen", not CS.can_place("dev:dockport", C(x0 + 10, y0 + 2)))
	_check("Ecke (keine 5 geraden Wandfelder) abgewiesen", not CS.can_place("dev:dockport", C(x0 + 15, y0)))
	_check("Boden abgewiesen", not CS.can_place("dev:dockport", C(x0 + 12, y0 + 2)))
	var blocker = g.place_device("bed", top + Vector2i(1, 1))
	_check("Belegte Innenreihe abgewiesen (%s)" % CS.place_reason("dev:dockport", top), not CS.can_place("dev:dockport", top))
	g.remove_device(blocker)
	for dv in g.devices.values():
		if dv.type == "crate" and g.zone[g.idx(dv.pos)] == 0:
			dv.inv.add("plate", 6, 90.0)
			dv.inv.add("circuit", 2, 90.0)
			break
	_check("Bau geplant", CS.place("dev:dockport", top))
	_check("Crew baut die Schleuse", _until_done(top))
	_secs(1)
	_check("Neue Schleuse 5×2 an der Wand, Richtung nach oben", g.device_at(top) != null and g.device_at(top).type == "dockport" and _layout_ok(g, top, Vector2i(0, -1)))
	_check("Jetzt drei Schleusen, Hülle dicht", ship.ports().size() == 3 and _sealed())

	# 3) Abbauen über ein Seitenfeld, wieder einbauen
	_check("Abbau über ein Seitenfeld der Schleuse", R.order("uninstall", top + Vector2i(-2, 1)) == "" and CS.jobs.has(g.idx(top)))
	_until_done(top)
	_secs(1)
	var restored: bool = g.get_tile(top) == ShipGrid.Tile.WALL
	for u in range(-2, 3):
		restored = restored and g.get_tile(top + Vector2i(u, 1)) == ShipGrid.Tile.FLOOR and g.get_tile(top + Vector2i(u, 0)) == ShipGrid.Tile.WALL
	_check("Abgebaut: Außenwand geschlossen, Innenreihe wieder Boden, Hülle dicht", g.device_at(top) == null and restored and _sealed())
	var pk := 0
	for i in g.piles:
		pk += g.piles[i].count("pk_dockport")
	_check("Ein Schleusen-Gegenstand liegt an Bord", pk == 1)
	_check("Wiedereinbau geplant (%s)" % R.install_reason("pk_dockport", top), CS.place("install:pk_dockport", top))
	_until_done(top)
	_secs(1)
	_check("Wieder eingebaut als 5×2", g.device_at(top) != null and _layout_ok(g, top, Vector2i(0, -1)))

	# 4) Koppeln: Station Tür an Tür an der Außentür, Durchgang
	Config.ENABLE_STATION = true
	seat_pilot()
	P.request_undock()
	_secs(20)
	var t0: Dictionary = P.loc_state(P.loc("tycho"), P.secs())
	P.vel = t0.vel
	P.pos = t0.pos + Vector2(0.05, 0)
	P.angle = P.dock_alignment("tycho").angle
	_check("Angedockt (%s)" % P.dock_block_reason("tycho"), P.dock("tycho"))
	var st = root.get_node("StationSystem")
	var hp: Vector2i = g.pos(st.hatch)
	var hd = g.devices[st.hatch]
	_check("Station koppelt an der Außentür einer 5×2-Schleuse", st.active() and hd.type == "dockport" and g.linked.has(st.hatch)
		and g.get_tile(hp + hd.outward()) == ShipGrid.Tile.DOOR and g.zone[g.idx(hp + hd.outward())] == 3)
	_check("Gekoppelt: Außentür begehbar, Weg vom Schiff durch beide Türen auf die Station", g.walkable(hp)
		and not ship.find_path(hp - hd.outward() * 2, hp + hd.outward() * 2).is_empty())
	_check("Schleuse lässt sich angedockt nicht abbauen", R.reason("uninstall", hp) != "")
	Config.ENABLE_STATION = false
	st.clear()

	# 5) Alter Spielstand (feines Raster) mit 1-Feld-Schleusen: umstellen bzw. als Gegenstand
	_fresh()
	g = ship.grid
	save.save_game(true)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save.path()))
	# beide Schleusen in die alte Form bringen: nur die Tür in der Wand, Innenreihe Boden
	var w := int(data.ship.w)
	var blocked_pos := Vector2i(-1, -1)
	for dd in data.ship.devices:
		if dd.type != "dockport":
			continue
		dd.erase("shape")
		var p := Vector2i(int(dd.x), int(dd.y))
		var d: Vector2i = -Device.PUSH_DIRS[int(dd.rot)]
		var along := Vector2i(d.y, d.x)
		for u in range(-2, 3):
			data.ship.tiles[(p - d + along * u).y * w + (p - d + along * u).x] = ShipGrid.Tile.FLOOR
		dd.rot = 0
		if d == Vector2i(0, 1):
			blocked_pos = p
	# vor die untere Schleuse ein Gerät stellen: dort ist kein Platz für 5×2
	var bed: Dictionary = {}
	for dd in data.ship.devices:
		if dd.type == "bed":
			bed = dd.duplicate()
	bed.x = blocked_pos.x + 1
	bed.y = blocked_pos.y - 1
	data.ship.devices.append(bed)
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	gs.new_game()
	save.load_game(true)
	g = ship.grid
	_check("Umstellung: eine Schleuse umgebaut, eine als Gegenstand (%s)" % str(g.migrated), g.migrated.converted == 1 and g.migrated.packed == 1)
	var rp: Array = ship.ports()
	_check("Rechte Schleuse jetzt 5×2 an derselben Außentür", rp.size() == 1 and rp[0].pos == right.pos and _layout_ok(g, rp[0].pos, rp[0].dir))
	var pk2 := 0
	for i in g.piles:
		pk2 += g.piles[i].count("pk_dockport")
	_check("Untere: Wand geschlossen, Schleuse liegt einmal als Gegenstand an Bord", g.get_tile(blocked_pos) == ShipGrid.Tile.WALL and pk2 == 1 and _sealed())
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	_check("Erneut geladen: keine zweite Umstellung", ship.grid.migrated.converted == 0 and ship.grid.migrated.packed == 0 and ship.ports().size() == 1)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
