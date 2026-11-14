## Tests: „Seek Ship“ im Lebenslauf (Ostranauts 2.4): Angebot, Ablehnen, Kauf beendet die Erstellung,
## mit 47 erzwungen; Spielbeginn mit dem gekauften Schiff und seinem Kredit
##   godot --headless --path . --script res://tests/boot.gd -- test_seek_ship
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
	var F = root.get_node("FleetSystem")
	var E = root.get_node("EconomySystem")
	root.get_node("SaveSystem").slot = 956
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)

	# 1) Pool und Angebot
	var ids: Array = CHS.starter_ships().map(func(t): return t.id)
	_check("Startschiffe: Rostlaube, Lumen, Bairn (%s)" % str(ids), ids == ["rostlaube", "lumen", "bairn"])
	# Price ≈ ship value: selling a new ship (60 % of the value) never brings more than it costs
	var F0 = root.get_node("FleetSystem")
	var fair := true
	for t in CHS.starter_ships():
		var gv: ShipGrid = root.get_node("ShipSystem").grid if t.id == "rostlaube" else F0.build_template(t)
		var val: int = F0.ship_value(gv)
		fair = fair and int(t.price) >= int(val * 0.6) and int(t.price) <= int(val * 1.2)
	_check("Loan = price ≈ ship value (Rustbucket %d, Lumen %d, Bairn %d)" % [CHS.starter_ship("rostlaube").price, CHS.starter_ship("lumen").price, CHS.starter_ship("bairn").price], fair)
	var c := CrewMember.new(990, "Seeker", Color.WHITE, Vector2i.ZERO)
	CHS.begin(c)
	var a0: int = c.age
	_check("Seek Ship: +1 Jahr, Angebot Lumen", CHS.seek_ship(c, "lumen") == "lumen" and c.age == a0 + 1 and CHS.ship_offer(c) == "lumen")
	_check("Offenes Angebot sperrt Ereignis, Sparen, Lebensstationen", CHS.adventure_block_reason(c) != "" and CHS.save_money(c) == "" and CHS.available(c).is_empty())
	CHS.decline_ship(c)
	_check("Ablehnen: kein Angebot, kein weiteres Jahr", CHS.ship_offer(c) == "" and c.age == a0 + 1 and not CHS.creation_ended(c))
	var ok_rand := true
	for n in 6:
		var got: String = CHS.seek_ship(c)
		ok_rand = ok_rand and got in ids
		CHS.decline_ship(c)
	_check("Zufällige Angebote aus dem Pool", ok_rand)

	# 2) Kauf: Entwürfe werden bestätigt, Erstellung endet
	CHS.set_course(c, true, "civil")
	var age_b: int = c.age
	CHS.seek_ship(c, "bairn")
	_check("Kaufen", CHS.buy_ship(c))
	_check("Kurs bestätigt (+3), Schiff gekauft, Erstellung beendet", c.age == age_b + 1 + 3 and CHS.ship_bought(c) == "bairn" and CHS.creation_ended(c))
	_check("Danach nichts mehr: kein Ereignis, kein Kurs, kein neues Schiff",
		CHS.adventure_block_reason(c) != "" and not CHS.set_course(c, true, "business") and CHS.seek_ship(c) == "" and CHS.available(c).is_empty())
	_check("Lebenslauf: „Bought the Freighter Bairn …“", c.history.any(func(h): return String(h).contains("Bought the Freighter Bairn")))

	# 3) Mit 47 erzwungen: erstes Angebot wird angenommen
	var d := CrewMember.new(991, "Late", Color.WHITE, Vector2i.ZERO)
	CHS.begin(d)
	d.age = 46
	CHS.seek_ship(d, "lumen")
	_check("Mit 47: Angebot erzwungen angenommen", d.age == 47 and CHS.ship_bought(d) == "lumen" and CHS.ship_offer(d) == "")
	var e := CrewMember.new(992, "Old", Color.WHITE, Vector2i.ZERO)
	CHS.begin(e)
	e.age = 46
	CHS.save_money(e, 300)
	_check("Mit 47 ohne Angebot: ein zufälliges Schiff wird übernommen", e.age == 47 and CHS.ship_bought(e) in ids and e.history.any(func(h): return String(h).contains("Had to take")))
	var npc := CrewMember.new(993, "Npc", Color.WHITE, Vector2i.ZERO)
	CHS.begin(npc, false)
	npc.age = 46
	CHS.save_money(npc, 300)
	_check("Zufällige Figuren bekommen kein Schiff", CHS.ship_bought(npc) == "")

	# 4) Oberfläche und Spielbeginn mit dem Schiff
	var mira: CrewMember = root.get_node("CrewSystem").player()
	CHS.begin(mira)
	var cui = ui.char_ui
	cui.open_creation()
	await process_frame
	var sk := _find(cui.creation_box, "seek_ship")
	_check("Knopf „Seek Ship (1 year)“", sk != null and sk.text == "Seek Ship (1 year)" and not sk.disabled)
	sk.pressed.emit()
	await process_frame
	var go: Button = null
	for b in cui.creation_bottom.get_children():
		if b is Button and not b.is_queued_for_deletion() and b.text == "Let's go":
			go = b
	_check("Angebot offen: Kaufen/Ablehnen, Los geht's gesperrt", _find(cui.creation_box, "ship_buy") != null and _find(cui.creation_box, "ship_decline") != null and go != null and go.disabled)
	# auf Lumen festlegen und kaufen
	CHS.decline_ship(mira)
	CHS.seek_ship(mira, "lumen")
	cui.refresh_creation()
	await process_frame
	_find(cui.creation_box, "ship_buy").pressed.emit()
	await process_frame
	_check("Gekauft: Erstellung beendet", CHS.ship_bought(mira) == "lumen" and _find(cui.creation_box, "seek_ship") == null)
	for b in cui.creation_bottom.get_children():
		if b is Button and not b.is_queued_for_deletion() and b.text == "Let's go":
			go = b
	go.pressed.emit()
	await process_frame
	var g = root.get_node("ShipSystem").grid
	var helms := 0
	var thr := 0
	for i in g.devices:
		if g.foreign(i):
			continue
		if g.devices[i].type == "helm":
			helms += 1
		if g.devices[i].type == "thruster":
			thr += 1
	_check("Spielbeginn auf der Shuttle Lumen (%s), loan = its price" % F.current_name, F.current_name == "Shuttle Lumen" and F.registered_name == "Shuttle Lumen" and E.debt == int(CHS.starter_ship("lumen").price))
	_check("Lumen-Schiff: Steuerpult und ein Triebwerk", helms == 1 and thr == 1)
	var on_board := true
	for cm in root.get_node("CrewSystem").crew:
		on_board = on_board and g.walkable(cm.tile()) and not g.foreign(g.idx(cm.tile()))
	_check("Crew steht an Bord", on_board)
	_check("Angedockt an Tycho mit Station", root.get_node("PhysicsSystem").docked == "tycho")

	# 5) Ohne Kauf: Rostlaube und Startkredit wie bisher
	gs.new_game()
	CHS.begin(CHS.get_node("/root/CrewSystem").player())
	F.start_with(CHS.ship_bought(root.get_node("CrewSystem").player()))
	_check("Without buying: Rustbucket with the start loan", F.current_name == "Rustbucket" and E.debt == Config.START_DEBT)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
