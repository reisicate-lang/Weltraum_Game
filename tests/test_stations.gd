## Tests für begehbare Stationen
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
	# Eigener Speicherplatz: Tests überschreiben keine echten Spielstände und laufen parallel
	root.get_node("SaveSystem").slot = 908
	# Diese Tests prüfen auch die (vorübergehend abgeschaltete) Station und das Wrack
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

	# 1) Aufbau beim Start (angedockt am Tycho-Schrottplatz)
	_check("Station steht beim Start", st.active() and st.station_id == "tycho")
	_check("Sechs Räume am Schrottplatz (%d)" % st.rooms.size(), st.rooms.size() == 6)
	_check("Luke in der Schiffswand", st.hatch >= 0 and g.tiles[st.hatch] == ShipGrid.Tile.DOOR)
	var overlap := false
	for i in st.tiles:
		if g.zone[i] != 3:
			overlap = true
	_check("Stationsfelder gehören zur Station", not overlap)
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
	_check("Gus sitzt in der Bar", st.npcs.any(func(n): return n.kind == "contact"))
	_check("Bewerber stehen im Heuerbüro", st.npcs.any(func(n): return n.kind == "candidate"))
	_check("Weg vom Schiff zum Markt", not ship.find_path(mira.tile(), market.desk + Vector2i(-1, 0)).is_empty())
	var air_i: int = g.idx(market.desk + Vector2i(-1, 0))
	_check("Station hat Atemluft (%.0f kPa)" % g.pressure(air_i), g.pressure(air_i) > 90.0 and g.o2[air_i] > 19.0)
	_check("Station zählt nicht zur Schiffsmasse", not g.foreign(st.hatch) and g.foreign(air_i))

	# 2) Auf der Station darf man nichts bauen oder abreißen
	_check("Tresen kann man nicht abreißen", not build.can_place("remove", market.desk))
	_check("Luke kann man nicht abreißen", not build.can_place("remove", g.pos(st.hatch)))
	_check("Keine Wand auf dem Stationsboden", not build.can_place("wall", market.desk + Vector2i(-1, 0)))
	var beside := Vector2i(-1, -1)
	for i in st.tiles:
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = g.pos(i) + dd
			if g.in_bounds(q) and g.get_tile(q) == ShipGrid.Tile.SPACE and g.zone[g.idx(q)] == 0:
				beside = q
	_check("Neben der Station darf man bauen", beside.x >= 0 and build.can_place("floor", beside))

	# 3) Hingehen und reden
	var npc: Dictionary = st.npc_for_desk(market.desk)
	_check("Händler gefunden", not npc.is_empty())
	st.approach(mira, npc)
	_check("Mira läuft zum Markt", not st.pending.is_empty())
	var waited := 0
	while not st.pending.is_empty() and waited < 30:
		_run(0.25)
		waited += 1
	_check("Gespräch am Markt geöffnet (%s)" % ui.talk_line, ui.window_kind == "trade" and ui.trade_tab == "sell" and ui.talk_role == "market")
	_check("Mira hat keinen Raumanzug gebraucht", mira.suit == null)
	_check("Mira steht auf der Station", g.zone[g.idx(mira.tile())] == 3)

	# 4) Direkt aus dem Gepäck verkaufen
	mira.inv.add("scrap", 4, 80.0)
	var before: int = econ.credits
	econ.sell("scrap", 4, mira.inv)
	_check("Verkauf aus dem Gepäck (+%d Cr)" % (econ.credits - before), econ.credits > before and mira.inv.count("scrap") == 0)

	# 5) Abdocken geht erst, wenn alle an Bord sind
	seat_pilot()   # Pilot am Steuerpult (Flugbefehle nur dort)
	_check("Abdocken verweigert, solange Mira auf der Station ist", not phys.undock() and phys.docked == "tycho")
	ui.close_window()
	mira.order_move(ship.spawn_point())
	_run(1.0)
	_check("Mira ist zurück an Bord", g.zone[g.idx(mira.tile())] == 0)

	# 6) Luke ist dicht: Schiffsluft und Stationsluft mischen sich nicht durch die Luke
	var hatch_pos: Vector2i = g.pos(st.hatch)
	var inside: int = g.idx(hatch_pos + Vector2i(-1, 0))
	_check("Schiffsluft da", g.pressure(inside) > 50.0)

	# 7) Speichern und Laden baut die Station gleich wieder auf
	var save = root.get_node("SaveSystem")
	save.save_game(true)
	var rooms_before: int = st.rooms.size()
	gs.new_game()
	save.load_game(true)
	_check("Nach dem Laden steht die Station wieder (%d Räume)" % st.rooms.size(), st.active() and st.rooms.size() == rooms_before)
	var zone3 := 0
	for i in ship.grid.tiles.size():
		if ship.grid.zone[i] == 3:
			zone3 += 1
	_check("Keine doppelten Stationsfelder nach dem Laden", zone3 == st.tiles.size())

	# 8) Abdocken entfernt alles, Luke wird wieder Wand
	g = ship.grid
	var h: int = st.hatch
	for c in crew.crew:
		c.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	_run(0.1)
	seat_pilot()   # Pilot am Steuerpult (Flugbefehle nur dort)
	_check("Abdocken klappt", phys.undock())
	_check("Station weg", not st.active() and st.npcs.is_empty())
	_check("Luftschleuse bleibt, nur gelöst (Außentür ist der Port)", g.tiles[h] == ShipGrid.Tile.DOOR and root.get_node("AirlockSystem").is_lock_door(h) and not g.linked.has(h)
		and g.get_tile(g.pos(h) + Vector2i(-1, 0)) == ShipGrid.Tile.SPACE)
	var left := 0
	for i in g.tiles.size():
		if g.zone[i] == 3:
			left += 1
	_check("Keine Stationsfelder mehr", left == 0)

	# 9) Andocken am Kármán-Ring: mit Werft
	phys.dock("karman", true)
	var kinds: Array = st.rooms.map(func(r): return r.kind)
	_check("Kármán-Ring hat eine Werft (%s)" % ", ".join(kinds), "shipyard" in kinds)
	var yard: Dictionary = {}
	for r in st.rooms:
		if r.kind == "shipyard":
			yard = r
	st.talk(st.npc_for_desk(yard.desk), crew.player())
	_check("Werftbüro öffnet den Reiter Schiffe", ui.trade_tab == "ships")
	_check("Lindqvist ist in der Bar", st.npcs.any(func(n): return n.kind == "contact" and "Lindqvist" in n.name))

	# 10) Ein Tag auf der Station: Figuren laufen herum, keiner bleibt stecken
	var start_pos: Array = st.npcs.map(func(n): return n.pos)
	_run(30.0)
	var moved := 0
	for k in st.npcs.size():
		if k < start_pos.size() and st.npcs[k].pos.distance_to(start_pos[k]) > 0.1:
			moved += 1
	_check("Figuren bewegen sich (%d)" % moved, moved >= 2)
	var outside := false
	for n in st.npcs:
		if ship.grid.zone[ship.grid.idx(Vector2i(n.pos))] != 3:
			outside = true
	_check("Figuren bleiben auf der Station", not outside)

	# 11) Kein Andockschlauch am Trümmerfeld
	for c in crew.crew:
		c.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	seat_pilot()   # Pilot am Steuerpult (Flugbefehle nur dort)
	phys.undock()
	phys.dock("debris", true)
	_check("Am Trümmerfeld gibt es keine Station", not st.active())

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
