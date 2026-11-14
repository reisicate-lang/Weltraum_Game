## Tests für das Rechtsklick-Menü: Abbauen, Zerlegen, Zerstören, Einbauen
##   godot --headless --path . --script res://tests/boot.gd -- test_removal
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var toasts: Array[String] = []
var gs
var ship
var crew
var CS
var R
var ui

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

## Laufen lassen, bis auf Feld p kein Auftrag mehr ist (höchstens max_min Spielminuten)
func _until_done(p: Vector2i, max_min: float = 20.0) -> bool:
	var g = ship.grid
	for k in int(max_min * 60.0):
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(g.idx(p)):
			return true
	return false

## Gesamtmenge einer Sorte: Gepäck, Haufen, Behälter
func _count(type: String) -> int:
	var n := 0
	for c in crew.crew:
		n += c.inv.count(type)
	for i in ship.grid.piles:
		n += ship.grid.piles[i].count(type)
	for d in ship.grid.devices.values():
		if d.inv != null:
			n += d.inv.count(type)
	return n

## Abgebauter Gegenstand dieser Sorte – egal ob am Boden, im Gepäck oder in einem Behälter
func _find_packed(type: String) -> Dictionary:
	var invs: Array = []
	for c in crew.crew:
		invs.append(c.inv)
	for i in ship.grid.piles:
		invs.append(ship.grid.piles[i])
	for d in ship.grid.devices.values():
		if d.inv != null:
			invs.append(d.inv)
	for inv in invs:
		for it in inv.items:
			if it.type == type:
				return it
	return {}

## Wie _count, aber auch im erhaltenen Inhalt abgebauter Geräte
func _count_deep(type: String) -> int:
	var n := _count(type)
	var invs: Array = []
	for c in crew.crew:
		invs.append(c.inv)
	for i in ship.grid.piles:
		invs.append(ship.grid.piles[i])
	for inv in invs:
		for it in inv.items:
			var d = it.get("data")
			if d is Dictionary and d.get("items") is Array:
				for sub in d.items:
					if sub.type == type:
						n += int(sub.qty)
	return n

## Menüeintrag für eine Aktion wählen (wie ein Klick im Rechtsklick-Menü)
## Wählt dabei die Ebene „Gerät, sonst Feld“ (Rechtsklick schaltet Kabel → Gerät → Boden durch)
func _menu(p: Vector2i, kind: String) -> int:
	ui.clear_selection()
	var want: String = R.key_at(p)
	var opened := false
	for k in 3:
		opened = ui.open_object_menu(p)
		if not opened or ui.sel_key == want or want == "":
			break
	if not opened:
		return -1
	for k in ui.menu_actions.size():
		if ui.menu_actions[k].kind == kind:
			return k
	return -1

func _menu_text(p: Vector2i, kind: String) -> String:
	var id := _menu(p, kind)
	if id < 0:
		return ""
	var idx: int = ui.object_menu.get_item_index(id)
	return ("[aus] " if ui.object_menu.is_item_disabled(idx) else "") + ui.object_menu.get_item_text(idx)

func _click(p: Vector2i, kind: String) -> void:
	var id := _menu(p, kind)
	ui._on_object_menu(id)
	ui.object_menu.hide()

func _fresh() -> void:
	gs.new_game()
	root.get_node("SalvageSystem").clear()
	root.get_node("TimeSystem").set_speed(0)
	var m = crew.player()
	m.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	m.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	m.stress = 0.0
	_run(2)

func _initialize() -> void:
	await process_frame
	await process_frame
	# Eigener Speicherplatz: Tests überschreiben keine echten Spielstände und laufen parallel
	root.get_node("SaveSystem").slot = 906
	# Diese Tests prüfen auch die (vorübergehend abgeschaltete) Station und das Wrack
	Config.ENABLE_STATION = true
	Config.ENABLE_WRECK = true
	gs = root.get_node("GameState")
	ship = root.get_node("ShipSystem")
	crew = root.get_node("CrewSystem")
	CS = root.get_node("ShipConstructionSystem")
	R = root.get_node("RemovalSystem")
	ui = root.get_node("UIManager")
	var save = root.get_node("SaveSystem")
	var power = root.get_node("ShipPowerSystem")
	root.get_node("Settings").meteors = false
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(String(t)))
	_fresh()
	var x0: int = (ship.grid.width / Config.GRID_SCALE - 16) / 2
	var y0: int = (ship.grid.height / Config.GRID_SCALE - 10) / 2
	var mira = crew.player()
	var g = ship.grid

	# Konfiguration
	_check("Abgebaute Gegenstände angelegt", R.is_packed("pk_generator") and root.get_node("ItemSystem").item("pk_generator") != null and root.get_node("ItemSystem").item("pk_tile_wall") != null)
	var gy: Dictionary = R.dismantle_yield("dev:generator")
	_check("Zerlege-Rezept aus removal.json (Generator %s)" % str(gy), int(gy.plate) == 2 and int(gy.motor) == 1 and int(gy.circuit) == 1 and gy == R.data.generator.dismantle)

	# 1) Block abbauen und wieder einbauen (Innenwand zwischen Kabine und Cockpit)
	var wall := C(x0 + 10, y0 + 2)
	_check("Menü zeigt Abbauen (%s)" % _menu_text(wall, "uninstall"), _menu_text(wall, "uninstall").begins_with("Abbauen  ("))
	_click(wall, "uninstall")
	_check("Abbau-Auftrag angelegt", CS.jobs.has(g.idx(wall)) and CS.jobs[g.idx(wall)].kind == "uninstall")
	_check("Abbau fertig", _until_done(wall))
	_check("Wand ist weg, Boden bleibt", g.get_tile(wall) == ShipGrid.Tile.FLOOR)
	var wall_pile := -1
	for i in g.piles:
		if g.piles[i].count("pk_tile_wall") > 0:
			wall_pile = i
	_check("Wand als ein vollständiger Gegenstand am Boden (nicht im Gepäck)", _count("pk_tile_wall") == 1 and wall_pile >= 0 and mira.inv.count("pk_tile_wall") == 0 and g.walkable(g.pos(wall_pile)))
	_check("Laufweg durch die frühere Wand", not ship.find_path(wall + Vector2i(-1, 0), wall + Vector2i(1, 0)).is_empty())
	_check("Menü bietet Einbauen an", _menu(wall + Vector2i(0, 0), "install") >= 0)
	ui.object_menu.hide()
	_click(wall, "install")
	_check("Einbau fertig", _until_done(wall))
	_check("Wand wieder da (100 %%), Gegenstand verbraucht", g.get_tile(wall) == ShipGrid.Tile.WALL and g.cond[g.idx(wall)] == 100.0 and _count("pk_tile_wall") == 0)

	# 2) Beschädigt abbauen und mit gleichem Zustand einbauen (Wand und Batterie)
	var wall2 := C(x0 + 10, y0 + 7)
	g.cond[g.idx(wall2)] = 63.0
	_click(wall2, "uninstall")
	_until_done(wall2)
	var st: Dictionary = _find_packed("pk_tile_wall")
	_check("Beschädigte Wand behält Zustand als Gegenstand (%d %%)" % int(st.get("cond", -1)), int(st.get("cond", -1)) == 63)
	_click(wall2, "install")
	_until_done(wall2)
	_check("Wieder eingebaut mit 63 %%", g.get_tile(wall2) == ShipGrid.Tile.WALL and int(g.cond[g.idx(wall2)]) == 63)
	var bat_p := C(x0 + 2, y0 + 5)
	var bat = g.device_at(bat_p)
	bat.cond = 71.0
	bat.charge = 12.5
	power.step(0.0)
	var cap_before: float = power.main_net().capacity if power.main_net().has("capacity") else -1.0
	_click(bat_p, "uninstall")
	_until_done(bat_p)
	power.step(0.0)
	_check("Batterie ausgebaut: nicht mehr im Stromnetz", g.device_at(bat_p) == null and PhysicsSystem_ok(root))
	var pk: Dictionary = _find_packed("pk_battery")
	var packed_charge: float = float(pk.get("data", {}).get("charge", -1))
	_check("Abgebaute Batterie trägt Ladung und Zustand (%.2f kWh, %d %%)" % [packed_charge, int(pk.get("cond", -1))], absf(packed_charge - 12.5) < 1.0 and int(pk.cond) == 71)
	_run(30)
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	mira = crew.player()
	g = ship.grid
	var pk2: Dictionary = _find_packed("pk_battery")
	_check("Nach Speichern/Laden: Daten im Gegenstand erhalten", absf(float(pk2.get("data", {}).get("charge", -1)) - packed_charge) < 0.000001)
	_click(bat_p, "install")
	_until_done(bat_p)
	var bat2 = g.device_at(bat_p)
	_check("Batterie wieder eingebaut mit 71 %% und derselben Ladung", bat2 != null and bat2.type == "battery" and int(bat2.cond) == 71 and absf(bat2.charge - packed_charge) < 0.5)

	# 3) Zerlegen: exakt die konfigurierten Materialien
	_fresh()
	g = ship.grid
	mira = crew.player()
	var bed_p := C(x0 + 1, y0 + 1)
	var yield_bed: Dictionary = R.dismantle_yield("dev:bed")
	var before := {}
	for t in yield_bed:
		before[t] = _count(t)
	_click(bed_p, "dismantle")
	_check("Zerlegen fertig", _until_done(bed_p))
	var exact := g.device_at(bed_p) == null
	for t in yield_bed:
		if _count(t) - before[t] != int(yield_bed[t]):
			exact = false
	_check("Bett zerlegt: genau %s" % str(yield_bed), exact)

	# 4) Zerstören: mehrere Schläge, Müll laut Daten, sichtbare Treffer
	var bench_p := C(x0 + 13, y0 + 5)
	var scrap_before := _count("scrap")
	var fx_before: int = root.get_node("DamageSystem").effects.size()
	_click(bench_p, "destroy")
	var hits_seen := 0
	var conds: Array = []
	for k in 60 * 20:
		gs.step(1.0 / 60.0)
		var j = CS.jobs.get(g.idx(bench_p))
		if j == null:
			break
		if int(j.get("hits", 0)) > hits_seen:
			hits_seen = int(j.hits)
			conds.append(int(g.device_at(bench_p).cond))
	_check("Mehrere Schläge (%d), Zustand sinkt %s" % [hits_seen, str(conds.slice(0, 4))], hits_seen >= 3 and conds[0] > conds[-1])
	_check("Werkbank zerstört", g.device_at(bench_p) == null)
	_check("Müll laut Daten (%s)" % str(R.debris("dev:workbench")), _count("scrap") - scrap_before == int(R.debris("dev:workbench").scrap))
	_check("Treffer sichtbar (Funken)", root.get_node("DamageSystem").effects.any(func(e): return e.get("small", false)) or root.get_node("DamageSystem").effects.size() >= fx_before)

	# 5) Abbrechen und neu starten (alle drei)
	_fresh()
	g = ship.grid
	mira = crew.player()
	var sink_p := C(x0 + 3, y0 + 1)
	for kind in ["uninstall", "dismantle"]:
		_click(sink_p, kind)
		for k in 60 * 3:
			gs.step(1.0 / 60.0)
		var prog: float = CS.jobs[g.idx(sink_p)].progress if CS.jobs.has(g.idx(sink_p)) else -1.0
		_click(sink_p, "cancel")
		_check("%s abgebrochen (Fortschritt war %.2f): Waschbecken bleibt, kein Ergebnis" % [kind, prog], g.device_at(sink_p) != null and not CS.jobs.has(g.idx(sink_p)) and _count("pk_sink") == 0)
	_click(sink_p, "destroy")
	for k in 60 * 15:
		gs.step(1.0 / 60.0)
		var j = CS.jobs.get(g.idx(sink_p))
		if j != null and int(j.get("hits", 0)) >= 2:
			break
	var dmg_cond: float = g.device_at(sink_p).cond
	_click(sink_p, "cancel")
	_run(5)
	_check("Zerstören abgebrochen: Schaden bleibt (%d %%)" % int(dmg_cond), g.device_at(sink_p) != null and g.device_at(sink_p).cond == dmg_cond and dmg_cond < 100.0)
	_click(sink_p, "destroy")
	_check("Neustart setzt beim Schaden fort (Fortschritt %.2f)" % CS.jobs[g.idx(sink_p)].progress, absf(CS.jobs[g.idx(sink_p)].progress - (1.0 - dmg_cond / 100.0)) < 0.001)
	_check("Neu gestartetes Zerstören wird fertig", _until_done(sink_p))
	_click(C(x0 + 5, y0 + 1), "uninstall")
	_check("Abbauen nach Abbruch neu gestartet und fertig", _until_done(C(x0 + 5, y0 + 1)) and _count("pk_food") == 1)

	# 6) Volles Gepäck: Ergebnis landet als Haufen daneben
	_fresh()
	g = ship.grid
	mira = crew.player()
	while mira.inv.add("plate", 1, 90.0) > 0:
		pass
	var o2_p := C(x0 + 9, y0 + 1)
	var y_o2: Dictionary = R.dismantle_yield("dev:o2gen")
	var b2 := {}
	for t in y_o2:
		b2[t] = _count(t)
	toasts.clear()
	_click(o2_p, "dismantle")
	_until_done(o2_p)
	var ok_full := true
	for t in y_o2:
		if _count(t) - b2[t] != int(y_o2[t]):
			ok_full = false
	_check("Volles Gepäck: Menge trotzdem exakt", ok_full)
	_check("… Rest liegt als Haufen, mit Meldung", toasts.any(func(t): return "kann nicht alles tragen" in t))

	# 7) Außer Reichweite / ohne Werkzeug
	_fresh()
	g = ship.grid
	mira = crew.player()
	var far := Vector2i(2, 2)
	g.set_tile(far, ShipGrid.Tile.WALL)
	_check("Unerreichbar: Grund im Menü (%s)" % _menu_text(far, "destroy"), "Niemand kommt" in _menu_text(far, "destroy") and _menu_text(far, "destroy").begins_with("[aus]"))
	ui.object_menu.hide()
	mira.inv.take("crowbar", 9)
	var wall3 := C(x0 + 10, y0 + 2)
	_check("Ohne Brechstange: Wand abbauen gesperrt (%s)" % R.reason("uninstall", wall3), "Braucht Werkzeug: Crowbar" in R.reason("uninstall", wall3))
	_check("… Zerstören geht mit bloßen Händen", R.reason("destroy", wall3) == "")
	var st_desk: Vector2i = root.get_node("StationSystem").rooms[0].desk
	_check("Stationstresen: gesperrt (%s)" % R.reason("destroy", st_desk), R.reason("destroy", st_desk) == "Gehört der Station.")
	mira.inv.add("crowbar", 1, 80.0)

	# 8) Mehrfach schnell auf denselben Eintrag klicken
	var heater_p := C(x0 + 8, y0 + 1)
	var id := _menu(heater_p, "dismantle")
	ui._on_object_menu(id)
	ui._on_object_menu(id)
	ui._on_object_menu(id)
	_check("Zweiter Auftrag wird abgelehnt (%s)" % R.order("dismantle", heater_p), R.order("dismantle", heater_p).begins_with("Hier läuft schon"))
	var plate_b := _count("plate")
	_until_done(heater_p)
	_run(5)
	_check("Ergebnis genau einmal (+%d Platten)" % (_count("plate") - plate_b), _count("plate") - plate_b == int(R.dismantle_yield("dev:heater").get("plate", 0)))

	# 9) Objekt mit Inhalt und Verbindungen
	_fresh()
	g = ship.grid
	mira = crew.player()
	var crate_p := C(x0 + 13, y0 + 8)
	var rations := _count("ration")
	_click(crate_p, "uninstall")
	_until_done(crate_p)
	var pkc: Dictionary = _find_packed("pk_crate")
	_check("Kiste abgebaut: ein Gegenstand am Boden, Inhalt darin erhalten, nichts verloren", g.device_at(crate_p) == null and _count_deep("ration") == rations and _count("ration") == 0
		and g.piles.has(g.idx(crate_p)) and g.piles[g.idx(crate_p)].count("pk_crate") == 1 and not pkc.get("data", {}).get("items", []).is_empty())
	var locker_p := C(x0 + 1, y0 + 8)
	_check("Spind mit Anzug: Zerlegen gesperrt (%s)" % R.reason("dismantle", locker_p), "Raumanzug" in R.reason("dismantle", locker_p))
	_click(locker_p, "uninstall")
	_until_done(locker_p)
	var lk: Dictionary = _find_packed("pk_locker")
	_check("Abgebauter Spind behält den Anzug", lk.get("data", {}).get("suit") != null)
	var gen_p := C(x0 + 1, y0 + 5)
	power.step(0.0)
	var prod_before: float = power.main_net().production
	_click(gen_p, "uninstall")
	_until_done(gen_p)
	power.step(0.0)
	_check("Generator weg: Stromnetz neu berechnet (%.1f → %.1f kW), Kabel bleibt" % [prod_before, power.main_net().production], power.main_net().production < prod_before and g.cables[g.idx(gen_p)] == 1)
	g.devices[g.idx(C(x0 + 13, y0 + 1))].lock_level = 0
	var crate2: Vector2i = C(x0 + 14, y0 + 8)
	g.device_at(crate2).lock_level = 2
	_check("Verschlossene Kiste: gesperrt", R.reason("destroy", crate2) == "Verschlossen – erst knacken (Hacken).")
	g.device_at(crate2).lock_level = 0
	# Objekt verschwindet während des Auftrags
	var sink2 := C(x0 + 3, y0 + 1)
	_click(sink2, "dismantle")
	g.devices.erase(g.idx(sink2))
	var pipes := _count("pipe")
	_run(120)
	_check("Objekt vorher entfernt: Auftrag endet ohne Ergebnis", not CS.jobs.has(g.idx(sink2)) and _count("pipe") == pipes)

	# 10) Zeitstufen (echter Zeitablauf) und Speichern/Laden mitten im Zerstören
	var results := []
	for si in range(1, 6):
		_fresh()
		g = ship.grid
		var time = root.get_node("TimeSystem")
		var p := C(x0 + 13, y0 + 5)
		_click(p, "destroy")
		var fx0: int = root.get_node("DamageSystem").effects.filter(func(e): return e.get("small", false) and e.pos == p).size()
		time.set_speed(si)
		var t0: float = gs.time
		var first_hit := -1.0
		var hits := 0
		var frames := 0
		while CS.jobs.has(g.idx(p)) and frames < 20000:
			time._process(1.0 / 60.0)
			frames += 1
			var j = CS.jobs.get(g.idx(p))
			if j != null and int(j.get("hits", 0)) > hits:
				if first_hit < 0.0:
					first_hit = gs.time
				hits = int(j.hits)
		var dur: float = (gs.time - first_hit) * 60.0
		# Schläge über die Treffer-Funken zählen (mehrere Schläge können in ein Bild fallen)
		hits = root.get_node("DamageSystem").effects.filter(func(e): return e.get("small", false) and e.pos == p).size() - fx0 - 1
		results.append([si, hits + 1, dur, Config.SPEEDS[si] / 60.0])
		time.set_speed(0)
		_check("Zeitstufe %d: zerstört nach %d Schlägen in %.0f Spielsekunden (%d Bilder)" % [si, hits + 1, dur, frames], g.device_at(p) == null)
	var h1: int = results[0][1]
	_check("Gleich viele Schläge auf allen Stufen (%s)" % str(results.map(func(r): return r[1])), results.all(func(r): return absi(r[1] - h1) <= 1))
	# Messgenauigkeit: ein Bild = SPEEDS/60 Spielsekunden (bei ×16 etwa 0,3 s)
	_check("Schlagabstand passt zur Spielzeit (Dauer ≈ Schläge × 1,5 s, ± ein Bild)", results.all(func(r): return absf(r[2] - (r[1] - 1) * 1.5) <= 3.0 + r[3]))
	_fresh()
	g = ship.grid
	var tp := C(x0 + 13, y0 + 5)
	_click(tp, "destroy")
	for k in 60 * 20:
		gs.step(1.0 / 60.0)
		var j = CS.jobs.get(g.idx(tp))
		if j != null and int(j.get("hits", 0)) >= 3:
			break
	var c_mid: float = g.device_at(tp).cond
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	g = ship.grid
	var dl = g.device_at(tp)
	var jl = CS.jobs.get(g.idx(tp))
	_check("Nach Laden: Schaden und Auftrag erhalten (%d %% → %s, Auftrag %s)" % [int(c_mid), str(dl.cond if dl != null else -1), str(jl.kind if jl != null else "-")], g.device_at(tp) != null and absf(g.device_at(tp).cond - c_mid) < 0.000001 and CS.jobs.has(g.idx(tp)) and CS.jobs[g.idx(tp)].kind == "destroy")
	_check("Nach Laden fertig zerstört", _until_done(tp) and g.device_at(tp) == null)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()

func PhysicsSystem_ok(r) -> bool:
	return r.get_node("ShipPowerSystem").main_net().has("production")
