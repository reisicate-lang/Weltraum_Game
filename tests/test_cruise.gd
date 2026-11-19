## Tests: regions of the solar system and the long-range cruise (Earth–Moon, Mars, Belt,
## Jupiter, Saturn): local maps, cruise time and fuel, arrival, docking at a new station from
## its Godot design, wreck targets per region, gravity and crashes per region, saving, cockpit
##   godot --headless --path . --script res://tests/boot.gd -- test_cruise
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FAIL    " + name)

## Fly out of the wake zone: 600 km away from the nearest station
func _leave_wake(P) -> void:
	var st_pos: Vector2 = P.pos
	for l in P.locations:
		if l.kind == "station" and P.pos.distance_to(P.loc_state(l, P.secs()).pos) < 500.0:
			st_pos = P.loc_state(l, P.secs()).pos
	var dir: Vector2 = (P.pos - st_pos).normalized() if P.pos.distance_to(st_pos) > 1.0 else (st_pos - Vector2(P.main_body().x, P.main_body().y)).normalized()
	P.pos = st_pos + dir * 600.0

var msgs: Array = []
func _on_over(_t: String, text: String) -> void:
	msgs.append(text)

func _ids(P) -> Array:
	return P.locations.map(func(l): return l.id)

func _initialize() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var SS = root.get_node("SaveSystem")
	SS.slot = 968
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var P = root.get_node("PhysicsSystem")
	var F = root.get_node("FleetSystem")
	root.get_node("ShipPowerSystem")._dirty = true
	root.get_node("ShipPowerSystem").step(0.01)
	seat_pilot()

	# 1) Regions and local maps
	var rids: Array = P.regions().map(func(r): return r.id)
	_check("Five regions: %s" % str(rids), rids == ["earth", "mars", "belt", "jupiter", "saturn"])
	_check("Start in Earth–Moon: only its places on the map", P.region == "earth" and _ids(P).has("tycho") and not _ids(P).has("ares") and not P.loc("ares").is_empty())
	_check("Every new place has a Godot design", ["ares", "phobos_field", "ceres_exchange", "belt_rock", "europa_station", "titan_outpost"].all(
		func(id): return ResourceLoader.exists("res://designs/places/%s.tscn" % id)))

	# 2) Cruise conditions
	_check("Docked: undock first", P.cruise_info("mars").reason == "Undock first.")
	P.undock()
	_check("Right after undocking: inside the wake zone (%s)" % P.cruise_info("mars").reason, P.cruise_info("mars").reason.begins_with("Inside the wake zone of Tycho"))
	_leave_wake(P)
	var info: Dictionary = P.cruise_info("mars")
	_check("Earth → Mars: %.1f days, %d fuel" % [info.days, int(info.fuel)], is_equal_approx(info.days, 3.0 + 2.5 * 0.52) and info.reason == "")
	_check("Saturn is much further (%.1f days)" % P.cruise_info("saturn").days, P.cruise_info("saturn").days > 20.0)
	var tanks: Array = P.ship_devices("fueltank")
	var keep: float = tanks[0].stock
	for t in tanks:
		t.stock = 0.0
	_check("Without fuel: refused", P.cruise_info("mars").reason.begins_with("Not enough fuel"))
	tanks[0].stock = keep
	var f0: float = P.fuel()
	_check("Course set for Mars: fuel used, cruise running", P.start_cruise("mars") and P.fuel() < f0 - 50.0 and not P.cruise.is_empty() and P.status().begins_with("Long-range cruise to Mars"))

	# 3) Time passes, arrival in the Mars region
	gs.time = float(P.cruise.t1) + 0.1
	P.step(0.1)
	_check("Arrived: region Mars, its places on the map", P.region == "mars" and P.cruise.is_empty() and _ids(P).has("ares") and not _ids(P).has("tycho"))
	var r: Dictionary = P.rel_to("ares")
	_check("The ship drifts %.0f km from Ares Orbital with matched speed, target set" % r.dist, absf(r.dist - 150.0) < 1.0 and r.speed < 0.001 and P.target == "ares")
	var gdir: Vector2 = P.gravity(P.pos).normalized()
	_check("Gravity points to Mars", gdir.dot((Vector2.ZERO - P.pos).normalized()) > 0.99)

	# 4) Docking at the new station from its design
	_check("Docking at Ares Orbital", P.dock("ares", true) and P.docked == "ares" and not P.station().is_empty() and P.station().get("shipyard", false))
	_check("Bulk market of Ares mapped (Mars orbital)", Bulk.traded("industrial", "ares") or Bulk.wiki_station("ares") == "MHNG")

	# 5) Wreck targets belong to the region of their place
	var site: Dictionary = F.add_site("ares")
	_check("A wreck target next to Ares shows on the Mars map", _ids(P).has(site.id) and P.region_of(site) == "mars")

	# 6) Saving/loading keeps the region
	SS.save_game()
	P.region = "earth"
	P._refilter()
	SS.load_game(true)
	_check("Saving/loading: still at Mars", P.region == "mars" and _ids(P).has("ares"))

	# 7) Cockpit: solar system section
	var ui = root.get_node("UIManager")
	seat_pilot()
	ui.nav_open = true
	ui._last_nav = ""
	ui._refresh_nav()
	var texts := []
	for ch in ui.nav_side.get_children():
		if ch.is_queued_for_deletion():
			continue
		for x in [ch] + ch.get_children():
			if x is Label:
				texts.append(x.text)
	ui.nav_open = false
	_check("Cockpit lists the other worlds", texts.any(func(t): return String(t).begins_with("SOLAR SYSTEM · here: Mars")) and texts.any(func(t): return String(t).begins_with("Earth–Moon ·")))

	# 7b) Time lapse while cruising (real frames through the TimeSystem)
	root.get_node("ShipPowerSystem")._dirty = true
	root.get_node("ShipPowerSystem").step(0.01)   # after loading the grid is computed again
	seat_pilot()
	var ub: String = P.undock_block_reason()
	_check("Undock from Ares (%s)" % ub, P.undock())
	_leave_wake(P)
	for t in P.ship_devices("fueltank"):
		t.stock = t.data().stock
	var t0: float = gs.time
	var why: String = P.cruise_info("belt").reason
	_check("Cruise to the Belt can start (%s)" % why, P.start_cruise("belt"))
	root.get_node("TimeSystem").set_speed(1)
	for k in 30:
		await process_frame
	root.get_node("TimeSystem").set_speed(0)
	_check("Cruising: time lapse (%.0f game minutes in 30 frames)" % (gs.time - t0), gs.time - t0 > 60.0)
	P.cruise = {}

	# 8) Crash into Mars
	P.pos = Vector2(3390.0 + 50.0, 0.0)
	P.vel = Vector2.ZERO
	root.get_node("EconomySystem").game_over.connect(_on_over)
	P._check_hazards()
	root.get_node("EconomySystem").game_over.disconnect(_on_over)
	_check("Crash into Mars ends the game (%s)" % (msgs[0] if not msgs.is_empty() else "-"), P.crashed and not msgs.is_empty() and String(msgs[0]).contains("Mars"))

	print("%d OK, %d failed" % [ok_count, fail_count])
	quit()
