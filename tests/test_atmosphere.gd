## Acceptance tests for atmosphere and room pressure (plan "Atmosphere and room pressure")
## Fixed simulation step (1 game second), crew/fire/gas devices off
## (except when refilling). Checked are kPa, vacuum path and gas amounts.
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

## New empty test grid (all space)
func _grid() -> void:
	g = ShipGrid.new(24, 16)
	root.get_node("ShipSystem").grid = g
	root.get_node("StationSystem").reset()
	root.get_node("ShipConstructionSystem").jobs.clear()
	root.get_node("CrewSystem").crew.clear()
	root.get_node("PhysicsSystem").docked = ""
	root.get_node("EventBus").ship_changed.emit()

## Room with inner area x0..x1, y0..y1, walls around it
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

## Complete a job as the crew would (without crew)
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
	# Own save slot: tests do not overwrite real saves and can run in parallel
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
	_check("Airtight cabin: deviation after 60 s %.5f kPa (≤ 0.01)" % dev, dev <= 0.01)
	_check("Airtight cabin: no vacuum path", atm.room_leak(atm.room_of(cab[0])) == "" and atm.vented.o2 == 0.0)

	# 2) Open and close a door: two equally large chambers, 100 and 20 kPa
	_grid()
	var a := _room(4, 4, 7, 7)
	var b := _room(9, 4, 12, 7)
	var door := g.idx(Vector2i(8, 5))
	g.tiles[door] = T.DOOR
	_fill(a, 100.0)
	_fill(b, 20.0)
	var all: Array = a + b + [door]
	var tot0 := _total(all)
	_check("Two separate rooms through the door", atm.room_of(a[0]) != atm.room_of(b[0]))
	g.door_open_until[door] = 1e12
	var diff0 := _mean(a) - _mean(b)
	_sim(30)
	var diff1 := _mean(a) - _mean(b)
	_check("Open door reduces the difference (%.1f → %.1f kPa in 30 s)" % [diff0, diff1], diff1 < diff0 - 0.5)
	_check("… the amount per gas is conserved", _same(_total(all), tot0))
	# Close the door, vent closed: airtight
	g.door_open_until[door] = 0.0
	atm.set_vent(door, true)
	var ma := _mean(a)
	var mb := _mean(b)
	_sim(60)
	_check("Airtight door: room pressures constant (%.4f / %.4f kPa change)" % [absf(_mean(a) - ma), absf(_mean(b) - mb)],
		absf(_mean(a) - ma) <= 0.01 and absf(_mean(b) - mb) <= 0.01)
	# Vent open: only weak exchange
	atm.set_vent(door, false)
	var d_before := _mean(a) - _mean(b)
	_sim(30)
	var d_vent := d_before - (_mean(a) - _mean(b))
	_check("Door vent: weak exchange continues (%.2f kPa in 30 s, open it was %.2f)" % [d_vent, diff0 - diff1],
		d_vent > 0.0 and d_vent < (diff0 - diff1) * 0.5)
	_check("… and stays visible as a weak gas path", atm.rooms[atm.room_of(a[0])].links.get(atm.room_of(b[0])) == "vent")
	# the door timer runs out
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
	_check("Door timer expired: no more exchange afterwards (%.4f kPa)" % absf(_mean(a) - ma), not g.door_open(door) and absf(_mean(a) - ma) <= 0.01 and ma < 100.0)

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
	# Queuing and cancelling changes nothing
	CS.jobs[g.idx(wall)] = {"kind": "uninstall", "x": wall.x, "y": wall.y, "target": "tile:wall", "tool": "", "progress": 0.5,
		"claimed_by": -1, "retry_at": 0.0, "paid": true, "need": 1.0}
	_sim(5)
	_check("Queued removal: wall stands, rooms separate", g.tiles[g.idx(wall)] == T.WALL and atm.room_of(a[0]) != atm.room_of(b[0]))
	CS.cancel(CS.jobs[g.idx(wall)])
	_check("Cancelled removal: nothing changed", g.tiles[g.idx(wall)] == T.WALL and atm.room_of(a[0]) == room_before)
	_complete("uninstall", wall, "tile:wall", Vector2i(7, 5))
	_check("After completion: one shared room", atm.room_of(a[0]) == atm.room_of(b[0]) and atm.room_of(g.idx(wall)) == atm.room_of(a[0]))
	_check("… without a vacuum edge", atm.room_leak(atm.room_of(a[0])) == "")
	_sim(120)
	_check("… Gasmenge je Gasart erhalten", _same(_total(all), tot0))
	_check("… the pressure difference decreases (40.0 → %.1f kPa after 120 s)" % (_mean(a) - _mean(b)), _mean(a) - _mean(b) < 39.0)

	# 4) Remove an outer wall; control chamber behind an airtight door
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
	_check("Outer wall becomes floor with a vacuum edge", g.tiles[g.idx(outer)] == T.FLOOR and atm.vacuum_edges(g.idx(outer)) == 1)
	_check("Cabin has a direct vacuum path", atm.room_leak(atm.room_of(a[0])) == "direct")
	_sim(30)
	_check("Cabin pressure drops (%.1f kPa after 30 s)" % _mean(a), _mean(a) < 99.0 and atm.vented.o2 > 0.0)
	_check("Control chamber behind an airtight door holds pressure (%.3f kPa)" % _mean(b), absf(_mean(b) - 100.0) <= 0.01 and atm.room_leak(atm.room_of(b[0])) == "")
	# Open the door: the control chamber gets an indirect vacuum path; closing isolates it again
	g.door_open_until[door] = 1e12
	_check("Open door: the control chamber loses air through the door", atm.room_leak(atm.room_of(b[0])) == "door")
	_sim(10)
	g.door_open_until[door] = 0.0
	mb = _mean(b)
	_sim(30)
	_check("Door closed again: control chamber isolated (%.4f kPa change)" % absf(_mean(b) - mb), atm.room_leak(atm.room_of(b[0])) == "" and absf(_mean(b) - mb) <= 0.01)

	# 5) Remove a floor in the middle of the room (outer walls intact)
	_grid()
	a = _room(4, 4, 8, 8)
	_fill(a, 100.0)
	var hole := Vector2i(6, 6)
	CS.jobs[g.idx(hole)] = {"kind": "uninstall", "x": hole.x, "y": hole.y, "target": "tile:floor", "tool": "", "progress": 0.3,
		"claimed_by": -1, "retry_at": 0.0, "paid": true, "need": 1.0}
	_sim(10)
	_check("Queued floor removal: no leak", atm.room_leak(atm.room_of(a[0])) == "" and absf(_mean(a) - 100.0) <= 0.01)
	CS.cancel(CS.jobs[g.idx(hole)])
	_complete("uninstall", hole, "tile:floor", Vector2i(5, 6))
	var nb := [g.idx(hole + Vector2i(1, 0)), g.idx(hole + Vector2i(-1, 0)), g.idx(hole + Vector2i(0, 1)), g.idx(hole + Vector2i(0, -1))]
	_check("The hole is space, the four neighbours have vacuum edges", g.tiles[g.idx(hole)] == T.SPACE and nb.all(func(i): return atm.vacuum_edges(i) == 1))
	_check("Diagonal neighbours get no vacuum edge", atm.vacuum_edges(g.idx(hole + Vector2i(1, 1))) == 0)
	_sim(20)
	_check("Room pressure drops despite intact outer walls (%.1f kPa after 20 s)" % _mean(a.filter(func(i): return g.holds_air(i))), _mean(a.filter(func(i): return g.holds_air(i))) < 99.0)
	# Diagonal anliegende, dichte Tasche verliert nichts:
	# Room up to (8,8); the corner tile (8,8) becomes the hole. Pocket (9,9) only touches it diagonally,
	# its four sides (9,8), (8,9), (10,9), (9,10) are wall.
	_grid()
	a = _room(4, 4, 8, 8)
	var pocket := _room(9, 9, 9, 9)
	_fill(a, 100.0)
	_fill(pocket, 100.0)
	var pocket0 := _total(pocket)
	_check("The pocket is its own airtight room", atm.room_of(pocket[0]) != atm.room_of(a[0]) and atm.room_leak(atm.room_of(pocket[0])) == "")
	_complete("uninstall", Vector2i(8, 8), "tile:floor", Vector2i(7, 8))
	_sim(30)
	_check("An airtight pocket touching only diagonally loses no gas", _same(_total(pocket), pocket0, 0.0001) and atm.room_leak(atm.room_of(pocket[0])) == "")
	_check("… the room itself leaks", atm.room_leak(atm.room_of(a[0])) == "direct")

	# 6) Seal and refill
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
	print("        (leak down to %.1f kPa took %d game seconds)" % [rest, leak_s])
	_check("Restdruck messbar beim Verschluss (%.1f kPa)" % rest, rest > 10.0)
	_complete("install", hole, "pk_tile_floor", Vector2i(5, 6))
	_sim(1)
	_check("No vacuum flow from the next step on (%.6f)" % atm.last_vented, atm.last_vented == 0.0 and atm.room_leak(atm.room_of(a[0])) == "")
	var t_closed := _total(a)
	_sim(60)
	_check("Without a source the gas amount stays constant", _same(_total(a), t_closed))
	var oxy = root.get_node("OxygenSystem")
	var tank_p := Vector2i(4, 4)
	var tank := g.place_device("airtank", tank_p)
	var stock0: float = tank.stock
	var t_before := _total(a)
	for k in 60:
		oxy.step(1.0 / 60.0)
		atm.simulate(1.0 / 60.0)
	var t_after := _total(a)
	_check("Full air tank: O₂ and N₂ rise (%.1f → %.1f / %.1f → %.1f)" % [t_before.x, t_after.x, t_before.y, t_after.y], t_after.x > t_before.x and t_after.y > t_before.y)
	_check("… the tank stock drops (%.0f → %.0f)" % [stock0, tank.stock], tank.stock < stock0)
	tank.stock = 0.0
	t_before = _total(a)
	for k in 60:
		oxy.step(1.0 / 60.0)
		atm.simulate(1.0 / 60.0)
	_check("Empty tank: no rise", _same(_total(a), t_before))

	# 7) Two leaks and loading a save
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
	_check("First hole closed: the second keeps leaking (%.3f kPa in the last step)" % atm.last_vented, atm.last_vented > 0.0 and atm.room_leak(atm.room_of(a[0])) == "direct")
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
	_check("After loading: stored partial pressures are the starting state", same)
	_check("… the same vacuum path is detected (only at the second hole)", g.tiles[g.idx(h2)] == T.SPACE and g.tiles[g.idx(h1)] == T.FLOOR
		and atm.vacuum_edges(g.idx(h2 + Vector2i(1, 0))) == 1 and atm.vacuum_edges(g.idx(h1 + Vector2i(1, 0))) == 0 and atm.room_leak(atm.room_of(a[0])) == "direct")
	_sim(1)
	_check("… and keeps leaking there", atm.last_vented > 0.0)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
