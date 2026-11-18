## Tests: Barter Zone after Ostranauts "Trading" 2.1 / "Salvaging" 3.3 (mark tiles, sell from
## piles and containers there, send purchases there, saving)
##   godot --headless --path . --script res://tests/boot.gd -- test_barter
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
	var SS = root.get_node("SaveSystem")
	SS.slot = 961
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var E = root.get_node("EconomySystem")
	var CS = root.get_node("ShipConstructionSystem")
	var g: ShipGrid = root.get_node("ShipSystem").grid
	root.get_node("ShipPowerSystem")._dirty = true
	root.get_node("ShipPowerSystem").step(0.01)

	# Two free floor tiles side by side and a crate
	var a := Vector2i(-1, -1)
	for i in g.tiles.size():
		var p := g.pos(i)
		var q := p + Vector2i(1, 0)
		if Barter.valid(g, i) and g.device_at(p) == null and not g.piles.has(i) and g.in_bounds(q) and Barter.valid(g, g.idx(q)) and g.device_at(q) == null and not g.piles.has(g.idx(q)):
			a = p
			break
	var b := a + Vector2i(1, 0)
	var crate: Device = null
	for i in g.devices:
		if g.devices[i].type == "crate" and not g.foreign(i):
			crate = g.devices[i]

	# 1) Marking
	_check("Drag over two tiles marks both", CS.place("barter", a) and CS.place("barter", b) and Barter.tiles(g).size() == 2)
	_check("Space cannot be marked", not CS.can_place("barter", Vector2i(0, 0)))
	await process_frame
	CS.place("barter", b)
	_check("A new drag over a marked tile unmarks it", Barter.tiles(g).size() == 1 and g.barter.has(g.idx(a)))
	await process_frame
	CS.place("barter", b)
	CS.place("barter", crate.pos)
	_check("Marked: two floor tiles and the crate tile", Barter.tiles(g).size() == 3)

	# 2) Selling from the zone while docked at Tycho
	_check("Docked at Tycho, terminal online", E.terminal_online())
	g.drop_items(a, "plate", 5, 100.0)
	crate.inv.add("circuit", 2, 100.0)
	var invs: Array = Barter.inventories(g)
	_check("Zone: the pile and the crate (%d inventories)" % invs.size(), invs.size() == 2 and invs.has(g.piles[g.idx(a)]) and invs.has(crate.inv))
	var cr: int = E.credits
	var pile: Inventory = g.piles[g.idx(a)]
	E.sell_barter("plate", 5, pile)
	_check("Plates sold straight from the pile (%d → %d Cr), pile gone" % [cr, E.credits], E.credits > cr and not g.piles.has(g.idx(a)))
	cr = E.credits
	E.sell_barter_all()
	_check("“Sell zone” also sells the crate contents", E.credits > cr and crate.inv.count("circuit") == 0)

	# 3) Purchases into the zone
	E.credits = 100000
	var t_before: int = E.terminal().inv.count("fuelcan")
	E.buy_to_barter = true
	E.buy("fuelcan", 2)
	var spot := Barter.drop_spot(g)
	_check("Send to Barter Zone: the fuel cans lie on a zone tile", g.piles.has(g.idx(spot)) and g.piles[g.idx(spot)].count("fuelcan") == 2 and E.terminal().inv.count("fuelcan") == t_before)
	E.buy_to_barter = false
	E.buy("fuelcan", 1)
	_check("Switched off: the purchase goes into the terminal again", E.terminal().inv.count("fuelcan") == t_before + 1)

	# 4) UI: the sell tab lists the zone
	var ui = root.get_node("UIManager")
	ui.trade_tab = "sell"
	ui.open_window("terminal")
	var texts := []
	for row in ui.window_box.get_children():
		for x in [row] + row.get_children():
			if x is Label or x is Button:
				texts.append(x.text)
	_check("Sell tab: Barter Zone with its total and “Sell zone”", texts.any(func(s): return String(s).begins_with("Barter Zone total")) and texts.has("Sell zone"))
	ui.close_window()

	# 5) Undocked: no barter
	var P = root.get_node("PhysicsSystem")
	seat_pilot()
	P.undock()
	cr = E.credits
	E.sell_barter("fuelcan", 2, g.piles[g.idx(spot)])
	_check("Undocked: nothing is sold", E.credits == cr and g.piles[g.idx(spot)].count("fuelcan") == 2)

	# 6) Saving/loading keeps the zone
	var marked: Array = Barter.tiles(g)
	SS.save_game()
	SS.load_game(true)
	var g2: ShipGrid = root.get_node("ShipSystem").grid
	_check("Saving/loading keeps the Barter Zone", Barter.tiles(g2).size() == marked.size() and g2.barter.has(g2.idx(a)))

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
