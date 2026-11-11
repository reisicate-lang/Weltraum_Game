## Tests: „Resume Task“ im Rechtsklick-Menü – von WASD unterbrochenen Auftrag fortsetzen
## Mit echten Tasten- und Mausereignissen über die Hauptszene.
##   godot --headless --path . --script res://tests/boot.gd -- test_resume
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var gs
var ui
var ship
var CS
var R
var main
var mira
var screen := Vector2.ZERO
var toasts: Array = []

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _aim(t: Vector2i) -> void:
	for k in 8:
		var got: Vector2i = main._tile_at_mouse()
		if got == t:
			return
		main.cam.position += Vector2(t - got) * Config.TILE_SIZE
		await process_frame

func _rclick(t: Vector2i) -> void:
	await _aim(t)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = pressed
		ev.position = screen
		ev.global_position = screen
		root.push_input(ev)
		await process_frame
	await process_frame

func _lclick(t: Vector2i) -> void:
	await _aim(t)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = screen
		ev.global_position = screen
		root.push_input(ev)
		await process_frame

## Index des Menüeintrags „Resume Task“ (oder -1)
func _resume_entry() -> int:
	if not ui.object_menu.visible:
		return -1
	for k in ui.menu_actions.size():
		if ui.menu_actions[k].kind == "resume":
			var idx: int = ui.object_menu.get_item_index(k)
			if ui.object_menu.get_item_text(idx) == "Resume Task":
				return k
	return -1

## Auftrag „Abbauen“ an p anlegen und Mira arbeiten lassen, bis frac des Fortschritts erreicht ist
func _start_work(p: Vector2i, frac: float) -> Dictionary:
	root.get_node("TimeSystem").set_speed(0)
	mira.manual_until = 0.0   # Handsteuerung aus dem vorigen Fall beenden
	_check("Abbauauftrag an %s angelegt" % str(p), R.order("uninstall", p) == "")
	var job: Dictionary = CS.jobs[ship.grid.idx(p)]
	for k in 60 * 30:
		gs.step(1.0 / 60.0)
		if is_same(mira.job, job) and job.progress >= job.need * frac:
			break
	_check("Mira arbeitet am Auftrag (%.0f %%)" % (job.progress / job.need * 100.0), is_same(mira.job, job) and job.progress >= job.need * frac and job.progress < job.need)
	return job

## Mit WASD von p weglaufen (die Taste, die die Entfernung vergrößert), bis außer Reichweite
func _wasd_away(p: Vector2i) -> void:
	for code in [KEY_S, KEY_W, KEY_D, KEY_A]:
		var d0: float = mira.pos.distance_to(Vector2(p) + Vector2(0.5, 0.5))
		_key(code, true)
		var t0 := _now()
		while _now() - t0 < 0.5 and mira.is_next_to(p):
			await process_frame
		var t1 := _now()
		while _now() - t1 < 0.15:
			await process_frame
		_key(code, false)
		await process_frame
		if not mira.is_next_to(p):
			return
		if mira.pos.distance_to(Vector2(p) + Vector2(0.5, 0.5)) < d0:
			continue

func _initialize() -> void:
	await process_frame
	await process_frame
	root.get_node("SaveSystem").slot = 922
	gs = root.get_node("GameState")
	ui = root.get_node("UIManager")
	ship = root.get_node("ShipSystem")
	CS = root.get_node("ShipConstructionSystem")
	R = root.get_node("RemovalSystem")
	root.get_node("Settings").meteors = false
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.char_ui.creation.visible = false
	ui.close_help()
	ui.set_tool("select")
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(t))
	mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	var g = ship.grid
	var x0: int = (g.width / Config.GRID_SCALE - 16) / 2
	var y0: int = (g.height / Config.GRID_SCALE - 10) / 2
	screen = root.get_viewport().get_canvas_transform() * ((Vector2(C(x0 + 2, y0 + 5)) + Vector2(0.5, 0.5)) * Config.TILE_SIZE)
	await process_frame
	var bat := C(x0 + 2, y0 + 5)
	var spots := {}
	for d in g.devices.values():
		if g.zone[g.idx(d.pos)] == 0 and d.type in ["bed", "workbench", "terminal", "heater"] and not spots.has(d.type):
			spots[d.type] = d.pos
	_check("Ziele gefunden: %s" % str(spots.keys()), spots.size() == 4)

	# 1) Arbeit beginnen, mit WASD weg, sofort „Resume Task“: läuft ohne Wartezeit zurück, Fortschritt bleibt
	var bed: Vector2i = spots.bed
	var job: Dictionary = await _start_work(bed, 0.4)
	root.get_node("TimeSystem").set_speed(1)
	await _wasd_away(bed)
	var released := _now()
	var p_before: float = job.progress
	_check("1: WASD unterbricht, Figur außer Reichweite", mira.job == null and not mira.is_next_to(bed))
	_check("1: Auftrag bleibt offen, reserviert und mit Fortschritt (%.2f)" % job.progress, is_same(CS.jobs.get(g.idx(bed)), job) and job.claimed_by == mira.id and is_equal_approx(job.progress, p_before) and is_same(mira.resume_job, job))
	await _rclick(bat)
	var k := _resume_entry()
	_check("1: Rechtsklick-Menü zeigt „Resume Task“", k >= 0)
	_check("1: Ebenenauswahl im selben Menü weiter da (%s)" % ui.sel_key, ui.sel_key == "cable")
	ui._on_object_menu(k)
	ui.object_menu.hide()
	var chosen := _now()
	var p0: Vector2 = mira.pos
	var moved := -1.0
	while _now() - chosen < 1.0:
		await process_frame
		if mira.pos.distance_to(p0) > 0.05:
			moved = _now()
			break
	_check("1: Auswahl %.2f s nach dem Loslassen (innerhalb der 0,5-s-Sperre)" % (chosen - released), chosen - released < 0.45)
	_check("1: Figur läuft %.2f s nach der Auswahl los (ohne Wartezeit)" % (moved - chosen), moved > 0.0 and moved - chosen <= 0.15)
	_check("1: Derselbe Auftrag übernommen, kein neuer", is_same(mira.job, job) and CS.jobs.size() == 1)
	root.get_node("TimeSystem").set_speed(5)
	var low := INF
	var t0 := _now()
	while _now() - t0 < 20.0 and CS.jobs.has(g.idx(bed)):
		await process_frame
		if is_same(mira.job, job) and mira.is_next_to(bed):
			low = minf(low, job.progress)
	_check("1: Arbeit beim bisherigen Fortschritt fortgesetzt (ab %.2f, vorher %.2f)" % [low, p_before], low >= p_before - 0.001)
	_check("1: Auftrag fertig, Bett abgebaut", not CS.jobs.has(g.idx(bed)) and g.device_at(bed) == null)

	# 2) Mit WASD unterbrechen, ohne den Arbeitsbereich zu verlassen: direkt am Ort weiter
	var wb: Vector2i = spots.workbench
	job = await _start_work(wb, 0.3)
	root.get_node("TimeSystem").set_speed(1)
	var tile_before: Vector2i = mira.tile()
	# Taste zur Werkbank hin: das Gerät blockiert, die Figur bleibt stehen, WASD unterbricht trotzdem
	var dv: Vector2i = wb - mira.tile()
	var toward: Key = (KEY_D if dv.x > 0 else KEY_A) if absi(dv.x) >= absi(dv.y) else (KEY_S if dv.y > 0 else KEY_W)
	_key(toward, true)
	for n in 3:
		await process_frame
	_key(toward, false)
	await process_frame
	p_before = job.progress
	_check("2: WASD unterbricht, Figur bleibt am Arbeitsort (Auftrag %s, Nachbar %s, gemerkt %s)" % [mira.job != null, mira.is_next_to(wb), is_same(mira.resume_job, job)], mira.job == null and mira.is_next_to(wb) and is_same(mira.resume_job, job))
	await _rclick(bat)
	k = _resume_entry()
	_check("2: „Resume Task“ angeboten", k >= 0)
	ui._on_object_menu(k)
	ui.object_menu.hide()
	t0 = _now()
	while _now() - t0 < 0.3:
		await process_frame
	_check("2: Arbeit läuft sofort am Ort weiter (%.3f → %.3f)" % [p_before, job.progress], is_same(mira.job, job) and job.progress > p_before and mira.is_next_to(wb))
	_check("2: Figur ist nicht weggelaufen", mira.tile() == tile_before or mira.is_next_to(wb))
	root.get_node("TimeSystem").set_speed(5)
	t0 = _now()
	while _now() - t0 < 20.0 and CS.jobs.has(g.idx(wb)):
		await process_frame
	_check("2: Werkbank abgebaut", not CS.jobs.has(g.idx(wb)))

	# 3a) Menü offen, Auftrag inzwischen abgeschlossen: alte Option legt nichts Neues an
	var term: Vector2i = spots.terminal
	job = await _start_work(term, 0.3)
	root.get_node("TimeSystem").set_speed(1)
	await _wasd_away(term)
	await _rclick(bat)
	k = _resume_entry()
	_check("3a: „Resume Task“ angeboten", k >= 0)
	CS.complete(job, mira.tile(), mira)
	var n_jobs: int = CS.jobs.size()
	toasts.clear()
	ui._on_object_menu(k)
	ui.object_menu.hide()
	_check("3a: Kurze englische Meldung (%s)" % str(toasts), toasts.has("Task is already finished or cancelled."))
	_check("3a: Kein neuer Auftrag, Figur ohne Auftrag", CS.jobs.size() == n_jobs and not CS.jobs.has(g.idx(term)) and mira.job == null and mira.resume_job == null)
	ui._on_object_menu(k)   # zweiter Klick auf die alte Option
	_check("3a: Zweite Auswahl der alten Option ebenfalls ohne Auftrag", CS.jobs.size() == n_jobs and mira.job == null)
	await _rclick(bat)
	_check("3a: Danach kein „Resume Task“ mehr im Menü", _resume_entry() < 0)
	ui.object_menu.hide()

	# 3b) Menü offen, Ziel inzwischen entfernt
	var heat: Vector2i = spots.heater
	job = await _start_work(heat, 0.3)
	root.get_node("TimeSystem").set_speed(1)
	await _wasd_away(heat)
	await _rclick(bat)
	k = _resume_entry()
	_check("3b: „Resume Task“ angeboten", k >= 0)
	g.remove_device(g.device_at(heat))
	n_jobs = CS.jobs.size()
	toasts.clear()
	ui._on_object_menu(k)
	ui.object_menu.hide()
	_check("3b: Kurze englische Meldung (%s)" % str(toasts), toasts.has("Target was removed."))
	_check("3b: Kein neuer Auftrag, Figur ohne Auftrag", CS.jobs.size() <= n_jobs and mira.job == null and mira.resume_job == null)
	await _rclick(bat)
	_check("3b: Danach kein „Resume Task“ mehr im Menü", _resume_entry() < 0)
	ui.object_menu.hide()

	# 5) Auto-Modus aus: „Resume Task“ ist ein Befehl und wird trotzdem ausgeführt
	var crate := Vector2i(-1, -1)
	for d in g.devices.values():
		if d.type == "crate" and g.zone[g.idx(d.pos)] == 0:
			crate = d.pos
			break
	job = await _start_work(crate, 0.3)
	root.get_node("TimeSystem").set_speed(1)
	await _wasd_away(crate)
	mira.set_auto(false)
	await _rclick(bat)
	k = _resume_entry()
	_check("5: Auto-Modus aus: „Resume Task“ angeboten", k >= 0)
	ui._on_object_menu(k)
	ui.object_menu.hide()
	root.get_node("TimeSystem").set_speed(5)
	t0 = _now()
	while _now() - t0 < 20.0 and CS.jobs.has(g.idx(crate)):
		await process_frame
	_check("5: Auto-Modus aus: Kiste trotzdem fertig abgebaut", not CS.jobs.has(g.idx(crate)) and g.device_at(crate) == null)
	_check("5: Danach steht die Figur wieder (kein neuer Auftrag)", mira.job == null)
	mira.set_auto(true)

	# 4) Normaler Laufbefehl nach WASD behält die 0,5-s-Frist; Ebenenauswahl wechselt weiter
	root.get_node("TimeSystem").set_speed(1)
	for j in CS.jobs.values():
		CS.cancel(j)
	_key(KEY_D, true)
	t0 = _now()
	while _now() - t0 < 0.2:
		await process_frame
	_key(KEY_D, false)
	await process_frame
	released = _now()
	var target := Vector2i(-1, -1)
	for i in g.tiles.size():
		var q: Vector2i = g.pos(i)
		var dd := absi(q.x - mira.tile().x) + absi(q.y - mira.tile().y)
		if dd >= 4 and dd <= 8 and g.zone[i] == 0 and g.tiles[i] == ShipGrid.Tile.FLOOR and not g.devices.has(i) and not g.piles.has(i) and not ship.find_path(mira.tile(), q).is_empty():
			target = q
			break
	await _lclick(target)
	p0 = mira.pos
	moved = -1.0
	while _now() - released < 2.0:
		await process_frame
		if mira.pos.distance_to(p0) > 0.05:
			moved = _now()
			break
	_check("4: Laufbefehl startet %.2f s nach dem Loslassen (≈ 0,5 s)" % (moved - released), moved > 0.0 and moved - released >= 0.45 and moved - released <= 0.7)
	ui.clear_selection()
	var keys: Array = []
	for n in 4:
		await _rclick(bat)
		keys.append(ui.sel_key)
	ui.object_menu.hide()
	_check("4: Rechtsklicks auf dieselbe Kachel: %s" % str(keys), keys == ["cable", "dev:battery", "tile:floor", "cable"])

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
