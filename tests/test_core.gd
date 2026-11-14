## Kernspiel mit abgeschalteter Station und abgeschaltetem Wrack (beide Schalter aus)
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
	# Eigener Speicherplatz: Tests überschreiben keine echten Spielstände und laufen parallel
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

	# Station und Wrack sind im Spiel eingeschaltet; hier wird der Kern mit beiden Schaltern aus geprüft
	_check("Standard: Station und Wrack eingeschaltet", Config.ENABLE_STATION and Config.ENABLE_WRECK)
	Config.ENABLE_STATION = false
	Config.ENABLE_WRECK = false

	# 1) Neues Spiel: keine Station, kein Wrack
	gs.new_game()
	gs.step(1.0 / 60.0)   # einmal rechnen, damit das Stromnetz steht
	var g = ship.grid
	_check("Keine Stationsfelder, Station inaktiv", _zone(g, 3) == 0 and not st.active() and st.npcs.is_empty())
	_check("Keine Wrackfelder, kein Wrack", _zone(g, 1) == 0 and salv.wreck_name == "" and salv.port == -1)
	_check("Keine Schleuse verbunden", g.linked.is_empty())
	_check("Trotzdem an Tycho angedockt, Terminal online", P.docked == "tycho" and econ.terminal_online())

	# 2) Handel geht weiter, Bergung nicht
	var cr: int = econ.credits
	toasts.clear()
	econ.buy_claim()
	_check("Bergungsrecht abgelehnt, mit Meldung", econ.credits == cr and toasts.any(func(t): return "Salvage is temporarily disabled" in t))
	econ.terminal().inv.add("scrap", 3, 80.0)
	econ.sell_all()
	_check("Verkaufen am Terminal geht", econ.credits > cr)
	ui.open_window("trade")
	var labels: Array = []
	for b in ui.window_box.find_children("*", "Button", true, false):
		labels.append(b.text)
	_check("Reiter „Bergung“ ist ausgeblendet", not "Salvage" in labels and "Sell" in labels)
	ui.close_window()

	# 3) Ziele: Wrack-Ziele werden übersprungen
	goals.done.clear()
	goals.done.append("suit")
	_check("Nach dem Raumanzug kommt „Verkaufen“ (%s)" % goals.current().get("id", ""), goals.current().get("id", "") == "sell")

	# 4) Ab- und wieder andocken, Reisen: keine Felder entstehen
	gs.step(1.0 / 60.0)
	seat_pilot()   # Pilot am Steuerpult (Flugbefehle nur dort)
	_check("Abdocken klappt", P.request_undock())
	for k in 20 * 60:
		gs.step(1.0 / 60.0)
	_check("Wieder andocken an Tycho", P.dock("tycho", true) and P.docked == "tycho")
	_check("… ohne Station und Wrack", _zone(g, 3) == 0 and _zone(g, 1) == 0)
	seat_pilot()   # Pilot am Steuerpult (Flugbefehle nur dort)
	P.request_undock()
	P.dock("debris", true)
	_check("Trümmerfeld: kein Wrack", _zone(g, 1) == 0 and salv.wreck_name == "")
	seat_pilot()   # Pilot am Steuerpult (Flugbefehle nur dort)
	P.request_undock()
	P.dock("kx7", true)
	_check("Asteroid: kein Felsbrocken", _zone(g, 1) == 0)
	seat_pilot()   # Pilot am Steuerpult (Flugbefehle nur dort)
	P.request_undock()
	P.dock("tycho", true)

	# 5) Ein Tag Kernspiel: Mira lebt, Luft hält
	var mira = crew.player()
	for k in 24 * 60 * 12:   # 5 Spielsekunden pro Schritt
		gs.step(5.0 / 60.0)
	_check("Nach einem Tag: Mira gesund (%d)" % int(mira.health), mira.health > 80.0)
	var inside: int = g.idx(ship.spawn_point())
	_check("Nach einem Tag: Luft im Schiff (%d kPa)" % int(g.pressure(inside)), g.pressure(inside) > 85.0)

	# 6) Alter Spielstand mit Station und Wrack: lädt sauber, Wrack wird am Ort abgelegt
	Config.ENABLE_STATION = true
	Config.ENABLE_WRECK = true
	gs.new_game()
	# Ein Port: Station lösen und ein Wrack direkt ankoppeln (wie nach dem Andocken am Wrackziel)
	st.clear()
	salv.generate()
	var had_wreck: String = salv.wreck_name
	_check("(Vorbereitung) Spielstand mit angekoppeltem Wrack", had_wreck != "" and _zone(g, 1) == 0 and _zone(ship.grid, 1) > 0)
	save.save_game(true)
	Config.ENABLE_STATION = false
	Config.ENABLE_WRECK = false
	gs.new_game()
	save.load_game(true)
	g = ship.grid
	_check("Geladen: keine Stationsfelder, Station inaktiv", _zone(g, 3) == 0 and not st.active())
	_check("Geladen: keine Wrackfelder", _zone(g, 1) == 0 and salv.wreck_name == "")
	_check("Geladen: Schleusen frei", g.linked.is_empty())
	var parked = null
	for site in fleet.sites:
		if fleet.places.get(site.id, {}).get("wreck") != null:
			parked = fleet.places[site.id].wreck
	_check("Wrack nicht gelöscht, sondern als eigenes Wrackziel abgelegt (%s)" % (parked.name if parked != null else "-"), parked != null and parked.name == had_wreck)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
