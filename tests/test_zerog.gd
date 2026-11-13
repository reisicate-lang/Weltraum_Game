## Tests: Fähigkeit „Zero-g Ops“ (ID zerog) – Kurs 1 Jahr, nur Prüf-Flag, Praxis, Speichern
##   godot --headless --path . --script res://tests/boot.gd -- test_zerog
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

func _vacuum_tile() -> Vector2i:
	var g = ship.grid
	for i in g.tiles.size():
		if g.tiles[i] == ShipGrid.Tile.SPACE:
			return g.pos(i)
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
	save.slot = 935
	root.get_node("Settings").meteors = false
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(t))
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.close_help()
	var mira: CrewMember = root.get_node("CrewSystem").player()
	var s: SkillData = SK.skill("zerog")
	_check("Skill vorhanden, ID zerog, englischer Name", s != null and s.skill_name == "Zero-g Ops")
	_check("Definition: 1 Jahr, nur Prüf-Flag, keine Zahlenwirkung", s.course_years == 1 and s.check_flag and s.gameplay_effects.is_empty() and s.work_value_bonus == 0.0 and s.piloting_bonus == 0.0)

	# 1) Charaktererstellung: ±1 Jahr
	var cui = ui.char_ui
	CHS.begin(mira)
	_check("1: Zero-g Ops ist Start-Skill", SK.acquired(mira, "zerog"))
	SK.set_progress(mira, "zerog", 0.0)   # für die Kursprüfung zurücksetzen
	cui.open_creation()
	await process_frame
	var base: int = mira.age
	var tip: String = _course_row("zerog").tooltip_text if _course_row("zerog") != null else ""
	_check("1: Tooltip: 1 Jahr, Flag, Lernwege, Fortschritt (%s)" % tip.replace("\n", " | "),
		"costs 1 year." in tip and "no numeric modifier" in tip and "moving in vacuum" in tip and "Textbook: Zero-g Ops" in tip and "Learning progress:" in tip)
	_check("1: Auswählen: Vorschau +1", await _press_course("zerog", "Add") and CHS.preview_age(mira) == base + 1 and mira.age == base and "(incl. Zero-g Ops course +1 year)" in _texts(cui.creation_box))
	_check("1: Entfernen: Vorschau −1", await _press_course("zerog", "Remove") and CHS.preview_age(mira) == base)
	await _press_course("zerog", "Add")
	var hist0: int = mira.history.size()
	CHS.confirm(mira)
	CHS.confirm(mira)
	_check("1: Bestätigt: Alter +1 genau einmal, erworben", mira.age == base + 1 and mira.history.size() == hist0 + 1 and SK.acquired(mira, "zerog"))
	cui.creation.visible = false

	# 2) Prüf-Flag, keine Zahlenwirkung
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var a := CrewMember.new(601, "Plain", Color.WHITE, Vector2i.ZERO)
	var b := CrewMember.new(602, "Zero-g", Color.WHITE, Vector2i.ZERO)
	SK.set_progress(b, "zerog", 100.0)
	_check("2: Abfrage über die Prüflogik: mit Skill ja, ohne nein", SK.meets(b, {"zerog": SK.ACQUIRED}) and SK.acquired(b, "zerog") and not SK.meets(a, {"zerog": SK.ACQUIRED}))
	var vac := _vacuum_tile()
	a.pos = Vector2(vac) + Vector2(0.5, 0.5)
	b.pos = Vector2(vac) + Vector2(0.5, 0.5)
	_check("2: Im Vakuum gleiches Tempo mit und ohne Skill (%.2f / %.2f)" % [a.move_factor(), b.move_factor()], is_equal_approx(a.move_factor(), b.move_factor()) and is_equal_approx(a.move_factor(), 0.6))
	var job := {"kind": "device", "dev": "bed", "x": 0, "y": 0}
	_check("2: Kein Arbeitswert-Bonus", is_equal_approx(SK.work_value(a, job), SK.work_value(b, job)))
	_check("2: Keine alte Wirkung (Vakuum-Tempo)", SK.effect(b, "eva_speed") == 0.0)

	# 3) Praxis: Arbeit im Anzug trainiert, speichern/laden, Lehrbuch weiter
	mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	SK.set_progress(mira, "zerog", 0.0)
	var age0: int = mira.age
	mira.suit = {"o2": 100.0, "battery": 100.0}
	var bed := Vector2i(-1, -1)
	for d in ship.grid.devices.values():
		if d.type == "bed":
			bed = d.pos
	_check("3: Praxis: Abbauauftrag am Bett, Figur trägt Anzug", R.order("uninstall", bed) == "")
	for k in 60 * 20:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(ship.grid.idx(bed)):
			break
	var p_work: float = SK.progress(mira, "zerog")
	_check("3: Arbeit im Anzug erhöht Zero-g Ops (%.3f %%)" % p_work, p_work > 0.0 and p_work < 100.0)
	var mover := CrewMember.new(603, "Mover", Color.WHITE, Vector2i.ZERO)
	SK.train(mover, "eva_move", 30.0)
	_check("3: Bewegung im Vakuum (eva_move) trainiert Zero-g Ops (%.3f %%)" % SK.progress(mover, "zerog"), SK.progress(mover, "zerog") > 0.0)
	save.save_game(true)
	gs.new_game()
	_check("3: Laden", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	_check("3: Fortschritt nach dem Laden gleich (%.3f %%), Flag noch nicht gesetzt" % SK.progress(mira, "zerog"), absf(SK.progress(mira, "zerog") - p_work) < 0.0001 and not SK.acquired(mira, "zerog"))
	toasts.clear()
	var first := -1.0
	var early := false
	for book in ["book_zerog_1", "book_zerog_2", "book_zerog_3"]:
		var guard := 0
		while guard < 20000 and SK.study(mira, book, 30.0) > 0.0:
			guard += 1
			if first < 0.0:
				first = SK.progress(mira, "zerog")
			if SK.progress(mira, "zerog") < 100.0 and SK.meets(mira, {"zerog": SK.ACQUIRED}):
				early = true
			SK.decay_recent(mira, 120.0)
	_check("3: Lehrbuch setzt am gespeicherten Stand an (%.3f → %.3f %%)" % [p_work, first], first > p_work)
	_check("3: Flag erst bei 100 %", not early and SK.acquired(mira, "zerog"))
	_check("3: Genau eine Freischaltung (%s)" % str(toasts), toasts.filter(func(t): return "acquired Zero-g Ops" in t).size() == 1)
	_check("3: Alter unverändert", mira.age == age0)

	# 4) Alter Spielstand mit erworbenem Skill; Schiffswechsel
	var dd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
	dd.crew[0].skills["zerog"] = {"p": 100.0, "xp": 30.0, "hist": []}
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(dd))
	f.close()
	gs.new_game()
	_check("4: Alter Spielstand geladen", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	_check("4: Erworben, neue Definition (kein Vakuum-Tempo), andere Skills erhalten",
		SK.acquired(mira, "zerog") and SK.effect(mira, "eva_speed") == 0.0 and is_equal_approx(SK.progress(mira, "construction"), 33.0))
	var fleet = root.get_node("FleetSystem")
	var g2 := ShipGrid.new()
	fleet._build_template(g2, {"id": "lumen", "w": 10, "h": 7})
	var id2: int = fleet.next_id
	fleet.next_id += 1
	fleet.ships.append({"id": id2, "name": "Test Ship", "location": fleet.here(), "data": g2.to_data()})
	var old_id: int = fleet.current_id
	fleet.switch_to(id2)
	_check("4: Schiffswechsel: erworben", fleet.current_id == id2 and SK.acquired(mira, "zerog"))
	fleet.switch_to(old_id)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
