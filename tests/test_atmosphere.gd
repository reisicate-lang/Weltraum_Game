## Abnahmetests Atmosphäre und Raumdruck (Bauplan „Atmosphäre und Raumdruck“)
## Fester Simulationsschritt (1 Spielsekunde), Crew/Feuer/Gasgeräte aus
## (außer beim Wiederbefüllen). Geprüft werden kPa, Vakuumweg und Gasmengen.
##   godot --headless --path . --script res://tests/boot.gd -- test_atmosphere
extends "res://tests/test_base.gd"

const T := ShipGrid.Tile
var ok_count := 0
var fail_count := 0
var atm
var g: ShipGrid

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

## Neues leeres Testraster (alles Weltraum)
func _grid() -> void:
	g = ShipGrid.new(24, 16)
	root.get_node("ShipSystem").grid = g
	root.get_node("StationSystem").reset()
	root.get_node("ShipConstructionSystem").jobs.clear()
	root.get_node("CrewSystem").crew.clear()
	root.get_node("PhysicsSystem").docked = ""
	root.get_node("EventBus").ship_changed.emit()

## Raum mit Innenfläche x0..x1, y0..y1, Wände drumherum
func _room(x0: int, y0: int, x1: int, y1: int) -> Array:
	var cells: Array = []
	for y in range(y0 - 1, y1 + 2):
		for x in range(x0 - 1, x1 + 2):
			var inside := x >= x0 and x <= x1 and y >= y0 and y <= y1
			if inside:
				g.tiles[g.idx(Vector2i(x, y))] = T.FLOOR
				cells.append(g.idx(Vector2i(x, y)))
			elif g.tiles[g.idx(Vector2i(x, y))] == T.SPACE:
				g.tiles[g.idx(Vector2i(x, y))] = T.WALL
	return cells

func _fill(cells: Array, kpa: float) -> void:
	for i in cells:
		g.o2[i] = kpa * 0.21
		g.n2[i] = kpa * 0.79
		g.co2[i] = 0.0

func _sim(seconds: int, advance_time := false) -> void:
	for k in seconds:
		if advance_time:
			root.get_node("GameState").time += 1.0 / 60.0
		atm.simulate(1.0 / 60.0)

func _mean(cells: Array) -> float:
	var s := 0.0
	for i in cells:
		s += g.pressure(i)
	return s / cells.size()

func _total(cells: Array) -> Vector3:
	return atm.gas_sum(cells)

func _same(a: Vector3, b: Vector3, tol := 0.001) -> bool:
	return absf(a.x - b.x) <= tol and absf(a.y - b.y) <= tol and absf(a.z - b.z) <= tol

## Auftrag wie von der Crew abschließen (ohne Crew)
func _complete(kind: String, p: Vector2i, target: String, worker: Vector2i) -> void:
	var job := {"kind": kind, "x": p.x, "y": p.y, "target": target, "tool": "", "progress": 1.0, "claimed_by": -1,
		"retry_at": 0.0, "paid": true, "need": 1.0}
	if kind == "install":
		job.item = target
		job.packed = {"type": target, "qty": 1, "cond": 100.0}
	root.get_node("ShipConstructionSystem").complete(job, worker, null)

func _initialize() -> void:
	await process_frame
	await process_frame
	# Eigener Speicherplatz: Tests überschreiben keine echten Spielstände und laufen parallel
	root.get_node("SaveSystem").slot = 902
	atm = root.get_node("AtmosphereSystem")
	root.get_node("Settings").meteors = false
	var CS = root.get_node("ShipConstructionSystem")

	# 1) Dichte Kabine
	_grid()
	var cab := _room(4, 4, 7, 7)
	_fill(cab, 100.0)
	_sim(60)
	var dev := 0.0
	for i in cab:
		dev = maxf(dev, absf(g.pressure(i) - 100.0))
	_check("Dichte Kabine: Abweichung nach 60 s %.5f kPa (≤ 0,01)" % dev, dev <= 0.01)
	_check("Dichte Kabine: kein Vakuumweg", atm.room_leak(atm.room_of(cab[0])) == "" and atm.vented.o2 == 0.0)

	# 2) Tür öffnen und schließen: zwei gleich große Kammern, 100 und 20 kPa
	_grid()
	var a := _room(4, 4, 7, 7)
	var b := _room(9, 4, 12, 7)
	var door := g.idx(Vector2i(8, 5))
	g.tiles[door] = T.DOOR
	_fill(a, 100.0)
	_fill(b, 20.0)
	var all: Array = a + b + [door]
	var tot0 := _total(all)
	_check("Zwei getrennte Räume durch die Tür", atm.room_of(a[0]) != atm.room_of(b[0]))
	g.door_open_until[door] = 1e12
	var diff0 := _mean(a) - _mean(b)
	_sim(30)
	var diff1 := _mean(a) - _mean(b)
	_check("Offene Tür verringert die Differenz (%.1f → %.1f kPa in 30 s)" % [diff0, diff1], diff1 < diff0 - 0.5)
	_check("… Gasmenge je Gasart bleibt erhalten", _same(_total(all), tot0))
	# Tür schließen, Schlitz zu: dicht
	g.door_open_until[door] = 0.0
	atm.set_vent(door, true)
	var ma := _mean(a)
	var mb := _mean(b)
	_sim(60)
	_check("Dichte Tür: Raumdrücke konstant (%.4f / %.4f kPa Änderung)" % [absf(_mean(a) - ma), absf(_mean(b) - mb)],
		absf(_mean(a) - ma) <= 0.01 and absf(_mean(b) - mb) <= 0.01)
	# Schlitz offen: nur schwacher Austausch
	atm.set_vent(door, false)
	var d_before := _mean(a) - _mean(b)
	_sim(30)
	var d_vent := d_before - (_mean(a) - _mean(b))
	_check("Lüftungsschlitz: schwacher Austausch läuft weiter (%.2f kPa in 30 s, offen waren es %.2f)" % [d_vent, diff0 - diff1],
		d_vent > 0.0 and d_vent < (diff0 - diff1) * 0.5)
	_check("… und bleibt als schwacher Gasweg sichtbar", atm.rooms[atm.room_of(a[0])].links.get(atm.room_of(b[0])) == "vent")
	# Timer der Tür läuft ab
	_grid()
	a = _room(4, 4, 7, 7)
	b = _room(9, 4, 12, 7)
	door = g.idx(Vector2i(8, 5))
	g.tiles[door] = T.DOOR
	g.vent_closed[door] = 1
	_fill(a, 100.0)
	_fill(b, 20.0)
	var gs = root.get_node("GameState")
	g.door_open_until[door] = gs.time + 0.2   # 12 Spielsekunden offen
	_sim(15, true)
	ma = _mean(a)
	_sim(60, true)
	_check("Tür-Timer abgelaufen: danach kein Austausch mehr (%.4f kPa)" % absf(_mean(a) - ma), not g.door_open(door) and absf(_mean(a) - ma) <= 0.01 and ma < 100.0)

	# 3) Innenwand abbauen
	_grid()
	a = _room(4, 4, 7, 7)
	b = _room(9, 4, 12, 7)
	_fill(a, 100.0)
	_fill(b, 60.0)
	var wall := Vector2i(8, 5)
	all = a + b + [g.idx(wall)]
	tot0 = _total(all)
	var room_before: int = atm.room_of(a[0])
	# Vormerken und abbrechen ändert nichts
	CS.jobs[g.idx(wall)] = {"kind": "uninstall", "x": wall.x, "y": wall.y, "target": "tile:wall", "tool": "", "progress": 0.5,
		"claimed_by": -1, "retry_at": 0.0, "paid": true, "need": 1.0}
	_sim(5)
	_check("Vorgemerkter Abbau: Wand steht, Räume getrennt", g.tiles[g.idx(wall)] == T.WALL and atm.room_of(a[0]) != atm.room_of(b[0]))
	CS.cancel(CS.jobs[g.idx(wall)])
	_check("Abgebrochener Abbau: nichts verändert", g.tiles[g.idx(wall)] == T.WALL and atm.room_of(a[0]) == room_before)
	_complete("uninstall", wall, "tile:wall", Vector2i(7, 5))
	_check("Nach Abschluss: ein gemeinsamer Raum", atm.room_of(a[0]) == atm.room_of(b[0]) and atm.room_of(g.idx(wall)) == atm.room_of(a[0]))
	_check("… ohne Vakuumkante", atm.room_leak(atm.room_of(a[0])) == "")
	_sim(120)
	_check("… Gasmenge je Gasart erhalten", _same(_total(all), tot0))
	_check("… Druckdifferenz nimmt ab (40,0 → %.1f kPa nach 120 s)" % (_mean(a) - _mean(b)), _mean(a) - _mean(b) < 39.0)

	# 4) Außenwand abbauen; Kontrollkammer hinter dichter Tür
	_grid()
	a = _room(4, 4, 7, 7)
	b = _room(9, 4, 12, 7)
	door = g.idx(Vector2i(8, 5))
	g.tiles[door] = T.DOOR
	g.vent_closed[door] = 1
	_fill(a, 100.0)
	_fill(b, 100.0)
	var outer := Vector2i(3, 5)
	_complete("uninstall", outer, "tile:wall", Vector2i(4, 5))
	_check("Außenwand wird Boden mit Vakuumkante", g.tiles[g.idx(outer)] == T.FLOOR and atm.vacuum_edges(g.idx(outer)) == 1)
	_check("Kabine hat einen direkten Vakuumweg", atm.room_leak(atm.room_of(a[0])) == "direct")
	_sim(30)
	_check("Kabinendruck sinkt (%.1f kPa nach 30 s)" % _mean(a), _mean(a) < 99.0 and atm.vented.o2 > 0.0)
	_check("Kontrollkammer hinter dichter Tür hält Druck (%.3f kPa)" % _mean(b), absf(_mean(b) - 100.0) <= 0.01 and atm.room_leak(atm.room_of(b[0])) == "")
	# Tür öffnen: Kontrollkammer bekommt indirekten Vakuumweg; schließen isoliert wieder
	g.door_open_until[door] = 1e12
	_check("Offene Tür: Kontrollkammer verliert über die Tür", atm.room_leak(atm.room_of(b[0])) == "door")
	_sim(10)
	g.door_open_until[door] = 0.0
	mb = _mean(b)
	_sim(30)
	_check("Tür wieder zu: Kontrollkammer isoliert (%.4f kPa Änderung)" % absf(_mean(b) - mb), atm.room_leak(atm.room_of(b[0])) == "" and absf(_mean(b) - mb) <= 0.01)

	# 5) Boden in der Raummitte abbauen (intakte Außenwände)
	_grid()
	a = _room(4, 4, 8, 8)
	_fill(a, 100.0)
	var hole := Vector2i(6, 6)
	CS.jobs[g.idx(hole)] = {"kind": "uninstall", "x": hole.x, "y": hole.y, "target": "tile:floor", "tool": "", "progress": 0.3,
		"claimed_by": -1, "retry_at": 0.0, "paid": true, "need": 1.0}
	_sim(10)
	_check("Vorgemerkter Bodenabbau: kein Leck", atm.room_leak(atm.room_of(a[0])) == "" and absf(_mean(a) - 100.0) <= 0.01)
	CS.cancel(CS.jobs[g.idx(hole)])
	_complete("uninstall", hole, "tile:floor", Vector2i(5, 6))
	var nb := [g.idx(hole + Vector2i(1, 0)), g.idx(hole + Vector2i(-1, 0)), g.idx(hole + Vector2i(0, 1)), g.idx(hole + Vector2i(0, -1))]
	_check("Loch ist Weltraum, die vier Nachbarn haben Vakuumkanten", g.tiles[g.idx(hole)] == T.SPACE and nb.all(func(i): return atm.vacuum_edges(i) == 1))
	_check("Diagonale Nachbarn bekommen keine Vakuumkante", atm.vacuum_edges(g.idx(hole + Vector2i(1, 1))) == 0)
	_sim(20)
	_check("Raumdruck sinkt trotz intakter Außenwände (%.1f kPa nach 20 s)" % _mean(a.filter(func(i): return g.holds_air(i))), _mean(a.filter(func(i): return g.holds_air(i))) < 99.0)
	# Diagonal anliegende, dichte Tasche verliert nichts:
	# Raum bis (8,8); das Eckfeld (8,8) wird das Loch. Tasche (9,9) berührt es nur diagonal,
	# ihre vier Seiten (9,8), (8,9), (10,9), (9,10) sind Wand.
	_grid()
	a = _room(4, 4, 8, 8)
	var pocket := _room(9, 9, 9, 9)
	_fill(a, 100.0)
	_fill(pocket, 100.0)
	var pocket0 := _total(pocket)
	_check("Tasche ist ein eigener dichter Raum", atm.room_of(pocket[0]) != atm.room_of(a[0]) and atm.room_leak(atm.room_of(pocket[0])) == "")
	_complete("uninstall", Vector2i(8, 8), "tile:floor", Vector2i(7, 8))
	_sim(30)
	_check("Nur diagonal angrenzende dichte Tasche verliert kein Gas", _same(_total(pocket), pocket0, 0.0001) and atm.room_leak(atm.room_of(pocket[0])) == "")
	_check("… der Raum selbst leckt", atm.room_leak(atm.room_of(a[0])) == "direct")

	# 6) Abdichten und wiederbefüllen
	_grid()
	a = _room(4, 4, 8, 8)
	_fill(a, 100.0)
	hole = Vector2i(6, 6)
	_complete("uninstall", hole, "tile:floor", Vector2i(5, 6))
	var air_cells: Array = a.filter(func(i): return g.holds_air(i))
	var leak_s := 0
	while _mean(air_cells) > 60.0 and leak_s < 1800:
		_sim(10)
		leak_s += 10
	var rest := _mean(air_cells)
	print("        (Leck bis %.1f kPa dauerte %d Spielsekunden)" % [rest, leak_s])
	_check("Restdruck messbar beim Verschluss (%.1f kPa)" % rest, rest > 10.0)
	_complete("install", hole, "pk_tile_floor", Vector2i(5, 6))
	_sim(1)
	_check("Ab dem nächsten Schritt kein Vakuumfluss (%.6f)" % atm.last_vented, atm.last_vented == 0.0 and atm.room_leak(atm.room_of(a[0])) == "")
	var t_closed := _total(a)
	_sim(60)
	_check("Ohne Quelle bleibt die Gasmenge konstant", _same(_total(a), t_closed))
	var oxy = root.get_node("OxygenSystem")
	var tank_p := Vector2i(4, 4)
	var tank := g.place_device("airtank", tank_p)
	var stock0: float = tank.stock
	var t_before := _total(a)
	for k in 60:
		oxy.step(1.0 / 60.0)
		atm.simulate(1.0 / 60.0)
	var t_after := _total(a)
	_check("Voller Lufttank: O₂ und N₂ steigen (%.1f → %.1f / %.1f → %.1f)" % [t_before.x, t_after.x, t_before.y, t_after.y], t_after.x > t_before.x and t_after.y > t_before.y)
	_check("… der Tankvorrat sinkt (%.0f → %.0f)" % [stock0, tank.stock], tank.stock < stock0)
	tank.stock = 0.0
	t_before = _total(a)
	for k in 60:
		oxy.step(1.0 / 60.0)
		atm.simulate(1.0 / 60.0)
	_check("Leerer Tank: kein Anstieg", _same(_total(a), t_before))

	# 7) Zwei Lecks und Spielstand laden
	_grid()
	a = _room(4, 4, 9, 8)
	_fill(a, 100.0)
	var h1 := Vector2i(5, 6)
	var h2 := Vector2i(8, 6)
	_complete("uninstall", h1, "tile:floor", Vector2i(5, 5))
	_complete("uninstall", h2, "tile:floor", Vector2i(8, 5))
	_sim(2)
	_complete("install", h1, "pk_tile_floor", Vector2i(5, 5))
	_sim(1)
	_check("Erstes Loch zu: zweites leckt weiter (%.3f kPa im letzten Schritt)" % atm.last_vented, atm.last_vented > 0.0 and atm.room_leak(atm.room_of(a[0])) == "direct")
	var save = root.get_node("SaveSystem")
	save.save_game(true)
	var snap: Array = []
	for i in a:
		snap.append(Vector3(g.o2[i], g.n2[i], g.co2[i]))
	_grid()
	save.load_game(true)
	g = root.get_node("ShipSystem").grid
	var same := true
	for k in a.size():
		var v := Vector3(g.o2[a[k]], g.n2[a[k]], g.co2[a[k]])
		if not _same(v, snap[k], 0.0001):
			same = false
	_check("Nach dem Laden: gespeicherte Partialdrücke sind der Startzustand", same)
	_check("… derselbe Vakuumweg wird erkannt (nur am zweiten Loch)", g.tiles[g.idx(h2)] == T.SPACE and g.tiles[g.idx(h1)] == T.FLOOR
		and atm.vacuum_edges(g.idx(h2 + Vector2i(1, 0))) == 1 and atm.vacuum_edges(g.idx(h1 + Vector2i(1, 0))) == 0 and atm.room_leak(atm.room_of(a[0])) == "direct")
	_sim(1)
	_check("… und leckt dort weiter", atm.last_vented > 0.0)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
