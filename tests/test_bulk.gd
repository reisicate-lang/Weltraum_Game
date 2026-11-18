## Tests: Bulk Trading after Ostranauts "Trading" 5 (cargo pods with four protections,
## abstract goods, prices per station, mass, removal lock, saving, Cargo tab)
##   godot --headless --path . --script res://tests/boot.gd -- test_bulk
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
	SS.slot = 963
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	root.get_node("ShipPowerSystem")._dirty = true
	root.get_node("ShipPowerSystem").step(0.01)
	var E = root.get_node("EconomySystem")
	var P = root.get_node("PhysicsSystem")
	var R = root.get_node("RemovalSystem")
	var g: ShipGrid = root.get_node("ShipSystem").grid

	# 1) Pods and the shop
	var IS = root.get_node("ItemSystem")
	_check("Four pod types: Standard, Climate-Controlled, Radiation-Shielded, Specialty",
		IS.device("cargo_pod") != null and IS.device("cargo_pod_climate") != null and IS.device("cargo_pod_radiation") != null and IS.device("cargo_pod_specialty") != null)
	_check("Pods are sold in every station market", E.SHOP_PACKED.has("pk_cargo_pod") and E.SHOP_PACKED.has("pk_cargo_pod_specialty"))
	_check("Without a pod: no bulk trading (%s)" % Bulk.block_reason(g), Bulk.block_reason(g).begins_with("No cargo pod"))

	# Two free floor tiles for a standard and a climate pod
	var free: Array = []
	for i in g.tiles.size():
		if free.size() < 2 and g.tiles[i] == ShipGrid.Tile.FLOOR and not g.foreign(i) and g.device_at(g.pos(i)) == null and not g.piles.has(i) and not g.linked.has(i):
			free.append(g.pos(i))
	var std: Device = g.place_device("cargo_pod", free[0])
	var cli: Device = g.place_device("cargo_pod_climate", free[1])
	_check("Two pods: 20 units of room", Bulk.capacity(g) == 20 and Bulk.block_reason(g) == "")

	# 2) Buying by protection
	E.credits = 1000000
	var m0: float = P.mass()
	_check("Foodstuffs (climate): 10 fit into the climate pod", Bulk.buy("food", 10) == 10)
	_check("More climate goods do not fit into the standard pod", Bulk.room_for(g, "food") == 0 and Bulk.room_for(g, "medicine") == 0)
	_check("Isotopes need radiation shielding: no room", Bulk.room_for(g, "isotopes") == 0)
	_check("Ore (standard): 10 fit", Bulk.buy("ore", 12) == 10 and Bulk.units(g.bulk) == 20)
	_check("Cargo mass: 20 units × 0.1 t (%.2f t more)" % (P.mass() - m0), is_equal_approx(P.mass() - m0, 2.0))
	_check("Specialty takes everything", Bulk.fits({"standard": 0, "climate": 0, "radiation": 0, "specialty": 2}, {"samples": 5, "isotopes": 5, "food": 5, "ore": 5}))
	_check("… but not more than its room", not Bulk.fits({"standard": 0, "climate": 0, "radiation": 0, "specialty": 1}, {"samples": 5, "ore": 6}))

	# 3) The climate pod cannot be removed while the food needs it
	_check("Uninstalling the full climate pod is refused (%s)" % R.reason("uninstall", cli.pos), R.reason("uninstall", cli.pos).begins_with("The cargo would not fit"))

	# 4) Prices per station: cheap where produced, dear where in demand
	_check("Foodstuffs: Kármán cheaper than L4 (%d vs %d)" % [Bulk.buy_price("food", "karman"), Bulk.sell_price("food", "l4")], Bulk.buy_price("food", "karman") < Bulk.sell_price("food", "l4"))
	var cr: int = E.credits
	_check("Selling at Tycho: food back to credits", Bulk.sell("food", 99) == 10 and E.credits > cr and not g.bulk.has("food"))
	_check("Now the climate pod can go", R.reason("uninstall", cli.pos) == "")

	# 5) Saving/loading: the cargo belongs to the ship
	SS.save_game()
	SS.load_game(true)
	var g2: ShipGrid = root.get_node("ShipSystem").grid
	_check("Saving/loading keeps the cargo (%s)" % str(g2.bulk), int(g2.bulk.get("ore", 0)) == 10)

	# 6) Cargo tab
	root.get_node("ShipPowerSystem")._dirty = true
	root.get_node("ShipPowerSystem").step(0.01)
	var ui = root.get_node("UIManager")
	ui.trade_tab = "cargo"
	ui.open_window("terminal")
	var texts := []
	for row in ui.window_box.get_children():
		for x in [row] + row.get_children():
			if x is Label or x is Button:
				texts.append(x.text)
	_check("Cargo tab: pods, goods and buttons", texts.any(func(s): return String(s).begins_with("Cargo pods: 1 standard, 1 climate")) and texts.any(func(s): return String(s).begins_with("Ore Concentrate")) and texts.has("Buy 10"))
	ui.close_window()

	print("%d OK, %d failed" % [ok_count, fail_count])
	quit()
