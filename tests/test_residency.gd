## Tests: residential status after Ostranauts "Residential Status" (visas with wiki prices and
## requirements, Embassy kiosks, citizen discount on bulk trading, home with unlimited power and
## a free docking port, saving)
##   godot --headless --path . --script res://tests/boot.gd -- test_residency
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
	SS.slot = 964
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var E = root.get_node("EconomySystem")
	var P = root.get_node("PhysicsSystem")
	var Q = root.get_node("QuestSystem")
	var SK = root.get_node("SkillSystem")
	var PS = root.get_node("ShipPowerSystem")
	var mira: CrewMember = root.get_node("CrewSystem").player()
	PS._dirty = true
	PS.step(0.01)

	# 1) Start and wiki prices
	_check("Start: illegal occupant of K-Leg", Residency.visas.is_empty() and Residency.status_text() == "Residential status: illegal occupant of K-Leg")
	_check("Wiki prices: Investor 5 000 000, Skilled Labor 750 000, Local 500 000, National 250 000, home 5 000 000",
		Residency.JURISDICTIONS.karman.visas == {"investor": 5000000, "skilled": 750000, "local": 500000, "national": 250000} and Residency.HOME_PRICE == 5000000)

	# 2) Requirements at Tycho (K-Leg)
	E.credits = 20000000
	SK.set_progress(mira, "spaceship", 100.0)
	_check("Tycho does not process K-Leg applications (wiki: No at OKLG)", Residency.visa_reason(mira, "tycho", "tycho", "skilled").begins_with("This kiosk does not process"))
	SK.set_progress(mira, "civil", 0.0)
	SK.set_progress(mira, "electrical", 0.0)
	SK.set_progress(mira, "excavation", 0.0)
	_check("Galilean Skilled Labor needs Civil, Electrical or Excavation (%s)" % Residency.visa_reason(mira, "tycho", "karman", "skilled"), Residency.visa_reason(mira, "tycho", "karman", "skilled").begins_with("Needs one of"))
	_check("National Service: needs the Ceres warzone", Residency.visa_reason(mira, "tycho", "l4", "national").contains("Ceres"))
	_check("CCRE Local Sponsored: needs a friendly resident", Residency.visa_reason(mira, "tycho", "l4", "local").begins_with("Needs a friendly resident"))
	Q.reputation["syndicate"] = 60.0
	_check("With reputation 60 on L4: Local Sponsored visa bought for 500 000", Residency.buy_visa(mira, "l4", "local") and E.credits == 20000000 - 500000 and Residency.citizen("l4"))
	_check("Xinhua Investor visa at Tycho: 5 000 000", Residency.buy_visa(mira, "hephaistos", "investor") and Residency.citizen("hephaistos"))

	# 3) K-Leg visa at another station with Spaceship Engineering
	seat_pilot()
	P.undock()
	_check("Docked at Habitat L4", P.dock("l4", true))
	_check("K-Leg Skilled Labor at L4 with Spaceship Engineering: 750 000", Residency.buy_visa(mira, "tycho", "skilled") and Residency.visas.tycho == "skilled")
	_check("Status lists the citizenships (%s)" % Residency.status_text(), Residency.status_text().begins_with("Citizen of"))

	# 4) Citizen discount on bulk trading at L4 (10 %, own choice)
	var buy_l4: int = Bulk.buy_price("food", "l4")
	Residency.visas.erase("l4")
	var buy_no: int = Bulk.buy_price("food", "l4")
	Residency.visas["l4"] = "local"
	_check("Citizen buys bulk goods cheaper on L4 (%d vs %d Cr)" % [buy_l4, buy_no], buy_l4 < buy_no)

	# 5) Home on L4: unlimited power, own docking port
	_check("No home at Kármán without citizenship", Residency.home_reason("karman") == "Only citizens may buy a home here.")
	var cr: int = E.credits
	_check("Home on L4 bought for 5 000 000", Residency.buy_home() and E.credits == cr - 5000000 and Residency.at_home())
	for d in P.ship_devices("battery"):
		d.charge = 0.0
	PS.step(0.01)
	var full := true
	for d in P.ship_devices("battery"):
		full = full and is_equal_approx(d.charge, PS.capacity_of(d))
	_check("At home: batteries stay full", full)
	E.credits = 1000
	E.next_hour = gs.time + 60.0
	gs.time += 3.0 * 60.0 + 1.0
	E.step(0.0)
	_check("At home: no docking fee", E.credits == 1000)

	# 6) Station tab: Embassy Services and Real Estate
	var ui = root.get_node("UIManager")
	ui.trade_tab = "station"
	ui.open_window("terminal")
	var texts := []
	for row in ui.window_box.get_children():
		for x in [row] + row.get_children():
			if x is Label or x is Button:
				texts.append(x.text)
	_check("Station tab: Embassy Services with visas and the Real Estate row", texts.any(func(t): return String(t).begins_with("EMBASSY SERVICES")) and texts.any(func(t): return String(t).contains("Investor visa")) and texts.any(func(t): return String(t).begins_with("REAL ESTATE")))
	ui.close_window()

	# 7) Saving/loading
	SS.save_game()
	Residency.reset()
	SS.load_game(true)
	_check("Saving/loading keeps visas and the home", Residency.citizen("l4") and Residency.citizen("tycho") and Residency.homes.has("l4"))

	print("%d OK, %d failed" % [ok_count, fail_count])
	quit()
