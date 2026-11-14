## Tests: skill "Software Engineering" (ID software) – course 1 year, +4 on debugging the navigation console
##   godot --headless --path . --script res://tests/boot.gd -- test_software
extends "res://tests/test_base.gd"

const OLD_SAVE := "res://tests/fixtures/old_save_blueports.json"

var ok_count := 0
var fail_count := 0
var toasts: Array = []
var gs
var ui
var SK
var CHS
var CS
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
	var c := CrewMember.new(300 + randi() % 1000, "Test", Color.WHITE, Vector2i.ZERO)
	SK.set_progress(c, "software", p)
	return c

func _helm() -> Device:
	for d in ship.grid.devices.values():
		if d.type == "helm" and ship.grid.zone[ship.grid.idx(d.pos)] == 0:
			return d
	return null

## Create a debug job as the player would: right-click menu on the navigation console, entry "Debug navigation console"
func _debug_via_menu(h: Device) -> Dictionary:
	ui.set_tool("select")
	ui.open_object_menu(h.pos)
	var k := -1
	for n in ui.menu_actions.size():
		if ui.menu_actions[n].kind == "debug":
			k = n
	if k < 0:
		return {}
	var idx: int = ui.object_menu.get_item_index(k)
	if ui.object_menu.is_item_disabled(idx) or not ui.object_menu.get_item_text(idx).begins_with("Debug navigation console"):
		return {}
	ui._on_object_menu(k)
	ui.object_menu.hide()
	return CS.jobs.get(ship.grid.idx(h.pos), {})

func _initialize() -> void:
	await process_frame
	await process_frame
	gs = root.get_node("GameState")
	ui = root.get_node("UIManager")
	SK = root.get_node("SkillSystem")
	CHS = root.get_node("CharacterSystem")
	CS = root.get_node("ShipConstructionSystem")
	save = root.get_node("SaveSystem")
	ship = root.get_node("ShipSystem")
	save.slot = 931
	root.get_node("Settings").meteors = false
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(t))
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.close_help()
	var mira: CrewMember = root.get_node("CrewSystem").player()
	var s: SkillData = SK.skill("software")
	_check("Skill vorhanden, ID software, englischer Name", s != null and s.skill_name == "Software Engineering")
	_check("Definition: 1 year, +4 on software, old effects replaced", s.course_years == 1 and s.work_value_bonus == 4.0 and Array(s.work_categories) == ["software"] and s.gameplay_effects.is_empty())

	# 1) Charaktererstellung: ±1 Jahr
	var cui = ui.char_ui
	CHS.begin(mira)
	CHS.apply_career(mira, "school")
	cui.open_creation()
	await process_frame
	var base: int = mira.age
	var tip: String = _course_row("software").tooltip_text if _course_row("software") != null else ""
	_check("1: Tooltip: Kosten, Wirkung, Lernwege, Fortschritt (%s)" % tip.replace("\n", " | "),
		"costs 1 year." in tip and "+4 work value" in tip and "debugging the navigation console" in tip and "Textbook: Software Engineering" in tip and "Learning progress:" in tip)
	_check("1: Choose: preview +1", await _press_course("software", "Add") and CHS.preview_age(mira) == base + 1 and mira.age == base and "(incl. Software Engineering course +1 year)" in _texts(cui.creation_box))
	_check("1: Remove: preview −1", await _press_course("software", "Remove") and CHS.preview_age(mira) == base)
	await _press_course("software", "Add")
	var hist0: int = mira.history.size()
	CHS.confirm(mira)
	CHS.confirm(mira)
	_check("1: Confirmed: age +1 exactly once, acquired", mira.age == base + 1 and mira.history.size() == hist0 + 1 and SK.acquired(mira, "software"))
	cui.creation.visible = false

	# 2) Debug job at the navigation console: +4; electrical repair of the same console: no bonus
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var helm := _helm()
	var job := _debug_via_menu(helm)
	_check("2: Debug job created through the right-click menu on the navigation console", not job.is_empty() and job.kind == "debug" and job.paid)
	var a := _fresh(0.0)
	var b := _fresh(100.0)
	_check("2: Debugging is software work", SK.job_categories(job) == ["software"])
	_check("2: Debugging: work value %.2f → %.2f, exactly +4" % [SK.work_value(a, job), SK.work_value(b, job)], is_equal_approx(SK.work_value(b, job) - SK.work_value(a, job), 4.0))
	_check("2: No bonus yet at 99.9 %", is_equal_approx(SK.work_value(_fresh(99.9), job), SK.work_value(a, job)))
	_check("2: A second debug job at the same console is not possible", not CS.can_place("debug", helm.pos))
	CS.cancel(job)
	var rep := {"kind": "repair", "x": helm.pos.x, "y": helm.pos.y}
	_check("2: Electrical repair of the console: no software bonus (%.2f / %.2f)" % [SK.work_value(a, rep), SK.work_value(b, rep)], is_equal_approx(SK.work_value(a, rep), SK.work_value(b, rep)))
	var unin := {"kind": "uninstall", "x": helm.pos.x, "y": helm.pos.y, "target": "dev:helm"}
	_check("2: Uninstalling the console: no software bonus", is_equal_approx(SK.work_value(a, unin), SK.work_value(b, unin)))
	var hk := _fresh(100.0)
	_check("2: Old effects gone (computer speed, hacking assistance, hacking value)", SK.effect(hk, "work_computer") == 0.0 and SK.effect(hk, "hack_assist") == 0.0 and SK.hack_value(hk) == 0.0)

	# 3) Learn by debugging, save, load, continue with a textbook
	mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	SK.set_progress(mira, "software", 0.0)
	var age0: int = mira.age
	job = _debug_via_menu(helm)
	_check("3: Debug job created", not job.is_empty())
	toasts.clear()
	var done := false
	for k in 60 * 30:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(ship.grid.idx(helm.pos)):
			done = true
			break
	var p_work: float = SK.progress(mira, "software")
	_check("3: Mira debugs the console (message: %s), software %.3f %%" % [str(toasts.filter(func(t): return "debugged" in t)), p_work], done and p_work > 0.0 and toasts.has("Navigation console debugged."))
	_check("3: Debugging creates no new job and does not change the console", not CS.jobs.has(ship.grid.idx(helm.pos)) and ship.grid.device_at(helm.pos) == helm)
	save.save_game(true)
	gs.new_game()
	_check("3: Load", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	helm = _helm()
	var dj := {"kind": "debug", "x": helm.pos.x, "y": helm.pos.y}
	_check("3: Progress unchanged after loading (%.3f %%), no bonus yet" % SK.progress(mira, "software"), absf(SK.progress(mira, "software") - p_work) < 0.0001 and is_equal_approx(SK.work_value_bonus(mira, dj), 0.0))
	toasts.clear()
	var first := -1.0
	var early := false
	for book in ["book_software_1", "book_software_2", "book_software_3"]:
		var guard := 0
		while guard < 20000 and SK.study(mira, book, 30.0) > 0.0:
			guard += 1
			if first < 0.0:
				first = SK.progress(mira, "software")
			if SK.progress(mira, "software") < 100.0 and SK.work_value_bonus(mira, dj) != 0.0:
				early = true
			SK.decay_recent(mira, 120.0)
	_check("3: The textbook starts from the stored progress (%.3f → %.3f %%)" % [p_work, first], first > p_work)
	_check("3: Bonus only at 100 %", not early and SK.acquired(mira, "software") and is_equal_approx(SK.work_value_bonus(mira, dj), 4.0))
	_check("3: Exactly one unlock", toasts.filter(func(t): return "acquired Software Engineering" in t).size() == 1)
	_check("3: Age unchanged", mira.age == age0)
	var fleet = root.get_node("FleetSystem")
	var g2 := ShipGrid.new()
	fleet._build_template(g2, {"id": "lumen", "w": 10, "h": 7})
	var id2: int = fleet.next_id
	fleet.next_id += 1
	fleet.ships.append({"id": id2, "name": "Test Ship", "location": fleet.here(), "data": g2.to_data()})
	var old_id: int = fleet.current_id
	fleet.switch_to(id2)
	_check("3: Schiffswechsel: erworben", SK.acquired(mira, "software"))
	fleet.switch_to(old_id)

	# 4) Old save with Software Engineering acquired: bonus right away when debugging
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
	d.crew[0].skills["software"] = {"p": 100.0, "xp": 30.0, "hist": []}
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	gs.new_game()
	_check("4: Old save loaded", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	helm = _helm()
	job = _debug_via_menu(helm)
	_check("4: Debug job created in the old save", not job.is_empty())
	_check("4: Bonus without training again (work value %.2f, +%.0f)" % [SK.work_value(mira, job), SK.work_value_bonus(mira, job)],
		SK.acquired(mira, "software") and is_equal_approx(SK.work_value_bonus(mira, job), 4.0) and SK.effect(mira, "work_computer") == 0.0)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
