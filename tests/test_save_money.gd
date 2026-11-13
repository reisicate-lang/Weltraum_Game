## Tests: „Save Some Money“ im Lebenslauf (Ostranauts 2.3): 1 Jahr, etwa 300–600 Cr Startgeld
##   godot --headless --path . --script res://tests/boot.gd -- test_save_money
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

func _find(where: Node, meta: String) -> Button:
	for ch in where.get_children():
		if ch.is_queued_for_deletion():
			continue
		if ch is Button and ch.has_meta(meta):
			return ch
		var b := _find(ch, meta)
		if b != null:
			return b
	return null

func _initialize() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var CHS = root.get_node("CharacterSystem")
	var ui = root.get_node("UIManager")
	root.get_node("SaveSystem").slot = 952
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)

	# 1) Logik: +1 Jahr, Betrag 300–600, Lebenslaufzeile
	var c := CrewMember.new(990, "Saver", Color.WHITE, Vector2i.ZERO)
	CHS.begin(c)
	var a0: int = c.age
	var line: String = CHS.save_money(c, 450)
	_check("Fester Betrag: +1 Jahr, +450 Cr (%s)" % line, c.age == a0 + 1 and CHS.start_credits(c) == 450 and line.contains("Saved some money (+450 Cr)") and c.history.has(line))
	var ok_range := true
	for k in 20:
		var before: int = CHS.start_credits(c)
		if CHS.save_money(c) == "":
			break
		var got: int = CHS.start_credits(c) - before
		ok_range = ok_range and got >= 300 and got <= 600
	_check("Zufällig immer 300–600 Cr", ok_range)
	_check("Mit 29 greift das Altern (Middle age)", c.get_meta("aged_29", false))
	# Ende der Erstellung: mit 47 nicht mehr
	c.age = CHS.max_age
	_check("Mit 47 gesperrt", CHS.save_money(c) == "" and c.age == CHS.max_age)
	# Offenes Ereignis sperrt
	var d := CrewMember.new(991, "Busy", Color.WHITE, Vector2i.ZERO)
	CHS.begin(d)
	CHS.start_encounter(d)
	_check("Offenes Ereignis sperrt Save Some Money", CHS.save_money(d) == "" and d.age == 18)

	# 2) Oberfläche
	var mira: CrewMember = root.get_node("CrewSystem").player()
	CHS.begin(mira)
	var cui = ui.char_ui
	cui.open_creation()
	await process_frame
	var b := _find(cui.creation_box, "save_money")
	_check("Knopf „Save Some Money (1 year)“", b != null and b.text == "Save Some Money (1 year)" and not b.disabled and b.tooltip_text.contains("300–600"))
	var age_b: int = mira.age
	b.pressed.emit()
	await process_frame
	_check("Klick: +1 Jahr und Startgeld (%d Cr)" % CHS.start_credits(mira), mira.age == age_b + 1 and CHS.start_credits(mira) >= 300)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
