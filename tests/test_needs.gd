## Tests für die Tageszeit und die Abstände von Hunger und Durst
##   godot --headless --path . --script res://tests/boot.gd -- test_needs
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

func _initialize() -> void:
	await process_frame
	await process_frame
	root.get_node("Settings").meteors = false
	var gs = root.get_node("GameState")
	var ts = root.get_node("TimeSystem")
	gs.new_game()

	# 1) Bei ×1 ist eine echte Sekunde eine Spielsekunde, ein Spieltag also 24 echte Stunden
	ts.set_speed(1)
	var per_sec: float = Config.SPEEDS[ts.speed_index] * Config.MINUTES_PER_SECOND
	_check("×1: 1 echte Sekunde = 1 Spielsekunde", absf(per_sec * 60.0 - 1.0) < 1e-9)
	_check("×1: ein Spieltag dauert 24 echte Stunden (%.1f h)" % (1440.0 / per_sec / 3600.0), absf(1440.0 / per_sec - 86400.0) < 1e-6)
	_check("×16: ein Spieltag dauert 90 echte Minuten", absf(1440.0 / (16.0 * Config.MINUTES_PER_SECOND) / 60.0 - 90.0) < 1e-6)
	ts.set_speed(0)

	# 2) Abstände laut Werten: wach etwa alle 6 h essen, alle 2 h trinken, leer nach etwa 20 h
	var f: Dictionary = Config.NEEDS.food
	var w: Dictionary = Config.NEEDS.water
	_check("Mahlzeit etwa alle 6 h (%.1f h)" % (f.gain / f.decay), f.gain / f.decay >= 5.0 and f.gain / f.decay <= 7.0)
	_check("Glas Wasser etwa alle 2 h (%.1f h)" % (w.gain / w.decay), w.gain / w.decay >= 1.5 and w.gain / w.decay <= 3.0)
	_check("Ohne Essen leer nach 20 h", absf(100.0 / f.decay - 20.0) < 0.01)
	_check("Ohne Trinken leer nach 20 h", absf(100.0 / w.decay - 20.0) < 0.01)

	# 3) Ein halber Tag (12 h) mit der Startcrew: Mira isst 2×, trinkt 5–7×, bleibt gesund
	var crew = root.get_node("CrewSystem").crew
	var m = crew[0]
	var meals := 0
	var drinks := 0
	var last := ""
	var lowest := {"food": 100.0, "water": 100.0}
	var g = root.get_node("ShipSystem").grid
	var food0 := 0.0
	var water0 := 0.0
	for d in g.devices.values():
		if d.data().need == "food": food0 += d.stock
		if d.data().need == "water": water0 += d.stock
	for k in 12 * 60 * 2:
		gs.step(0.5)
		var a: String = str(m.activity.get("need", "")) if m.activity is Dictionary else ""
		if a != last:
			if a == "food": meals += 1
			if a == "water": drinks += 1
		last = a
		for n in lowest:
			lowest[n] = minf(lowest[n], m.needs[n])
	var food1 := 0.0
	var water1 := 0.0
	for d in g.devices.values():
		if d.data().need == "food": food1 += d.stock
		if d.data().need == "water": water1 += d.stock
	_check("12 h: %d Mahlzeiten (erwartet 2)" % meals, meals == 2)
	_check("12 h: %d Gläser Wasser (erwartet 5–7)" % drinks, drinks >= 5 and drinks <= 7)
	_check("Hunger und Durst bleiben im grünen Bereich (min. %.0f / %.0f)" % [lowest.food, lowest.water], lowest.food > 55.0 and lowest.water > 75.0)
	_check("Gesundheit bleibt voll (%.1f)" % m.health, m.health >= 99.9)
	_check("Verbrauch Essen %.2f Portionen (erwartet ca. 1)" % (food0 - food1), food0 - food1 > 0.8 and food0 - food1 < 1.6)
	_check("Verbrauch Wasser %.2f l (erwartet unter 1 l)" % (water0 - water1), water0 - water1 > 0.4 and water0 - water1 < 1.0)

	# 4) Im Anzug unterbricht leichter Durst die Arbeit nicht, starker schon
	m.stop_activity()
	m.release_job()
	m.suit = {"o2": 100.0, "battery": 100.0}
	m.needs.water = 75.0
	m.needs.food = 90.0
	_check("Im Anzug: Durst 75 unterbricht nicht", not m._start_need())
	m.needs.water = 55.0
	_check("Im Anzug: Durst 55 unterbricht", m._start_need() and m.activity.need == "water")
	m.stop_activity()
	m.suit = null
	m.needs.water = 85.0
	_check("Ohne Anzug: Durst 85 führt zum Wasserspender", m._start_need() and m.activity.need == "water")
	m.stop_activity()

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
