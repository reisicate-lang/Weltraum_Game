## Tests for the auto mode of a character
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
	# Own save slot: tests do not overwrite real saves and can run in parallel
	root.get_node("SaveSystem").slot = 903
	# These tests also check the (temporarily disabled) station and the wreck
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

	# 1) Auto on: pick a task, walk there, carry it out, look for the next one
	var mira = _fresh()
	var g = ship.grid
	gs.selected = mira
	ui._refresh_auto(mira)
	_check("Default: auto on, the button shows “Auto: ON”", mira.auto_mode and ui.auto_button.text == "Auto: ON")
	var bed := C(x0 + 1, y0 + 1)
	var sink := C(x0 + 3, y0 + 1)
	R.order("dismantle", bed)
	R.order("dismantle", sink)
	for k in 10:
		_run(1)
		if mira.job != null:
			break
	var first = mira.job
	_check("Picks a task on its own (%s)" % (CS.label(first) if first != null else "-"), first != null and first.claimed_by == mira.id)
	var start_pos: Vector2 = mira.pos
	_run(4)
	_check("Walks to the target on its own (%.1f tiles)" % mira.pos.distance_to(start_pos), mira.pos.distance_to(start_pos) > 1.0)
	var done := false
	for k in 60 * 20:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(g.idx(bed)) and not CS.jobs.has(g.idx(sink)):
			done = true
			break
	_check("Carries out both tasks one after the other", done and g.device_at(bed) == null and g.device_at(sink) == null)
	_run(5)
	_check("No task left: stays put (%s)" % mira.task, mira.job == null and mira.path.is_empty())

	# 2) Switch off halfway along the path: stop at once
	mira = _fresh()
	g = ship.grid
	gs.selected = mira
	var far := C(x0 + 1, y0 + 1)
	R.order("dismantle", far)
	# The character only looks for jobs every few game seconds: wait until it starts walking
	for k in 10:
		_run(1)
		if mira.job != null and not mira.path.is_empty():
			break
	_check("On the way to the bed", mira.job != null and not mira.path.is_empty())
	var job_ref = mira.job
	ui.toggle_auto()
	var stop_pos: Vector2 = mira.pos
	_check("The button shows “Auto: OFF”", ui.auto_button.text == "Auto: OFF" and not mira.auto_mode)
	_check("Target and path dropped", mira.job == null and mira.path.is_empty() and mira.order == null)
	_check("The job stays open and free", CS.jobs.has(g.idx(far)) and job_ref != null and job_ref.claimed_by == -1)
	_run(20)
	_check("Stands still (%.3f tiles moved)" % mira.pos.distance_to(stop_pos), mira.pos.distance_to(stop_pos) < 0.01)
	_check("Starts nothing new (%s)" % mira.task, mira.job == null and mira.activity == null and mira.task.contains("auto mode off"))

	# 3) Switch off in the middle of work: no half-done change, nothing twice
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
	_check("Off in the middle of work: the bed still stands, no result", worked and g.device_at(far) != null and mira.inv.count("plate") == plates)
	_check("… the progress stays with the open job (%.2f)" % float(CS.jobs[g.idx(far)].progress), CS.jobs.has(g.idx(far)) and float(CS.jobs[g.idx(far)].progress) > 0.3)

	# 4) Switch on again: re-evaluate tasks (now takes the nearer one)
	var near := C(x0 + 2, y0 + 8)   # charger, close to the starting point
	R.order("dismantle", near)
	var d_far: float = mira.pos.distance_to(Vector2(far))
	var d_near: float = mira.pos.distance_to(Vector2(near))
	ui.toggle_auto()
	_run(2)
	_check("On again: re-evaluates and takes the nearer task (charger %.1f, bed %.1f tiles away)" % [d_near, d_far],
		mira.job != null and CS.pos_of(mira.job) == (near if d_near < d_far else far))
	for k in 60 * 25:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(g.idx(far)) and not CS.jobs.has(g.idx(near)):
			break
	_check("Erledigt danach beide (Ergebnis je einmal)", g.device_at(far) == null and g.device_at(near) == null)

	# 5) Switch off while carrying: the device is set down, not doubled
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
	_check("Carrying cancelled: crate set down, exists exactly once", carried and mira.carrying == null and crates_after == crates_before)

	# 6) Off: needs not on its own, but a warning; manual orders still work
	mira.needs.food = 10.0
	toasts.clear()
	var p0: Vector2 = mira.pos
	_run(10)
	_check("Off + hunger: does not go eating on its own", mira.activity == null and mira.pos.distance_to(p0) < 0.01)
	_check("… aber warnt (%s)" % (toasts[-1] if not toasts.is_empty() else "-"), toasts.any(func(t): return "auto mode is off" in t))
	_check("A manual walk order also works while off", mira.order_move(ship.spawn_point() + Vector2i(1, 0)))
	_run(5)
	_check("… and is carried out", mira.tile() == ship.spawn_point() + Vector2i(1, 0))

	# 7) Emergency: without air the character flees anyway
	var i: int = g.idx(mira.tile())
	g.o2[i] = 0.0; g.n2[i] = 0.0; g.co2[i] = 0.0
	mira.needs.air = 40.0
	_run(1)
	_check("Off + no air: emergency escape (%s)" % mira.task, mira.activity != null and mira.activity.has("flee"))
	var flee_from: Vector2 = mira.pos
	_run(5)
	_check("… and walks into safe air (%.1f tiles)" % mira.pos.distance_to(flee_from), mira.pos.distance_to(flee_from) > 0.5)

	# 8) Saving and loading keeps the switch
	_run(30)
	var save = root.get_node("SaveSystem")
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	_check("Still off after loading", not crew.player().auto_mode)
	crew.player().set_auto(true)

	# 9) No reachable task: stays put
	mira = _fresh()
	g = ship.grid
	var island := Vector2i(2, 2)
	g.set_tile(island, ShipGrid.Tile.WALL)
	CS.jobs[g.idx(island)] = {"kind": "destroy", "x": 2, "y": 2, "target": "tile:wall", "tool": "", "progress": 0.0,
		"claimed_by": -1, "retry_at": 0.0, "paid": true, "need": 1.0, "hit_acc": 0.0}
	var p1: Vector2 = mira.pos
	_run(20)
	_check("Only an unreachable task: stays put (%s)" % mira.task, mira.job == null and mira.pos.distance_to(p1) < 0.01)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
