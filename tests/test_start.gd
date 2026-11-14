## Tests: starting values after Ostranauts 1.1 (start at 18, nine starting traits, two starting skills)
##   godot --headless --path . --script res://tests/boot.gd -- test_start
extends "res://tests/test_base.gd"

const OLD_SAVE := "res://tests/fixtures/old_save_blueports.json"
const START := ["feeble", "fragile", "micro_g_hypovolemic", "immunosuppressed", "insomniac", "slow_metabolism", "sharp_hearing", "unfit", "visually_impaired"]

var ok_count := 0
var fail_count := 0

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _initialize() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var CHS = root.get_node("CharacterSystem")
	var SK = root.get_node("SkillSystem")
	var TS = root.get_node("TraitSystem")
	var save = root.get_node("SaveSystem")
	save.slot = 937
	root.get_node("Settings").meteors = false
	gs.new_game()

	# New character: start at 18, asteroid profile
	var c := CrewMember.new(990, "Fresh", Color.WHITE, Vector2i.ZERO)
	CHS.begin(c)
	_check("Startalter 18", c.age == 18 and CHS.start_age == 18)
	_check("Nine starting traits as in the wiki (%s)" % str(c.traits), c.traits.size() == 9 and START.all(func(t): return t in c.traits))
	_check("Starting skills Spaceship Engineering and Zero-g Ops acquired", SK.acquired(c, "spaceship") and SK.acquired(c, "zerog"))
	_check("No other skills", c.skills.keys().size() == 2)
	_check("Effect of the starting traits: Piloting −0.2, food ×%.3f, sleep ×0.75, combat ×0.8" % TS.factor(c, "hunger"),
		is_equal_approx(SK.piloting(c), -0.2) and is_equal_approx(TS.factor(c, "hunger"), 1.15 * 0.75) and is_equal_approx(TS.factor(c, "sleep_gain"), 0.75) and is_equal_approx(TS.factor(c, "combat"), 0.8))
	_check("Life story entry for the start", c.history.size() == 1 and "asteroid" in c.history[0])
	var ids: Array = CHS.available(c).map(func(k): return k.id)
	_check("Life steps open from 18, no school (%d steps)" % ids.size(), not "school" in ids and ids.size() == CHS.careers.size() and CHS.careers.all(func(k): return int(k.min_age) == 18 and not "school" in k.requires))
	# Negative starting traits can be removed for years
	CHS.toggle_trait(c, "feeble")
	CHS.toggle_trait(c, "visually_impaired")
	_check("Removing Feeble (−2) and Visually Impaired (−1) costs 3 years", CHS.preview_age(c) == 21)
	_check("Confirmed: gone, age 21", CHS.confirm(c) and c.age == 21 and not "feeble" in c.traits and not "visually_impaired" in c.traits)

	# New game: Mira with the starting profile plus shipyard apprenticeship
	var mira = root.get_node("CrewSystem").player()
	# A random event of the apprenticeship can add or replace a trait (e.g. Tough instead of Fragile)
	var kept: int = START.filter(func(t): return t in mira.traits).size()
	_check("New game: Mira 21 (18 + apprenticeship), starting traits %d of 9 (%s)" % [kept, str(mira.traits)], mira.age == 21 and kept >= 8 and SK.acquired(mira, "spaceship") and SK.acquired(mira, "zerog"))
	_check("The apprenticeship does not grant Spaceship Engineering twice", not mira.history.any(func(h): return "Acquired Spaceship Engineering" in h))

	# Random characters (applicants): no asteroid profile
	var npc: CrewMember = CHS.generate_npc()
	_check("Applicant without the asteroid profile (%s)" % str(npc.traits), not START.all(func(t): return t in npc.traits) and not SK.acquired(npc, "zerog") and not npc.history[0].contains("asteroid"))

	# Old saves stay as they were
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(OLD_SAVE))
	f.close()
	gs.new_game()
	_check("Old save loaded", save.load_game(true))
	var m2 = root.get_node("CrewSystem").player()
	_check("Old save: no starting traits added afterwards (%s), age %d" % [str(m2.traits), m2.age], m2.traits == ["coordinated"] and m2.age == 21)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
