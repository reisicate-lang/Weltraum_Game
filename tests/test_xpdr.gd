## Tests: Transponder und Antenne nach Ostranauts „Ship Ownership“ (XPDR/ANT FAULT, Andocken)
##   godot --headless --path . --script res://tests/boot.gd -- test_xpdr
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
	root.get_node("SaveSystem").slot = 951
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	seat_pilot()
	var P = root.get_node("PhysicsSystem")
	var PS = root.get_node("ShipPowerSystem")
	var g = root.get_node("ShipSystem").grid
	PS._dirty = true
	PS.step(0.01)

	# 1) Startschiff: beides eingebaut und versorgt
	var xp: Array = P.ship_devices("transponder")
	var an: Array = P.ship_devices("antenna")
	_check("Startschiff hat Transponder und Antenne", xp.size() == 1 and an.size() == 1)
	_check("Beide mit Strom, keine Warnung (%s)" % str(P.xpdr_faults()), xp[0].powered and an[0].powered and P.xpdr_faults().is_empty())
	_check("Kármán-Ring, L4, Hephaistos verlangen Transponder; Tycho nicht",
		bool(P.loc("karman").get("requires_xpdr", false)) and bool(P.loc("l4").get("requires_xpdr", false))
		and bool(P.loc("hephaistos").get("requires_xpdr", false)) and not bool(P.loc("tycho").get("requires_xpdr", false)))
	_check("Mit beidem: kein Grund gegen Kármán-Ring", P.xpdr_dock_reason("karman") == "")

	# 2) Antenne fehlt → ANT FAULT, Station lehnt ab
	var ant = an[0]
	g.remove_device(ant)
	PS._dirty = true
	PS.step(0.01)
	_check("Ohne Antenne: ANT FAULT (%s)" % str(P.xpdr_faults()), P.xpdr_faults() == ["ANT FAULT"])
	var why: String = P.xpdr_dock_reason("karman")
	_check("Kármán-Ring lehnt ab: %s" % why, why.contains("antenna missing"))
	_check("Tycho nimmt das Schiff trotzdem", P.xpdr_dock_reason("tycho") == "")
	_check("dock_block_reason nennt den Grund", P.dock_block_reason("karman") == why)
	var before: String = P.docked
	_check("Auch erzwungenes Andocken (Ankunft) scheitert", not P.dock("karman", true) and P.docked == before)
	_check("can_dock: nein", not P.can_dock("karman"))
	if P.docked != "":
		P.docked = ""
	P.travel = {}
	P.travel_to("karman")
	_check("Schnellreise zum Kármán-Ring wird gar nicht erst gestartet", P.travel.is_empty())
	g.put_device(ant)

	# 3) Transponder kaputt / ohne Strom
	var x = xp[0]
	x.broken = true
	PS._dirty = true
	PS.step(0.01)
	_check("Transponder kaputt: XPDR FAULT, „transponder damaged“", P.xpdr_faults() == ["XPDR FAULT"] and P.xpdr_dock_reason("l4").contains("transponder damaged"))
	x.broken = false
	g.cables[g.idx(x.pos)] = 0
	PS._dirty = true
	PS.step(0.01)
	_check("Transponder ohne Kabel: „transponder unpowered“ (%s)" % P.xpdr_dock_reason("l4"), not x.powered and P.xpdr_dock_reason("l4").contains("transponder unpowered"))
	g.cables[g.idx(x.pos)] = 1
	PS._dirty = true
	PS.step(0.01)
	_check("Wieder angeschlossen: alles gut", P.xpdr_faults().is_empty())

	# 4) Werftschiffe kommen mit beidem, am Kabel
	var F = root.get_node("FleetSystem")
	for t in P.space.shipyard:
		var sg: ShipGrid = F.build_template(t)
		var n := 0
		for i in sg.devices:
			if sg.devices[i].type in ["transponder", "antenna"] and sg.cables[i] == 1:
				n += 1
		_check("Werftschiff %s: Transponder und Antenne am Kabel" % t.name, n == 2)

	# 5) Alter Spielstand ohne beides: Teile liegen an Bord
	var SS = root.get_node("SaveSystem")
	g.remove_device(x)
	g.remove_device(ant)
	SS.save_game()
	var f := FileAccess.open(SS.path(), FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	d.erase("xpdr")
	f = FileAccess.open(SS.path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	SS.load_game(true)
	var g2 = root.get_node("ShipSystem").grid
	var pk := {"pk_transponder": 0, "pk_antenna": 0}
	for i in g2.piles:
		for k in pk:
			pk[k] += g2.piles[i].count(k)
	_check("Altstand: Transponder und Antenne als Teile an Bord (%s)" % str(pk), pk.pk_transponder == 1 and pk.pk_antenna == 1)
	SS.save_game()
	SS.load_game(true)
	var pk2 := 0
	for i in root.get_node("ShipSystem").grid.piles:
		pk2 += root.get_node("ShipSystem").grid.piles[i].count("pk_transponder")
	_check("Neuer Spielstand: keine weiteren Teile", pk2 == 1)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
