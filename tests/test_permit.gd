## Tests: Ayotimiwa Salvage Permit (Ostranauts Salvaging 2, Trading 2.3): tiers 1:1, bound to the
## transponder, N.A.S.S. fine for docking at a derelict near a station without a valid permit
##   godot --headless --path . --script res://tests/boot.gd -- test_permit
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FAIL    " + name)

func _initialize() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var SS = root.get_node("SaveSystem")
	SS.slot = 957
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	seat_pilot()
	var E = root.get_node("EconomySystem")
	var F = root.get_node("FleetSystem")
	var P = root.get_node("PhysicsSystem")
	var D = root.get_node("DialogueSystem")
	root.get_node("ShipPowerSystem").step(0.01)

	# 1) Tiers as in the wiki
	var tiers := []
	for t in Config.PERMIT_TIERS:
		tiers.append("%s %d %d" % [t.name, t.cost, t.hours])
	_check("Tiers: %s" % ", ".join(tiers), tiers == ["Yellow 5000 24", "Red 13500 72", "Blue 30000 168", "Silver 120000 720", "Black 1000000 7200"])
	_check("New game: no permit", not E.permit_valid() and E.permit_text() == "Salvage permit: none")

	# 2) Buying
	E.credits = 4999
	_check("4999 Cr are not enough for Yellow", not E.buy_permit("yellow") and E.credits == 4999)
	E.credits = 5000
	var sites: int = F.sites.size()
	_check("Yellow bought: 0 Cr left, 24 h, a new derelict", E.buy_permit("yellow") and E.credits == 0 and is_equal_approx(E.permit_hours_left(), 24.0) and F.sites.size() == sites + 1)
	_check("Valid, shown with the time left (%s)" % E.permit_text(), E.permit_valid() and E.permit_text() == "Salvage permit: Yellow, 24 h left")
	E.credits = 13500
	_check("Red on top extends to 96 h", E.buy_permit("red") and is_equal_approx(E.permit_hours_left(), 96.0))
	D.claim_discount = true
	E.credits = 2500
	_check("Gus' tip: the next Yellow costs half", E.permit_cost("yellow") == 2500 and E.buy_permit("yellow") and E.credits == 0 and not D.claim_discount)

	# 3) Bound to the transponder of this ship
	var reg: String = F.registry_id
	F.registry_id = "X-TEST"
	_check("Other ship: not valid (%s)" % E.permit_text(), not E.permit_valid() and E.permit_text() == "Salvage permit: bought for another ship")
	F.registry_id = reg
	var xp = P.ship_devices("transponder")[0]
	xp.broken = true
	_check("Broken transponder: not readable (%s)" % E.permit_text(), not E.permit_valid() and E.permit_text().contains("XPDR FAULT"))
	xp.broken = false

	# 4) Saving/loading
	var until: float = E.permit_until
	SS.save_game()
	E.permit_until = 0.0
	E.permit_reg = ""
	SS.load_game(true)
	root.get_node("ShipPowerSystem")._dirty = true
	root.get_node("ShipPowerSystem").step(0.01)   # after loading the grid is computed again
	_check("Saving/loading keeps the permit", is_equal_approx(E.permit_until, until) and E.permit_reg == reg and E.permit_valid())

	# 5) N.A.S.S. fine when docking at a derelict near a station
	var near_station := {"kind": "wreck", "near": "tycho"}
	E.credits = 100
	var debt0: int = E.debt
	E.check_permit_on_dock(near_station)
	_check("With a valid permit: no fine", E.credits == 100 and E.debt == debt0)
	gs.time = E.permit_until + 1.0
	_check("Expired after 120 h", not E.permit_valid() and E.permit_text() == "Salvage permit: expired")
	E.check_permit_on_dock(near_station)
	_check("Without a permit: %d Cr fine, 100 Cr paid, the rest onto the loan" % Config.NASS_FINE, E.credits == 0 and E.debt == debt0 + Config.NASS_FINE - 100)
	E.credits = 100
	E.check_permit_on_dock({"kind": "wreck", "near": "debris"})
	E.check_permit_on_dock({"kind": "station", "id": "tycho"})
	_check("No fine in the debris field or at a station", E.credits == 100)
	# Really docking at the derelict that the permit pointed to
	E.credits = 6000
	var site: Dictionary = F.sites[F.sites.size() - 1]
	seat_pilot()   # after loading the pilot is no longer at the console
	var docked_ok: bool = P.undock() and P.dock(site.id, true)
	_check("Docking at %s without a permit costs the fine (%d Cr left)" % [site.name, E.credits], docked_ok and E.credits == 1000)

	# 6) Display at the navigation console
	var ui = root.get_node("UIManager")
	ui.nav_open = true
	ui._last_nav = ""
	ui._refresh_nav()
	var shown := false
	for ch in ui.nav_side.get_children():
		if ch is Label and not ch.is_queued_for_deletion() and ch.text.begins_with("Salvage permit"):
			shown = true
	ui.nav_open = false
	_check("The navigation console shows the permit status", shown)

	# 7) Docking fee per hour at a station (Ostranauts Flying 4.1), one running log entry
	P.undock()
	P.dock("tycho", true)
	E.credits = 1000
	E.next_hour = gs.time + 60.0
	gs.time += 3.0 * 60.0 + 1.0
	E.step(0.0)
	_check("3 h docked at Tycho: 3 × %d Cr, one log line (%s)" % [Config.DOCK_FEE, E.log_entries[0].text], E.credits == 1000 - 3 * Config.DOCK_FEE and E.log_entries[0].text == "Docking fee (3 h)")
	P.undock()
	gs.time += 2.0 * 60.0
	E.step(0.0)
	_check("Drifting outside: no docking fee", E.credits == 1000 - 3 * Config.DOCK_FEE)

	# 8) Abandoned permits on derelicts (Ostranauts Trading 2.3)
	var mira: CrewMember = root.get_node("CrewSystem").player()
	E.permit_until = 0.0
	E.permit_reg = ""
	mira.inv.add("permit_red", 1, 60.0, {"until": gs.time - 60.0})
	var old_it: Dictionary = mira.inv.items[mira.inv.items.size() - 1]
	_check("Expired found permit: cannot be registered (%s)" % E.permit_item_text(old_it), E.permit_item_reason(old_it) == "This permit has expired." and not E.register_permit_item(mira, old_it))
	mira.inv.add("permit_yellow", 1, 60.0, {"until": gs.time + 10.0 * 60.0})
	var ok_it: Dictionary = mira.inv.items[mira.inv.items.size() - 1]
	_check("Valid found permit: registered for its 10 h left, item used up", E.register_permit_item(mira, ok_it) and E.permit_valid() and is_equal_approx(E.permit_hours_left(), 10.0) and not mira.inv.items.has(ok_it) and mira.inv.items.has(old_it))
	var site3: Dictionary = F.add_site("debris")
	_check("Docked at a fresh derelict", P.dock(site3.id, true))
	var g = root.get_node("ShipSystem").grid
	var found := 0
	for k in 200:
		var t: String = root.get_node("SalvageSystem").maybe_drop_permit(g)
		if t != "":
			found += 1
	_check("Derelicts: about every 4th has a permit (%d of 200 tries)" % found, found > 25 and found < 80)

	print("%d OK, %d failed" % [ok_count, fail_count])
	quit()
