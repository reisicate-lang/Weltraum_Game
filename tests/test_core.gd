## Core game with the station and the wreck disabled (both switches off)
##   godot --headless --path . --script res://tests/boot.gd -- test_core
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

func _zone(g, z: int) -> int:
	var n := 0
	for i in g.tiles.size():
		if g.zone[i] == z and g.tiles[i] != 0:
			n += 1
	return n

func _initialize() -> void:
	await process_frame
	await process_frame
	# Own save slot: tests do not overwrite real saves and can run in parallel
	root.get_node("SaveSystem").slot = 904
	var gs = root.get_node("GameState")
	var ship = root.get_node("ShipSystem")
	var st = root.get_node("StationSystem")
	var salv = root.get_node("SalvageSystem")
	var P = root.get_node("PhysicsSystem")
	var econ = root.get_node("EconomySystem")
	var crew = root.get_node("CrewSystem")
	var goals = root.get_node("GoalSystem")
	var fleet = root.get_node("FleetSystem")
	var ui = root.get_node("UIManager")
	var save = root.get_node("SaveSystem")
	root.get_node("Settings").meteors = false
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(String(t)))

	# Station and wreck are enabled in the game; here the core is checked with both switches off
	_check("Default: station and wreck enabled", Config.ENABLE_STATION and Config.ENABLE_WRECK)
	Config.ENABLE_STATION = false
	Config.ENABLE_WRECK = false

	# 1) New game: no station, no wreck
	gs.new_game()
	gs.step(1.0 / 60.0)   # compute once so the power network is up
	var g = ship.grid
	_check("No station tiles, station inactive", _zone(g, 3) == 0 and not st.active() and st.npcs.is_empty())
	_check("No wreck tiles, no wreck", _zone(g, 1) == 0 and salv.wreck_name == "" and salv.port == -1)
	_check("No airlock connected", g.linked.is_empty())
	_check("Still docked at Tycho, terminal online", P.docked == "tycho" and econ.terminal_online())

	# 2) Trading still works, salvage does not
	var cr: int = econ.credits
	toasts.clear()
	econ.buy_permit("yellow")
	_check("Salvage permit refused, with a message", econ.credits == cr and toasts.any(func(t): return "Salvage is temporarily disabled" in t))
	econ.terminal().inv.add("scrap", 3, 80.0)
	econ.sell_all()
	_check("Selling at the terminal works", econ.credits > cr)
	ui.open_window("trade")
	var labels: Array = []
	for b in ui.window_box.find_children("*", "Button", true, false):
		labels.append(b.text)
	_check("The “Salvage” tab is hidden", not "Salvage" in labels and "Sell" in labels)
	ui.close_window()

	# 3) Goals: wreck goals are skipped
	goals.done.clear()
	goals.done.append("suit")
	_check("After the space suit comes “Sell” (%s)" % goals.current().get("id", ""), goals.current().get("id", "") == "sell")

	# 4) Undock and dock again, travel: no tiles are created
	gs.step(1.0 / 60.0)
	seat_pilot()   # Pilot at the navigation console (flight commands only there)
	_check("Abdocken klappt", P.request_undock())
	for k in 20 * 60:
		gs.step(1.0 / 60.0)
	_check("Wieder andocken an Tycho", P.dock("tycho", true) and P.docked == "tycho")
	_check("… without station and wreck", _zone(g, 3) == 0 and _zone(g, 1) == 0)
	seat_pilot()   # Pilot at the navigation console (flight commands only there)
	P.request_undock()
	P.dock("debris", true)
	_check("Debris field: no wreck", _zone(g, 1) == 0 and salv.wreck_name == "")
	seat_pilot()   # Pilot at the navigation console (flight commands only there)
	P.request_undock()
	P.dock("kx7", true)
	_check("Asteroid: no chunk of rock", _zone(g, 1) == 0)
	seat_pilot()   # Pilot at the navigation console (flight commands only there)
	P.request_undock()
	P.dock("tycho", true)

	# 5) One day of the core game: Mira lives, the air holds
	var mira = crew.player()
	for k in 24 * 60 * 12:   # 5 Spielsekunden pro Schritt
		gs.step(5.0 / 60.0)
	_check("After one day: Mira healthy (%d)" % int(mira.health), mira.health > 80.0)
	var inside: int = g.idx(ship.spawn_point())
	_check("After one day: air in the ship (%d kPa)" % int(g.pressure(inside)), g.pressure(inside) > 85.0)

	# 6) Old save with station and wreck: loads cleanly, the wreck is stored at the place
	Config.ENABLE_STATION = true
	Config.ENABLE_WRECK = true
	gs.new_game()
	# One port: release the station and couple a wreck directly (as after docking at the wreck target)
	st.clear()
	salv.generate()
	var had_wreck: String = salv.wreck_name
	_check("(setup) save with a coupled wreck", had_wreck != "" and _zone(g, 1) == 0 and _zone(ship.grid, 1) > 0)
	save.save_game(true)
	Config.ENABLE_STATION = false
	Config.ENABLE_WRECK = false
	gs.new_game()
	save.load_game(true)
	g = ship.grid
	_check("Loaded: no station tiles, station inactive", _zone(g, 3) == 0 and not st.active())
	_check("Loaded: no wreck tiles", _zone(g, 1) == 0 and salv.wreck_name == "")
	_check("Geladen: Schleusen frei", g.linked.is_empty())
	var parked = null
	for site in fleet.sites:
		if fleet.places.get(site.id, {}).get("wreck") != null:
			parked = fleet.places[site.id].wreck
	_check("Wreck not deleted but stored as its own wreck target (%s)" % (parked.name if parked != null else "-"), parked != null and parked.name == had_wreck)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
