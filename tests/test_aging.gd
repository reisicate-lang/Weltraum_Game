## Tests: Altern während der Erstellung (Ostranauts 1.2): Traits mit 29 und 42, Ende mit 47
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
	_check("Höchstalter 47", CHS.max_age == 47)

	# 1) Middle age (29) und Old age (42): je ein negativer Trait, genau einmal
	var c := CrewMember.new(990, "Aging", Color.WHITE, Vector2i.ZERO)
	CHS.begin(c)
	var n0: int = c.traits.size()
	var steps := ["military", "university", "trader"]   # 18 → 22 → 26 → 29
	for id in steps:
		CHS.apply_career(c, id)
	var aged29: Array = c.history.filter(func(h): return h.begins_with("29: Middle age"))
	_check("Mit %d: Middle age, ein negativer Trait dazu (%s)" % [c.age, str(aged29)], c.age == 29 and aged29.size() == 1 and c.traits.size() == n0 + 1)
	var newest: String = c.traits[-1]
	_check("Der neue Trait ist negativ und kein Gegenstück-Konflikt (%s)" % newest, TS.get_trait(newest).cost < 0)
	for id in ["medic", "miner", "salvager", "electrician"]:   # 29 → 32 → 35 → 38 → 41
		CHS.apply_career(c, id)
	var before42: int = c.traits.size()
	CHS.start_encounter(c, "grind")
	CHS.resolve_encounter(c, "movies")   # 41 → 42
	_check("Mit 42 (durch ein Ereignis): Old age, noch ein Trait", c.age == 42 and c.history.filter(func(h): return h.begins_with("42: Old age")).size() == 1 and c.traits.size() >= before42)
	_check("Middle age nur einmal", c.history.filter(func(h): return h.begins_with("29: Middle age")).size() == 1)

	# 2) Ende mit 47: nichts darüber hinaus, Entwürfe verfallen
	CHS.set_course(c, true, "acting")   # +1 im Entwurf
	for id in ["hacker", "bar"]:          # 42 → 45 → 47
		CHS.apply_career(c, id)
	_check("Mit 47 endet die Erstellung (Alter %d)" % c.age, c.age == 47 and CHS.creation_ended(c))
	_check("Entwürfe verfallen bei 47", not CHS.course_drafted(c, "acting") and CHS.preview_age(c) == 47)
	_check("Keine Lebensstation, kein Ereignis, kein Kurs, kein Trait mehr", CHS.available(c).is_empty() and CHS.adventure_block_reason(c) != "" and not CHS.set_course(c, true, "song") and CHS.trait_block_reason(c, "brave") != "")
	_check("Bestätigen geht", CHS.confirm(c) and c.age == 47)

	# 3) Brig kann nicht über 47 führen
	var b := CrewMember.new(991, "Brig", Color.WHITE, Vector2i.ZERO)
	CHS.begin(b)
	b.age = 46
	b.set_meta("aged_29", true)
	b.set_meta("aged_42", true)
	CHS.start_encounter(b, "king", 0.9)
	CHS.resolve_encounter(b, "mug")   # immer Brig: +1 Jahr +1–3
	_check("Brig mit 46: Alter auf 47 gekappt (%d)" % b.age, b.age == 47 and CHS.creation_ended(b))

	# 4) Kurse und Traits beim Bestätigen lösen das Altern ebenfalls aus
	var k := CrewMember.new(992, "Confirm", Color.WHITE, Vector2i.ZERO)
	CHS.begin(k)
	k.age = 27
	CHS.set_course(k, true, "civil")   # +3 → 30
	var t0: int = k.traits.size()
	CHS.confirm(k)
	_check("Kurs über 29 bestätigt: Middle age (Alter %d)" % k.age, k.age == 30 and k.history.any(func(h): return h.begins_with("29: Middle age")) and k.traits.size() == t0 + 1)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
