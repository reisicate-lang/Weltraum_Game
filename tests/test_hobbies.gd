## Tests: hobbies after Ostranauts 2.2.2 (18 skills with year costs, wiki effect only)
##   godot --headless --path . --script res://tests/boot.gd -- test_hobbies
extends "res://tests/test_base.gd"

const OLD_SAVE := "res://tests/fixtures/old_save_blueports.json"
const WIKI := {"acting": ["Acting", 1], "armed_melee": ["Armed Melee", 2], "cooking": ["Cooking", 1], "dance": ["Dance", 1],
	"folk": ["Folk Etiquette", 1], "forensic": ["Forensic Science", 1], "gambling": ["Gambling", 1], "hacking": ["Hacking", 2],
	"military_et": ["Military Etiquette", 1], "oligarch_et": ["Oligarch Etiquette", 1], "persuasion": ["Persuasion", 1],
	"physics": ["Physics", 1], "psychology": ["Psychology", 1], "ranged": ["Ranged Gunpowder Weapons", 1], "song": ["Song", 1],
	"stealth": ["Stealth", 1], "street": ["Street Etiquette", 1], "unarmed": ["Unarmed Melee", 2]}

var ok_count := 0
var fail_count := 0
var gs
var ui
var SK
var CHS
var save

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _hobby_button(id: String) -> Button:
	for row in ui.char_ui.creation_box.get_children():
		if row.is_queued_for_deletion() or not row is HFlowContainer:
			continue
		for b in row.get_children():
			if b is Button and b.get_meta("hobby_course", "") == id:
				return b
	return null

func _press(id: String) -> bool:
	var b := _hobby_button(id)
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	await process_frame
	return true

func _initialize() -> void:
	await process_frame
	await process_frame
	gs = root.get_node("GameState")
	ui = root.get_node("UIManager")
	SK = root.get_node("SkillSystem")
	CHS = root.get_node("CharacterSystem")
	save = root.get_node("SaveSystem")
	save.slot = 939
	root.get_node("Settings").meteors = false
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.close_help()

	# 1) Data as in the wiki
	var wrong: PackedStringArray = []
	for id in WIKI:
		var s: SkillData = SK.skill(id)
		if s == null or s.skill_name != WIKI[id][0] or s.course_years != WIKI[id][1] or not s.is_hobby or not s.gameplay_effects.is_empty() or ItemSystem.item("book_%s_3" % id) == null:
			wrong.append(id)
	_check("18 hobbies: English names, years as in the index, without an old effect, textbook Complete (wrong: %s)" % ", ".join(wrong), wrong.is_empty())
	var hobby_count: int = SK.skills.values().filter(func(s): return s.is_hobby).size()
	_check("Exactly 18 hobbies, Combat Training stays a normal skill", hobby_count == 18 and not SK.skill("combat_training").is_hobby and SK.skill("combat_training").course_years == 0 and not SK.skill("combat_training").gameplay_effects.is_empty())
	_check("The tooltip names the hobby, cost and effect", "Hobby (Ostranauts 2.2.2)." in SK.skill_tooltip(null, "hacking") and "costs 2 years" in SK.skill_tooltip(null, "hacking") and "+4 work value" in SK.skill_tooltip(null, "hacking"))

	# 2) Life story: hobby row, years like courses
	var mira: CrewMember = root.get_node("CrewSystem").player()
	CHS.begin(mira)
	var cui = ui.char_ui
	cui.open_creation()
	await process_frame
	var base: int = mira.age
	_check("All 18 hobby buttons in the life story", WIKI.keys().all(func(id): return _hobby_button(id) != null))
	_check("Choose Acting (+1): preview +1", await _press("acting") and CHS.preview_age(mira) == base + 1)
	_check("Add Hacking (+2): preview +3", await _press("hacking") and CHS.preview_age(mira) == base + 3)
	_check("Deselect Acting: preview +2", await _press("acting") and CHS.preview_age(mira) == base + 2)
	CHS.confirm(mira)
	CHS.confirm(mira)
	_check("Confirmed: Hacking acquired, age +2 exactly once", mira.age == base + 2 and SK.acquired(mira, "hacking") and not SK.acquired(mira, "acting"))
	cui.refresh_creation()
	await process_frame
	_check("An acquired hobby is marked and locked", _hobby_button("hacking").disabled and _hobby_button("hacking").text.begins_with("✔"))
	cui.creation.visible = false

	# 3) Effects after the wiki
	var a := CrewMember.new(701, "A", Color.WHITE, Vector2i.ZERO)
	var b := CrewMember.new(702, "B", Color.WHITE, Vector2i.ZERO)
	SK.set_progress(b, "hacking", 100.0)
	var debug := {"kind": "debug", "x": 0, "y": 0}
	_check("Hacking: +4 work value on software (debugging)", is_equal_approx(SK.work_value(b, debug) - SK.work_value(a, debug), 4.0))
	var u := CrewMember.new(703, "U", Color.WHITE, Vector2i.ZERO)
	var p0: float = SK.combat_power(u)
	SK.set_progress(u, "unarmed", 100.0)
	_check("Unarmed Melee: Kampfkraft %.1f → %.1f (Angriff +0,5)" % [p0, SK.combat_power(u)], is_equal_approx(SK.combat_power(u), p0 + 12.5))
	SK.set_progress(u, "unarmed", 99.9)
	_check("No bonus yet at 99.9 %", is_equal_approx(SK.combat_power(u), p0))
	var flags := ["acting", "cooking", "dance", "folk", "forensic", "gambling", "military_et", "oligarch_et", "persuasion", "physics", "psychology", "ranged", "song", "stealth", "street"]
	var f := CrewMember.new(704, "F", Color.WHITE, Vector2i.ZERO)
	for id in flags:
		SK.set_progress(f, id, 100.0)
	_check("15 pure check flags: can be queried, but no numeric effect", flags.all(func(id): return SK.meets(f, {id: SK.ACQUIRED}) and SK.skill(id).check_flag)
		and SK.effect(f, "meal_bonus") == 0.0 and SK.effect(f, "negotiate") == 0.0 and SK.effect(f, "smuggle") == 0.0 and SK.effect(f, "travel_saving") == 0.0)

	# 4) Textbook up to 100 %
	SK.set_progress(a, "song", 0.0)
	for book in ["book_song_1", "book_song_2", "book_song_3"]:
		var guard := 0
		while guard < 20000 and SK.study(a, book, 30.0) > 0.0:
			guard += 1
			SK.decay_recent(a, 120.0)
	_check("Song acquired through the three textbooks", SK.acquired(a, "song"))

	# 5) Old save: progress stays, new effect
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
	d.crew[0].skills["cooking"] = {"p": 100.0, "xp": 10.0, "hist": []}
	d.crew[0].skills["persuasion"] = {"p": 60.0, "xp": 10.0, "hist": []}
	var fl := FileAccess.open(save.path(), FileAccess.WRITE)
	fl.store_string(JSON.stringify(d))
	fl.close()
	gs.new_game()
	_check("Old save loaded", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	_check("Progress kept (Cooking 100 %, Persuasion 60 %), Cooking now a flag without a meal bonus",
		SK.acquired(mira, "cooking") and is_equal_approx(SK.progress(mira, "persuasion"), 60.0) and SK.effect(mira, "meal_bonus") == 0.0 and SK.effect(mira, "negotiate") == 0.0)
	_check("Eigene Freizeit-Hobbies weiter vorhanden (%s)" % str(mira.hobbies), mira.hobbies == ["tinkering"] and root.get_node("HobbySystem").get_hobby("tinkering") != null)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
