## Tests: aging during creation (Ostranauts 1.2): traits at 29 and 42, end at 47
##   godot --headless --path . --script res://tests/boot.gd -- test_aging
extends "res://tests/test_base.gd"

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
	var TS = root.get_node("TraitSystem")
	root.get_node("Settings").meteors = false
	gs.new_game()
	_check("Maximum age 47", CHS.max_age == 47)

	# 1) Middle age (29) and old age (42): one negative trait each, exactly once
	var c := CrewMember.new(990, "Aging", Color.WHITE, Vector2i.ZERO)
	CHS.begin(c)
	var n0: int = c.traits.size()
	var steps := ["military", "university", "trader"]   # 18 → 22 → 26 → 29
	for id in steps:
		CHS.apply_career(c, id)
	var aged29: Array = c.history.filter(func(h): return h.begins_with("29: Middle age"))
	_check("At %d: middle age, one negative trait added (%s)" % [c.age, str(aged29)], c.age == 29 and aged29.size() == 1 and c.traits.size() == n0 + 1)
	var newest: String = c.traits[-1]
	_check("The new trait is negative and has no counterpart conflict (%s)" % newest, TS.get_trait(newest).cost < 0)
	for id in ["medic", "miner", "salvager", "electrician"]:   # 29 → 32 → 35 → 38 → 41
		CHS.apply_career(c, id)
	var before42: int = c.traits.size()
	CHS.start_encounter(c, "grind")
	CHS.resolve_encounter(c, "movies")   # 41 → 42
	_check("At 42 (through an encounter): old age, another trait", c.age == 42 and c.history.filter(func(h): return h.begins_with("42: Old age")).size() == 1 and c.traits.size() >= before42)
	_check("Middle age only once", c.history.filter(func(h): return h.begins_with("29: Middle age")).size() == 1)

	# 2) End at 47: nothing beyond it, drafts expire
	CHS.set_course(c, true, "acting")   # +1 in the draft
	for id in ["hacker", "bar"]:          # 42 → 45 → 47
		CHS.apply_career(c, id)
	_check("At 47 creation ends (age %d)" % c.age, c.age == 47 and CHS.creation_ended(c))
	_check("Drafts expire at 47", not CHS.course_drafted(c, "acting") and CHS.preview_age(c) == 47)
	_check("No life step, no encounter, no course, no trait any more", CHS.available(c).is_empty() and CHS.adventure_block_reason(c) != "" and not CHS.set_course(c, true, "song") and CHS.trait_block_reason(c, "brave") != "")
	_check("Confirming works", CHS.confirm(c) and c.age == 47)

	# 3) The Brig cannot lead past 47
	var b := CrewMember.new(991, "Brig", Color.WHITE, Vector2i.ZERO)
	CHS.begin(b)
	b.age = 46
	b.set_meta("aged_29", true)
	b.set_meta("aged_42", true)
	CHS.start_encounter(b, "king", 0.9)
	CHS.resolve_encounter(b, "mug")   # immer Brig: +1 Jahr +1–3
	_check("Brig at 46: age capped at 47 (%d)" % b.age, b.age == 47 and CHS.creation_ended(b))

	# 4) Courses and traits also trigger aging when confirming
	var k := CrewMember.new(992, "Confirm", Color.WHITE, Vector2i.ZERO)
	CHS.begin(k)
	k.age = 27
	CHS.set_course(k, true, "civil")   # +3 → 30
	var t0: int = k.traits.size()
	CHS.confirm(k)
	_check("Course past 29 confirmed: middle age (age %d)" % k.age, k.age == 30 and k.history.any(func(h): return h.begins_with("29: Middle age")) and k.traits.size() == t0 + 1)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
