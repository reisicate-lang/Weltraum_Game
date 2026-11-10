## Tests für manuelles Abdocken (von Stationen und anderen Orten)
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

## Frisches Spiel, Crew sicher an Bord
func _fresh() -> void:
	var gs = root.get_node("GameState")
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var ship = root.get_node("ShipSystem")
	for c in root.get_node("CrewSystem").crew:
		c.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
		c.path.clear()
	_run(2)
	seat_pilot()   # Pilot am Steuerpult (Flugbefehle nur dort)

func _initialize() -> void:
	await process_frame
	await process_frame
	# Eigener Speicherplatz: Tests überschreiben keine echten Spielstände und laufen parallel
	root.get_node("SaveSystem").slot = 909
	# Diese Tests prüfen auch die (vorübergehend abgeschaltete) Station und das Wrack
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

	# 1) Abdocken ohne Verbindung
	_fresh()
	P.request_undock()
	_run(2)
	toasts.clear()
	_check("Frei treibend: Abdocken liefert false", not P.request_undock())
	_check("… mit verständlicher Meldung (%s)" % _last(), _last() == "Das Schiff ist nicht angedockt.")

	# 2) Abdocken an einem stillstehenden Ort (Habitat L4 steht fest)
	_fresh()
	P.request_undock()
	P.dock("l4", true)
	_run(2)
	var l4: Dictionary = P.loc_state(P.loc("l4"), P.secs())
	var hull_before := _hull(ship.grid)
	_check("An L4 angedockt, Station steht", P.docked == "l4" and st.active())
	_check("Abdocken von L4 klappt", P.request_undock())
	_check("Keine Sprungbewegung (Abstand %.4f km)" % P.pos.distance_to(l4.pos), P.pos.distance_to(l4.pos) < 0.001)
	var rel: float = (P.vel - l4.vel).length()
	_check("Sanfter Abstoß 3 m/s (%.1f m/s)" % (rel * 1000.0), absf(rel - P.UNDOCK_PUSH) < 0.0002)
	_check("Station und Luke entfernt", not st.active() and st.hatch == -1)
	_check("Wrack-Zustand am Ort abgelegt", fleet.places.has("l4"))
	_run(30)
	var r: Dictionary = P.rel_to("l4")
	_check("Schiff treibt gleichmäßig weg (%.0f m nach 30 s)" % (r.dist * 1000.0), r.dist > 0.07 and r.dist < 0.12)
	_check("Kein Zusammenstoß, Hülle unversehrt", _hull(ship.grid) == hull_before and not toasts.any(func(t): return "Zusammenstoß" in t))

	# 3) Abdocken an einem bewegten Ort (Kármán-Ring kreist um die Erde)
	_fresh()
	P.request_undock()
	P.dock("karman", true)
	_run(5)
	var k0: Dictionary = P.loc_state(P.loc("karman"), P.secs())
	P.angle = 1.0
	_check("Kármán-Ring bewegt sich (%.2f km/s)" % k0.vel.length(), k0.vel.length() > 1.0)
	_check("Abdocken vom bewegten Ring klappt", P.request_undock())
	_check("Bahngeschwindigkeit bleibt erhalten (%.3f km/s)" % P.vel.length(), absf(P.vel.length() - k0.vel.length()) < 0.01)
	_check("Ausrichtung bleibt erhalten", absf(P.angle - 1.0) < 0.0001)
	_check("Relativ nur der Abstoß (%.1f m/s)" % ((P.vel - k0.vel).length() * 1000.0), absf((P.vel - k0.vel).length() - P.UNDOCK_PUSH) < 0.0002)
	_run(20)
	var rk: Dictionary = P.rel_to("karman")
	_check("Mit dem Ring mitgeflogen, nicht zurückgeblieben (%.0f m)" % (rk.dist * 1000.0), rk.dist < 0.2)

	# 4) Mehrfaches schnelles Auslösen
	_fresh()
	toasts.clear()
	var first: bool = P.request_undock()
	var v1: Vector2 = P.vel
	var second: bool = P.request_undock()
	var third: bool = P.request_undock()
	_check("Nur der erste Aufruf dockt ab", first and not second and not third)
	_check("Abstoß nur einmal", P.vel == v1)
	_check("Genau eine Erfolgsmeldung", toasts.filter(func(t): return t.begins_with("Abgedockt")).size() == 1)

	# 5) Blockierende Sicherheitsbedingungen
	_fresh()
	var mira = crew.player()
	var market: Vector2i = st.rooms[0].desk + Vector2i(-1, 0)
	mira.pos = Vector2(market) + Vector2(0.5, 0.5)
	toasts.clear()
	_check("Crew auf der Station: Abdocken verweigert", not P.request_undock() and P.docked == "tycho" and st.active())
	_check("… Meldung nennt die Person (%s)" % _last(), mira.display_name in _last())
	mira.pos = Vector2(ship.grid.pos(st.hatch)) + Vector2(0.5, 0.5)
	_check("Crew in der Luke: verweigert (%s)" % P.undock_block_reason(), not P.request_undock() and "Luke" in _last())
	mira.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	var wreck_tile := Vector2i(-1, -1)
	for i in ship.grid.tiles.size():
		if ship.grid.zone[i] == 1 and ship.grid.walkable(ship.grid.pos(i)):
			wreck_tile = ship.grid.pos(i)
			break
	mira.pos = Vector2(wreck_tile) + Vector2(0.5, 0.5)
	_check("Crew auf dem Wrack: verweigert (%s)" % P.undock_block_reason(), not P.request_undock() and "Wrack" in _last())
	mira.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	var helm = P.ship_devices("helm")[0]
	helm.broken = true
	_check("Steuerpult kaputt: verweigert (%s)" % P.undock_block_reason(), not P.request_undock() and "kaputt" in _last())
	helm.broken = false
	_run(2)
	_check("Nach Beheben der Gründe klappt es", P.request_undock() and P.docked == "")

	# 6) Erneutes Andocken: erst gesperrt, nach Trennung und Sperrzeit wieder möglich
	_fresh()
	P.request_undock()
	_check("Sofort wieder andocken gesperrt", not P.can_dock("tycho") and not P.dock("tycho"))
	_check("… Grund wird genannt (%s)" % P.dock_block_reason("tycho"), "Gerade erst abgedockt" in P.dock_block_reason("tycho"))
	toasts.clear()
	P.start_autodock()
	_check("Auto-Dock ist ebenfalls gesperrt", P.autodock.is_empty() and "Gerade erst abgedockt" in _last())
	_run(16)
	# Bewusst zurückmanövrieren: Geschwindigkeit angleichen und heranfliegen
	var t0: Dictionary = P.loc_state(P.loc("tycho"), P.secs())
	P.vel = t0.vel
	P.pos = t0.pos + Vector2(0.05, 0)
	P.angle = P.dock_alignment("tycho").angle   # Schleuse zum Ziel drehen
	_check("Nach Sperrzeit und Annäherung wieder andockbar", P.can_dock("tycho") and P.dock("tycho") and P.docked == "tycho" and st.active())

	# 7) Alle Zeitstufen über den echten TimeSystem-Ablauf (×1, ×2, ×4, ×8, ×16)
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
		_check("Zeitstufe %d: frei, ohne Wiederandocken, gleichmäßig (%.0f m, %.1f m/s, %d Bilder)" % [si, rr.dist * 1000.0, rr.speed * 1000.0, frames],
			P.docked == "" and rr.speed > 0.0025 and rr.speed < 0.0035 and rr.dist > 0.1 and rr.dist < 0.3)
		_check("Zeitstufe %d: kein Zusammenstoß" % si, _hull(ship.grid) == hb and not toasts.any(func(t): return "Zusammenstoß" in t))
	time.set_speed(0)

	# 8) Speichern und Laden nach dem Abdocken
	_fresh()
	P.request_undock()
	_run(5)
	var p_before: Vector2 = P.pos
	var v_before: Vector2 = P.vel
	save.save_game(true)
	root.get_node("GameState").new_game()
	save.load_game(true)
	_check("Nach dem Laden nicht angedockt", P.docked == "" and not st.active())
	_check("Position und Geschwindigkeit erhalten", P.pos.distance_to(p_before) < 0.000001 and P.vel.distance_to(v_before) < 0.000001)
	var zone3 := 0
	for i in ship.grid.tiles.size():
		if ship.grid.zone[i] == 3:
			zone3 += 1
	_check("Keine Stationsreste im Schiff", zone3 == 0)
	_check("Sperre gegen Wieder-Andocken mitgeladen", P.redock_locked("tycho"))
	_run(12)
	_check("Weiter steuerbar nach dem Laden (Drift geht weiter)", P.pos.distance_to(p_before) > 0.02)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
