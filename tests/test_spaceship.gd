## Tests: Fähigkeit „Spaceship Engineering“ (ID spaceship) – Kurs 3 Jahre, Startprofil Werftlehre, +4 auf Strukturarbeit
##   godot --headless --path . --script res://tests/boot.gd -- test_spaceship
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
	var c := CrewMember.new(200 + randi() % 1000, "Test", Color.WHITE, Vector2i.ZERO)
	SK.set_progress(c, "spaceship", p)
	return c

## Wand des eigenen Schiffs: innen (kein All daneben) oder Hülle (All daneben)
func _wall(hull: bool) -> Vector2i:
	var g = ship.grid
	for i in g.tiles.size():
		if g.tiles[i] != ShipGrid.Tile.WALL or g.zone[i] != 0 or g.devices.has(i) or CS.jobs.has(i):
			continue
		var p: Vector2i = g.pos(i)
		var outside := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if g.get_tile(p + d) == ShipGrid.Tile.SPACE:
				outside = true
		if outside == hull:
			return p
	return Vector2i(-1, -1)

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
	save = root.get_node("SaveSystem")
	ship = root.get_node("ShipSystem")
	save.slot = 932
	root.get_node("Settings").meteors = false
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(t))
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.close_help()
	var mira: CrewMember = root.get_node("CrewSystem").player()
	var s: SkillData = SK.skill("spaceship")
	_check("Skill vorhanden, ID spaceship, englischer Name", s != null and s.skill_name == "Spaceship Engineering")
	_check("Definition: 3 Jahre, +4 auf Struktur, alte Wirkung und Voraussetzung ersetzt", s.course_years == 3 and s.work_value_bonus == 4.0 and Array(s.work_categories) == ["structure"] and s.gameplay_effects.is_empty() and s.required_skills.is_empty())

	# 1a) Manuell wählen und entfernen: ±3 Jahre
	var cui = ui.char_ui
	CHS.begin(mira)
	SK.set_progress(mira, "spaceship", 0.0)   # Start-Skill: für die Kursprüfung zurücksetzen
	cui.open_creation()
	await process_frame
	var base: int = mira.age
	var tip: String = _course_row("spaceship").tooltip_text if _course_row("spaceship") != null else ""
	_check("1: Tooltip: 3 Jahre, Strukturbonus, Erwerbswege, Fortschritt (%s)" % tip.replace("\n", " | "),
		"costs 3 years" in tip and "+4 work value" in tip and "Ship Structure" in tip and "Practical work on the ship structure" in tip
		and "Shipyard Apprenticeship" in tip and "Textbook: Spaceship Engineering" in tip and "Learning progress:" in tip)
	_check("1: Auswählen: Vorschau +3", await _press_course("spaceship", "Add") and CHS.preview_age(mira) == base + 3 and mira.age == base and "(incl. Spaceship Engineering course +3 years)" in _texts(cui.creation_box))
	_check("1: Entfernen: Vorschau −3", await _press_course("spaceship", "Remove") and CHS.preview_age(mira) == base)
	await _press_course("spaceship", "Add")
	var hist0: int = mira.history.size()
	CHS.confirm(mira)
	CHS.confirm(mira)
	_check("1: Manuell bestätigt: Alter +3 genau einmal, erworben", mira.age == base + 3 and mira.history.size() == hist0 + 1 and SK.acquired(mira, "spaceship"))
	cui.creation.visible = false

	# 1b) Startprofil Werftlehre (Shipyard Apprenticeship): vergibt den Skill genau einmal, nur seine eigenen Jahre
	var k: Dictionary = CHS.career("shipyard")
	_check("1: Startprofil „%s“: %d Jahre, vergibt spaceship" % [k.name, int(k.years)], k.name == "Shipyard Apprenticeship" and int(k.years) == 3 and k.grants == ["spaceship"] and not k.skills.has("spaceship"))
	for pre in [false, true]:
		var c := CrewMember.new(980, "Profile Test", Color.WHITE, Vector2i.ZERO)
		CHS.begin(c)
		_check("1: Start-Skill vorhanden (Asteroiden-Profil)", SK.acquired(c, "spaceship"))
		SK.set_progress(c, "spaceship", 0.0)
		if pre:
			SK.set_progress(c, "spaceship", 100.0)
		var a0: int = c.age
		toasts.clear()
		var line: String = CHS.apply_career(c, "shipyard")
		var label := "schon erworben" if pre else "neu"
		_check("1: Profil (%s): Skill genau einmal, Alter +3 (%d → %d)" % [label, a0, c.age], line != "" and SK.acquired(c, "spaceship") and c.skills.keys().count("spaceship") == 1 and c.age == a0 + 3)
		_check("1: Profil (%s): Erwerb im Lebenslauf %s" % [label, "nicht erneut" if pre else "einmal"], ("Acquired Spaceship Engineering" in line) != pre and toasts.is_empty())
		var line2: String = CHS.apply_career(c, "shipyard")
		_check("1: Profil (%s) ein zweites Mal: nichts doppelt" % label, line2 != "" and not "Acquired Spaceship Engineering" in line2 and c.skills.keys().count("spaceship") == 1)
	var c2 := CrewMember.new(981, "Profile Course", Color.WHITE, Vector2i.ZERO)
	CHS.begin(c2)
	SK.set_progress(c2, "spaceship", 0.0)
	CHS.set_course(c2, true, "spaceship")
	var a2: int = c2.age
	CHS.apply_career(c2, "shipyard")
	CHS.confirm(c2)
	_check("1: Kurs gewählt + Profil: nur die 3 Jahre des Profils (%d → %d)" % [a2, c2.age], c2.age == a2 + 3 and SK.acquired(c2, "spaceship") and not CHS.course_drafted(c2, "spaceship"))

	# 2) Strukturarbeit: +4; fachfremde Gerätereparatur: kein Bonus
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var g = ship.grid
	var a := _fresh(0.0)
	var b := _fresh(100.0)
	var inner := _wall(false)
	var hull := _wall(true)
	g.cond[g.idx(inner)] = 40.0
	g.cond[g.idx(hull)] = 40.0
	var dev: Device = _dev("generator")
	dev.cond = 40.0
	var cases := [
		["Wand bauen", {"kind": "build", "tile": ShipGrid.Tile.WALL, "x": 0, "y": 0, "paid": false}, 4.0],
		["Boden bauen", {"kind": "build", "tile": ShipGrid.Tile.FLOOR, "x": 0, "y": 0, "paid": false}, 4.0],
		["Tür bauen", {"kind": "build", "tile": ShipGrid.Tile.DOOR, "x": 0, "y": 0, "paid": false}, 4.0],
		["Innenwand reparieren", {"kind": "repair", "x": inner.x, "y": inner.y}, 4.0],
		["Hülle reparieren", {"kind": "repair", "x": hull.x, "y": hull.y}, 4.0],
		["Feuer löschen", {"kind": "extinguish", "x": inner.x, "y": inner.y}, 4.0],
		["Generator reparieren (Gerät)", {"kind": "repair", "x": dev.pos.x, "y": dev.pos.y}, 0.0],
		["Batterie bauen (Gerät)", {"kind": "device", "dev": "battery", "x": 0, "y": 0}, 0.0],
		["Triebwerk bauen (Gerät)", {"kind": "device", "dev": "thruster", "x": 0, "y": 0}, 0.0],
		["Kabel verlegen", {"kind": "cable", "x": 0, "y": 0}, 0.0],
		["Wand abreißen", {"kind": "remove", "x": inner.x, "y": inner.y}, 0.0],
	]
	for cs in cases:
		var d: float = SK.work_value(b, cs[1]) - SK.work_value(a, cs[1])
		_check("2: %s: Arbeitswert %.2f → %.2f (%+.0f, erwartet %+.0f)" % [cs[0], SK.work_value(a, cs[1]), SK.work_value(b, cs[1]), d, cs[2]], is_equal_approx(d, cs[2]))
	var wj: Dictionary = cases[0][1]
	_check("2: Gleiches Material für beide (Wand: %s)" % str(CS.cost(wj)), CS.cost(wj) == CS.cost(wj.duplicate()) and not CS.cost(wj).is_empty())
	_check("2: Bei 99,9 % noch kein Bonus", is_equal_approx(SK.work_value(_fresh(99.9), wj), SK.work_value(a, wj)))
	_check("2: Alte Wirkungen weg (Hülle, Triebwerk, Treibstoff)", SK.effect(b, "work_hull") == 0.0 and SK.effect(b, "work_propulsion") == 0.0)

	# 3) Strukturarbeit lernt, speichern, laden, Lehrbuch weiter
	mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	SK.set_progress(mira, "spaceship", 0.0)
	var age0: int = mira.age
	_check("3: Reparaturauftrag an der Innenwand", CS.place("repair", inner))
	var rj: Dictionary = CS.jobs.get(g.idx(inner), {})
	_check("3: Strukturarbeit trainiert Spaceship (%s)" % str(SK.job_profile(rj).actions), "spaceship_work" in SK.job_profile(rj).actions)
	var done := false
	for n in 60 * 30:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(g.idx(inner)):
			done = true
			break
	var p_work: float = SK.progress(mira, "spaceship")
	_check("3: Mira repariert die Wand: Fortschritt %.3f %%" % p_work, done and p_work > 0.0 and p_work < 100.0)
	save.save_game(true)
	gs.new_game()
	_check("3: Laden", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	_check("3: Fortschritt nach dem Laden gleich (%.3f %%), noch kein Bonus" % SK.progress(mira, "spaceship"), absf(SK.progress(mira, "spaceship") - p_work) < 0.0001 and is_equal_approx(SK.work_value_bonus(mira, wj), 0.0))
	toasts.clear()
	var first := -1.0
	var early := false
	for book in ["book_spaceship_1", "book_spaceship_2", "book_spaceship_3"]:
		var guard := 0
		while guard < 20000 and SK.study(mira, book, 30.0) > 0.0:
			guard += 1
			if first < 0.0:
				first = SK.progress(mira, "spaceship")
			if SK.progress(mira, "spaceship") < 100.0 and SK.work_value_bonus(mira, wj) != 0.0:
				early = true
			SK.decay_recent(mira, 120.0)
	_check("3: Lehrbuch setzt am gespeicherten Stand an (%.3f → %.3f %%)" % [p_work, first], first > p_work)
	_check("3: Bonus erst bei 100 %", not early and SK.acquired(mira, "spaceship") and is_equal_approx(SK.work_value_bonus(mira, wj), 4.0))
	_check("3: Genau eine Freischaltung (%s)" % str(toasts), toasts.filter(func(t): return "acquired Spaceship Engineering" in t).size() == 1)
	_check("3: Alter unverändert", mira.age == age0)
	var fleet = root.get_node("FleetSystem")
	var g2 := ShipGrid.new()
	fleet._build_template(g2, {"id": "lumen", "w": 10, "h": 7})
	var id2: int = fleet.next_id
	fleet.next_id += 1
	fleet.ships.append({"id": id2, "name": "Test Ship", "location": fleet.here(), "data": g2.to_data()})
	var old_id: int = fleet.current_id
	fleet.switch_to(id2)
	_check("3: Schiffswechsel: erworben", SK.acquired(mira, "spaceship"))
	fleet.switch_to(old_id)

	# 4) Alter Spielstand mit erworbenem Skill: Strukturbonus direkt
	var dd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
	dd.crew[0].skills["spaceship"] = {"p": 100.0, "xp": 30.0, "hist": []}
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(dd))
	f.close()
	gs.new_game()
	_check("4: Alter Spielstand geladen", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	_check("4: Strukturbonus ohne erneuten Erwerb (+%.0f), andere Skills erhalten" % SK.work_value_bonus(mira, wj),
		SK.acquired(mira, "spaceship") and is_equal_approx(SK.work_value_bonus(mira, wj), 4.0) and is_equal_approx(SK.progress(mira, "construction"), 33.0) and SK.effect(mira, "work_hull") == 0.0)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
