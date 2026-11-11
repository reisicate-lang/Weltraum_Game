## Tests für den Auto-Modus einer Figur
##   godot --headless --path . --script res://tests/boot.gd -- test_auto
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

func _fresh():
	gs.new_game()
	root.get_node("SalvageSystem").clear()
	root.get_node("TimeSystem").set_speed(0)
	var m = crew.player()
	m.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	m.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	m.stress = 0.0
	_run(2)
	return m

func _initialize() -> void:
	await process_frame
	await process_frame
	# Eigener Speicherplatz: Tests überschreiben keine echten Spielstände und laufen parallel
	root.get_node("SaveSystem").slot = 903
	# Diese Tests prüfen auch die (vorübergehend abgeschaltete) Station und das Wrack
	Config.ENABLE_STATION = true
	Config.ENABLE_WRECK = true
	gs = root.get_node("GameState")
	ship = root.get_node("ShipSystem")
	crew = root.get_node("CrewSystem")
	CS = root.get_node("ShipConstructionSystem")
	R = root.get_node("RemovalSystem")
	ui = root.get_node("UIManager")
	root.get_node("Settings").meteors = false
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(String(t)))
	var x0: int = (ship.grid.width / Config.GRID_SCALE - 16) / 2
	var y0: int = (ship.grid.height / Config.GRID_SCALE - 10) / 2

	# 1) Auto an: Aufgabe wählen, hinlaufen, ausführen, nächste suchen
	var mira = _fresh()
	var g = ship.grid
	gs.selected = mira
	ui._refresh_auto(mira)
	_check("Standard: Auto an, Knopf zeigt „Auto: AN“", mira.auto_mode and ui.auto_button.text == "Auto: AN")
	var bed := C(x0 + 1, y0 + 1)
	var sink := C(x0 + 3, y0 + 1)
	R.order("dismantle", bed)
	R.order("dismantle", sink)
	for k in 10:
		_run(1)
		if mira.job != null:
			break
	var first = mira.job
	_check("Wählt selbst eine Aufgabe (%s)" % (CS.label(first) if first != null else "-"), first != null and first.claimed_by == mira.id)
	var start_pos: Vector2 = mira.pos
	_run(4)
	_check("Läuft selbstständig zum Ziel (%.1f Felder)" % mira.pos.distance_to(start_pos), mira.pos.distance_to(start_pos) > 1.0)
	var done := false
	for k in 60 * 20:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(g.idx(bed)) and not CS.jobs.has(g.idx(sink)):
			done = true
			break
	_check("Führt beide Aufgaben nacheinander aus", done and g.device_at(bed) == null and g.device_at(sink) == null)
	_run(5)
	_check("Keine Aufgabe mehr: bleibt stehen (%s)" % mira.task, mira.job == null and mira.path.is_empty())

	# 2) Mitten auf dem Weg ausschalten: sofort stehen bleiben
	mira = _fresh()
	g = ship.grid
	gs.selected = mira
	var far := C(x0 + 1, y0 + 1)
	R.order("dismantle", far)
	_run(3)
	_check("Auf dem Weg zum Bett", mira.job != null and not mira.path.is_empty())
	var job_ref: Dictionary = mira.job
	ui.toggle_auto()
	var stop_pos: Vector2 = mira.pos
	_check("Knopf zeigt „Auto: AUS“", ui.auto_button.text == "Auto: AUS" and not mira.auto_mode)
	_check("Ziel und Laufweg verworfen", mira.job == null and mira.path.is_empty() and mira.order == null)
	_check("Auftrag bleibt offen und frei", CS.jobs.has(g.idx(far)) and job_ref.claimed_by == -1)
	_run(20)
	_check("Steht still (%.3f Felder bewegt)" % mira.pos.distance_to(stop_pos), mira.pos.distance_to(stop_pos) < 0.01)
	_check("Beginnt nichts Neues (%s)" % mira.task, mira.job == null and mira.activity == null and mira.task.contains("Auto-Modus aus"))

	# 3) Mitten in der Arbeit ausschalten: keine halbfertige Änderung, nichts doppelt
	ui.toggle_auto()
	var worked := false
	for k in 60 * 10:
		gs.step(1.0 / 60.0)
		if mira.job != null and float(mira.job.progress) > 0.3:
			worked = true
			break
	var plates: int = mira.inv.count("plate")
	ui.toggle_auto()
	_run(30)
	_check("Mitten in der Arbeit aus: Bett steht noch, kein Ergebnis", worked and g.device_at(far) != null and mira.inv.count("plate") == plates)
	_check("… Fortschritt bleibt beim offenen Auftrag (%.2f)" % float(CS.jobs[g.idx(far)].progress), CS.jobs.has(g.idx(far)) and float(CS.jobs[g.idx(far)].progress) > 0.3)

	# 4) Wieder einschalten: Aufgaben neu bewerten (nimmt jetzt die nähere)
	var near := C(x0 + 2, y0 + 8)   # Ladestation, nah am Startpunkt
	R.order("dismantle", near)
	var d_far: float = mira.pos.distance_to(Vector2(far))
	var d_near: float = mira.pos.distance_to(Vector2(near))
	ui.toggle_auto()
	_run(2)
	_check("Wieder an: bewertet neu und nimmt die nähere Aufgabe (Ladestation %.1f, Bett %.1f Felder entfernt)" % [d_near, d_far],
		mira.job != null and CS.pos_of(mira.job) == (near if d_near < d_far else far))
	for k in 60 * 25:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(g.idx(far)) and not CS.jobs.has(g.idx(near)):
			break
	_check("Erledigt danach beide (Ergebnis je einmal)", g.device_at(far) == null and g.device_at(near) == null)

	# 5) Beim Tragen ausschalten: Gerät wird abgestellt, nicht verdoppelt
	mira = _fresh()
	g = ship.grid
	var crates_before := 0
	for d in g.devices.values():
		if d.type == "crate":
			crates_before += 1
	CS.place_move(C(x0 + 13, y0 + 8), C(x0 + 12, y0 + 2))
	var carried := false
	for k in 60 * 10:
		gs.step(1.0 / 60.0)
		if mira.carrying != null:
			carried = true
			break
	gs.selected = mira
	ui.toggle_auto()
	var crates_after := 0
	for d in g.devices.values():
		if d.type == "crate":
			crates_after += 1
	_check("Tragen abgebrochen: Kiste abgestellt, genau einmal vorhanden", carried and mira.carrying == null and crates_after == crates_before)

	# 6) Aus: Bedürfnisse nicht selbst, aber Warnung; Befehle von Hand gehen weiter
	mira.needs.food = 10.0
	toasts.clear()
	var p0: Vector2 = mira.pos
	_run(10)
	_check("Aus + Hunger: geht nicht von selbst essen", mira.activity == null and mira.pos.distance_to(p0) < 0.01)
	_check("… aber warnt (%s)" % (toasts[-1] if not toasts.is_empty() else "-"), toasts.any(func(t): return "Auto-Modus ist aus" in t))
	_check("Laufbefehl von Hand geht auch bei Aus", mira.order_move(ship.spawn_point() + Vector2i(1, 0)))
	_run(5)
	_check("… und wird ausgeführt", mira.tile() == ship.spawn_point() + Vector2i(1, 0))

	# 7) Notfall: bei fehlender Luft flieht die Figur trotzdem
	var i: int = g.idx(mira.tile())
	g.o2[i] = 0.0; g.n2[i] = 0.0; g.co2[i] = 0.0
	mira.needs.air = 40.0
	_run(1)
	_check("Aus + keine Luft: Notfall-Flucht (%s)" % mira.task, mira.activity != null and mira.activity.has("flee"))
	var flee_from: Vector2 = mira.pos
	_run(5)
	_check("… und läuft in sichere Luft (%.1f Felder)" % mira.pos.distance_to(flee_from), mira.pos.distance_to(flee_from) > 0.5)

	# 8) Speichern und Laden behält den Schalter
	_run(30)
	var save = root.get_node("SaveSystem")
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	_check("Nach dem Laden weiter aus", not crew.player().auto_mode)
	crew.player().set_auto(true)

	# 9) Keine erreichbare Aufgabe: bleibt stehen
	mira = _fresh()
	g = ship.grid
	var island := Vector2i(2, 2)
	g.set_tile(island, ShipGrid.Tile.WALL)
	CS.jobs[g.idx(island)] = {"kind": "destroy", "x": 2, "y": 2, "target": "tile:wall", "tool": "", "progress": 0.0,
		"claimed_by": -1, "retry_at": 0.0, "paid": true, "need": 1.0, "hit_acc": 0.0}
	var p1: Vector2 = mira.pos
	_run(20)
	_check("Nur unerreichbare Aufgabe: bleibt stehen (%s)" % mira.task, mira.job == null and mira.pos.distance_to(p1) < 0.01)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
