## Tests: skill "EVA Suits" (ID eva) – course, EVA penalty 55 %, SUIT +4, practice, saving
##   godot --headless --path . --script res://tests/boot.gd -- test_eva
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

func _fresh(p: float, suit: bool) -> CrewMember:
	var c := CrewMember.new(600 + randi() % 1000, "Test", Color.WHITE, Vector2i.ZERO)
	SK.set_progress(c, "eva", p)
	if suit:
		c.suit = {"o2": 100.0, "battery": 100.0}
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
	save.slot = 928
	root.get_node("Settings").meteors = false
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(t))
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.close_help()
	var mira: CrewMember = root.get_node("CrewSystem").player()
	var s: SkillData = SK.skill("eva")
	_check("Skill vorhanden, ID eva, englischer Name", s != null and s.skill_name == "EVA Suits")
	_check("Definition: 3 years, removes the penalty, SUIT +4, old effects replaced", s.course_years == 3 and s.removes_eva_malus and s.work_value_bonus == 4.0 and Array(s.work_categories) == ["suit"] and s.gameplay_effects.is_empty())
	_check("Suit category: suit locker and charger in addition, their previous category stays",
		ItemSystem.device("locker").category == "furniture" and Array(ItemSystem.device("locker").extra_categories) == ["suit"]
		and ItemSystem.device("charger").category == "misc" and Array(ItemSystem.device("charger").extra_categories) == ["suit"])

	# 1) Character creation: choose and remove, 3 years each
	var cui = ui.char_ui
	CHS.begin(mira)
	CHS.apply_career(mira, "school")
	cui.open_creation()
	await process_frame
	var base: int = mira.age
	var tip: String = _course_row("eva").tooltip_text if _course_row("eva") != null else ""
	_check("1: Tooltip: Kosten, beide Effekte, Lernwege, Fortschritt (%s)" % tip.replace("\n", " | "),
		"costs 3 years" in tip and "removes the EVA work penalty" in tip and "55 %" in tip and "+4 work value" in tip and "Suits" in tip
		and "while wearing an EVA suit" in tip and "suit locker" in tip and "Textbook: EVA Suits" in tip and "Learning progress: 0.0 %" in tip
		and not "oxygen" in tip.to_lower())
	_check("1: Choose", await _press_course("eva", "Add"))
	_check("1: Preview +3 (%d), age unchanged" % CHS.preview_age(mira), CHS.preview_age(mira) == base + 3 and mira.age == base and "(incl. EVA Suits course +3 years)" in _texts(cui.creation_box))
	_check("1: Entfernen", await _press_course("eva", "Remove"))
	_check("1: Preview −3 (%d)" % CHS.preview_age(mira), CHS.preview_age(mira) == base)
	_check("1: Choose again", await _press_course("eva", "Add") and CHS.preview_age(mira) == base + 3)
	var hist0: int = mira.history.size()
	CHS.confirm(mira)
	CHS.confirm(mira)
	_check("1: Confirmed: age +3 exactly once, skill acquired", mira.age == base + 3 and mira.history.size() == hist0 + 1 and SK.acquired(mira, "eva"))
	cui.creation.visible = false

	# 2) Job outside the suit category: normal / penalty without the skill 55 % / penalty with the skill normal
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var bat := _dev_pos("battery")
	_check("2: Uninstall job at the battery (power, not suit)", R.order("uninstall", bat) == "")
	var job: Dictionary = CS.jobs[ship.grid.idx(bat)]
	var normal: float = SK.work_speed(_fresh(0.0, false), job)
	var malus: float = SK.work_speed(_fresh(0.0, true), job)
	var skilled: float = SK.work_speed(_fresh(100.0, true), job)
	_check("2: Without a suit normal rate (%.3f)" % normal, is_equal_approx(normal, 0.7))
	_check("2: In a suit without the skill 55 %% (%.3f = %.0f %%)" % [malus, malus / normal * 100.0], is_equal_approx(malus, normal * 0.55))
	_check("2: In a suit with the skill normal again (%.3f)" % skilled, is_equal_approx(skilled, normal))
	_check("2: At 99.9 % still a penalty", is_equal_approx(SK.work_speed(_fresh(99.9, true), job), malus))
	_check("2: Work value unchanged (no SUIT bonus outside)", is_equal_approx(SK.work_value(_fresh(100.0, true), job), SK.work_value(_fresh(0.0, true), job)))
	var stressed := _fresh(100.0, true)
	stressed.stress = 80.0
	_check("2: Andere Modifikatoren gelten weiter (Stress ×0,8: %.3f)" % SK.work_speed(stressed, job), is_equal_approx(SK.work_speed(stressed, job), normal * 0.8))
	CS.cancel(job)

	# 3) Job at the suit category: work value +4
	var locker := _dev_pos("locker")
	_check("3: Uninstall job at the suit locker", R.order("uninstall", locker) == "")
	var ljob: Dictionary = CS.jobs[ship.grid.idx(locker)]
	var wa: float = SK.work_value(_fresh(0.0, false), ljob)
	var wb: float = SK.work_value(_fresh(100.0, false), ljob)
	_check("3: Suit locker: work value %.2f → %.2f, exactly +4" % [wa, wb], is_equal_approx(wb - wa, 4.0))
	var cj := {"kind": "device", "dev": "charger", "x": 0, "y": 0}
	_check("3: Building a charger: exactly +4, same material", is_equal_approx(SK.work_value(_fresh(100.0, false), cj) - SK.work_value(_fresh(0.0, false), cj), 4.0) and CS.cost(cj) == ItemSystem.device("charger").cost)
	var both := _fresh(100.0, false)
	SK.set_progress(both, "civil", 100.0)
	_check("3: Together with Civil Engineering: suit locker +8 (furniture + suit)", is_equal_approx(SK.work_value_bonus(both, ljob), 8.0))
	var dj := {"kind": "device", "dev": "bed", "x": 0, "y": 0}
	_check("3: Bed (not suit): no SUIT bonus", is_equal_approx(SK.work_value_bonus(_fresh(100.0, false), dj), 0.0))
	var in_suit := _fresh(100.0, true)
	_check("3: With the skill in a suit at the suit locker: both effects (speed %.2f)" % SK.work_speed(in_suit, ljob), is_equal_approx(SK.work_speed(in_suit, ljob), 1.1))
	CS.cancel(ljob)

	# 4) Practice: work in a suit trains, save/load before finishing, then continue to 100 %
	mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	SK.set_progress(mira, "eva", 0.0)
	var age0: int = mira.age
	mira.suit = {"o2": 100.0, "battery": 100.0}
	var bed := _dev_pos("bed")
	_check("4: Practice: uninstall job at the bed, the character wears a suit", R.order("uninstall", bed) == "")
	var worked := false
	for k in 60 * 20:
		gs.step(1.0 / 60.0)
		if mira.job != null and mira.suit != null and SK.progress(mira, "eva") > 0.0:
			worked = true
		if not CS.jobs.has(ship.grid.idx(bed)):
			break
	var p_work: float = SK.progress(mira, "eva")
	_check("4: Work in a suit raises the progress (%.3f %%)" % p_work, worked and p_work > 0.0 and p_work < 100.0)
	var p_noskill := 0.0
	var plain := _fresh(0.0, false)
	SK.train_job(plain, {"kind": "device", "dev": "bed", "x": 0, "y": 0}, 30.0)
	_check("4: Work without a suit does not train EVA", is_equal_approx(SK.progress(plain, "eva"), p_noskill))
	_check("4: Before 100 %: both effects not active yet", not SK.acquired(mira, "eva") and is_equal_approx(SK.eva_factor(mira), 0.55) and is_equal_approx(SK.work_value_bonus(mira, ljob), 0.0))
	save.save_game(true)
	gs.new_game()
	_check("4: Load", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	_check("4: Progress unchanged after loading (%.3f %%)" % SK.progress(mira, "eva"), absf(SK.progress(mira, "eva") - p_work) < 0.0001)
	toasts.clear()
	var first := -1.0
	for book in ["book_eva_1", "book_eva_2", "book_eva_3"]:
		var guard := 0
		while guard < 20000 and SK.study(mira, book, 30.0) > 0.0:
			guard += 1
			if first < 0.0:
				first = SK.progress(mira, "eva")
			SK.decay_recent(mira, 120.0)
	_check("4: Weiterlernen ab gespeichertem Stand (%.3f → %.3f %%)" % [p_work, first], first > p_work)
	mira.suit = {"o2": 100.0, "battery": 100.0}
	var ljob2 := {"kind": "device", "dev": "locker", "x": 0, "y": 0}
	_check("4: At 100 %: both effects active", SK.acquired(mira, "eva") and is_equal_approx(SK.eva_factor(mira), 1.0) and is_equal_approx(SK.work_value_bonus(mira, ljob2), 4.0))
	_check("4: Exactly one unlock (%s)" % str(toasts), toasts.filter(func(t): return "acquired EVA Suits" in t).size() == 1)
	_check("4: Age unchanged", mira.age == age0)
	var fleet = root.get_node("FleetSystem")
	var g2 := ShipGrid.new()
	fleet._build_template(g2, {"id": "lumen", "w": 10, "h": 7})
	var id2: int = fleet.next_id
	fleet.next_id += 1
	fleet.ships.append({"id": id2, "name": "Test Ship", "location": fleet.here(), "data": g2.to_data()})
	var old_id: int = fleet.current_id
	fleet.switch_to(id2)
	_check("4: Schiffswechsel: erworben", SK.acquired(mira, "eva"))
	fleet.switch_to(old_id)

	# Old save with EVA acquired: updated effect right away
	for variant in [[100.0, true], [10.0, false]]:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
		d.crew[0].skills["eva"] = {"p": variant[0], "xp": 30.0, "hist": []}
		var f := FileAccess.open(save.path(), FileAccess.WRITE)
		f.store_string(JSON.stringify(d))
		f.close()
		gs.new_game()
		_check("4 alt (%d %%): geladen" % int(variant[0]), save.load_game(true))
		mira = root.get_node("CrewSystem").player()
		mira.suit = {"o2": 100.0, "battery": 100.0}
		_check("4 alt (%d %%): Fortschritt erhalten, Effekte %s" % [int(variant[0]), "aktiv" if variant[1] else "inaktiv"],
			is_equal_approx(SK.progress(mira, "eva"), variant[0]) and is_equal_approx(SK.eva_factor(mira), 1.0 if variant[1] else 0.55)
			and is_equal_approx(SK.work_value_bonus(mira, ljob2), 4.0 if variant[1] else 0.0))
		_check("4 old (%d %%): old effect gone (oxygen)" % int(variant[0]), SK.effect(mira, "suit_o2_saving") == 0.0 and SK.effect(mira, "eva_work") == 0.0)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
