## Tests: transponder and antenna after Ostranauts "Ship Ownership" (XPDR/ANT FAULT, docking)
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

	# 1) Starter ship: both installed and powered
	var xp: Array = P.ship_devices("transponder")
	var an: Array = P.ship_devices("antenna")
	_check("The starter ship has a transponder and an antenna", xp.size() == 1 and an.size() == 1)
	_check("Both powered, no warning (%s)" % str(P.xpdr_faults()), xp[0].powered and an[0].powered and P.xpdr_faults().is_empty())
	_check("Kármán Ring, L4, Hephaistos require a transponder; Tycho does not",
		bool(P.loc("karman").get("requires_xpdr", false)) and bool(P.loc("l4").get("requires_xpdr", false))
		and bool(P.loc("hephaistos").get("requires_xpdr", false)) and not bool(P.loc("tycho").get("requires_xpdr", false)))
	_check("With both: no reason against the Kármán Ring", P.xpdr_dock_reason("karman") == "")

	# 2) Antenne fehlt → ANT FAULT, Station lehnt ab
	var ant = an[0]
	g.remove_device(ant)
	PS._dirty = true
	PS.step(0.01)
	_check("Without an antenna: ANT FAULT (%s)" % str(P.xpdr_faults()), P.xpdr_faults() == ["ANT FAULT"])
	var why: String = P.xpdr_dock_reason("karman")
	_check("Kármán-Ring lehnt ab: %s" % why, why.contains("antenna missing"))
	_check("Tycho accepts the ship anyway", P.xpdr_dock_reason("tycho") == "")
	_check("dock_block_reason names the reason", P.dock_block_reason("karman") == why)
	var before: String = P.docked
	_check("Forced docking (arrival) also fails", not P.dock("karman", true) and P.docked == before)
	_check("can_dock: nein", not P.can_dock("karman"))
	if P.docked != "":
		P.docked = ""
	P.travel = {}
	P.travel_to("karman")
	_check("Fast travel to the Kármán Ring is not even started", P.travel.is_empty())
	g.put_device(ant)

	# 3) Transponder broken / without power
	var x = xp[0]
	x.broken = true
	PS._dirty = true
	PS.step(0.01)
	_check("Transponder broken: XPDR FAULT, “transponder damaged”", P.xpdr_faults() == ["XPDR FAULT"] and P.xpdr_dock_reason("l4").contains("transponder damaged"))
	x.broken = false
	g.cables[g.idx(x.pos)] = 0
	PS._dirty = true
	PS.step(0.01)
	_check("Transponder without a cable: “transponder unpowered” (%s)" % P.xpdr_dock_reason("l4"), not x.powered and P.xpdr_dock_reason("l4").contains("transponder unpowered"))
	g.cables[g.idx(x.pos)] = 1
	PS._dirty = true
	PS.step(0.01)
	_check("Wieder angeschlossen: alles gut", P.xpdr_faults().is_empty())

	# 4) Shipyard ships come with both, on a cable
	var F = root.get_node("FleetSystem")
	for t in P.space.shipyard:
		var sg: ShipGrid = F.build_template(t)
		var n := 0
		for i in sg.devices:
			if sg.devices[i].type in ["transponder", "antenna"] and sg.cables[i] == 1:
				n += 1
		_check("Shipyard ship %s: transponder and antenna on a cable" % t.name, n == 2)

	# 4b) Wiki rule: not repairable, breaks at 50 % when uninstalled, replacement at the market
	var D = root.get_node("DamageSystem")
	var CS = root.get_node("ShipConstructionSystem")
	var R = root.get_node("RemovalSystem")
	var E = root.get_node("EconomySystem")
	var IS = root.get_node("ItemSystem")
	_check("Transponder: not repairable, break chance 0.5, value 29 000", not IS.device("transponder").repairable and IS.device("transponder").uninstall_break == 0.5 and IS.device("transponder").item_value == 29000)
	x.cond = 40.0
	_check("Damaged: no repair job possible", not D.needs_repair(x.pos) and not CS.place("repair", x.pos))
	D._auto_repair()
	_check("Automatic repair skips it", not CS.jobs.has(g.idx(x.pos)))
	x.cond = 100.0
	_check("Salvage value per the wiki: %d Cr" % root.get_node("SalvageSystem").device_value(x), root.get_node("SalvageSystem").device_value(x) == 29000)
	_check("Abgebaut-Gegenstand ~29 000 Cr wert (%d)" % IS.item("pk_transponder").value, absi(IS.item("pk_transponder").value - 29000) <= 1)
	# Uninstall 40 times: about half broken
	var broke := 0
	var tries := 40
	seed(12345)
	for n in tries:
		var tdev: Device = g.place_device("transponder", x.pos + Vector2i(0, 0)) if g.device_at(x.pos) == null else g.device_at(x.pos)
		var job := {"kind": "uninstall", "x": tdev.pos.x, "y": tdev.pos.y, "target": "dev:transponder", "tool": "", "progress": 1.0, "claimed_by": -1, "retry_at": 0.0, "paid": true, "need": 1.0}
		R.finish(job, null, tdev.pos)
		for i in g.piles.keys():
			var pile = g.piles[i]
			for it in pile.items.duplicate():
				if it.type == "pk_transponder":
					if it.get("data") != null and bool(it.data.get("broken", false)):
						broke += 1
					pile.take("pk_transponder", 1)
	_check("Broken when uninstalled: %d of %d (≈ 50 %%)" % [broke, tries], broke >= 10 and broke <= 30)
	var antenna_broke := 0
	_check("Antenne bricht nie (Chance 0)", IS.device("antenna").uninstall_break == 0.0 and antenna_broke == 0)
	if g.device_at(x.pos) == null:
		x = g.place_device("transponder", x.pos)
	# Markt: Ersatz-Transponder kaufbar
	_check("The market sells replacement transponders", "pk_transponder" in E.SHOP_PACKED)
	var term = null
	for i in g.devices:
		if g.devices[i].type == "terminal":
			term = g.devices[i]
	P.docked = "tycho"
	E.credits = 100000
	var c0: int = E.credits
	E.buy("pk_transponder", 1)
	_check("Bought: in the terminal, %d Cr paid" % (c0 - E.credits), term.inv.count("pk_transponder") == 1 and c0 - E.credits >= 29000)

	# 5) Old save without both: the parts lie aboard
	var SS = root.get_node("SaveSystem")
	g.remove_device(g.device_at(x.pos))
	g.remove_device(ant)
	term.inv.take("pk_transponder", 1)
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
	_check("Old save: transponder and antenna aboard as parts (%s)" % str(pk), pk.pk_transponder == 1 and pk.pk_antenna == 1)
	SS.save_game()
	SS.load_game(true)
	var pk2 := 0
	for i in root.get_node("ShipSystem").grid.piles:
		pk2 += root.get_node("ShipSystem").grid.piles[i].count("pk_transponder")
	_check("New save: no additional parts", pk2 == 1)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
