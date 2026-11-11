## Tests für Andockschleusen: Andocken nur mit Schleuse, Tür an Tür, keine
## zusätzlichen Felder, Abdocken ohne Rest, Wrack an der Schleuse, alte Spielstände.
##   godot --headless --path . --script res://tests/boot.gd -- test_docking
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var toasts: Array[String] = []
var gs
var ship
var st
var P
var crew
var CS

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _run(seconds: float) -> void:
	for i in int(seconds):
		gs.step(1.0 / 60.0)

## Alle Felder einer Zone (Feldart je Index)
func _zone_tiles(z: int) -> Dictionary:
	var g = ship.grid
	var out := {}
	for i in g.tiles.size():
		if g.zone[i] == z and g.tiles[i] != 0:
			out[i] = g.tiles[i]
	return out

func _count_zone(z: int) -> int:
	return _zone_tiles(z).size()

func _fresh():
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var m = crew.player()
	m.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	m.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	_run(2)
	return m

func _initialize() -> void:
	await process_frame
	await process_frame
	# Eigener Speicherplatz: Tests überschreiben keine echten Spielstände und laufen parallel
	root.get_node("SaveSystem").slot = 905
	# Diese Tests prüfen auch die (vorübergehend abgeschaltete) Station und das Wrack
	Config.ENABLE_STATION = true
	Config.ENABLE_WRECK = true
	gs = root.get_node("GameState")
	ship = root.get_node("ShipSystem")
	st = root.get_node("StationSystem")
	P = root.get_node("PhysicsSystem")
	crew = root.get_node("CrewSystem")
	CS = root.get_node("ShipConstructionSystem")
	var salv = root.get_node("SalvageSystem")
	root.get_node("Settings").meteors = false
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(String(t)))

	# 1) Start: zwei Schleusen, Station Tür an Tür, kein Steg
	var mira = _fresh()
	var g = ship.grid
	var ports: Array = ship.ports()
	_check("Startschiff hat zwei Andockschleusen (%d)" % ports.size(), ports.size() == 2)
	_check("Keine Steg-Felder (Zone 2) mehr", _count_zone(2) == 0)
	var sp: Dictionary = {}
	for p in ports:
		if g.linked.has(p.i) and st.is_hatch(p.i):
			sp = p
	_check("Station hängt an einer Schleuse", st.active() and not sp.is_empty())
	var d: Vector2i = sp.pos + sp.dir
	_check("Tür an Tür: Stationstür direkt vor der Schleuse", g.get_tile(d) == ShipGrid.Tile.DOOR and g.zone[g.idx(d)] == 3)
	_check("… und dahinter gleich der Stationsgang", g.get_tile(d + sp.dir) == ShipGrid.Tile.FLOOR and g.zone[g.idx(d + sp.dir)] == 3)
	var wp: Dictionary = {}
	for p in ports:
		if p.i == salv.port:
			wp = p
	_check("Wrack hängt an der Schleuse nach unten, Wracktür direkt darunter", not wp.is_empty() and wp.dir == Vector2i(0, 1)
		and g.get_tile(wp.pos + Vector2i(0, 1)) == ShipGrid.Tile.DOOR and g.zone[g.idx(wp.pos + Vector2i(0, 1))] == 1)

	# 2) Laufen: durch die Schleuse in die Station und zurück
	var corridor: Vector2i = d + sp.dir * 2
	_check("Weg zur Station über die Schleuse", mira.order_move(corridor))
	_run(30)
	_check("Mira steht in der Station", g.zone[g.idx(mira.tile())] == 3)
	_check("… ohne Raumanzug", mira.suit == null)
	mira.order_move(ship.spawn_point())
	_run(30)
	_check("… und ist zurück an Bord", g.zone[g.idx(mira.tile())] == 0)
	var wreck_in: Vector2i = wp.pos + Vector2i(0, 2)
	_check("Weg ins Wrack über die untere Schleuse", not ship.find_path(mira.tile(), wreck_in).is_empty())

	# 3) Abdocken: nichts bleibt zurück, Schleuse bleibt
	var ship_tiles: Dictionary = _zone_tiles(0)
	var hatch: int = st.hatch
	_run(1)
	seat_pilot()   # Pilot am Steuerpult (Flugbefehle nur dort)
	_check("Abdocken klappt", P.request_undock())
	_check("Keine Stationsfelder mehr", _count_zone(3) == 0 and not st.active())
	_check("Kein Wrack mehr an der Leine (am Ort abgelegt)", _count_zone(1) == 0 and not g.linked.has(salv.port if salv.port >= 0 else -1))
	_check("Schiffsfelder unverändert", _zone_tiles(0) == ship_tiles)
	_check("Schleuse bleibt, nur gelöst", g.devices.has(hatch) and g.devices[hatch].type == "dockport" and not g.linked.has(hatch) and g.linked.is_empty())
	_check("Gelöste Schleuse ist nicht begehbar (kein Weg ins All)", not g.walkable(g.pos(hatch)))
	var nonspace := 0
	for i in g.tiles.size():
		if g.tiles[i] != 0:
			nonspace += 1
	_check("Keinerlei zusätzliche Felder außerhalb des Schiffs", nonspace == ship_tiles.size())

	# 4) Wieder andocken (bewusst, nach der Sperrzeit) – wieder bündig, wieder kein Extra-Feld
	_run(20)
	var t0: Dictionary = P.loc_state(P.loc("tycho"), P.secs())
	P.pos = t0.pos
	P.vel = t0.vel
	_check("Wieder andocken klappt", P.dock("tycho"))
	_check("Schiffsfelder auch nach erneutem Andocken unverändert", _zone_tiles(0) == ship_tiles)
	_check("Nur Station und Wrack kamen dazu", _count_zone(2) == 0 and _count_zone(3) > 0)

	# 5) Ohne Schleuse kein Andocken
	mira = _fresh()
	g = ship.grid
	_run(1)
	seat_pilot()   # Pilot am Steuerpult (Flugbefehle nur dort)
	P.request_undock()
	for p in ship.ports():
		g.devices.erase(p.i)
		g.tiles[p.i] = ShipGrid.Tile.WALL
	root.get_node("EventBus").ship_changed.emit()
	toasts.clear()
	_run(20)
	_check("Ohne Schleuse: Andocken verweigert", not P.dock("tycho", true) and P.docked == "")
	_check("… mit Meldung (%s)" % (toasts[-1] if not toasts.is_empty() else "-"), toasts.any(func(t): return "Keine Andockschleuse vorhanden" in t))
	_check("… und kein einziges neues Feld", _count_zone(3) == 0 and _count_zone(1) == 0)

	# 6) Schleuse bauen: nur in der Außenwand
	var x0: int = (g.width / Config.GRID_SCALE - 16) / 2
	var y0: int = (g.height / Config.GRID_SCALE - 10) / 2
	var hull_east := C(x0 + 15, y0 + 5)
	_check("Platzierung in der Außenwand erlaubt", CS.can_place("dev:dockport", hull_east))
	_check("Nicht in einer Innenwand", not CS.can_place("dev:dockport", C(x0 + 10, y0 + 2)))
	_check("Nicht auf Boden", not CS.can_place("dev:dockport", C(x0 + 4, y0 + 6)))
	_check("Nicht in einer Ecke", not CS.can_place("dev:dockport", C(x0 + 15, y0)))
	CS.place("dev:dockport", hull_east)
	var built := false
	for k in 60 * 20:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(g.idx(hull_east)):
			built = true
			break
	_check("Crew baut die Schleuse (Tür mit Schleuse in der Wand)", built and g.get_tile(hull_east) == ShipGrid.Tile.DOOR and g.device_at(hull_east) != null and g.device_at(hull_east).type == "dockport")
	_check("Mit gebauter Schleuse klappt das Andocken", P.dock("tycho", true) and st.active() and g.linked.has(g.idx(hull_east)))
	_check("Ohne Schleuse nach unten: kein Wrack, mit Meldung", _count_zone(1) == 0)
	toasts.clear()
	_check("Bergungsrecht ohne Schleuse nach unten: abgelehnt", not salv.generate() and toasts.any(func(t): return "nach unten" in t))
	_check("Angedockte Schleuse lässt sich nicht abbauen", root.get_node("RemovalSystem").reason("uninstall", hull_east) == "Die Schleuse ist gerade angedockt. Erst abdocken.")

	# 7) Speichern und Laden mit Andockung
	mira = _fresh()
	g = ship.grid
	var save = root.get_node("SaveSystem")
	var z3 := _count_zone(3)
	var z1 := _count_zone(1)
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	g = ship.grid
	_check("Nach dem Laden: Station und Wrack wieder Tür an Tür (%d / %d Felder)" % [_count_zone(3), _count_zone(1)],
		_count_zone(3) == z3 and _count_zone(1) == z1 and g.linked.size() == 2)
	_check("… und kein Steg", _count_zone(2) == 0)

	# 8) Alter Spielstand mit Steg, ohne Schleusen, Wrack an der alten Stelle
	mira = _fresh()
	g = ship.grid
	_run(1)
	st.clear()
	salv.clear()
	for p in ship.ports():
		g.devices.erase(p.i)
		g.tiles[p.i] = ShipGrid.Tile.WALL
	g.linked.clear()
	# Steg links und Leine nach unten (Zone 2), mit Mondmüll
	for y in range(y0 + 1, 30):
		var q := Vector2i(20, y)
		g.tiles[g.idx(q)] = ShipGrid.Tile.FLOOR
		g.zone[g.idx(q)] = 2
	g.drop_items(Vector2i(20, y0 + 1), "scrap", 4, 30.0)
	# Altes Wrack mit Tür bei (20, 30)
	for y in range(30, 36):
		for x in range(14, 27):
			var edge := x == 14 or x == 26 or y == 30 or y == 35
			g.tiles[g.idx(Vector2i(x, y))] = ShipGrid.Tile.WALL if edge else ShipGrid.Tile.FLOOR
			g.zone[g.idx(Vector2i(x, y))] = 1
	g.tiles[g.idx(Vector2i(20, 30))] = ShipGrid.Tile.DOOR
	g.place_device("crate", Vector2i(16, 33))
	save.save_game(true)
	var path: String = save.path()
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	data.erase("salvage")
	data.erase("station")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var scrap_total := 0
	gs.new_game()
	save.load_game(true)
	g = ship.grid
	for i in g.piles:
		scrap_total += g.piles[i].count("scrap")
	_check("Alter Spielstand: Steg-Felder entfernt", _count_zone(2) == 0)
	_check("… Mondmüll ins Schiff gerettet (%d Schrott)" % scrap_total, scrap_total >= 4)
	_check("… zwei Schleusen nachgerüstet", ship.ports().size() == 2)
	_check("… Station wieder angedockt", st.active() and g.linked.has(st.hatch))
	var crate_ok := false
	for dv in g.devices.values():
		if dv.type == "crate" and g.zone[g.idx(dv.pos)] == 1:
			crate_ok = true
	_check("… altes Wrack an die untere Schleuse gehängt (Kiste dabei)", salv.port >= 0 and crate_ok
		and g.get_tile(g.pos(salv.port) + Vector2i(0, 1)) == ShipGrid.Tile.DOOR)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
