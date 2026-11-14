## Tests: Fähigkeit „Mechanical Engineering“ (ID mechanical) – Kurs, +4 Arbeitswert nach Kategorie, Lernen, Speichern
##   godot --headless --path . --script res://tests/boot.gd -- test_mechanical
extends "res://tests/test_base.gd"

const OLD_SAVE := "res://tests/fixtures/old_save_blueports.json"
const BONUS_DEVICES := ["food", "water", "sink", "meatvat", "toilet", "chair", "table", "helm", "terminal", "pump", "bed", "crate", "locker", "workbench", "trainer",
	"heater", "scrubber", "o2gen", "airtank", "extinguisher", "charger"]

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

## Kurs-Zeile eines Skills im Lebenslauf (nicht zum Löschen vorgemerkt)
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
	SK.set_progress(c, "mechanical", civil)
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
	save.slot = 933
	root.get_node("Settings").meteors = false
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(t))
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.close_help()
	var mira: CrewMember = root.get_node("CrewSystem").player()
	var s: SkillData = SK.skill("mechanical")
	_check("Skill vorhanden, ID mechanical, englischer Name", s != null and s.skill_name == "Mechanical Engineering")
	_check("Definition: 3 Jahre, +4, fünf Kategorien, keine alte Tempo-Wirkung", s.course_years == 3 and s.work_value_bonus == 4.0 and Array(s.work_categories) == ["appliance", "control", "furniture", "hvac", "misc"] and s.gameplay_effects.is_empty())

	# 1) Charaktererstellung: hinzufügen und entfernen, jeweils genau 3 Jahre
	var cui = ui.char_ui
	CHS.begin(mira)
	CHS.apply_career(mira, "school")
	cui.open_creation()
	await process_frame
	var base: int = mira.age
	_check("1: Kurszeile Mechanical Engineering vorhanden (Vorschau %d)" % CHS.preview_age(mira), _course_row("mechanical") != null and CHS.preview_age(mira) == base)
	var tip: String = _course_row("mechanical").tooltip_text if _course_row("mechanical") != null else ""
	_check("1: Tooltip nennt 3 Jahre, +4, Kategorien, beide Lernwege, Fortschritt (%s)" % tip.replace("\n", " | "),
		"costs 3 years" in tip and "+4 work value" in tip and "Appliances, Controls, Furniture, Climate & Ventilation, Miscellaneous" in tip
		and "Practical work" in tip and "Textbook: Mechanical Engineering" in tip and "Learning progress: 0.0 %" in tip)
	_check("1: Hinzufügen", await _press_course("mechanical", "Add"))
	_check("1: Vorschau +3 (%d), Alter unverändert" % CHS.preview_age(mira), CHS.preview_age(mira) == base + 3 and mira.age == base and "Age: %d (incl. Mechanical Engineering course +3 years)" % (base + 3) in _texts(cui.creation_box))
	_check("1: Entfernen", await _press_course("mechanical", "Remove"))
	_check("1: Vorschau −3 (%d)" % CHS.preview_age(mira), CHS.preview_age(mira) == base and mira.age == base)
	_check("1: Erneut hinzufügen, dazu Business Admin (+2)", await _press_course("mechanical", "Add") and await _press_course("business", "Add") and CHS.preview_age(mira) == base + 5)
	_check("1: Business wieder entfernen → nur −2", await _press_course("business", "Remove") and CHS.preview_age(mira) == base + 3)
	var hist0: int = mira.history.size()
	CHS.confirm(mira)
	CHS.confirm(mira)
	_check("1: Bestätigt: Alter +3 genau einmal (%d)" % mira.age, mira.age == base + 3 and mira.history.size() == hist0 + 1)
	_check("1: Skill erworben, Business nicht", SK.acquired(mira, "mechanical") and not SK.acquired(mira, "business"))
	cui.creation.visible = false

	# 2) Gleicher Auftrag, gleiche Bedingungen: mit Skill genau +4 Arbeitswert
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var a := _fresh("Ann Plain", 0.0)
	var b := _fresh("Bo Civil", 100.0)
	var bed := _dev_pos("bed")
	_check("2: Abbauauftrag am Bett", R.order("uninstall", bed) == "")
	var job: Dictionary = CS.jobs[ship.grid.idx(bed)]
	var wa: float = SK.work_value(a, job)
	var wb: float = SK.work_value(b, job)
	_check("2: Bett (Möbel): Arbeitswert %.2f → %.2f, genau +4" % [wa, wb], is_equal_approx(wb - wa, 4.0))
	_check("2: Tempo +0,4 (%.2f → %.2f)" % [SK.work_speed(a, job), SK.work_speed(b, job)], is_equal_approx(SK.work_speed(b, job) - SK.work_speed(a, job), 0.4))
	_check("2: Werkzeug gilt weiter (%s für beide gleich)" % String(job.tool), R.worker_ok(a, job) == R.worker_ok(b, job) and String(job.tool) == R.tool_for("uninstall", "dev:bed"))
	_check("2: Bei 99,9 % noch kein Bonus", is_equal_approx(SK.work_value(_fresh("Almost", 99.9), job), wa))
	var bat := _dev_pos("battery")
	_check("2: Abbauauftrag an der Batterie", R.order("uninstall", bat) == "")
	var job2: Dictionary = CS.jobs[ship.grid.idx(bat)]
	_check("2: Batterie (Energie) außerhalb: kein Bonus (%.2f / %.2f)" % [SK.work_value(a, job2), SK.work_value(b, job2)], is_equal_approx(SK.work_value(a, job2), SK.work_value(b, job2)))
	var wall_job := {"kind": "build", "tile": ShipGrid.Tile.WALL, "x": 0, "y": 0}
	_check("2: Wand bauen: kein Bonus", is_equal_approx(SK.work_value(a, wall_job), SK.work_value(b, wall_job)))
	var heater_job := {"kind": "device", "dev": "heater", "x": 0, "y": 0, "paid": false}
	_check("2: Heizung bauen (Klima): +4, gleiche Materialkosten (%s)" % str(CS.cost(heater_job)),
		is_equal_approx(SK.work_value(b, heater_job) - SK.work_value(a, heater_job), 4.0) and CS.cost(heater_job) == ItemSystem.device("heater").cost)
	_check("2: Heizung (Elektrik) trainiert auch Mechanical Engineering (%s)" % str(SK.job_profile(heater_job).actions), "mechanical_work" in SK.job_profile(heater_job).actions)
	_check("2: Batterie trainiert kein mechanical_work", not "mechanical_work" in SK.job_profile({"kind": "device", "dev": "battery", "x": 0, "y": 0}).actions)
	var gen_rep := {"kind": "device", "dev": "generator", "x": 0, "y": 0}
	_check("2: Generator (mechanisch, aber Power): kein Bonus mehr", is_equal_approx(SK.work_value(b, gen_rep), SK.work_value(a, gen_rep)))
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
	_check("2: Zuordnung aller %d Geräte stimmt (Fehler: %s)" % [all_ids.size(), ", ".join(wrong)], wrong.is_empty())
	CS.cancel(job)
	CS.cancel(job2)

	# 3) Praktische Arbeit beginnen, speichern, laden, mit Lehrbuch weiter
	mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	SK.set_progress(mira, "mechanical", 0.0)
	var age0: int = mira.age
	var crate := _dev_pos("locker")
	_check("3: Abbauauftrag am Anzugschrank (Möbel)", R.order("uninstall", crate) == "")
	var job3: Dictionary = CS.jobs[ship.grid.idx(crate)]
	_check("3: Auftrag trainiert Mechanical Engineering", "mechanical" in SK.actions[SK.job_profile(job3).actions[0]].skills or "mechanical_work" in SK.job_profile(job3).actions)
	for k in 60 * 30:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(ship.grid.idx(crate)):
			break
	var p_work: float = SK.progress(mira, "mechanical")
	_check("3: Praktische Arbeit erhöht den Fortschritt (%.3f %%)" % p_work, p_work > 0.0 and p_work < 100.0)
	_check("3: Vor 100 %: kein Bonus", not SK.acquired(mira, "mechanical") and is_equal_approx(SK.work_value_bonus(mira, job), 0.0))
	save.save_game(true)
	gs.new_game()
	_check("3: Laden", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	_check("3: Fortschritt nach dem Laden gleich (%.3f %%)" % SK.progress(mira, "mechanical"), absf(SK.progress(mira, "mechanical") - p_work) < 0.0001)
	var bed2 := _dev_pos("bed")
	R.order("uninstall", bed2)
	var job4: Dictionary = CS.jobs[ship.grid.idx(bed2)]
	_check("3: Nach dem Laden noch kein Bonus", is_equal_approx(SK.work_value_bonus(mira, job4), 0.0))
	toasts.clear()
	var first := -1.0
	var reads := 0
	for book in ["book_mechanical_1", "book_mechanical_2", "book_mechanical_3"]:
		var guard := 0
		while guard < 20000 and SK.study(mira, book, 30.0) > 0.0:
			guard += 1
			reads += 1
			if first < 0.0:
				first = SK.progress(mira, "mechanical")
			SK.decay_recent(mira, 120.0)
			if SK.progress(mira, "mechanical") < 100.0 and SK.work_value_bonus(mira, job4) != 0.0:
				first = -99.0   # Bonus zu früh
	_check("3: Lehrbuch lernt am gespeicherten Fortschritt weiter (%.3f → %.3f %%)" % [p_work, first], first > p_work)
	_check("3: Bonus erst bei 100 %% (%d × 30 min gelesen)" % reads, SK.acquired(mira, "mechanical") and is_equal_approx(SK.work_value_bonus(mira, job4), 4.0))
	_check("3: Genau eine Freischaltung (%s)" % str(toasts.filter(func(t): return "Mechanical Engineering" in t)), toasts.filter(func(t): return "acquired Mechanical Engineering" in t).size() == 1)
	_check("3: Alter unverändert (%d)" % mira.age, mira.age == age0)
	var tip2: String = SK.skill_tooltip(mira, "mechanical")
	_check("3: Tooltip zeigt aktuellen Fortschritt (acquired)", "Learning progress: 100.0 % (acquired)" in tip2)

	# Schiffswechsel und erneutes Speichern/Laden
	var fleet = root.get_node("FleetSystem")
	var g2 := ShipGrid.new()
	fleet._build_template(g2, {"id": "lumen", "w": 10, "h": 7})
	var id2: int = fleet.next_id
	fleet.next_id += 1
	fleet.ships.append({"id": id2, "name": "Test Ship", "location": fleet.here(), "data": g2.to_data()})
	var old_id: int = fleet.current_id
	fleet.switch_to(id2)
	_check("3: Schiffswechsel: Skill und Bonus bleiben", fleet.current_id == id2 and SK.acquired(mira, "mechanical") and is_equal_approx(SK.work_value_bonus(mira, {"kind": "device", "dev": "bed", "x": 0, "y": 0}), 4.0))
	fleet.switch_to(old_id)
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	mira = root.get_node("CrewSystem").player()
	_check("3: Erneut gespeichert/geladen: erworben", SK.acquired(mira, "mechanical"))

	# 4) Alter Spielstand mit bereits erworbenem Civil Engineering
	for variant in [[100.0, 4.0], [50.0, 0.0]]:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
		d.crew[0].skills["mechanical"] = {"p": variant[0], "xp": 30.0, "hist": []}
		var f := FileAccess.open(save.path(), FileAccess.WRITE)
		f.store_string(JSON.stringify(d))
		f.close()
		gs.new_game()
		_check("4 (%d %%): Alter Spielstand geladen" % int(variant[0]), save.load_game(true))
		mira = root.get_node("CrewSystem").player()
		var bj := {"kind": "device", "dev": "bed", "x": 0, "y": 0}
		_check("4 (%d %%): Fortschritt erhalten, Bonus %+.0f ohne Training" % [int(variant[0]), SK.work_value_bonus(mira, bj)],
			is_equal_approx(SK.progress(mira, "mechanical"), variant[0]) and is_equal_approx(SK.work_value_bonus(mira, bj), variant[1]) and is_equal_approx(SK.progress(mira, "construction"), 33.0))
		_check("4 (%d %%): Alte Tempo-Wirkung weg" % int(variant[0]), SK.effect(mira, "work_mechanical") == 0.0)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
