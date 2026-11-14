## Tests: skill "Electrical Engineering" (ID electrical) – course, +4 work value, learning, Electrician Gig, saving
##   godot --headless --path . --script res://tests/boot.gd -- test_electrical
extends "res://tests/test_base.gd"

const OLD_SAVE := "res://tests/fixtures/old_save_blueports.json"
const BONUS_DEVICES := ["food", "water", "sink", "meatvat", "toilet", "light", "transponder", "antenna", "helm", "terminal", "pump", "battery", "battery_compact", "battery_mini", "power_switch", "generator", "solar", "autodock", "autofarm"]

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

## Course row of a skill in the life story (not queued for deletion)
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

func _fresh(name: String, civil: float) -> CrewMember:
	var c := CrewMember.new(800 + randi() % 1000, name, Color.WHITE, Vector2i.ZERO)
	SK.set_progress(c, "electrical", civil)
	return c

func _dev_pos(type: String) -> Vector2i:
	for d in ship.grid.devices.values():
		if d.type == type and ship.grid.zone[ship.grid.idx(d.pos)] == 0:
			return d.pos
	return Vector2i(-1, -1)

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
	save.slot = 927
	root.get_node("Settings").meteors = false
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(t))
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.close_help()
	var mira: CrewMember = root.get_node("CrewSystem").player()
	var s: SkillData = SK.skill("electrical")
	_check("Skill vorhanden, ID electrical, englischer Name", s != null and s.skill_name == "Electrical Engineering")
	_check("Definition: 3 years, +4, four categories, old speed effect replaced", s.course_years == 3 and s.work_value_bonus == 4.0 and Array(s.work_categories) == ["appliance", "control", "power", "sensor"] and s.gameplay_effects.is_empty())

	# 1) Character creation: add and remove, exactly 3 years each
	var cui = ui.char_ui
	CHS.begin(mira)
	CHS.apply_career(mira, "school")
	cui.open_creation()
	await process_frame
	var base: int = mira.age
	_check("1: Course row Electrical Engineering present (preview %d)" % CHS.preview_age(mira), _course_row("electrical") != null and CHS.preview_age(mira) == base)
	var tip: String = _course_row("electrical").tooltip_text if _course_row("electrical") != null else ""
	_check("1: Tooltip names 3 years, +4, categories, both ways to learn, progress (%s)" % tip.replace("\n", " | "),
		"costs 3 years" in tip and "+4 work value" in tip and "Appliances, Controls, Power Systems, Sensors" in tip
		and "Practical work" in tip and "Textbook: Electrical Engineering" in tip and "Electrician Gig" in tip and "Status: not acquired" in tip and "Learning progress: 0.0 %" in tip)
	_check("1: Add", await _press_course("electrical", "Add"))
	_check("1: Preview +3 (%d), age unchanged" % CHS.preview_age(mira), CHS.preview_age(mira) == base + 3 and mira.age == base and "Age: %d (incl. Electrical Engineering course +3 years)" % (base + 3) in _texts(cui.creation_box))
	_check("1: Entfernen", await _press_course("electrical", "Remove"))
	_check("1: Preview −3 (%d)" % CHS.preview_age(mira), CHS.preview_age(mira) == base and mira.age == base)
	_check("1: Add again, plus Business Admin (+2)", await _press_course("electrical", "Add") and await _press_course("business", "Add") and CHS.preview_age(mira) == base + 5)
	_check("1: Remove Business again → only −2", await _press_course("business", "Remove") and CHS.preview_age(mira) == base + 3)
	var hist0: int = mira.history.size()
	CHS.confirm(mira)
	CHS.confirm(mira)
	_check("1: Confirmed: age +3 exactly once (%d)" % mira.age, mira.age == base + 3 and mira.history.size() == hist0 + 1)
	_check("1: Skill acquired, Business not", SK.acquired(mira, "electrical") and not SK.acquired(mira, "business"))
	cui.creation.visible = false

	# 2) Identical job per category, without and with the acquired skill
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var a := _fresh("Ann Plain", 0.0)
	var b := _fresh("Eli Electric", 100.0)
	for cs in [["appliance", "sink", 4.0], ["control", "terminal", 4.0], ["power", "battery", 4.0], ["sensor", "autofarm", 4.0],
			["furniture", "bed", 0.0], ["hvac", "heater", 0.0], ["propulsion", "thruster", 0.0], ["misc", "extinguisher", 0.0]]:
		var dj := {"kind": "device", "dev": cs[1], "x": 0, "y": 0, "paid": false}
		var wa: float = SK.work_value(a, dj)
		var wb: float = SK.work_value(b, dj)
		_check("2: %s (%s bauen): Arbeitswert %.2f → %.2f, erwartet %+.0f, Material gleich" % [cs[0], cs[1], wa, wb, cs[2]],
			is_equal_approx(wb - wa, cs[2]) and ItemSystem.device(cs[1]).category == cs[0] and CS.cost(dj) == ItemSystem.device(cs[1]).cost)
	var bat := _dev_pos("battery")
	_check("2: Uninstall job at the battery (tool as before)", R.order("uninstall", bat) == "")
	var job: Dictionary = CS.jobs[ship.grid.idx(bat)]
	_check("2: Uninstalling the battery: exactly +4 (%.2f → %.2f), same tool rule" % [SK.work_value(a, job), SK.work_value(b, job)],
		is_equal_approx(SK.work_value(b, job) - SK.work_value(a, job), 4.0) and R.worker_ok(a, job) == R.worker_ok(b, job) and String(job.tool) == R.tool_for("uninstall", "dev:battery"))
	_check("2: No bonus yet at 99.9 %", is_equal_approx(SK.work_value(_fresh("Almost", 99.9), job), SK.work_value(a, job)))
	var cable_job := {"kind": "cable", "x": 0, "y": 0}
	var wall_job := {"kind": "build", "tile": ShipGrid.Tile.WALL, "x": 0, "y": 0}
	_check("2: Outside the field: laying cable and building walls without a bonus", is_equal_approx(SK.work_value(a, cable_job), SK.work_value(b, cable_job)) and is_equal_approx(SK.work_value(a, wall_job), SK.work_value(b, wall_job)))
	var trains := func(dev: String) -> bool:
		for act in SK.job_profile({"kind": "device", "dev": dev, "x": 0, "y": 0}).actions:
			if SK.actions.has(act) and "electrical" in SK.actions[act].skills:
				return true
		return false
	_check("2: Building a sink (mechanical, appliances) trains Electrical through electrical_work", "electrical_work" in SK.job_profile({"kind": "device", "dev": "sink", "x": 0, "y": 0}).actions and trains.call("sink"))
	_check("2: Building a bed does not train Electrical", not trains.call("bed"))
	var wrong: PackedStringArray = []
	var all_ids: Array = []
	var dir := DirAccess.open("res://resources/components/")
	for f in dir.get_files():
		var ff := f.trim_suffix(".remap")
		if ff.ends_with(".tres"):
			all_ids.append(ff.trim_suffix(".tres"))
	for id in all_ids:
		var dj := {"kind": "device", "dev": id, "x": 0, "y": 0}
		var diff: float = SK.work_value(b, dj) - SK.work_value(a, dj)
		if is_equal_approx(diff, 4.0) != (id in BONUS_DEVICES):
			wrong.append("%s (%+.1f)" % [id, diff])
	_check("2: Mapping of all %d devices correct (wrong: %s)" % [all_ids.size(), ", ".join(wrong)], wrong.is_empty())
	CS.cancel(job)

	# 3) Start practical work, save, load, continue with a textbook
	mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	SK.set_progress(mira, "electrical", 0.0)
	var age0: int = mira.age
	var crate := _dev_pos("sink")
	_check("3: Uninstall job at the sink (appliance)", R.order("uninstall", crate) == "")
	var job3: Dictionary = CS.jobs[ship.grid.idx(crate)]
	_check("3: The job trains Electrical Engineering (%s)" % str(SK.job_profile(job3).actions), "electrical_work" in SK.job_profile(job3).actions)
	for k in 60 * 30:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(ship.grid.idx(crate)):
			break
	var p_work: float = SK.progress(mira, "electrical")
	_check("3: Practical work raises the progress (%.3f %%)" % p_work, p_work > 0.0 and p_work < 100.0)
	_check("3: Before 100 %: no bonus", not SK.acquired(mira, "electrical") and is_equal_approx(SK.work_value_bonus(mira, job), 0.0))
	save.save_game(true)
	gs.new_game()
	_check("3: Load", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	_check("3: Progress unchanged after loading (%.3f %%)" % SK.progress(mira, "electrical"), absf(SK.progress(mira, "electrical") - p_work) < 0.0001)
	var job4 := {"kind": "device", "dev": "battery", "x": 0, "y": 0}
	_check("3: Still no bonus after loading", is_equal_approx(SK.work_value_bonus(mira, job4), 0.0))
	toasts.clear()
	var first := -1.0
	var reads := 0
	for book in ["book_electrical_1", "book_electrical_2", "book_electrical_3"]:
		var guard := 0
		while guard < 20000 and SK.study(mira, book, 30.0) > 0.0:
			guard += 1
			reads += 1
			if first < 0.0:
				first = SK.progress(mira, "electrical")
			SK.decay_recent(mira, 120.0)
			if SK.progress(mira, "electrical") < 100.0 and SK.work_value_bonus(mira, job4) != 0.0:
				first = -99.0   # bonus too early
	_check("3: The textbook continues from the stored progress (%.3f → %.3f %%)" % [p_work, first], first > p_work)
	_check("3: Bonus only at 100 %% (%d × 30 min read)" % reads, SK.acquired(mira, "electrical") and is_equal_approx(SK.work_value_bonus(mira, job4), 4.0))
	_check("3: Exactly one unlock (%s)" % str(toasts.filter(func(t): return "Electrical Engineering" in t)), toasts.filter(func(t): return "acquired Electrical Engineering" in t).size() == 1)
	_check("3: Age unchanged (%d)" % mira.age, mira.age == age0)
	var tip2: String = SK.skill_tooltip(mira, "electrical")
	_check("3: Tooltip shows the current progress (acquired)", "Learning progress: 100.0 % (acquired)" in tip2)

	# Switching ships and saving/loading again
	var fleet = root.get_node("FleetSystem")
	var g2 := ShipGrid.new()
	fleet._build_template(g2, {"id": "lumen", "w": 10, "h": 7})
	var id2: int = fleet.next_id
	fleet.next_id += 1
	fleet.ships.append({"id": id2, "name": "Test Ship", "location": fleet.here(), "data": g2.to_data()})
	var old_id: int = fleet.current_id
	fleet.switch_to(id2)
	_check("3: Switching ships: skill and bonus stay", fleet.current_id == id2 and SK.acquired(mira, "electrical") and is_equal_approx(SK.work_value_bonus(mira, {"kind": "device", "dev": "battery", "x": 0, "y": 0}), 4.0))
	fleet.switch_to(old_id)
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	mira = root.get_node("CrewSystem").player()
	_check("3: Erneut gespeichert/geladen: erworben", SK.acquired(mira, "electrical"))

	# 4) Life step "Electrician Gig": grants the skill directly, only its own age booking
	var gig: Dictionary = CHS.career("electrician")
	_check("4: The life step is called Electrician Gig, %d years, grants electrical" % int(gig.years), gig.name == "Electrician Gig" and int(gig.years) == 3 and gig.grants == ["electrical"] and not gig.skills.has("electrical"))
	for pre in [false, true]:
		var c := CrewMember.new(990, "Gig Test", Color.WHITE, Vector2i.ZERO)
		CHS.begin(c)
		CHS.apply_career(c, "school")
		if pre:
			SK.set_progress(c, "electrical", 100.0)
			SK._entry(c, "electrical").unlocked = true
		var age_before: int = c.age
		var keys_before: int = c.skills.size() + (0 if c.skills.has("electrical") else 1)
		toasts.clear()
		var line: String = CHS.apply_career(c, "electrician")
		var label := "with the skill already" if pre else "without the skill"
		_check("4 (%s): life step chosen (%s)" % [label, line], line != "")
		_check("4 (%s): skill acquired exactly once (%.0f %%, entries %d)" % [label, SK.progress(c, "electrical"), c.skills.keys().count("electrical")],
			SK.acquired(c, "electrical") and c.skills.keys().count("electrical") == 1 and c.skills.size() <= keys_before + 2)
		_check("4 (%s): only the life step's age booking (%d → %d)" % [label, age_before, c.age], c.age == age_before + 3 and CHS.preview_age(c) == c.age)
		_check("4 (%s): the life story reports the acquisition %s" % [label, "not again" if pre else "einmal"], ("Acquired Electrical Engineering" in line) != pre and toasts.is_empty())
	# Course already in the draft, then the gig: the course drops out, no second booking when confirming
	var c2 := CrewMember.new(991, "Gig Course", Color.WHITE, Vector2i.ZERO)
	CHS.begin(c2)
	CHS.apply_career(c2, "school")
	CHS.set_course(c2, true, "electrical")
	var a0: int = c2.age
	_check("4: Course in the draft (+3 preview)", CHS.preview_age(c2) == a0 + 3)
	CHS.apply_career(c2, "electrician")
	CHS.confirm(c2)
	_check("4: Course + gig: only the life step's 3 years booked (%d → %d), course out of the draft" % [a0, c2.age], c2.age == a0 + 3 and not CHS.course_drafted(c2, "electrical") and SK.acquired(c2, "electrical"))

	# 4) Old save with Civil Engineering already acquired
	for variant in [[100.0, 4.0], [50.0, 0.0]]:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
		d.crew[0].skills["electrical"] = {"p": variant[0], "xp": 30.0, "hist": []}
		var f := FileAccess.open(save.path(), FileAccess.WRITE)
		f.store_string(JSON.stringify(d))
		f.close()
		gs.new_game()
		_check("5 (%d %%): old save loaded" % int(variant[0]), save.load_game(true))
		mira = root.get_node("CrewSystem").player()
		var bj := {"kind": "device", "dev": "battery", "x": 0, "y": 0}
		_check("5 (%d %%): progress kept, bonus %+.0f without training" % [int(variant[0]), SK.work_value_bonus(mira, bj)],
			is_equal_approx(SK.progress(mira, "electrical"), variant[0]) and is_equal_approx(SK.work_value_bonus(mira, bj), variant[1]) and is_equal_approx(SK.progress(mira, "construction"), 33.0))
		_check("5 (%d %%): old speed effect gone (electrical, cables)" % int(variant[0]), SK.effect(mira, "work_electrical") == 0.0 and SK.effect(mira, "cable_speed") == 0.0)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
