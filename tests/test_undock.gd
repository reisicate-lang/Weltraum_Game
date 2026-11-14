## Tests for manual undocking (from stations and other places)
##   godot --headless --path . --script res://tests/boot.gd -- test_undock
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var toasts: Array[String] = []

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _run(seconds: float) -> void:
	var gs = root.get_node("GameState")
	for i in int(seconds):
		gs.step(1.0 / 60.0)

func _last() -> String:
	return toasts[-1] if not toasts.is_empty() else ""

func _hull(g) -> float:
	var s := 0.0
	for i in g.tiles.size():
		if g.zone[i] == 0 and g.tiles[i] != 0:
			s += g.cond[i]
	return s

## Fresh game, crew safely aboard
func _fresh() -> void:
	var gs = root.get_node("GameState")
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var ship = root.get_node("ShipSystem")
	for c in root.get_node("CrewSystem").crew:
		c.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
		c.path.clear()
	_run(2)
	seat_pilot()   # Pilot at the navigation console (flight commands only there)

func _initialize() -> void:
	await process_frame
	await process_frame
	# Own save slot: tests do not overwrite real saves and can run in parallel
	root.get_node("SaveSystem").slot = 909
	# These tests also check the (temporarily disabled) station and the wreck
	Config.ENABLE_STATION = true
	Config.ENABLE_WRECK = true
	root.get_node("Settings").meteors = false
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(String(t)))
	var P = root.get_node("PhysicsSystem")
	var st = root.get_node("StationSystem")
	var crew = root.get_node("CrewSystem")
	var ship = root.get_node("ShipSystem")
	var fleet = root.get_node("FleetSystem")
	var time = root.get_node("TimeSystem")
	var save = root.get_node("SaveSystem")

	# 1) Undocking without a connection
	_fresh()
	P.request_undock()
	_run(2)
	toasts.clear()
	_check("Frei treibend: Abdocken liefert false", not P.request_undock())
	_check("… with an understandable message (%s)" % _last(), _last() == "The ship is not docked.")

	# 2) Undocking at a stationary place (Habitat L4 does not move)
	_fresh()
	P.request_undock()
	P.dock("l4", true)
	_run(2)
	var l4: Dictionary = P.loc_state(P.loc("l4"), P.secs())
	var hull_before := _hull(ship.grid)
	_check("Docked at L4, station stationary", P.docked == "l4" and st.active())
	_check("Undocking from L4 works", P.request_undock())
	_check("No jump (distance %.4f km)" % P.pos.distance_to(l4.pos), P.pos.distance_to(l4.pos) < 0.001)
	var rel: float = (P.vel - l4.vel).length()
	_check("Gentle push-off 3 m/s (%.1f m/s)" % (rel * 1000.0), absf(rel - P.UNDOCK_PUSH) < 0.0002)
	_check("Station and hatch removed", not st.active() and st.hatch == -1)
	_check("No wreck is stored at the station (wrecks are their own targets)", fleet.places.get("l4", {}).get("wreck") == null)
	_run(30)
	var r: Dictionary = P.rel_to("l4")
	_check("Ship drifts away steadily (%.0f m after 30 s)" % (r.dist * 1000.0), r.dist > 0.07 and r.dist < 0.12)
	_check("No collision, hull unharmed", _hull(ship.grid) == hull_before and not toasts.any(func(t): return "Collision" in t))

	# 3) Undocking at a moving place (Kármán Ring orbits Earth)
	_fresh()
	P.request_undock()
	P.dock("karman", true)
	_run(5)
	var k0: Dictionary = P.loc_state(P.loc("karman"), P.secs())
	P.angle = 1.0
	_check("Kármán Ring moves (%.2f km/s)" % k0.vel.length(), k0.vel.length() > 1.0)
	_check("Undocking from the moving ring works", P.request_undock())
	_check("Orbital velocity is kept (%.3f km/s)" % P.vel.length(), absf(P.vel.length() - k0.vel.length()) < 0.01)
	_check("Heading is kept", absf(P.angle - 1.0) < 0.0001)
	_check("Relative, only the push-off (%.1f m/s)" % ((P.vel - k0.vel).length() * 1000.0), absf((P.vel - k0.vel).length() - P.UNDOCK_PUSH) < 0.0002)
	_run(20)
	var rk: Dictionary = P.rel_to("karman")
	_check("Flew along with the ring, did not stay behind (%.0f m)" % (rk.dist * 1000.0), rk.dist < 0.2)

	# 4) Triggering several times quickly
	_fresh()
	toasts.clear()
	var first: bool = P.request_undock()
	var v1: Vector2 = P.vel
	var second: bool = P.request_undock()
	var third: bool = P.request_undock()
	_check("Only the first call undocks", first and not second and not third)
	_check("Push-off only once", P.vel == v1)
	_check("Exactly one success message", toasts.filter(func(t): return t.begins_with("Undocked")).size() == 1)

	# 5) Blockierende Sicherheitsbedingungen
	_fresh()
	var mira = crew.player()
	var market: Vector2i = st.rooms[0].desk + Vector2i(-1, 0)
	mira.pos = Vector2(market) + Vector2(0.5, 0.5)
	toasts.clear()
	_check("Crew on the station: undocking refused", not P.request_undock() and P.docked == "tycho" and st.active())
	_check("… the message names the person (%s)" % _last(), mira.display_name in _last())
	mira.pos = Vector2(ship.grid.pos(st.hatch)) + Vector2(0.5, 0.5)
	_check("Crew in the hatch: refused (%s)" % P.undock_block_reason(), not P.request_undock() and "hatch" in _last())
	mira.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	# A wreck at the port (otherwise its own target): release the station, couple the wreck directly
	st.clear()
	_check("(setup) wreck at the port", root.get_node("SalvageSystem").generate())
	var wreck_tile := Vector2i(-1, -1)
	for i in ship.grid.tiles.size():
		if ship.grid.zone[i] == 1 and ship.grid.walkable(ship.grid.pos(i)):
			wreck_tile = ship.grid.pos(i)
			break
	mira.pos = Vector2(wreck_tile) + Vector2(0.5, 0.5)
	_check("Crew on the wreck: refused (%s)" % P.undock_block_reason(), not P.request_undock() and "wreck" in _last())
	mira.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	var helm = P.ship_devices("helm")[0]
	helm.broken = true
	_check("Navigation console broken: refused (%s)" % P.undock_block_reason(), not P.request_undock() and "broken" in _last())
	helm.broken = false
	_run(2)
	_check("It works after fixing the reasons", P.request_undock() and P.docked == "")

	# 6) Docking again: locked at first, possible again after separating and the lock time
	_fresh()
	P.request_undock()
	_check("Docking again immediately is locked", not P.can_dock("tycho") and not P.dock("tycho"))
	_check("… the reason is given (%s)" % P.dock_block_reason("tycho"), "Just undocked" in P.dock_block_reason("tycho"))
	toasts.clear()
	P.start_autodock()
	_check("Auto-Dock is locked as well", P.autodock.is_empty() and "Just undocked" in _last())
	_run(16)
	# Deliberately manoeuvre back: match velocity and fly in
	var t0: Dictionary = P.loc_state(P.loc("tycho"), P.secs())
	P.vel = t0.vel
	P.pos = t0.pos + Vector2(0.05, 0)
	P.angle = P.dock_alignment("tycho").angle   # turn the airlock towards the target
	_check("Dockable again after the lock time and approach", P.can_dock("tycho") and P.dock("tycho") and P.docked == "tycho" and st.active())

	# 7) All time speeds through the real TimeSystem flow (×1, ×2, ×4, ×8, ×16)
	for si in range(1, 6):
		_fresh()
		var hb := _hull(ship.grid)
		toasts.clear()
		time.set_speed(si)
		for f in 3:
			time._process(1.0 / 60.0)
		_check("Zeitstufe %d: Abdocken klappt" % si, P.request_undock())
		var game_s := 0.0
		var frames := 0
		while game_s < 60.0 and frames < 4000:
			time._process(1.0 / 60.0)
			game_s += (1.0 / 60.0) * Config.SPEEDS[si] * 60.0 * Config.MINUTES_PER_SECOND
			frames += 1
		var rr: Dictionary = P.rel_to("tycho")
		_check("Speed %d: free, no re-docking, steady (%.0f m, %.1f m/s, %d frames)" % [si, rr.dist * 1000.0, rr.speed * 1000.0, frames],
			P.docked == "" and rr.speed > 0.0025 and rr.speed < 0.004 and rr.dist > 0.1 and rr.dist < 0.3)   # 3 m/s push-off + orbital drift
		_check("Speed %d: no collision" % si, _hull(ship.grid) == hb and not toasts.any(func(t): return "Collision" in t))
	time.set_speed(0)

	# 8) Saving and loading after undocking
	_fresh()
	P.request_undock()
	_run(5)
	var p_before: Vector2 = P.pos
	var v_before: Vector2 = P.vel
	save.save_game(true)
	root.get_node("GameState").new_game()
	save.load_game(true)
	_check("Not docked after loading", P.docked == "" and not st.active())
	_check("Position and velocity kept", P.pos.distance_to(p_before) < 0.000001 and P.vel.distance_to(v_before) < 0.000001)
	var zone3 := 0
	for i in ship.grid.tiles.size():
		if ship.grid.zone[i] == 3:
			zone3 += 1
	_check("No station leftovers in the ship", zone3 == 0)
	_check("Lock against re-docking loaded too", P.redock_locked("tycho"))
	_run(12)
	_check("Still steerable after loading (drift continues)", P.pos.distance_to(p_before) > 0.02)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
