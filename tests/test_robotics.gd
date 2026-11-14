## Tests: skill "Robotics Engineering" (ID robotics) – course 1 year, +4 on controls/sensors, practice, navigation station
##   godot --headless --path . --script res://tests/boot.gd -- test_robotics
extends "res://tests/test_base.gd"

const OLD_SAVE := "res://tests/fixtures/old_save_blueports.json"
const BONUS_DEVICES := ["transponder", "antenna", "helm", "terminal", "pump", "autodock", "autofarm"]

var ok_count := 0
var fail_count := 0
var toasts: Array = []
var gs
var ui
var SK
var CHS
var CS
var R
var save
var ship

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _texts(n: Node) -> String:
	var out := ""
	for ch in n.get_children():
		if ch.is_queued_for_deletion():
			continue
		if ch is Label:
			out += ch.text + "\n"
		out += _texts(ch)
	return out

func _course_row(id: String) -> Node:
	for ch in ui.char_ui.creation_box.get_children():
		if not ch.is_queued_for_deletion() and ch.get_meta("course", "") == id:
			return ch
	return null

func _press_course(id: String, text: String) -> bool:
	var row := _course_row(id)
	if row == null:
		return false
	for ch in row.get_children():
		if ch is Button and ch.text == text:
			ch.pressed.emit()
			await process_frame
			return true
	return false

func _fresh(p: float) -> CrewMember:
	var c := CrewMember.new(400 + randi() % 1000, "Test", Color.WHITE, Vector2i.ZERO)
	SK.set_progress(c, "robotics", p)
	return c

func _dev(type: String) -> Device:
	for d in ship.grid.devices.values():
		if d.type == type and ship.grid.zone[ship.grid.idx(d.pos)] == 0:
			return d
	return null

func _initialize() -> void:
	await process_frame
	await process_frame
	gs = root.get_node("GameState")
	ui = root.get_node("UIManager")
	SK = root.get_node("SkillSystem")
	CHS = root.get_node("CharacterSystem")
	CS = root.get_node("ShipConstructionSystem")
	R = root.get_node("RemovalSystem")
	save = root.get_node("SaveSystem")
	ship = root.get_node("ShipSystem")
	save.slot = 930
	root.get_node("Settings").meteors = false
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(t))
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.close_help()
	var mira: CrewMember = root.get_node("CrewSystem").player()
	var s: SkillData = SK.skill("robotics")
	_check("Skill vorhanden, ID robotics, englischer Name", s != null and s.skill_name == "Robotics Engineering")
	_check("Definition: 1 year, +4 on controls and sensors, old effect and prerequisite replaced", s.course_years == 1 and s.work_value_bonus == 4.0 and Array(s.work_categories) == ["control", "sensor"] and s.gameplay_effects.is_empty() and s.required_skills.is_empty())

	# 1) Character creation: ±1 year, applied once; tooltip
	var cui = ui.char_ui
	CHS.begin(mira)
	CHS.apply_career(mira, "school")
	cui.open_creation()
	await process_frame
	var base: int = mira.age
	var tip: String = _course_row("robotics").tooltip_text if _course_row("robotics") != null else ""
	_check("1: Tooltip: Kosten, Bonus, Lernwege, Fortschritt (%s)" % tip.replace("\n", " | "),
		"costs 1 year." in tip and "+4 work value" in tip and "Affected categories: Controls, Sensors." in tip
		and "Practical work" in tip and "Repairing the navigation console" in tip and "Textbook: Robotics Engineering" in tip and "Learning progress:" in tip)
	_check("1: Choose: preview +1", await _press_course("robotics", "Add") and CHS.preview_age(mira) == base + 1 and mira.age == base and "(incl. Robotics Engineering course +1 year)" in _texts(cui.creation_box))
	_check("1: Remove: preview −1", await _press_course("robotics", "Remove") and CHS.preview_age(mira) == base)
	_check("1: Choose again", await _press_course("robotics", "Add") and CHS.preview_age(mira) == base + 1)
	var hist0: int = mira.history.size()
	CHS.confirm(mira)
	CHS.confirm(mira)
	_check("1: Confirmed: age +1 exactly once, acquired", mira.age == base + 1 and mira.history.size() == hist0 + 1 and SK.acquired(mira, "robotics"))
	cui.creation.visible = false

	# 2) The same work at a control and a sensor, without/with the skill
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var a := _fresh(0.0)
	var b := _fresh(100.0)
	for cs in [["control", "helm", 4.0], ["control", "terminal", 4.0], ["sensor", "autodock", 4.0], ["sensor", "autofarm", 4.0],
			["appliance", "sink", 0.0], ["power", "battery", 0.0], ["furniture", "bed", 0.0], ["hvac", "heater", 0.0]]:
		var dj := {"kind": "device", "dev": cs[1], "x": 0, "y": 0, "paid": false}
		_check("2: %s (%s bauen): Arbeitswert %.2f → %.2f, erwartet %+.0f, Material gleich" % [cs[0], cs[1], SK.work_value(a, dj), SK.work_value(b, dj), cs[2]],
			is_equal_approx(SK.work_value(b, dj) - SK.work_value(a, dj), cs[2]) and CS.cost(dj) == ItemSystem.device(cs[1]).cost)
	var term: Device = _dev("terminal")
	_check("2: Uninstall job at the trade terminal (control)", R.order("uninstall", term.pos) == "")
	var job: Dictionary = CS.jobs[ship.grid.idx(term.pos)]
	_check("2: Uninstalling the terminal: exactly +4 (%.2f → %.2f), same tool rule" % [SK.work_value(a, job), SK.work_value(b, job)], is_equal_approx(SK.work_value(b, job) - SK.work_value(a, job), 4.0) and R.worker_ok(a, job) == R.worker_ok(b, job))
	_check("2: No bonus yet at 99.9 %", is_equal_approx(SK.work_value(_fresh(99.9), job), SK.work_value(a, job)))
	var cable_job := {"kind": "cable", "x": 0, "y": 0}
	_check("2: Outside the field (laying cable): no Robotics bonus", is_equal_approx(SK.work_value(a, cable_job), SK.work_value(b, cable_job)))
	var wrong: PackedStringArray = []
	var dir := DirAccess.open("res://resources/components/")
	for f in dir.get_files():
		var id := f.trim_suffix(".remap").trim_suffix(".tres")
		if not f.trim_suffix(".remap").ends_with(".tres"):
			continue
		var d := {"kind": "device", "dev": id, "x": 0, "y": 0}
		if is_equal_approx(SK.work_value(b, d) - SK.work_value(a, d), 4.0) != (id in BONUS_DEVICES):
			wrong.append(id)
	_check("2: Mapping of all devices correct (wrong: %s)" % ", ".join(wrong), wrong.is_empty())
	CS.cancel(job)

	# 3) Start practice, save, load, continue with a textbook
	mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	SK.set_progress(mira, "robotics", 0.0)
	var age0: int = mira.age
	_check("3: Practice: uninstall job at the trade terminal", R.order("uninstall", term.pos) == "")
	var job3: Dictionary = CS.jobs[ship.grid.idx(term.pos)]
	_check("3: The job trains Robotics (%s)" % str(SK.job_profile(job3).actions), "robotics_work" in SK.job_profile(job3).actions)
	for k in 60 * 30:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(ship.grid.idx(term.pos)):
			break
	var p_work: float = SK.progress(mira, "robotics")
	_check("3: Practice raises the progress (%.3f %%)" % p_work, p_work > 0.0 and p_work < 100.0)
	save.save_game(true)
	gs.new_game()
	_check("3: Load", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	var hj := {"kind": "device", "dev": "helm", "x": 0, "y": 0}
	_check("3: Progress unchanged after loading (%.3f %%), no bonus yet" % SK.progress(mira, "robotics"), absf(SK.progress(mira, "robotics") - p_work) < 0.0001 and is_equal_approx(SK.work_value_bonus(mira, hj), 0.0))
	toasts.clear()
	var first := -1.0
	var early := false
	for book in ["book_robotics_1", "book_robotics_2", "book_robotics_3"]:
		var guard := 0
		while guard < 20000 and SK.study(mira, book, 30.0) > 0.0:
			guard += 1
			if first < 0.0:
				first = SK.progress(mira, "robotics")
			if SK.progress(mira, "robotics") < 100.0 and SK.work_value_bonus(mira, hj) != 0.0:
				early = true
			SK.decay_recent(mira, 120.0)
	_check("3: The textbook starts from the stored progress (%.3f → %.3f %%)" % [p_work, first], first > p_work)
	_check("3: Bonus only at 100 %", not early and SK.acquired(mira, "robotics") and is_equal_approx(SK.work_value_bonus(mira, hj), 4.0))
	_check("3: Exactly one unlock (%s)" % str(toasts), toasts.filter(func(t): return "acquired Robotics Engineering" in t).size() == 1)
	_check("3: Age unchanged", mira.age == age0)
	var fleet = root.get_node("FleetSystem")
	var g2 := ShipGrid.new()
	fleet._build_template(g2, {"id": "lumen", "w": 10, "h": 7})
	var id2: int = fleet.next_id
	fleet.next_id += 1
	fleet.ships.append({"id": id2, "name": "Test Ship", "location": fleet.here(), "data": g2.to_data()})
	var old_id: int = fleet.current_id
	fleet.switch_to(id2)
	_check("3: Schiffswechsel: erworben", SK.acquired(mira, "robotics"))
	fleet.switch_to(old_id)

	# 4) Navigation station: repairing the console (repair_nav) trains Robotics
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	SK.set_progress(mira, "robotics", 0.0)
	var e0: float = SK.progress(mira, "electrical")
	var helm: Device = _dev("helm")
	helm.cond = 40.0
	_check("4: Repair job at the navigation console (navigation station)", CS.place("repair", helm.pos))
	var rjob: Dictionary = CS.jobs.get(ship.grid.idx(helm.pos), {})
	_check("4: Aktionen enthalten repair_nav (%s)" % str(SK.job_profile(rjob).actions), "repair_nav" in SK.job_profile(rjob).actions and "robotics" in SK.actions["repair_nav"].skills)
	var direct := _fresh(0.0)
	SK.train_job(direct, rjob, 10.0)
	_check("4: repair_nav direkt: Lernzuwachs %.3f %%" % SK.progress(direct, "robotics"), SK.progress(direct, "robotics") > 0.0)
	var fixed := false
	for k in 60 * 40:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(ship.grid.idx(helm.pos)):
			fixed = true
			break
	_check("4: Mira repairs the console: Robotics %.3f %%, electrical %.3f → %.3f %%" % [SK.progress(mira, "robotics"), e0, SK.progress(mira, "electrical")],
		fixed and SK.progress(mira, "robotics") > 0.0 and SK.progress(mira, "electrical") > e0)

	# 4b) Old save with Robotics acquired
	var dd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
	dd.crew[0].skills["robotics"] = {"p": 100.0, "xp": 30.0, "hist": []}
	var fl := FileAccess.open(save.path(), FileAccess.WRITE)
	fl.store_string(JSON.stringify(dd))
	fl.close()
	gs.new_game()
	_check("4: Old save loaded", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	_check("4: Bonus without acquiring it again (+%.0f), old effect gone" % SK.work_value_bonus(mira, hj), SK.acquired(mira, "robotics") and is_equal_approx(SK.work_value_bonus(mira, hj), 4.0) and SK.effect(mira, "work_robotic") == 0.0 and is_equal_approx(SK.progress(mira, "construction"), 33.0))

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
