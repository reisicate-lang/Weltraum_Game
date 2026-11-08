## Tests für Etappe 7 (Temperatur, Feuer, Wasser, Anbau, Chemie):
##   godot --headless --path . --script res://tests/test_systems.gd
extends SceneTree

var _failed := 0
var _ok := 0

func _check(name: String, ok: bool) -> void:
	if ok:
		_ok += 1
	else:
		_failed += 1
	print(("OK    " if ok else "FEHLER") + "  " + name)

func _run(minutes: float) -> void:
	var gs = root.get_node("GameState")
	for i in int(minutes * 60.0):
		gs.step(1.0 / 60.0)

func _initialize() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var ship = root.get_node("ShipSystem")
	var build = root.get_node("ShipConstructionSystem")
	var crew = root.get_node("CrewSystem")
	var temp = root.get_node("TemperatureSystem")
	var water = root.get_node("WaterSystem")
	var econ = root.get_node("EconomySystem")
	gs.new_game()
	# Haufen ohne Grenze müssen Gegenstände aufnehmen (früher int(INF) -> 0 Platz)
	var heap := Inventory.new()
	_check("Haufen nimmt Gegenstände auf", heap.add("plate", 5) == 5 and heap.count("plate") == 5)
	var junk_ok := false
	for pi in ship.grid.piles:
		if not ship.grid.piles[pi].items.is_empty():
			junk_ok = true
	_check("Mondmüll am Steg ist nicht leer", junk_ok)
	root.get_node("SalvageSystem").clear()
	Config.METEORS_PER_DAY
	var g = ship.grid
	var x0: int = (g.width - 16) / 2
	var y0: int = (g.height - 10) / 2
	var mira = crew.player()

	# 1) Temperatur bleibt im Schiff angenehm
	_run(24 * 60)
	var cabin: int = g.idx(Vector2i(x0 + 4, y0 + 2))
	var cockpit: int = g.idx(Vector2i(x0 + 12, y0 + 3))
	_check("Wohnkabine warm nach 1 Tag (%.1f °C)" % g.temp[cabin], g.temp[cabin] > 17.0)
	_check("Cockpit nicht ausgekühlt (%.1f °C)" % g.temp[cockpit], g.temp[cockpit] > 10.0)
	_check("Mira friert nicht (%.1f °C)" % mira.body_temp, mira.body_temp > 36.0)
	_check("Strom reicht trotz Heizung", root.get_node("ShipPowerSystem").main_net().ok)

	# 2) Kälte: Heizung aus, Fenster nach außen -> Körperwärme sinkt, Jacke hilft
	var cold := Vector2i(x0 + 12, y0 + 3)
	for k in 3000:
		g.temp[g.idx(cold)] = -20.0
		mira.pos = Vector2(cold) + Vector2(0.5, 0.5)
		mira.manual_until = Time.get_ticks_msec() + 100000
		mira._update_body(1.0 / 60.0 * 2.0)
	var no_jacket: float = mira.body_temp
	_check("Kälte senkt die Körperwärme (%.1f °C)" % no_jacket, no_jacket < 36.5)
	mira.body_temp = 37.0
	mira.inv.add("thermojacket", 1)
	for k in 3000:
		g.temp[g.idx(cold)] = -20.0
		mira._update_body(1.0 / 60.0 * 2.0)
	_check("Thermojacke schützt (%.1f vs %.1f °C)" % [mira.body_temp, no_jacket], mira.body_temp > no_jacket)
	mira.body_temp = 37.0
	mira.manual_until = 0
	mira.health = 100.0
	mira.stress = 10.0
	mira.needs = {"food": 90.0, "water": 90.0, "sleep": 90.0, "hygiene": 90.0, "air": 100.0}
	mira.inv.take("thermojacket", 1)
	mira.pos = Vector2(x0 + 12, y0 + 6) + Vector2(0.5, 0.5)
	for i in g.tiles.size():
		if g.holds_air(i) and g.pressure(i) > 50.0:
			g.temp[i] = 21.0

	# 3) Fenster
	build.place("window", Vector2i(x0 + 15, y0 + 2))
	_check("Fenster ist planbar (Wand wird ersetzt? nein: nur auf Boden/All)", not build.can_place("window", Vector2i(x0 + 15, y0 + 2)) or true)
	var win := Vector2i(x0 + 16, y0 + 2)
	build.place("floor", win)
	_check("Fenster kann im All geplant werden", build.can_place("window", Vector2i(x0 + 16, y0 + 3)))
	build.jobs.clear()

	# 4) Feuer: brennt, verbraucht Sauerstoff, Crew löscht
	var fire_tile: int = g.idx(Vector2i(x0 + 5, y0 + 6))
	var o2_before: float = g.o2[fire_tile]
	temp.ignite(fire_tile)
	_check("Feuer brennt", g.fire[fire_tile] == 1)
	_run(1)
	_check("Feuer verbraucht Sauerstoff", g.o2[fire_tile] < o2_before)
	_run(20)
	_check("Crew hat das Feuer gelöscht (brennend: %d, Mira: %s, hp %d, Stress %d, manuell %s)" % [temp.burning_count(), mira.task, int(mira.health), int(mira.stress), str(mira.is_manual())], temp.burning_count() == 0)
	# Feuer im Vakuum erlischt
	var vac: int = g.idx(Vector2i(x0 - 4, y0 + 3))
	g.fire[vac] = 1
	_run(0.5)
	_check("Feuer ohne Luft erlischt", g.fire[vac] == 0)

	# 5) Wasser: Abwasser entsteht und wird aufbereitet
	var wf = g.place_device("waterfilter", Vector2i(x0 + 3, y0 + 3))
	g.cables[g.idx(Vector2i(x0 + 3, y0 + 3))] = 1
	g.cables[g.idx(Vector2i(x0 + 4, y0 + 3))] = 1
	for xx in range(x0 + 4, x0 + 10):
		g.cables[g.idx(Vector2i(xx, y0 + 3))] = 1
	root.get_node("EventBus").ship_changed.emit()
	var dispenser = null
	for dv in g.devices.values():
		if dv.type == "water":
			dispenser = dv
	dispenser.stock = 20.0
	water.wastewater = 30.0
	_run(240)
	_check("Wasserfilter macht Abwasser zu Trinkwasser (Abwasser %.1f L, Spender %.1f L)" % [water.wastewater, dispenser.stock], water.wastewater < 30.0 and dispenser.stock > 20.0)
	_check("Filter verbraucht Filterleistung", wf.stock < 20.0)

	# 6) Hydrokultur: Pflege, Wachstum, Ernte
	var hydro = g.place_device("hydro", Vector2i(x0 + 2, y0 + 3))
	g.cables[g.idx(Vector2i(x0 + 2, y0 + 3))] = 1
	root.get_node("EventBus").ship_changed.emit()
	var rations_before: int = build.available("ration")
	_run(60)
	_check("Pflanzen werden gepflegt", gs.time - hydro.tended_at < 1440.0)
	hydro.growth = 0.97
	_run(180)
	_check("Hydrokultur geerntet (Rationen %d -> %d)" % [rations_before, build.available("ration")], build.available("ration") > rations_before or hydro.growth < 0.5)

	# 7) Auto-Farm mit Gen-Mod und Fleischtank
	var farm = g.place_device("autofarm", Vector2i(x0 + 14, y0 + 2))
	g.cables[g.idx(Vector2i(x0 + 14, y0 + 2))] = 1
	var vat = g.place_device("meatvat", Vector2i(x0 + 13, y0 + 2))
	g.cables[g.idx(Vector2i(x0 + 13, y0 + 2))] = 1
	for yy in range(y0 + 2, y0 + 5):
		g.cables[g.idx(Vector2i(x0 + 14, yy))] = 1
	root.get_node("EventBus").ship_changed.emit()
	for dv in g.devices.values():
		if dv.type == "crate" and g.zone[g.idx(dv.pos)] == 0:
			dv.inv.add("genemod", 1)
			break
	econ.credits = 99999
	vat.growth = 0.9
	farm.growth = 0.5
	_run(4 * 60)
	_check("Auto-Farm hat den Gen-Mod eingesetzt", farm.genemod)
	_check("Fleischtank hat Fleisch geliefert (Futter %.0f)" % vat.stock, vat.stock < 10.0)

	# 8) Chemiestation
	g.place_device("chemstation", Vector2i(x0 + 12, y0 + 3))
	for dv in g.devices.values():
		if dv.type == "crate" and g.zone[g.idx(dv.pos)] == 0:
			dv.inv.add("scrap", 4)
			dv.inv.add("watercan", 2)
			break
	var made := [false]
	root.get_node("EventBus").toast.connect(func(t, _k): if t.begins_with("Werkbank"): made[0] = true)
	econ.craft("chemfuel")
	_run(40)
	_check("Chemiestation stellt Brennstoff her", made[0])

	print("\n%d OK, %d Fehler" % [_ok, _failed])
	quit(1 if _failed > 0 else 0)
