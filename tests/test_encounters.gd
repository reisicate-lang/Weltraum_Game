## Tests: life encounters ("Seek Adventure", Ostranauts 2.1) with RISK tokens
##   godot --headless --path . --script res://tests/boot.gd -- test_encounters
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var gs
var ui
var CHS
var SK
var save

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _fresh() -> CrewMember:
	var c := CrewMember.new(800 + randi() % 1000, "Test", Color.WHITE, Vector2i.ZERO)
	CHS.begin(c)
	return c

func _find(where: Node, meta: String, value) -> Button:
	for ch in where.get_children():
		if ch.is_queued_for_deletion():
			continue
		if ch is Button and ch.has_meta(meta) and (value == null or ch.get_meta(meta) == value):
			return ch
		var b := _find(ch, meta, value)
		if b != null:
			return b
	return null

func _initialize() -> void:
	await process_frame
	await process_frame
	gs = root.get_node("GameState")
	ui = root.get_node("UIManager")
	CHS = root.get_node("CharacterSystem")
	SK = root.get_node("SkillSystem")
	save = root.get_node("SaveSystem")
	save.slot = 938
	root.get_node("Settings").meteors = false
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.close_help()

	# 1) Data as in the wiki
	_check("8 encounters with 6/5/5/6/5/5/5/5 answers", CHS.encounters.size() == 8 and CHS.encounters.map(func(e): return e.choices.size()) == [6, 5, 5, 6, 5, 5, 5, 5])
	var tokens_ok := {}
	for e in CHS.encounters:
		for ch in e.choices:
			if ch.get("risk", false):
				tokens_ok[e.risk_token] = ch.label
	_check("7 RISK answers with their own token (%s)" % str(tokens_ok.keys()), tokens_ok.size() == 7 and tokens_ok.get("IsEncRichHackFailChance") == "Hack Them" and tokens_ok.get("IsEncShadyDealFailChance") == "Join the Scheme")

	# 2) Einfache Antwort: Daily Grind → Electrician Gig
	var c := _fresh()
	var a0: int = c.age
	_check("Ereignis beginnen", CHS.start_encounter(c, "grind") == "grind" and CHS.pending_encounter(c) == "grind" and c.age == a0)
	_check("An open encounter locks life steps, confirming and a new encounter", CHS.apply_career(c, "trader") == "" and not CHS.confirm(c) and CHS.adventure_block_reason(c) != "")
	var line: String = CHS.resolve_encounter(c, "electrician")
	_check("Electrician Gig: 1 Jahr, +200 Cr, Electrical Engineering, Patient (%s)" % line, c.age == a0 + 1 and int(c.get_meta("credits", 0)) == 200 and SK.acquired(c, "electrical") and "patient" in c.traits and CHS.pending_encounter(c) == "")
	_check("Lebenslauf-Eintrag", c.history[-1] == line and "Daily Grind – Electrician Gig" in line)

	# 3) Voraussetzung: Hack Them braucht Hacking
	CHS.start_encounter(c, "king", 0.9)
	var hack: Dictionary = CHS.encounter_choice(CHS.encounter("king"), "hack")
	_check("Hack Them locked without Hacking (%s)" % CHS.choice_block_reason(c, hack), CHS.choice_block_reason(c, hack) == "Needs %s." % SK.skill("hacking").skill_name and CHS.resolve_encounter(c, "hack") == "")
	CHS.resolve_encounter(c, "drunk")
	CHS.start_encounter(c, "grind")
	CHS.resolve_encounter(c, "hacking")
	_check("After Daily Grind → Hacking, Hack Them can be chosen", CHS.choice_block_reason(c, hack) == "")
	_check("Fehlende Belohnung vermerkt (Motherboard)", "Not in game: Components: Motherboard" in c.history[-1])

	# 4) RISK tokens: 50 % at the start, only the RISK answer removes one, tokens pile up
	var r := _fresh()
	SK.set_progress(r, "unarmed", 100.0)
	CHS.start_encounter(r, "crackdown", 0.1)
	_check("Token beim Beginn (Wurf < 0,5)", int(CHS.risk_tokens(r).get("IsEncHeroFailChance", 0)) == 1)
	CHS.resolve_encounter(r, "bluff")
	_check("Andere Antwort entfernt keinen Token", int(CHS.risk_tokens(r).get("IsEncHeroFailChance", 0)) == 1)
	CHS.start_encounter(r, "crackdown", 0.1)
	CHS.resolve_encounter(r, "alarm")
	_check("Tokens pile up (2)", int(CHS.risk_tokens(r).get("IsEncHeroFailChance", 0)) == 2)
	CHS.start_encounter(r, "crackdown", 0.9)
	var age_b: int = r.age
	line = CHS.resolve_encounter(r, "hero")
	var brig_years: int = r.age - age_b - 1
	_check("With a token: RISK fails, one token gone (%s)" % line, "failure" in line and int(CHS.risk_tokens(r).IsEncHeroFailChance) == 1)
	_check("Brig: +%d years (1–3), Excavation, enemies" % brig_years, brig_years >= 1 and brig_years <= 3 and SK.acquired(r, "excavation") and "Law enforcement" in r.enemies and "Prisoner friend" in r.contacts)
	CHS.start_encounter(r, "crackdown", 0.9)
	line = CHS.resolve_encounter(r, "hero")
	_check("Second try: one token still left → failure again", "failure" in line and int(CHS.risk_tokens(r).IsEncHeroFailChance) == 0)
	CHS.start_encounter(r, "crackdown", 0.9)
	var cr0 := int(r.get_meta("credits", 0))
	line = CHS.resolve_encounter(r, "hero")
	_check("Without a token: RISK succeeds (+1750 Cr, Brave) (%s)" % line, "success" in line and int(r.get_meta("credits", 0)) == cr0 + 1750 and "brave" in r.traits)
	_check("Another encounter has its own tokens", int(CHS.risk_tokens(r).get("IsEncRichHackFailChance", 0)) == 0)

	# 5) Trait rule: Tough replaces Fragile (starting trait)
	var t := _fresh()
	SK.set_progress(t, "street", 100.0)
	CHS.start_encounter(t, "shady", 0.9)
	line = CHS.resolve_encounter(t, "violence")
	_check("Instigate Violence: Fragile gone, Tough not added (%s)" % line, not "fragile" in t.traits and not "tough" in t.traits and "lost Fragile" in line)

	# 6) Random item: Smash It gives a motor with 50 %
	var motors := 0
	for n in 30:
		var m := _fresh()
		CHS.start_encounter(m, "salvage")
		CHS.resolve_encounter(m, "smash")
		motors += m.inv.count("motor")
	_check("Smash It: motor in about half the cases (%d of 30)" % motors, motors >= 5 and motors <= 25)

	# 7) Life steps no longer bring random encounters
	var k := _fresh()
	var h0: int = k.history.size()
	for n in 3:
		CHS.apply_career(k, ["trader", "miner", "medic"][n])
	_check("Life steps: exactly one entry per step", k.history.size() == h0 + 3)

	# 8) UI: Seek Adventure, answers, locked Let's go
	var mira: CrewMember = root.get_node("CrewSystem").player()
	CHS.begin(mira)
	var cui = ui.char_ui
	cui.open_creation()
	await process_frame
	var adv := _find(cui.creation_box, "adventure", null)
	_check("Button “Seek Adventure (1 year)”", adv != null and adv.text == "Seek Adventure (1 year)" and not adv.disabled)
	adv.pressed.emit()
	await process_frame
	var ev: Dictionary = CHS.encounter(CHS.pending_encounter(mira))
	var choices: Array = ev.choices.map(func(x): return _find(cui.creation_box, "choice", x.id))
	_check("Encounter “%s” with %d answer buttons" % [ev.get("name", "?"), choices.size()], not ev.is_empty() and choices.all(func(b): return b != null))
	var go: Button = null
	for b in cui.creation_bottom.get_children():
		if b is Button and not b.is_queued_for_deletion() and b.text == "Let's go":
			go = b
	_check("Let's go locked while the encounter is open", go != null and go.disabled)
	var free_b: Button = null
	for b in choices:
		if not b.disabled:
			free_b = b
			break
	var a1: int = mira.age
	free_b.pressed.emit()
	await process_frame
	_check("Answer chosen: encounter done, at least 1 year older", CHS.pending_encounter(mira) == "" and mira.age >= a1 + 1)
	cui.creation.visible = false

	# 9) RISK tokens are saved with the character
	gs.new_game()
	mira = root.get_node("CrewSystem").player()
	CHS.risk_tokens(mira)["IsEncPokerFailChance"] = 2
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	_check("Tokens kept after loading", int(CHS.risk_tokens(root.get_node("CrewSystem").player()).get("IsEncPokerFailChance", 0)) == 2)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
