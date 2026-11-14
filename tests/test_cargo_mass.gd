## Tests for the mass of loose cargo (container ↔ floor, foreign zones, loading, switching ships)
##   godot --headless --path . --script res://tests/boot.gd -- test_cargo_mass
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var P
var ship
var fleet

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _near(a: float, b: float, eps: float = 0.000001) -> bool:
	return absf(a - b) < eps

## First container on your own ship
func _crate():
	for d in P.ship_devices("crate"):
		if not ship.grid.foreign(ship.grid.idx(d.pos)):
			return d
	return null

## Free, walkable tile of a zone without a device and without a pile
func _free_tile(zone: int, skip: Array = []) -> Vector2i:
	var g = ship.grid
	for i in g.tiles.size():
		if g.zone[i] == zone and g.tiles[i] == ShipGrid.Tile.FLOOR and not g.devices.has(i) and not g.piles.has(i) and not skip.has(i):
			return g.pos(i)
	return Vector2i(-1, -1)

## Stack from one inventory into another (as the crew does it: take out, put down)
func _move(from: Inventory, type: String, qty: int, to_floor: Vector2i = Vector2i(-1, -1), to_inv: Inventory = null) -> void:
	for st in from.take(type, qty):
		if to_inv != null:
			to_inv.add(st.type, st.qty, st.cond, st.get("data"))
		else:
			ship.grid.drop_items(to_floor, st.type, st.qty, st.cond, st.get("data"))
	ship.grid.clean_piles()

## Independently computed mass of a ship grid (hull, devices, containers, own floor stacks)
func _hand_mass(g: ShipGrid) -> float:
	var m := 0.0
	for i in g.tiles.size():
		if g.tiles[i] != ShipGrid.Tile.SPACE and g.zone[i] == 0:
			m += float(Config.TILE_MASS[g.tiles[i]])
	for i in g.devices:
		m += g.devices[i].data().mass
		if g.devices[i].inv != null:
			m += g.devices[i].inv.weight() / 1000.0
	for i in g.piles:
		if g.tiles[i] != ShipGrid.Tile.SPACE and g.zone[i] == 0:
			m += g.piles[i].weight() / 1000.0
	return m

## What the crew carries aboard (also counts towards the ship mass)
func _crew_mass() -> float:
	var g = ship.grid
	var m := 0.0
	for c in root.get_node("CrewSystem").crew:
		var i: int = g.idx(c.tile())
		if g.zone[i] == 0 and g.tiles[i] != ShipGrid.Tile.SPACE:
			m += c.inv.weight() / 1000.0
	return m

func _initialize() -> void:
	await process_frame
	await process_frame
	root.get_node("SaveSystem").slot = 917
	P = root.get_node("PhysicsSystem")
	ship = root.get_node("ShipSystem")
	fleet = root.get_node("FleetSystem")
	root.get_node("Settings").meteors = false
	var gs = root.get_node("GameState")
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	for k in 3:
		gs.step(1.0 / 60.0)   # distribute power so the thrusters report thrust
	var g = ship.grid
	var crate = _crate()
	_check("Own container present", crate != null)
	# Empty the container and put exactly 20 plates (8 kg each = 160 kg) in
	crate.inv.items.clear()
	g.piles.clear()
	var m_empty: float = P.mass()
	crate.inv.add("plate", 20, 90.0)
	var w: float = crate.inv.weight() / 1000.0
	_check("Stapel wiegt 0,160 t (%.3f t)" % w, _near(w, 0.16))

	# 1) Container → own floor → back: mass and acceleration the same
	var m0: float = P.mass()
	var a0: float = P.main_accel()
	var r0: float = P.rcs_accel()
	_check("A stack in the container counts once (%.3f t → %.3f t)" % [m_empty, m0], _near(m0, m_empty + 0.16))
	var floor_p := _free_tile(0)
	_check("Free tile on your own floor", floor_p != Vector2i(-1, -1))
	_move(crate.inv, "plate", 20, floor_p)
	_check("Container empty, the stack lies on the floor", crate.inv.items.is_empty() and g.piles.has(g.idx(floor_p)) and g.piles[g.idx(floor_p)].count("plate") == 20)
	_check("On your own floor: mass the same (%.4f t)" % P.mass(), _near(P.mass(), m0))
	_check("… Haupttriebwerk-Beschleunigung gleich (%.1f kN, %.6f m/s²)" % [P.max_thrust(), P.main_accel() * 1000.0], _near(P.main_accel(), a0, 1e-12) and P.max_thrust() > 0.0)
	_check("… RCS acceleration the same", _near(P.rcs_accel(), r0, 1e-12))
	# half and half: still counts exactly once
	_move(g.piles[g.idx(floor_p)], "plate", 7, Vector2i(-1, -1), crate.inv)
	_check("Split (7 in the container, 13 on the floor): mass the same", _near(P.mass(), m0))
	_move(g.piles[g.idx(floor_p)], "plate", 13, Vector2i(-1, -1), crate.inv)
	_check("Put back: mass and acceleration the same", _near(P.mass(), m0) and _near(P.main_accel(), a0, 1e-12) and _near(P.rcs_accel(), r0, 1e-12))
	_check("… floor empty, 20 plates in the container", not g.piles.has(g.idx(floor_p)) and crate.inv.count("plate") == 20)

	# 2) Transfer to a foreign zone: the mass drops by the stack weight
	Config.ENABLE_WRECK = true
	root.get_node("StationSystem").clear()   # one port: release the station, couple the wreck
	_check("Wreck attached", root.get_node("SalvageSystem").generate())
	g = ship.grid
	crate = _crate()
	var m1: float = P.mass()
	var wreck_p := _free_tile(1)
	_check("Wrackfeld (fremder Bereich) vorhanden", wreck_p != Vector2i(-1, -1))
	_move(crate.inv, "plate", 20, wreck_p)
	_check("Stack from the ship onto the wreck: mass drops by 0.160 t (%.3f → %.3f t)" % [m1, P.mass()], _near(m1 - P.mass(), 0.16))
	var m2: float = P.mass()
	var wreck_p2 := _free_tile(1, [g.idx(wreck_p)])
	g.drop_items(wreck_p2, "plate", 50, 80.0)
	_check("Another foreign floor stack changes nothing", _near(P.mass(), m2))
	var space_i := -1
	for i in g.tiles.size():
		if g.zone[i] == 0 and g.tiles[i] == ShipGrid.Tile.SPACE and not g.piles.has(i):
			space_i = i
			break
	g.drop_items(g.pos(space_i), "plate", 10, 80.0)
	_check("A pile in space next to the hull does not count", _near(P.mass(), m2))
	var thr: float = P.max_thrust()
	_check("Acceleration = thrust ÷ own mass", _near(P.main_accel(), thr / P.mass() / 1000.0, 1e-12))
	Config.ENABLE_WRECK = false

	# 3) Load a save with an own floor stack, then switch ships
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	g = ship.grid
	crate = _crate()
	crate.inv.items.clear()
	g.piles.clear()
	var m_base: float = P.mass()
	floor_p = _free_tile(0)
	g.drop_items(floor_p, "plate", 20, 90.0)
	var m_saved: float = P.mass()
	_check("Before saving: the floor stack counts (%.3f t)" % m_saved, _near(m_saved, m_base + 0.16))
	root.get_node("SaveSystem").save_game(true)
	gs.new_game()
	root.get_node("SaveSystem").load_game(true)
	g = ship.grid
	_check("Loaded: the stack lies on the floor again", g.piles.has(g.idx(floor_p)) and g.piles[g.idx(floor_p)].count("plate") == 20)
	_check("… and counts exactly once (%.3f t)" % P.mass(), _near(P.mass(), m_saved, 0.00001))
	# second ship at the same place, with its own floor stack (5 plates = 40 kg)
	var g2 := ShipGrid.new()
	fleet._build_template(g2, {"id": "lumen", "w": 10, "h": 7})
	var g2_floor := Vector2i(-1, -1)
	for i in g2.tiles.size():
		if g2.tiles[i] == ShipGrid.Tile.FLOOR and not g2.devices.has(i):
			g2_floor = g2.pos(i)
			break
	g2.drop_items(g2_floor, "plate", 5, 90.0)
	var id2: int = fleet.next_id
	fleet.next_id += 1
	fleet.ships.append({"id": id2, "name": "Testschiff", "location": fleet.here(), "data": g2.to_data()})
	var m2_expected: float = _hand_mass(g2)
	var old_id: int = fleet.current_id
	fleet.switch_to(id2)
	g = ship.grid
	_check("Switched to the second ship", fleet.current_id == id2)
	m2_expected += _crew_mass()
	_check("Only its own cargo counts (%.3f t, expected %.3f t)" % [P.mass(), m2_expected], _near(P.mass(), m2_expected, 0.00001))
	var pile_w := 0.0
	for i in g.piles:
		pile_w += g.piles[i].weight()
	_check("… the old stack is not aboard, own stack 40 kg (%.0f kg)" % pile_w, _near(pile_w, 40.0))
	fleet.switch_to(old_id)
	g = ship.grid
	_check("Switched back: the old stack is there again and counts once", g.piles.has(g.idx(floor_p)) and _near(P.mass(), m_saved, 0.00001))

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
