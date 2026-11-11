## Tests: Inventar per Tab, Abbau als ganzer Gegenstand am Boden, Gewicht und Schiffsmasse,
## 1×3-Triebwerke in der Außenwand, Umstellung alter Spielstände
##   godot --headless --path . --script res://tests/boot.gd -- test_parts
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var gs
var P
var ui
var ship
var CS
var R
var save
var main
var x0 := 0
var y0 := 0
var toasts: Array[String] = []

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _secs(s: float) -> void:
	for k in int(s):
		gs.step(1.0 / 60.0)

func _until_done(p: Vector2i, max_s: int = 3600) -> bool:
	for k in max_s:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(ship.grid.idx(p)):
			return true
	return false

func _mira():
	return root.get_node("CrewSystem").player()

## Taste so, wie sie die Hauptszene bekommt (gedrückt, gehalten = Echo, losgelassen)
func _key(code: int, pressed: bool = true, echo: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	ev.echo = echo
	# Tab nimmt die Hauptszene schon in _input (vor der Oberfläche), alles andere unbehandelt
	if code == KEY_TAB:
		main._input(ev)
	else:
		main._unhandled_input(ev)

## Alle Inventare an Bord und auf dem Raster (Gepäck, Haufen, Behälter)
func _invs() -> Array:
	var out: Array = []
	for c in root.get_node("CrewSystem").crew:
		out.append(c.inv)
	for i in ship.grid.piles:
		out.append(ship.grid.piles[i])
	for d in ship.grid.devices.values():
		if d.inv != null:
			out.append(d.inv)
	return out

## Stückzahl einer Sorte überall, auch im erhaltenen Inhalt abgebauter Geräte
func _deep(type: String) -> int:
	var n := 0
	for inv in _invs():
		for it in inv.items:
			n += _deep_stack(it, type)
	return n

func _deep_stack(it: Dictionary, type: String) -> int:
	var n := int(it.qty) if it.type == type else 0
	var d = it.get("data")
	if d is Dictionary and d.get("items") is Array:
		for sub in d.items:
			n += _deep_stack(sub, type)
	return n

func _find(type: String) -> Dictionary:
	for inv in _invs():
		for it in inv.items:
			if it.type == type:
				return it
	return {}

func _pile_with(type: String) -> int:
	for i in ship.grid.piles:
		if ship.grid.piles[i].count(type) > 0:
			return i
	return -1

## Stapel vergleichbar machen (nach dem Laden sind Zahlen aus JSON Kommazahlen)
func _norm(items: Array) -> Array:
	var out: Array = []
	for it in items:
		out.append([String(it.type), int(it.qty), snappedf(float(it.cond), 0.01)])
	return out

func _beside(p: Vector2i) -> Vector2:
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var q: Vector2i = p + d
		if ship.grid.walkable(q):
			return Vector2(q) + Vector2(0.5, 0.5)
	return Vector2(p) + Vector2(0.5, 0.5)

func _fresh() -> void:
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.char_ui.creation.visible = false
	var g = ship.grid
	x0 = (g.width / Config.GRID_SCALE - 16) / 2
	y0 = (g.height / Config.GRID_SCALE - 10) / 2
	var m = _mira()
	m.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	_secs(2)

func _stock_crate() -> void:
	for dv in ship.grid.devices.values():
		if dv.type == "crate" and ship.grid.zone[ship.grid.idx(dv.pos)] == 0:
			dv.inv.add("motor", 4, 90.0)
			dv.inv.add("pipe", 12, 90.0)
			dv.inv.add("plate", 16, 90.0)
			return

func _initialize() -> void:
	await process_frame
	await process_frame
	save = root.get_node("SaveSystem")
	save.slot = 919
	gs = root.get_node("GameState")
	P = root.get_node("PhysicsSystem")
	ui = root.get_node("UIManager")
	ship = root.get_node("ShipSystem")
	CS = root.get_node("ShipConstructionSystem")
	R = root.get_node("RemovalSystem")
	root.get_node("Settings").meteors = false
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(String(t)))
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	_fresh()
	var g = ship.grid

	# ---------------- 1) Tab: persönliches Inventar ----------------
	_check("1: Inventar zu Beginn geschlossen", not ui.inv_open and not ui.container_panel.visible)
	_key(KEY_TAB)
	_check("1: Tab öffnet das Inventar", ui.inv_open and ui.container_panel.visible)
	for k in 8:
		_key(KEY_TAB, true, true)            # gehalten: Echo-Ereignisse
	_key(KEY_TAB, false)                     # losgelassen
	_check("1: Halten und Loslassen wechseln nicht", ui.inv_open and ui.container_panel.visible)
	_key(KEY_TAB)
	_check("1: Erneuter Druck schließt es", not ui.inv_open and not ui.container_panel.visible)
	# Im Cockpit
	var mira = _mira()
	var helm = P.ship_devices("helm")[0]
	mira.pos = _beside(helm.pos)
	ui.toggle_nav(true)
	_check("1: Im Cockpit", ui.nav_open)
	var tgt0: String = P.target
	_key(KEY_TAB)
	_check("1: Cockpit: Tab öffnet das Inventar, Ziel bleibt", ui.inv_open and ui.container_panel.visible and ui.nav_open and P.target == tgt0)
	for k in 8:
		_key(KEY_TAB, true, true)
	_key(KEY_TAB, false)
	_check("1: Cockpit: Halten wechselt nicht", ui.inv_open)
	_key(KEY_TAB)
	_check("1: Cockpit: erneuter Druck schließt es, Ziel bleibt", not ui.inv_open and not ui.container_panel.visible and P.target == tgt0)
	_key(KEY_T)
	_check("1: Cockpit: T wechselt das Ziel (%s → %s)" % [tgt0, P.target], P.target != tgt0)
	var tgt1: String = P.target
	_key(KEY_T, true, true)
	_check("1: … T halten wechselt nicht mehrfach", P.target == tgt1)
	ui._last_nav = ""
	ui._refresh_nav()
	var zb: Button = null
	for row in ui.nav_side.get_children():
		if row.is_queued_for_deletion():
			continue
		for b in row.find_children("*", "Button", true, false):
			if b.text == "Ziel" and zb == null:
				zb = b
	zb.pressed.emit()
	_check("1: Zielwahl per Maus („Ziel“-Knopf) geht weiter (%s)" % P.target, zb != null and P.target != tgt1)
	var hint := false
	for kk in ui.FLIGHT_KEYS:
		if kk[0] == "T" and "Ziel" in kk[1]:
			hint = true
		if kk[0] == "Tab" and "Inventar" in kk[1]:
			hint = hint and true
	_check("1: Tastenhinweis im Cockpit: T = Ziel, Tab = Inventar", hint and ui.FLIGHT_KEYS.any(func(kk): return kk[0] == "Tab" and "Inventar" in kk[1]))
	ui.leave_flight()
	# Behälter offen + Tab: Austausch geht weiter
	var crate_p := C(x0 + 13, y0 + 8)
	mira.pos = _beside(crate_p)
	mira.path.clear()
	ui.open_container(crate_p)
	_key(KEY_TAB)
	var crate = g.device_at(crate_p)
	var r0: int = crate.inv.count("ration")
	ui._transfer(true, "ration", 2)
	_check("1: Mit offenem Behälter: Inventar offen, Austausch geht (%d → %d Rationen)" % [r0, crate.inv.count("ration")], ui.inv_open and ui.open_pos == crate_p and crate.inv.count("ration") == r0 - 2 and mira.inv.count("ration") >= 2)
	ui._transfer(false, "ration", 2)
	_check("1: … und zurück", crate.inv.count("ration") == r0)
	_key(KEY_TAB)
	_check("1: Tab schließt das Fenster", not ui.container_panel.visible and not ui.inv_open)

	# ---------------- 2) Beschädigtes, befülltes Gerät abbauen ----------------
	_fresh()
	g = ship.grid
	mira = _mira()
	crate = g.device_at(crate_p)
	crate.cond = 55.0
	var content_before: Array = crate.inv.to_data()
	var content_kg: float = crate.inv.weight()
	var m_before: float = P.mass()
	var piles_before: int = g.piles.size()
	# erst abbrechen
	_check("2: Abbau beauftragt", R.order("uninstall", crate_p) == "")
	var job: Dictionary = CS.jobs[g.idx(crate_p)]
	for k in 1200:
		gs.step(1.0 / 60.0)
		if float(job.progress) > 0.0:
			break
	_check("2: Abbau läuft (%.2f)" % float(job.progress), float(job.progress) > 0.0 and float(job.progress) < float(job.need))
	CS.cancel(job)
	_secs(2)
	_check("2: Abgebrochen: Gerät bleibt eingebaut, Inhalt gleich, kein Gegenstand", g.device_at(crate_p) == crate and crate.inv.to_data() == content_before
		and _deep("pk_crate") == 0 and g.piles.size() == piles_before)
	# jetzt vollständig
	R.order("uninstall", crate_p)
	_until_done(crate_p)
	var pi: int = _pile_with("pk_crate")
	var it: Dictionary = _find("pk_crate")
	_check("2: Genau ein vollständiger Gegenstand am Boden", g.device_at(crate_p) == null and _deep("pk_crate") == 1 and pi >= 0 and g.piles[pi].count("pk_crate") == 1)
	_check("2: … erreichbar (begehbares Feld, Weg vorhanden)", pi >= 0 and g.walkable(g.pos(pi)) and (mira.tile() == g.pos(pi) or not ship.find_path(mira.tile(), g.pos(pi)).is_empty()))
	_check("2: … Zustand 55 %%, Inhalt erhalten (%d Stapel)" % it.get("data", {}).get("items", []).size(), int(it.get("cond", -1)) == 55 and it.data.items == content_before)
	var w_item: float = R.mass_kg("dev:crate") + content_kg
	_check("2: … Gewicht = Gerät + Inhalt genau einmal (%.1f kg)" % Inventory.stack_weight(it), absf(Inventory.stack_weight(it) - w_item) < 0.001)
	_check("2: … Schiffsmasse unverändert", absf(P.mass() - m_before) < 0.000001)
	# Aufheben (normale Bodeninteraktion: daneben stellen, E/Klick → Nehmen)
	mira.pos = Vector2(g.pos(pi)) + Vector2(0.5, 0.5)
	mira.path.clear()
	mira.order = null
	ui.interact()
	_check("2: E öffnet den Haufen", ui.open_pos == g.pos(pi))
	ui._transfer(true, "pk_crate", 1)
	_check("2: Aufgehoben: in den Händen (%s)" % mira.inv.in_hands().get("type", "-"), mira.inv.in_hands().get("type", "") == "pk_crate" and _pile_with("pk_crate") == -1)
	_check("2: … Masse unverändert, Gewicht gleich", absf(P.mass() - m_before) < 0.000001 and absf(Inventory.stack_weight(mira.inv.in_hands()) - w_item) < 0.001)
	ui.close_container()
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	g = ship.grid
	mira = _mira()
	var h: Dictionary = mira.inv.in_hands()
	_check("2: Nach Laden: noch in den Händen, Zustand, Gewicht und Inhalt gleich", h.get("type", "") == "pk_crate" and int(h.cond) == 55 and _norm(h.data.items) == _norm(content_before)
		and absf(Inventory.stack_weight(h) - w_item) < 0.001 and absf(P.mass() - m_before) < 0.001)
	_check("2: Wiedereinbau beauftragt (%s)" % R.install_reason("pk_crate", crate_p), CS.place("install:pk_crate", crate_p))
	_until_done(crate_p)
	var c2 = g.device_at(crate_p)
	_check("2: Wieder eingebaut: Zustand 55 %%, Inhalt gleich", c2 != null and c2.type == "crate" and int(c2.cond) == 55 and c2.inv.to_data() == content_before)
	_check("2: … nichts doppelt, Masse wie vorher", _deep("pk_crate") == 0 and absf(P.mass() - m_before) < 0.001)

	# ---------------- 3) Umlagern und Gewicht ----------------
	_fresh()
	g = ship.grid
	mira = _mira()
	var plate_crate := C(x0 + 14, y0 + 8)   # Kiste mit Platten
	crate = g.device_at(plate_crate)
	mira.pos = _beside(plate_crate)
	mira.path.clear()
	mira.auto_mode = false
	var m3: float = P.mass()
	var w_plate: float = root.get_node("ItemSystem").item("plate").weight
	var plate_w := func() -> float:
		for inv in _invs():
			for st in inv.items:
				if st.type == "plate":
					return Inventory.stack_weight(st) / int(st.qty)
		return -1.0
	ui.open_container(plate_crate)
	var pl0: int = _deep("plate")
	ui._transfer(true, "plate", 1)
	_check("3: Kiste → Gepäck: 1 Platte (%.1f kg/Stück), Masse gleich" % plate_w.call(), mira.inv.count("plate") == 1 and absf(P.mass() - m3) < 0.000001 and plate_w.call() == w_plate)
	ui.close_container()
	ui._drop_own("plate", 1)
	var pp := _pile_with("plate")
	_check("3: Gepäck → Boden: Masse gleich", pp >= 0 and mira.inv.count("plate") == 0 and absf(P.mass() - m3) < 0.000001)
	ui.open_container(g.pos(pp))
	ui._transfer(true, "plate", 1)
	_check("3: Boden → Gepäck: Masse gleich", mira.inv.count("plate") == 1 and absf(P.mass() - m3) < 0.000001)
	ui.open_container(plate_crate)
	ui._transfer(false, "plate", 1)
	_check("3: Gepäck → Kiste: Masse gleich, nichts verloren", mira.inv.count("plate") == 0 and _deep("plate") == pl0 and absf(P.mass() - m3) < 0.000001)
	# Von Bord: auf das Wrack (fremder Bereich)
	Config.ENABLE_WRECK = true
	root.get_node("StationSystem").clear()   # ein Port: Station lösen, Wrack ankoppeln
	_check("3: Wrack angehängt", root.get_node("SalvageSystem").generate())
	var m_w: float = P.mass()
	ui._transfer(true, "plate", 1)
	var wreck_t := Vector2i(-1, -1)
	for i in g.tiles.size():
		if g.zone[i] == 1 and g.walkable(g.pos(i)) and not g.piles.has(i):
			wreck_t = g.pos(i)
			break
	mira.pos = Vector2(wreck_t) + Vector2(0.5, 0.5)
	var carried: float = mira.inv.weight() / 1000.0
	_check("3: Figur mit Gepäck geht aufs Wrack: Masse sinkt um ihr Gepäck (%.3f t)" % carried, absf(m_w - P.mass() - carried) < 0.000001 and carried >= w_plate / 1000.0)
	ui._drop_own("plate", 1)
	mira.pos = _beside(plate_crate)
	_check("3: Platte auf dem Wrack abgelegt, Figur zurück: Masse um 8 kg kleiner", absf(m_w - P.mass() - w_plate / 1000.0) < 0.000001)
	Config.ENABLE_WRECK = false
	# Zu schwer: Gepäck voll → bleibt am Boden
	while mira.inv.room("plate") > 0:
		mira.inv.add("plate", 1, 90.0)
	g.drop_items(mira.tile(), "plate", 1, 90.0)
	var fp: int = g.idx(mira.tile())
	ui.open_container(mira.tile())
	toasts.clear()
	ui._transfer(true, "plate", 1)
	_check("3: Gepäck zu schwer (%.0f kg): Platte bleibt am Boden (%s)" % [mira.inv.load_weight(), toasts[-1] if not toasts.is_empty() else ""], g.piles.has(fp) and g.piles[fp].count("plate") == 1 and "tragen" in toasts[-1])
	# Hände belegt: zweites abgebautes Gerät bleibt am Boden
	mira.inv.add("pk_bed", 1, 90.0, {"type": "bed", "x": 0, "y": 0, "cond": 90.0, "broken": false, "stock": -1.0, "charge": 0.0, "items": []})
	g.drop_items(mira.tile(), "pk_sink", 1, 90.0)
	ui._transfer(true, "pk_sink", 1)
	_check("3: Hände voll: zweites Gerät bleibt am Boden", g.piles[fp].count("pk_sink") == 1 and mira.inv.count("pk_sink") == 0 and mira.inv.in_hands().type == "pk_bed")
	ui.close_container()

	# ---------------- 4) Triebwerke 1×3 in der Außenwand ----------------
	_fresh()
	g = ship.grid
	mira = _mira()
	_stock_crate()
	var thr: float = root.get_node("ItemSystem").device("thruster").thrust
	# Ungültige Plätze (Vorschau = can_place / place_reason, alle drei Felder)
	CS.build_rot = 2
	var inner_wall := inside_wall(x0 + 10, y0 + 2, Vector2i(1, 0))   # Trennwand Kabine/Cockpit, dahinter Boden
	_check("4: Innenwand abgewiesen (%s)" % CS.place_reason("dev:thruster", inner_wall), not CS.can_place("dev:thruster", inner_wall) and "Innenwand" in CS.place_reason("dev:thruster", inner_wall))
	CS.build_rot = 3
	var swapped := inside_wall(x0 + 12, y0, Vector2i(0, 1))          # innen draußen im All, außen in der Kabine
	_check("4: Vertauschte Innen-/Außenseite abgewiesen (%s)" % CS.place_reason("dev:thruster", swapped), not CS.can_place("dev:thruster", swapped) and "inner" in CS.place_reason("dev:thruster", swapped))
	CS.build_rot = 1
	var blocked := inside_wall(x0 + 7, y0, Vector2i(0, -1))
	var nozzle := blocked + Vector2i(0, -2)
	var junk = g.place_device("solar", nozzle)   # etwas schwebt vor der Düse
	_check("4: Blockiertes Düsenfeld abgewiesen (%s)" % CS.place_reason("dev:thruster", blocked), not CS.can_place("dev:thruster", blocked) and "Düsenfeld" in CS.place_reason("dev:thruster", blocked))
	g.remove_device(junk)
	_check("4: Vorschau umfasst 3 Felder", CS.cells_of("thruster", blocked, 1).size() == 3 and CS.cells_of("thruster", blocked, 1)[2] == nozzle)
	_check("4: Überschneidung mit vorhandenem Triebwerk abgewiesen", not CS.can_place("dev:thruster", C(x0 + 1, y0 + 2)))
	# Horizontale Außenwand (oben, schiebt nach rechts) und vertikale (vorn, schiebt zurück)
	var top := inside_wall(x0 + 12, y0, Vector2i(0, -1))
	cable_line(g, top, C(x0 + 13, y0 + 1))            # Anschluss an die Heizung daneben
	var front := inside_wall(x0 + 15, y0 + 2, Vector2i(1, 0))
	cable_line(g, front, C(x0 + 14, y0 + 2))          # Anschluss an die Steuerpult-Leitung
	var n0: int = P.ship_devices("thruster").size()
	var right0: float = P.thrust_dir(Vector2i(0, 1))
	var back0: float = P.thrust_dir(Vector2i(-1, 0))
	CS.build_rot = 1
	_check("4: Oben planbar", CS.place("dev:thruster", top))
	CS.build_rot = 2
	_check("4: Vorn planbar", CS.place("dev:thruster", front))
	_until_done(top)
	_until_done(front)
	_secs(1)
	var t_top = g.device_at(top)
	var t_front = g.device_at(front)
	_check("4: Oben: 3 Felder, ein Gerät (innen, Wand, Düse)", t_top != null and t_top.type == "thruster" and g.device_at(top + Vector2i(0, -1)) == t_top and g.device_at(top + Vector2i(0, -2)) == t_top
		and g.get_tile(top + Vector2i(0, -1)) == ShipGrid.Tile.WALL and g.get_tile(top + Vector2i(0, -2)) == ShipGrid.Tile.SPACE)
	_check("4: Vorn: 3 Felder, ein Gerät", t_front != null and g.device_at(front + Vector2i(1, 0)) == t_front and g.device_at(front + Vector2i(2, 0)) == t_front)
	_check("4: Je einmal Schub (rechts +%d, zurück +%d kN), je ein Gerät" % [int(P.thrust_dir(Vector2i(0, 1)) - right0), int(P.thrust_dir(Vector2i(-1, 0)) - back0)],
		P.thrust_dir(Vector2i(0, 1)) - right0 == thr and P.thrust_dir(Vector2i(-1, 0)) - back0 == thr and P.ship_devices("thruster").size() == n0 + 2)
	var m4: float = P.mass()
	var p_cabin: float = g.pressure(g.idx(top))
	# Abbau über das mittlere Wandfeld
	_check("4: Abbau über das Wandfeld", R.order("uninstall", top + Vector2i(0, -1)) == "")
	_until_done(top)
	_secs(120)
	_check("4: Ganz entfernt, Schub rechts weg", g.device_at(top) == null and g.device_at(top + Vector2i(0, -1)) == null and g.device_at(top + Vector2i(0, -2)) == null and P.thrust_dir(Vector2i(0, 1)) == right0)
	_check("4: Wand und Druckhülle intakt (%.1f → %.1f kPa)" % [p_cabin, g.pressure(g.idx(top))], g.get_tile(top + Vector2i(0, -1)) == ShipGrid.Tile.WALL and absf(g.pressure(g.idx(top)) - p_cabin) < 2.0 and p_cabin > 80.0)
	var tp := _pile_with("pk_thruster")
	_check("4: Ein vollständiges Triebwerk-Item innen an Bord", _deep("pk_thruster") == 1 and tp >= 0 and g.zone[tp] == 0 and g.tiles[tp] == ShipGrid.Tile.FLOOR and g.walkable(g.pos(tp)))
	_check("4: Masse unverändert (Item an Bord, %.4f t)" % (P.mass() - m4), absf(P.mass() - m4) < 0.000001)

	# ---------------- 5) Alter Spielstand mit 1×1-Triebwerken und Inventaren ----------------
	_fresh()
	g = ship.grid
	mira = _mira()
	mira.inv.items.clear()
	mira.inv.add("plate", 2, 80.0)
	# alter Stand: mehrere leichte abgebaute Teile im Gepäck waren erlaubt
	mira.inv.items.append({"type": "pk_generator", "qty": 1, "cond": 77.0, "data": g.device_at(C(x0 + 1, y0 + 5)).to_data()})
	mira.inv.items.append({"type": "pk_tile_wall", "qty": 1, "cond": 64.0})
	save.save_game(true)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save.path()))
	var old_pos := C(x0 + 11, y0 + 8)           # alte Position mitten im Raum
	var n_thr := 0
	for dd in data.ship.devices:
		if dd.type == "thruster":
			dd.erase("shape")
			n_thr += 1
			if n_thr == 2:
				dd.x = old_pos.x
				dd.y = old_pos.y
				dd.cond = 66.0
	var others: Array = []
	for dd in data.ship.devices:
		if dd.type != "thruster":
			others.append("%s@%d,%d" % [dd.type, int(dd.x), int(dd.y)])
	others.sort()
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var counts := {}
	for type in ["plate", "ration", "copper", "circuit", "pipe", "watercan", "fuelcan", "filter"]:
		counts[type] = _deep(type)
	gs.new_game()
	save.load_game(true)
	g = ship.grid
	mira = _mira()
	_check("5: Umstellung: 1 direkt umgebaut, 1 als Gegenstand (%s)" % str(g.migrated), g.migrated.converted == 1 and g.migrated.packed == 1)
	var thrusters: Array = P.ship_devices("thruster")
	_check("5: Das passende alte Triebwerk sitzt jetzt 1×3 in der Wand", thrusters.size() == 1 and thrusters[0].pos in [C(x0 + 1, y0 + 2), C(x0 + 1, y0 + 3)] and g.device_at(thrusters[0].pos + Vector2i(-2, 0)) == thrusters[0]
		and g.get_tile(thrusters[0].pos + Vector2i(-1, 0)) == ShipGrid.Tile.WALL)
	var pkt := _pile_with("pk_thruster")
	_check("5: Das andere liegt einmal als Gegenstand an seinem Platz (Zustand %d %%)" % int(_find("pk_thruster").get("cond", -1)), _deep("pk_thruster") == 1 and pkt == g.idx(old_pos) and g.walkable(old_pos) and int(_find("pk_thruster").cond) == 66)
	var others2: Array = []
	for dv in g.devices.values():
		if dv.type != "thruster":
			others2.append("%s@%d,%d" % [dv.type, dv.pos.x, dv.pos.y])
	others2.sort()
	_check("5: Keine anderen Bauteile überschrieben oder verloren (%d)" % others2.size(), others2 == others)
	var same := true
	for type in counts:
		if _deep(type) != counts[type]:
			same = false
	_check("5: Inventare vollständig (keine Gegenstände verloren oder doppelt)", same and mira.inv.count("pk_generator") == 1 and mira.inv.count("pk_tile_wall") == 1 and mira.inv.count("plate") == 2)
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	g = ship.grid
	_check("5: Erneut gespeichert und geladen: Umstellung greift nicht noch einmal", g.migrated.converted == 0 and g.migrated.packed == 0
		and P.ship_devices("thruster").size() == 1 and _deep("pk_thruster") == 1 and _deep("pk_generator") == 1)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
