## Tests: Startwerte nach Ostranauts 1.1 (Start mit 18, neun Start-Traits, zwei Start-Skills)
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

	# Neue Figur: Start mit 18, Asteroiden-Profil
	var c := CrewMember.new(990, "Fresh", Color.WHITE, Vector2i.ZERO)
	CHS.begin(c)
	_check("Startalter 18", c.age == 18 and CHS.start_age == 18)
	_check("Neun Start-Traits wie im Wiki (%s)" % str(c.traits), c.traits.size() == 9 and START.all(func(t): return t in c.traits))
	_check("Start-Skills Spaceship Engineering und Zero-g Ops erworben", SK.acquired(c, "spaceship") and SK.acquired(c, "zerog"))
	_check("Sonst keine Skills", c.skills.keys().size() == 2)
	_check("Wirkung der Start-Traits: Piloting −0,2, Essen ×%.3f, Schlaf ×0,75, Kampf ×0,8" % TS.factor(c, "hunger"),
		is_equal_approx(SK.piloting(c), -0.2) and is_equal_approx(TS.factor(c, "hunger"), 1.15 * 0.75) and is_equal_approx(TS.factor(c, "sleep_gain"), 0.75) and is_equal_approx(TS.factor(c, "combat"), 0.8))
	_check("Lebenslauf-Eintrag zum Start", c.history.size() == 1 and "asteroid" in c.history[0])
	var ids: Array = CHS.available(c).map(func(k): return k.id)
	_check("Lebensstationen ab 18 offen, keine Schule (%d Stationen)" % ids.size(), not "school" in ids and ids.size() == CHS.careers.size() and CHS.careers.all(func(k): return int(k.min_age) == 18 and not "school" in k.requires))
	# Negative Start-Traits lassen sich gegen Jahre entfernen
	CHS.toggle_trait(c, "feeble")
	CHS.toggle_trait(c, "visually_impaired")
	_check("Feeble (−2) und Visually Impaired (−1) entfernen kostet 3 Jahre", CHS.preview_age(c) == 21)
	_check("Bestätigt: weg, Alter 21", CHS.confirm(c) and c.age == 21 and not "feeble" in c.traits and not "visually_impaired" in c.traits)

	# Neues Spiel: Mira mit Startprofil plus Werftlehre
	var mira = root.get_node("CrewSystem").player()
	# Ein Zufallsereignis der Werftlehre kann einen Trait ergänzen oder ersetzen (z. B. Tough statt Fragile)
	var kept: int = START.filter(func(t): return t in mira.traits).size()
	_check("Neues Spiel: Mira 21 (18 + Werftlehre), Start-Traits %d von 9 (%s)" % [kept, str(mira.traits)], mira.age == 21 and kept >= 8 and SK.acquired(mira, "spaceship") and SK.acquired(mira, "zerog"))
	_check("Werftlehre vergibt Spaceship Engineering nicht doppelt", not mira.history.any(func(h): return "Acquired Spaceship Engineering" in h))

	# Zufällige Figuren (Bewerber): kein Asteroiden-Profil
	var npc: CrewMember = CHS.generate_npc()
	_check("Bewerber ohne Asteroiden-Profil (%s)" % str(npc.traits), not START.all(func(t): return t in npc.traits) and not SK.acquired(npc, "zerog") and not npc.history[0].contains("asteroid"))

	# Alte Spielstände bleiben, wie sie waren
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(OLD_SAVE))
	f.close()
	gs.new_game()
	_check("Alter Spielstand geladen", save.load_game(true))
	var m2 = root.get_node("CrewSystem").player()
	_check("Alter Stand: keine Start-Traits nachträglich (%s), Alter %d" % [str(m2.traits), m2.age], m2.traits == ["coordinated"] and m2.age == 21)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
