## Tests: docking at the only port of the starter ship – the outer door of the airlock on the left.
## Station and wreck couple there door to door; the wreck is its own navigation target.
## Old saves with the former docking ports (right/bottom) are released regularly.
##   godot --headless --path . --script res://tests/boot.gd -- test_docking
extends "res://tests/test_base.gd"

const OLD_SAVE := "res://tests/fixtures/old_save_blueports.json"

var ok_count := 0
var fail_count := 0
var toasts: Array[String] = []
var gs
var ship
var st
var P
var crew
var CS
var salv
var fleet
var A
var save
var x0 := 0
var y0 := 0

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

func _count_zone(z: int) -> int:
	var g = ship.grid
	var n := 0
	for i in g.tiles.size():
		if g.zone[i] == z and g.tiles[i] != 0:
			n += 1
	return n

func _sealed() -> bool:
	A.topology()
	for r in A.rooms.size():
		if ship.grid.zone[A.rooms[r].cells[0]] == 0 and A.room_leak(r) != "":
			return false
	return true

func _fresh():
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var m = crew.player()
	m.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	m.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	var g = ship.grid
	x0 = (g.width / Config.GRID_SCALE - 16) / 2
	y0 = (g.height / Config.GRID_SCALE - 10) / 2
	_run(2)
	seat_pilot()
	return m

## Put the ship calmly next to a place (distance dist km), optionally with the port towards the target
func _park_near(id: String, dist: float, align: bool) -> void:
	var stt: Dictionary = P.loc_state(P.loc(id), P.secs())
	P.pos = stt.pos + Vector2(dist, 0)
	P.vel = stt.vel
	P.ang_vel = 0.0
	P.angle = P.dock_alignment(id).angle if align else P.dock_alignment(id).angle + PI / 2.0

func _crew_home() -> void:
	for c in crew.crew:
		c.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
		c.path.clear()
		c.order = null

func _initialize() -> void:
	await process_frame
	await process_frame
	save = root.get_node("SaveSystem")
	save.slot = 905
	Config.ENABLE_STATION = true
	Config.ENABLE_WRECK = true
	gs = root.get_node("GameState")
	ship = root.get_node("ShipSystem")
	st = root.get_node("StationSystem")
	P = root.get_node("PhysicsSystem")
	crew = root.get_node("CrewSystem")
	CS = root.get_node("ShipConstructionSystem")
	salv = root.get_node("SalvageSystem")
	fleet = root.get_node("FleetSystem")
	A = root.get_node("AtmosphereSystem")
	root.get_node("Settings").meteors = false
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(String(t)))
	var mira = _fresh()
	var g = ship.grid

	# ---------------- 1) New game: only the airlock on the left is a port ----------------
	var ports: Array = ship.ports()
	var red: Dictionary = ports[0] if not ports.is_empty() else {}
	var lock_door := C(x0 - 3, y0 + 7)
	_check("1: Exactly one docking port: the outer door of the airlock on the left (%s)" % str(ports), ports.size() == 1 and red.pos == lock_door and red.dir == Vector2i(-1, 0)
		and root.get_node("AirlockSystem").is_lock_door(red.i))
	_check("1: No docking port devices any more, not buildable", P.ship_devices("dockport").is_empty() and not root.get_node("ItemSystem").device("dockport").buildable)
	var old_right := C(x0 + 15, y0 + 5)
	var old_down := C(x0 + 6, y0 + 9)
	_check("1: Continuous outer wall on the right and at the bottom", g.get_tile(old_right) == ShipGrid.Tile.WALL and g.get_tile(old_down) == ShipGrid.Tile.WALL
		and g.get_tile(old_right + Vector2i(1, 0)) == ShipGrid.Tile.SPACE and g.get_tile(old_down + Vector2i(0, 1)) == ShipGrid.Tile.SPACE)
	_check("1: Pressure hull airtight", _sealed())
	_check("1: Station door to door at the left outer door", st.active() and st.hatch == red.i and g.get_tile(red.pos + red.dir) == ShipGrid.Tile.DOOR and g.zone[g.idx(red.pos + red.dir)] == 3)
	_check("1: No wreck at the ship", _count_zone(1) == 0 and salv.wreck_name == "")
	var corridor: Vector2i = red.pos + red.dir * 3
	_check("1: Through the airlock into the station", mira.order_move(corridor))
	_run(240)
	_check("1: … Mira stands in the station, without a space suit", g.zone[g.idx(mira.tile())] == 3 and mira.suit == null)
	mira.order_move(ship.spawn_point())
	_run(240)
	_check("1: … and is back aboard, cabin pressurized", g.zone[g.idx(mira.tile())] == 0 and g.pressure(g.idx(ship.spawn_point())) > 90.0)

	# ---------------- 2) Wreck: its own target, passage only after clamping ----------------
	var site: Dictionary = {}
	for l in P.locations:
		if l.kind == "wreck":
			site = l
	_check("2: The wreck is its own target on the map (%s)" % site.get("name", "-"), not site.is_empty() and site.near == "tycho")
	P.target = site.id
	_check("2: Target chosen: no wreck zone at the ship", _count_zone(1) == 0)
	_check("2: Undocking from the station", P.request_undock() and not st.active() and not g.linked.has(red.i))
	_run(20)
	_check("2: Far away (%.1f km): no docking, no passage" % P.rel_to(site.id).dist, not P.can_dock(site.id) and _count_zone(1) == 0)
	_park_near(site.id, 1.0, true)
	_check("2: Outside docking range (%s)" % P.dock_block_reason(site.id), not P.dock(site.id) and _count_zone(1) == 0 and "Too far" in P.dock_block_reason(site.id))
	_park_near(site.id, 0.05, false)
	_check("2: Close, but the port is not aligned (%s)" % P.dock_block_reason(site.id), not P.dock(site.id) and _count_zone(1) == 0 and "does not face" in P.dock_block_reason(site.id))
	var stt: Dictionary = P.loc_state(site, P.secs())
	P.vel = stt.vel + Vector2(0.02, 0)
	P.angle = P.dock_alignment(site.id).angle
	_check("2: Too fast: no clamping", not P.dock(site.id) and _count_zone(1) == 0)
	P.vel = stt.vel
	_check("2: Slowed down and aligned: clamped", P.dock(site.id) and P.docked == site.id)
	var entry: Vector2i = salv.entry
	_check("2: Wreck door to door at the left outer door", _count_zone(1) > 0 and salv.port == red.i and entry == red.pos + red.dir
		and g.get_tile(entry) == ShipGrid.Tile.DOOR and g.linked.has(red.i))
	var wreck_name: String = salv.wreck_name
	var inside_wreck: Vector2i = entry + red.dir
	_check("2: Walkable into the wreck through the airlock", not ship.find_path(ship.spawn_point(), inside_wreck).is_empty() or not ship.find_path(ship.spawn_point(), entry).is_empty())
	_check("2: The ship stays airtight", _sealed())

	# ---------------- 3) From the wreck to the station: the same left port ----------------
	_crew_home()
	_check("3: Undocked from the wreck", P.request_undock() and _count_zone(1) == 0 and not g.linked.has(red.i))
	_check("3: The wreck stays at the target (saved)", fleet.places.get(site.id, {}).get("wreck") != null)
	_run(20)
	_park_near("tycho", 0.05, true)
	_check("3: Docked at the station (%s)" % P.dock_block_reason("tycho"), P.dock("tycho") and st.active())
	_check("3: Station door at the same left door", st.hatch == red.i and g.get_tile(red.pos + red.dir) == ShipGrid.Tile.DOOR and g.zone[g.idx(red.pos + red.dir)] == 3)
	# Autodock nutzt denselben Port
	P.request_undock()
	_run(20)
	_park_near("tycho", 0.5, false)
	P.start_autodock()
	for k in 60 * 15:
		gs.step(1.0 / 60.0)
		if P.docked != "":
			break
	_check("3: Autodock also couples at the left door", P.docked == "tycho" and st.hatch == red.i)
	# Back to the wreck: the same wreck is there again
	P.request_undock()
	_run(20)
	_park_near(site.id, 0.05, true)
	_check("3: At the wreck again: the same wreck (%s)" % salv.wreck_name, P.dock(site.id) and salv.wreck_name == wreck_name and salv.port == red.i)
	_crew_home()
	P.request_undock()

	# ---------------- 4) Old save with connections at the former ports ----------------
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(OLD_SAVE))
	f.close()
	gs.new_game()
	_check("4: Old save loaded", save.load_game(true))
	g = ship.grid
	_run(2)   # distribute power
	var docks: Array = P.ship_devices("dockport")
	_check("4: Station still hangs at the former right port, the wreck at the bottom one", docks.size() == 2 and st.active() and g.devices.has(st.hatch) and g.devices[st.hatch].type == "dockport"
		and salv.port >= 0 and g.devices.has(salv.port) and g.devices[salv.port].type == "dockport")
	_check("4: The airlock on the left is free, hull airtight", ship.ports().any(func(p): return p.i == red.i and not g.linked.has(p.i)) and _sealed())
	var crate37 := false
	for dv in g.devices.values():
		if dv.type == "crate" and absf(dv.cond - 37.0) < 0.01:
			crate37 = true
	_check("4: Cargo and progress kept (4321 Cr, crate 37 %)", root.get_node("EconomySystem").credits == 4321 and crate37)
	var old_wreck: String = salv.wreck_name
	var old_pos: Array = docks.map(func(d): return d.pos)
	seat_pilot()
	_crew_home()
	_check("4: Old connection released regularly (undocking)", P.request_undock() and not st.active() and _count_zone(1) == 0)
	_check("4: Former ports removed, openings are wall, hull airtight", P.ship_devices("dockport").is_empty()
		and old_pos.all(func(p): return g.get_tile(p) == ShipGrid.Tile.WALL) and _sealed())
	var old_site: Dictionary = {}
	for l in fleet.sites:
		if l.get("wreck_name", "") == old_wreck:
			old_site = l
	_check("4: The old wreck is now its own target (%s)" % old_wreck, not old_site.is_empty() and fleet.places.get(old_site.id, {}).get("wreck") != null)
	_run(20)
	_park_near("tycho", 0.05, true)
	_check("4: Docked again: station at the red port", P.dock("tycho") and st.hatch == red.i and g.get_tile(red.pos + red.dir) == ShipGrid.Tile.DOOR)
	_check("4: Former openings stay airtight", _sealed() and g.pressure(g.idx(ship.spawn_point())) > 90.0)
	P.request_undock()
	_run(20)
	_park_near(old_site.id, 0.05, true)
	_check("4: Old wreck coupled at the red port", P.dock(old_site.id) and salv.port == red.i and salv.wreck_name == old_wreck)
	_crew_home()
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	_check("4: Saved and loaded: wreck still at the red port", salv.port == red.i and _count_zone(1) > 0 and P.ship_devices("dockport").is_empty())

	# ---------------- 5) No docking without a port; the old airlock can no longer be installed ----------------
	_fresh()
	g = ship.grid
	P.request_undock()
	_run(20)
	g.set_tile(red.pos, ShipGrid.Tile.WALL)    # outer door bricked up: no port any more
	root.get_node("EventBus").ship_changed.emit()
	toasts.clear()
	_park_near("tycho", 0.05, true)
	_check("5: No docking without a port, with a message", ship.ports().is_empty() and not P.dock("tycho", true) and toasts.any(func(t): return "docking port" in t))
	_check("5: The former docking port cannot be installed", root.get_node("RemovalSystem").install_reason("pk_dockport", old_right) != "")

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
