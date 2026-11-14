## Tests for walkable stations
##   godot --headless --path . --script res://tests/boot.gd -- test_stations
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _run(minutes: float) -> void:
	var gs = root.get_node("GameState")
	for i in int(minutes * 60.0):
		gs.step(1.0 / 60.0)

func _initialize() -> void:
	await process_frame
	await process_frame
	# Own save slot: tests do not overwrite real saves and can run in parallel
	root.get_node("SaveSystem").slot = 908
	# These tests also check the (temporarily disabled) station and the wreck
	Config.ENABLE_STATION = true
	Config.ENABLE_WRECK = true
	var gs = root.get_node("GameState")
	var ship = root.get_node("ShipSystem")
	var st = root.get_node("StationSystem")
	var phys = root.get_node("PhysicsSystem")
	var econ = root.get_node("EconomySystem")
	var crew = root.get_node("CrewSystem")
	var build = root.get_node("ShipConstructionSystem")
	var ui = root.get_node("UIManager")
	root.get_node("Settings").meteors = false
	root.get_node("EventBus").toast.connect(func(t, k): print("  » ", t))
	gs.new_game()
	var g = ship.grid
	var mira = crew.player()

	# 1) Built at the start (docked at the Tycho Scrapyard)
	_check("Station steht beim Start", st.active() and st.station_id == "tycho")
	_check("Six rooms at the scrapyard (%d)" % st.rooms.size(), st.rooms.size() == 6)
	_check("Hatch in the ship wall", st.hatch >= 0 and g.tiles[st.hatch] == ShipGrid.Tile.DOOR)
	var overlap := false
	for i in st.tiles:
		if g.zone[i] != 3:
			overlap = true
	_check("Station tiles belong to the station", not overlap)
	var market: Dictionary = {}
	for r in st.rooms:
		if r.kind == "market":
			market = r
	_check("Markttresen steht", g.device_at(market.desk) != null and g.device_at(market.desk).type == "st_market")
	var staff := 0
	for n in st.npcs:
		if n.kind == "staff":
			staff += 1
	_check("Hinter jedem Tresen steht jemand (%d)" % staff, staff == st.rooms.size())
	_check("Gus sits in the bar", st.npcs.any(func(n): return n.kind == "contact"))
	_check("Applicants stand in the hiring office", st.npcs.any(func(n): return n.kind == "candidate"))
	_check("Path from the ship to the market", not ship.find_path(mira.tile(), market.desk + Vector2i(-1, 0)).is_empty())
	var air_i: int = g.idx(market.desk + Vector2i(-1, 0))
	_check("The station has breathable air (%.0f kPa)" % g.pressure(air_i), g.pressure(air_i) > 90.0 and g.o2[air_i] > 19.0)
	_check("The station does not count towards the ship mass", not g.foreign(st.hatch) and g.foreign(air_i))

	# 2) Nothing may be built or demolished on the station
	_check("Counters cannot be demolished", not build.can_place("remove", market.desk))
	_check("The hatch cannot be demolished", not build.can_place("remove", g.pos(st.hatch)))
	_check("No wall on the station floor", not build.can_place("wall", market.desk + Vector2i(-1, 0)))
	var beside := Vector2i(-1, -1)
	for i in st.tiles:
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = g.pos(i) + dd
			if g.in_bounds(q) and g.get_tile(q) == ShipGrid.Tile.SPACE and g.zone[g.idx(q)] == 0:
				beside = q
	_check("Building next to the station is allowed", beside.x >= 0 and build.can_place("floor", beside))

	# 3) Walk over and talk
	var npc: Dictionary = st.npc_for_desk(market.desk)
	_check("Trader found", not npc.is_empty())
	st.approach(mira, npc)
	_check("Mira walks to the market", not st.pending.is_empty())
	var waited := 0
	while not st.pending.is_empty() and waited < 30:
		_run(0.25)
		waited += 1
	_check("Conversation at the market opened (%s)" % ui.talk_line, ui.window_kind == "trade" and ui.trade_tab == "sell" and ui.talk_role == "market")
	_check("Mira did not need a space suit", mira.suit == null)
	_check("Mira stands on the station", g.zone[g.idx(mira.tile())] == 3)

	# 4) Sell straight from the pack
	mira.inv.add("scrap", 4, 80.0)
	var before: int = econ.credits
	econ.sell("scrap", 4, mira.inv)
	_check("Sale from the pack (+%d Cr)" % (econ.credits - before), econ.credits > before and mira.inv.count("scrap") == 0)

	# 5) Undocking only once everyone is aboard
	seat_pilot()   # Pilot at the navigation console (flight commands only there)
	_check("Undocking refused while Mira is on the station", not phys.undock() and phys.docked == "tycho")
	ui.close_window()
	mira.order_move(ship.spawn_point())
	_run(1.0)
	_check("Mira is back aboard", g.zone[g.idx(mira.tile())] == 0)

	# 6) The hatch is airtight: ship air and station air do not mix through the hatch
	var hatch_pos: Vector2i = g.pos(st.hatch)
	var inside: int = g.idx(hatch_pos + Vector2i(-1, 0))
	_check("Schiffsluft da", g.pressure(inside) > 50.0)

	# 7) Saving and loading rebuilds the station the same way
	var save = root.get_node("SaveSystem")
	save.save_game(true)
	var rooms_before: int = st.rooms.size()
	gs.new_game()
	save.load_game(true)
	_check("After loading the station stands again (%d rooms)" % st.rooms.size(), st.active() and st.rooms.size() == rooms_before)
	var zone3 := 0
	for i in ship.grid.tiles.size():
		if ship.grid.zone[i] == 3:
			zone3 += 1
	_check("No duplicate station tiles after loading", zone3 == st.tiles.size())

	# 8) Undocking removes everything, the hatch becomes wall again
	g = ship.grid
	var h: int = st.hatch
	for c in crew.crew:
		c.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	_run(0.1)
	seat_pilot()   # Pilot at the navigation console (flight commands only there)
	_check("Abdocken klappt", phys.undock())
	_check("Station weg", not st.active() and st.npcs.is_empty())
	_check("The airlock stays, only released (the outer door is the port)", g.tiles[h] == ShipGrid.Tile.DOOR and root.get_node("AirlockSystem").is_lock_door(h) and not g.linked.has(h)
		and g.get_tile(g.pos(h) + Vector2i(-1, 0)) == ShipGrid.Tile.SPACE)
	var left := 0
	for i in g.tiles.size():
		if g.zone[i] == 3:
			left += 1
	_check("No station tiles any more", left == 0)

	# 9) Docking at the Kármán Ring: with a shipyard
	phys.dock("karman", true)
	var kinds: Array = st.rooms.map(func(r): return r.kind)
	_check("The Kármán Ring has a shipyard (%s)" % ", ".join(kinds), "shipyard" in kinds)
	var yard: Dictionary = {}
	for r in st.rooms:
		if r.kind == "shipyard":
			yard = r
	st.talk(st.npc_for_desk(yard.desk), crew.player())
	_check("The shipyard office opens the Ships tab", ui.trade_tab == "ships")
	_check("Lindqvist is in the bar", st.npcs.any(func(n): return n.kind == "contact" and "Lindqvist" in n.name))

	# 10) A day on the station: characters walk around, nobody gets stuck
	var start_pos: Array = st.npcs.map(func(n): return n.pos)
	_run(30.0)
	var moved := 0
	for k in st.npcs.size():
		if k < start_pos.size() and st.npcs[k].pos.distance_to(start_pos[k]) > 0.1:
			moved += 1
	_check("Characters move (%d)" % moved, moved >= 2)
	var outside := false
	for n in st.npcs:
		if ship.grid.zone[ship.grid.idx(Vector2i(n.pos))] != 3:
			outside = true
	_check("Characters stay on the station", not outside)

	# 11) No docking hose at the debris field
	for c in crew.crew:
		c.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	seat_pilot()   # Pilot at the navigation console (flight commands only there)
	phys.undock()
	phys.dock("debris", true)
	_check("There is no station at the debris field", not st.active())

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
