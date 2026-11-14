## Tests: Andocken am einzigen Port des Startschiffs – der Außentür der Luftschleuse links.
## Station und Wrack koppeln dort Tür an Tür; das Wrack ist ein eigenes Navigationsziel.
## Alte Spielstände mit den früheren Andockschleusen (rechts/unten) werden regulär gelöst.
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

## Schiff ruhig neben einen Ort stellen (Abstand dist km), optional mit Port zum Ziel
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

	# ---------------- 1) Neues Spiel: nur die Luftschleuse links ist Port ----------------
	var ports: Array = ship.ports()
	var red: Dictionary = ports[0] if not ports.is_empty() else {}
	var lock_door := C(x0 - 3, y0 + 7)
	_check("1: Genau ein Andockport: die Außentür der Luftschleuse links (%s)" % str(ports), ports.size() == 1 and red.pos == lock_door and red.dir == Vector2i(-1, 0)
		and root.get_node("AirlockSystem").is_lock_door(red.i))
	_check("1: Keine Andockschleusen-Geräte mehr, nicht baubar", P.ship_devices("dockport").is_empty() and not root.get_node("ItemSystem").device("dockport").buildable)
	var old_right := C(x0 + 15, y0 + 5)
	var old_down := C(x0 + 6, y0 + 9)
	_check("1: Rechts und unten durchgehende Außenwand", g.get_tile(old_right) == ShipGrid.Tile.WALL and g.get_tile(old_down) == ShipGrid.Tile.WALL
		and g.get_tile(old_right + Vector2i(1, 0)) == ShipGrid.Tile.SPACE and g.get_tile(old_down + Vector2i(0, 1)) == ShipGrid.Tile.SPACE)
	_check("1: Druckhülle dicht", _sealed())
	_check("1: Station Tür an Tür an der linken Außentür", st.active() and st.hatch == red.i and g.get_tile(red.pos + red.dir) == ShipGrid.Tile.DOOR and g.zone[g.idx(red.pos + red.dir)] == 3)
	_check("1: Kein Wrack am Schiff", _count_zone(1) == 0 and salv.wreck_name == "")
	var corridor: Vector2i = red.pos + red.dir * 3
	_check("1: Durch die Luftschleuse in die Station", mira.order_move(corridor))
	_run(240)
	_check("1: … Mira steht in der Station, ohne Raumanzug", g.zone[g.idx(mira.tile())] == 3 and mira.suit == null)
	mira.order_move(ship.spawn_point())
	_run(240)
	_check("1: … und ist zurück an Bord, Kabine unter Druck", g.zone[g.idx(mira.tile())] == 0 and g.pressure(g.idx(ship.spawn_point())) > 90.0)

	# ---------------- 2) Wrack: eigenes Ziel, Übergang erst nach dem Klammern ----------------
	var site: Dictionary = {}
	for l in P.locations:
		if l.kind == "wreck":
			site = l
	_check("2: Das Wrack ist ein eigenes Ziel auf der Karte (%s)" % site.get("name", "-"), not site.is_empty() and site.near == "tycho")
	P.target = site.id
	_check("2: Ziel gewählt: kein Wrackbereich am Schiff", _count_zone(1) == 0)
	_check("2: Abdocken von der Station", P.request_undock() and not st.active() and not g.linked.has(red.i))
	_run(20)
	_check("2: Weit weg (%.1f km): kein Andocken, kein Übergang" % P.rel_to(site.id).dist, not P.can_dock(site.id) and _count_zone(1) == 0)
	_park_near(site.id, 1.0, true)
	_check("2: Außerhalb der Andockreichweite (%s)" % P.dock_block_reason(site.id), not P.dock(site.id) and _count_zone(1) == 0 and "Too far" in P.dock_block_reason(site.id))
	_park_near(site.id, 0.05, false)
	_check("2: Nah, aber Port nicht ausgerichtet (%s)" % P.dock_block_reason(site.id), not P.dock(site.id) and _count_zone(1) == 0 and "does not face" in P.dock_block_reason(site.id))
	var stt: Dictionary = P.loc_state(site, P.secs())
	P.vel = stt.vel + Vector2(0.02, 0)
	P.angle = P.dock_alignment(site.id).angle
	_check("2: Zu schnell: kein Klammern", not P.dock(site.id) and _count_zone(1) == 0)
	P.vel = stt.vel
	_check("2: Abgebremst und ausgerichtet: geklammert", P.dock(site.id) and P.docked == site.id)
	var entry: Vector2i = salv.entry
	_check("2: Wrack Tür an Tür an der linken Außentür", _count_zone(1) > 0 and salv.port == red.i and entry == red.pos + red.dir
		and g.get_tile(entry) == ShipGrid.Tile.DOOR and g.linked.has(red.i))
	var wreck_name: String = salv.wreck_name
	var inside_wreck: Vector2i = entry + red.dir
	_check("2: Durch die Luftschleuse ins Wrack begehbar", not ship.find_path(ship.spawn_point(), inside_wreck).is_empty() or not ship.find_path(ship.spawn_point(), entry).is_empty())
	_check("2: Schiff bleibt dicht", _sealed())

	# ---------------- 3) Vom Wrack zur Station: derselbe linke Port ----------------
	_crew_home()
	_check("3: Vom Wrack abgedockt", P.request_undock() and _count_zone(1) == 0 and not g.linked.has(red.i))
	_check("3: Wrack bleibt am Ziel (gespeichert)", fleet.places.get(site.id, {}).get("wreck") != null)
	_run(20)
	_park_near("tycho", 0.05, true)
	_check("3: An der Station angedockt (%s)" % P.dock_block_reason("tycho"), P.dock("tycho") and st.active())
	_check("3: Stationstür an derselben linken Tür", st.hatch == red.i and g.get_tile(red.pos + red.dir) == ShipGrid.Tile.DOOR and g.zone[g.idx(red.pos + red.dir)] == 3)
	# Autodock nutzt denselben Port
	P.request_undock()
	_run(20)
	_park_near("tycho", 0.5, false)
	P.start_autodock()
	for k in 60 * 15:
		gs.step(1.0 / 60.0)
		if P.docked != "":
			break
	_check("3: Autodock koppelt ebenfalls an der linken Tür", P.docked == "tycho" and st.hatch == red.i)
	# Zurück zum Wrack: dasselbe Wrack wieder da
	P.request_undock()
	_run(20)
	_park_near(site.id, 0.05, true)
	_check("3: Wieder am Wrack: dasselbe Wrack (%s)" % salv.wreck_name, P.dock(site.id) and salv.wreck_name == wreck_name and salv.port == red.i)
	_crew_home()
	P.request_undock()

	# ---------------- 4) Alter Spielstand mit Verbindungen an den früheren Ports ----------------
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(OLD_SAVE))
	f.close()
	gs.new_game()
	_check("4: Alter Spielstand geladen", save.load_game(true))
	g = ship.grid
	_run(2)   # Strom verteilen
	var docks: Array = P.ship_devices("dockport")
	_check("4: Station hängt noch am früheren rechten Port, Wrack am unteren", docks.size() == 2 and st.active() and g.devices.has(st.hatch) and g.devices[st.hatch].type == "dockport"
		and salv.port >= 0 and g.devices.has(salv.port) and g.devices[salv.port].type == "dockport")
	_check("4: Luftschleuse links ist frei, Hülle dicht", ship.ports().any(func(p): return p.i == red.i and not g.linked.has(p.i)) and _sealed())
	var crate37 := false
	for dv in g.devices.values():
		if dv.type == "crate" and absf(dv.cond - 37.0) < 0.01:
			crate37 = true
	_check("4: Ladung und Fortschritt erhalten (4321 Cr, Kiste 37 %)", root.get_node("EconomySystem").credits == 4321 and crate37)
	var old_wreck: String = salv.wreck_name
	var old_pos: Array = docks.map(func(d): return d.pos)
	seat_pilot()
	_crew_home()
	_check("4: Alte Verbindung regulär gelöst (Abdocken)", P.request_undock() and not st.active() and _count_zone(1) == 0)
	_check("4: Frühere Ports entfernt, Öffnungen sind Wand, Hülle dicht", P.ship_devices("dockport").is_empty()
		and old_pos.all(func(p): return g.get_tile(p) == ShipGrid.Tile.WALL) and _sealed())
	var old_site: Dictionary = {}
	for l in fleet.sites:
		if l.get("wreck_name", "") == old_wreck:
			old_site = l
	_check("4: Das alte Wrack ist jetzt ein eigenes Ziel (%s)" % old_wreck, not old_site.is_empty() and fleet.places.get(old_site.id, {}).get("wreck") != null)
	_run(20)
	_park_near("tycho", 0.05, true)
	_check("4: Erneut angedockt: Station am roten Port", P.dock("tycho") and st.hatch == red.i and g.get_tile(red.pos + red.dir) == ShipGrid.Tile.DOOR)
	_check("4: Frühere Öffnungen halten dicht", _sealed() and g.pressure(g.idx(ship.spawn_point())) > 90.0)
	P.request_undock()
	_run(20)
	_park_near(old_site.id, 0.05, true)
	_check("4: Altes Wrack am roten Port angekoppelt", P.dock(old_site.id) and salv.port == red.i and salv.wreck_name == old_wreck)
	_crew_home()
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	_check("4: Gespeichert und geladen: Wrack weiter am roten Port", salv.port == red.i and _count_zone(1) > 0 and P.ship_devices("dockport").is_empty())

	# ---------------- 5) Ohne Port kein Andocken; alte Schleuse nicht mehr einbaubar ----------------
	_fresh()
	g = ship.grid
	P.request_undock()
	_run(20)
	g.set_tile(red.pos, ShipGrid.Tile.WALL)    # Außentür zugemauert: kein Port mehr
	root.get_node("EventBus").ship_changed.emit()
	toasts.clear()
	_park_near("tycho", 0.05, true)
	_check("5: Ohne Port kein Andocken, mit Meldung", ship.ports().is_empty() and not P.dock("tycho", true) and toasts.any(func(t): return "docking port" in t))
	_check("5: Frühere Andockschleuse lässt sich nicht einbauen", root.get_node("RemovalSystem").install_reason("pk_dockport", old_right) != "")

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
