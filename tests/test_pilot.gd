## Tests: skill "Spaceship Piloting" (ID pilot) – course 3 years, Piloting +0.5 at the navigation console
##   godot --headless --path . --script res://tests/boot.gd -- test_pilot
extends "res://tests/test_base.gd"

const OLD_SAVE := "res://tests/fixtures/old_save_blueports.json"

var ok_count := 0
var fail_count := 0
var toasts: Array = []
var gs
var ui
var SK
var CHS
var P
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

func _run(sec: int) -> void:
	for k in sec:
		gs.step(1.0 / 60.0)

## Put the character next to the navigation console and let it operate the console
func _sit(c: CrewMember) -> void:
	var h: Device = P.ship_devices("helm")[0]
	var res: Dictionary = ship.nearest_adjacent(c.tile(), [h.pos], 1)
	var spot: Vector2i = res.path[-1] if res.ok and not res.path.is_empty() else c.tile()
	c.pos = Vector2(spot) + Vector2(0.5, 0.5)
	c.path.clear()
	P.helm_at = h.pos

func _initialize() -> void:
	await process_frame
	await process_frame
	gs = root.get_node("GameState")
	ui = root.get_node("UIManager")
	SK = root.get_node("SkillSystem")
	CHS = root.get_node("CharacterSystem")
	P = root.get_node("PhysicsSystem")
	save = root.get_node("SaveSystem")
	ship = root.get_node("ShipSystem")
	save.slot = 934
	root.get_node("Settings").meteors = false
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(t))
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.close_help()
	var mira: CrewMember = root.get_node("CrewSystem").player()
	var s: SkillData = SK.skill("pilot")
	_check("Skill vorhanden, ID pilot, englischer Name", s != null and s.skill_name == "Spaceship Piloting")
	_check("Definition: 3 years, Piloting +0.5, fuel saving replaced", s.course_years == 3 and is_equal_approx(s.piloting_bonus, 0.5) and s.gameplay_effects.is_empty())

	# 1) Character creation: ±3 years, applied once; tooltip
	var cui = ui.char_ui
	CHS.begin(mira)
	CHS.apply_career(mira, "school")
	cui.open_creation()
	await process_frame
	var base: int = mira.age
	var tip: String = _course_row("pilot").tooltip_text if _course_row("pilot") != null else ""
	_check("1: Tooltip: 3 years, Piloting +0.5, ways to learn, progress (%s)" % tip.replace("\n", " | "),
		"costs 3 years" in tip and "Piloting +0.5" in tip and "docking limits" in tip and "flying the ship at the navigation console" in tip and "Textbook: Spaceship Piloting" in tip and "Learning progress:" in tip)
	_check("1: Choose: preview +3", await _press_course("pilot", "Add") and CHS.preview_age(mira) == base + 3 and mira.age == base and "(incl. Spaceship Piloting course +3 years)" in _texts(cui.creation_box))
	_check("1: Remove: preview −3", await _press_course("pilot", "Remove") and CHS.preview_age(mira) == base)
	await _press_course("pilot", "Add")
	var hist0: int = mira.history.size()
	CHS.confirm(mira)
	CHS.confirm(mira)
	_check("1: Confirmed: age +3 exactly once, acquired", mira.age == base + 3 and mira.history.size() == hist0 + 1 and SK.acquired(mira, "pilot"))
	cui.creation.visible = false

	# 2) Effect at the navigation console: docking limits, RCS, rotation ×(1 + Piloting)
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	mira.auto_mode = false
	mira.traits.clear()   # traits like Coordinated change Piloting; here only the skill
	SK.set_progress(mira, "pilot", 0.0)
	_run(3)
	_sit(mira)
	_check("2: Mira flies at the navigation console", P.pilot_crew() == mira and P.operated_helm() != null)
	var rcs0: float = P.rcs_thrust()
	var rot0: float = P.rot_accel()
	var dock0: float = P.dock_factor()
	_check("2: Without the skill: Piloting 0, factor 1 (RCS %.1f kN, rotation %.4f)" % [rcs0, rot0], is_equal_approx(SK.piloting(mira), 0.0) and is_equal_approx(dock0, 1.0) and rcs0 > 0.0 and rot0 > 0.0)
	SK.set_progress(mira, "pilot", 99.9)
	_check("2: At 99.9 % still factor 1", is_equal_approx(P.pilot_factor(), 1.0))
	SK.set_progress(mira, "pilot", 100.0)
	_check("2: With the skill: Piloting +0.5 (%.2f)" % SK.piloting(mira), is_equal_approx(SK.piloting(mira), 0.5))
	_check("2: Andockgrenzen ×1,5 (%.2f)" % P.dock_factor(), is_equal_approx(P.dock_factor(), 1.5))
	_check("2: RCS thrust ×1.5 (%.1f → %.1f kN)" % [rcs0, P.rcs_thrust()], is_equal_approx(P.rcs_thrust(), rcs0 * 1.5))
	_check("2: Drehbeschleunigung ×1,5 (%.4f → %.4f)" % [rot0, P.rot_accel()], is_equal_approx(P.rot_accel(), rot0 * 1.5))
	var other := CrewMember.new(777, "Nobody", Color.WHITE, Vector2i.ZERO)
	SK.set_progress(other, "pilot", 100.0)
	_check("2: The skill of a character not at the console does not count", P.pilot_crew() == mira and not root.get_node("CrewSystem").crew.has(other))
	mira.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	_check("2: Mira away from the console: factor 1", P.pilot_crew() == null and is_equal_approx(P.pilot_factor(), 1.0))
	_check("2: No fuel saving any more", is_equal_approx(SK.pilot_fuel_factor(), 1.0))

	# 3) Practice: flying at the navigation console trains; save, load, continue with a textbook
	SK.set_progress(mira, "pilot", 0.0)
	_sit(mira)
	var age0: int = mira.age
	var st_id: String = P.docked
	P.request_undock()
	_run(120)
	var flew := false
	P.thrust = 1.0
	for k in 600:
		gs.step(1.0 / 60.0)
		_sit(mira)
		if SK.progress(mira, "pilot") > 0.0:
			flew = true
	P.stop_inputs()
	var p_work: float = SK.progress(mira, "pilot")
	_check("3: Undocked and flown: Piloting skill %.3f %%" % p_work, P.docked == "" and flew and p_work > 0.0 and p_work < 100.0)
	save.save_game(true)
	gs.new_game()
	_check("3: Load", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	_check("3: Progress unchanged after loading (%.3f %%), no bonus yet" % SK.progress(mira, "pilot"), absf(SK.progress(mira, "pilot") - p_work) < 0.0001 and is_equal_approx(SK.piloting(mira), 0.0))
	toasts.clear()
	var first := -1.0
	var early := false
	for book in ["book_pilot_1", "book_pilot_2", "book_pilot_3"]:
		var guard := 0
		while guard < 20000 and SK.study(mira, book, 30.0) > 0.0:
			guard += 1
			if first < 0.0:
				first = SK.progress(mira, "pilot")
			if SK.progress(mira, "pilot") < 100.0 and SK.piloting(mira) != 0.0:
				early = true
			SK.decay_recent(mira, 120.0)
	_check("3: The textbook starts from the stored progress (%.3f → %.3f %%)" % [p_work, first], first > p_work)
	_check("3: Piloting only at 100 %", not early and SK.acquired(mira, "pilot") and is_equal_approx(SK.piloting(mira), 0.5))
	_check("3: Exactly one unlock (%s)" % str(toasts), toasts.filter(func(t): return "acquired Spaceship Piloting" in t).size() == 1)
	_check("3: Age unchanged", mira.age == age0)
	# Docking limit directly: ship at 1.2 times the docking distance, same velocity as the station
	_run(3)   # distribute power
	_sit(mira)
	var r: Dictionary = P.rel_to(st_id)
	P.pos = r.pos + Vector2(float(P.space.dock_dist) * 1.2, 0.0)
	P.vel = r.vel
	var why_with: String = P.dock_block_reason(st_id)
	SK.set_progress(mira, "pilot", 0.0)
	var why_without: String = P.dock_block_reason(st_id)
	SK.set_progress(mira, "pilot", 100.0)
	_check("3: 1.2 times the docking distance: close enough with the skill (%s), too far without (%s)" % [why_with, why_without],
		not why_with.begins_with("Too far") and why_without.begins_with("Too far"))
	# Switching ships while undocked: refused instead of crashing
	var fl = root.get_node("FleetSystem")
	var gx := ShipGrid.new()
	fl._build_template(gx, {"id": "lumen", "w": 10, "h": 7})
	var idx: int = fl.next_id
	fl.next_id += 1
	fl.ships.append({"id": idx, "name": "Drifting Ship", "location": "", "data": gx.to_data()})
	var cur: int = fl.current_id
	toasts.clear()
	fl.switch_to(idx)
	_check("3: Abgedockt: Schiffswechsel abgelehnt (%s)" % str(toasts), fl.current_id == cur and toasts.has("You can only switch ships while docked."))
	fl.ships = fl.ships.filter(func(e): return e.id != idx)

	# 4) Old save with the skill acquired
	var dd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
	dd.crew[0].skills["pilot"] = {"p": 100.0, "xp": 30.0, "hist": []}
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(dd))
	f.close()
	gs.new_game()
	_check("4: Old save loaded", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	_run(3)
	_sit(mira)
	var fleet = root.get_node("FleetSystem")
	var g2 := ShipGrid.new()
	fleet._build_template(g2, {"id": "lumen", "w": 10, "h": 7})
	var id2: int = fleet.next_id
	fleet.next_id += 1
	fleet.ships.append({"id": id2, "name": "Test Ship", "location": fleet.here(), "data": g2.to_data()})
	var old_id: int = fleet.current_id
	fleet.switch_to(id2)
	_check("4: Schiffswechsel: erworben", SK.acquired(mira, "pilot") and fleet.current_id == id2)
	fleet.switch_to(old_id)
	_run(3)
	_sit(mira)
	var tp: float = root.get_node("TraitSystem").sum(mira, "piloting")
	_check("4: Piloting +0.5 without training again (traits %+.2f), factor %.2f at the console" % [tp, P.pilot_factor()], SK.acquired(mira, "pilot") and is_equal_approx(SK.piloting(mira), 0.5 + tp) and is_equal_approx(P.pilot_factor(), 1.5 + tp) and SK.effect(mira, "fuel_saving") == 0.0)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
