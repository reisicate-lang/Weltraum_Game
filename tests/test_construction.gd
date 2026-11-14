## Tests: skill "Construction" (ID construction) – course, practice + textbook, saving, existing effect
##   godot --headless --path . --script res://tests/boot.gd -- test_construction
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

func _fresh(p: float) -> CrewMember:
	var c := CrewMember.new(700 + randi() % 1000, "Test", Color.WHITE, Vector2i.ZERO)
	SK.set_progress(c, "construction", p)
	return c

func _dev_pos(type: String) -> Vector2i:
	for d in ship.grid.devices.values():
		if d.type == type and ship.grid.zone[ship.grid.idx(d.pos)] == 0:
			return d.pos
	return Vector2i(-1, -1)

## Effect of Construction (0 % against 100 %) on mining and mechanical jobs
func _effects_check(label: String) -> void:
	var a := _fresh(0.0)
	var b := _fresh(100.0)
	var g = ship.grid
	var gen := _dev_pos("generator")
	var wall := Vector2i(-1, -1)
	for i in g.tiles.size():
		if g.tiles[i] == ShipGrid.Tile.WALL and not g.devices.has(i):
			wall = g.pos(i)
			break
	# Expected as in the previous project state (measured at commit 204b8f8): speed difference
	var cases := [
		["Mining: remove rock/wall", {"kind": "remove", "x": wall.x, "y": wall.y}, 0.0],
		["Mining: uninstall wall", {"kind": "uninstall", "x": wall.x, "y": wall.y, "target": "tile:wall"}, 0.0],
		["Mechanik: Generator bauen", {"kind": "device", "dev": "generator", "x": 0, "y": 0}, 0.48],
		["Mechanik: Generator reparieren", {"kind": "repair", "x": gen.x, "y": gen.y}, 0.0],
		["Mechanik: Generator abbauen", {"kind": "uninstall", "x": gen.x, "y": gen.y, "target": "dev:generator"}, 0.0],
		["Build wall", {"kind": "build", "tile": ShipGrid.Tile.WALL, "x": 0, "y": 0}, 0.48],
	]
	for cs in cases:
		var d: float = SK.work_speed(b, cs[1]) - SK.work_speed(a, cs[1])
		_check("%s: %s Tempo %+.2f (= %+.1f Arbeitswert), erwartet %+.2f" % [label, cs[0], d, d * 10.0, cs[2]], is_equal_approx(d, cs[2]))

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
	save.slot = 926
	root.get_node("Settings").meteors = false
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(t))
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.close_help()
	var mira: CrewMember = root.get_node("CrewSystem").player()
	var s: SkillData = SK.skill("construction")
	_check("Skill vorhanden, ID construction, englischer Name", s != null and s.skill_name == "Construction" and s.course_years == 3)
	_check("Bestehende Zuordnung erhalten: Wirkung work_build 0,4, Praxisaktionen", s.gameplay_effects == {"work_build": 0.4}
		and Array(s.training_actions) == ["build_structure", "build_device", "repair_furniture", "deconstruct_furniture", "study_construction"]
		and s.work_value_bonus == 0.0 and s.work_categories.is_empty())

	# 1) Character creation: choose and remove, exactly 3 years each
	var cui = ui.char_ui
	CHS.begin(mira)
	CHS.apply_career(mira, "school")
	cui.open_creation()
	await process_frame
	var base: int = mira.age
	var p_school: float = SK.progress(mira, "construction")
	var tip: String = _course_row("construction").tooltip_text if _course_row("construction") != null else ""
	_check("1: Tooltip: cost, status, progress, only real effects (%s)" % tip.replace("\n", " | "),
		"costs 3 years" in tip and "Status: not acquired" in tip and ("Learning progress: %.1f %%" % p_school) in tip
		and "Building (walls, floors, cables, new devices, crafting, installing) +4.8 work value at 100 %" in tip and "one part less material" in tip
		and not "Mining" in tip and not "Affected categories" in tip)
	_check("1: Choose", await _press_course("construction", "Add"))
	_check("1: Preview +3 (%d), age unchanged" % CHS.preview_age(mira), CHS.preview_age(mira) == base + 3 and mira.age == base and "(incl. Construction course +3 years)" in _texts(cui.creation_box))
	_check("1: Entfernen", await _press_course("construction", "Remove"))
	_check("1: Preview −3 (%d)" % CHS.preview_age(mira), CHS.preview_age(mira) == base)
	_check("1: Choose again", await _press_course("construction", "Add") and CHS.preview_age(mira) == base + 3)
	var hist0: int = mira.history.size()
	CHS.confirm(mira)
	CHS.confirm(mira)
	_check("1: Confirmed: age +3 exactly once, skill acquired", mira.age == base + 3 and mira.history.size() == hist0 + 1 and SK.acquired(mira, "construction"))
	_check("1: Tooltip shows the status acquired", "Status: acquired." in SK.skill_tooltip(mira, "construction"))
	cui.creation.visible = false

	# 2) Practice + textbook: the same progress; save and load before finishing
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	SK.set_progress(mira, "construction", 0.0)
	var age0: int = mira.age
	var locker := _dev_pos("locker")
	_check("2: Practice: uninstall job at the suit locker", R.order("uninstall", locker) == "")
	for k in 60 * 30:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(ship.grid.idx(locker)):
			break
	var p_work: float = SK.progress(mira, "construction")
	_check("2: Practice raises the progress (%.3f %%)" % p_work, p_work > 0.0)
	var reads := 0
	while SK.study(mira, "book_construction_1", 30.0) > 0.0 and reads < 3:
		reads += 1
		SK.decay_recent(mira, 120.0)
	var p_mid: float = SK.progress(mira, "construction")
	_check("2: The textbook starts from the practice progress (%.3f → %.3f %%)" % [p_work, p_mid], p_mid > p_work and p_mid < 100.0)
	save.save_game(true)
	gs.new_game()
	_check("2: Load", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	_check("2: Progress unchanged after loading (%.3f %%)" % SK.progress(mira, "construction"), absf(SK.progress(mira, "construction") - p_mid) < 0.0001 and not SK.acquired(mira, "construction"))
	toasts.clear()
	var first := -1.0
	for book in ["book_construction_1", "book_construction_2", "book_construction_3"]:
		var guard := 0
		while guard < 20000 and SK.study(mira, book, 30.0) > 0.0:
			guard += 1
			reads += 1
			if first < 0.0:
				first = SK.progress(mira, "construction")
			SK.decay_recent(mira, 120.0)
	_check("2: Weiterlernen ab gespeichertem Stand (%.3f → %.3f %%)" % [p_mid, first], first > p_mid)
	var unlock := toasts.filter(func(t): return "acquired Construction" in t)
	_check("2: At 100 %% unlocked exactly once (%s)" % str(unlock), SK.acquired(mira, "construction") and unlock.size() == 1 and SK.readable_book(mira) == "")
	SK.train(mira, "build_device", 50.0)
	_check("2: No second unlock", toasts.filter(func(t): return "acquired Construction" in t).size() == 1)
	_check("2: Age unchanged (%d)" % mira.age, mira.age == age0)
	var fleet = root.get_node("FleetSystem")
	var g2 := ShipGrid.new()
	fleet._build_template(g2, {"id": "lumen", "w": 10, "h": 7})
	var id2: int = fleet.next_id
	fleet.next_id += 1
	fleet.ships.append({"id": id2, "name": "Test Ship", "location": fleet.here(), "data": g2.to_data()})
	var old_id: int = fleet.current_id
	fleet.switch_to(id2)
	_check("2: Schiffswechsel: erworben", fleet.current_id == id2 and SK.acquired(mira, "construction"))
	fleet.switch_to(old_id)
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	_check("2: Erneut geladen: erworben", SK.acquired(root.get_node("CrewSystem").player(), "construction"))

	# 3) Existing save with Construction acquired; effect as before
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
	_check("3: Fixture has Construction (%.0f %%)" % float(d.crew[0].skills.construction.p), d.crew[0].skills.has("construction"))
	d.crew[0].skills["construction"] = {"p": 100.0, "xp": 40.0, "hist": []}
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	gs.new_game()
	_check("3: Old save loaded", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	_check("3: Construction stays acquired, other skills kept", SK.acquired(mira, "construction") and is_equal_approx(SK.progress(mira, "civil"), 18.0))
	_check("3: Wirkung sofort aktiv (Bauen +%.2f)" % SK.effect(mira, "work_build"), is_equal_approx(SK.effect(mira, "work_build"), 0.48))
	var acts: Array = []
	for a in SK.actions:
		if "construction" in SK.actions[a].skills:
			acts.append(a)
	acts.sort()
	_check("3: Practice mappings unchanged (%s)" % str(acts), acts == ["build_device", "build_structure", "deconstruct_furniture", "repair_furniture", "study_construction"])
	_effects_check("3")

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
