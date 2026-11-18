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
	_check("Two pods installed", Bulk.pod_count(g) == 2 and Bulk.block_reason(g) == "")

	# 2) Wiki data: pod prices, one good per pod (1000 kg)
	_check("Pod prices from the wiki: 5 000 / 12 000 / 12 000 / 20 000, 50 kg each", IS.device("cargo_pod").item_value == 5000 and IS.device("cargo_pod_climate").item_value == 12000
		and IS.device("cargo_pod_radiation").item_value == 12000 and IS.device("cargo_pod_specialty").item_value == 20000 and is_equal_approx(IS.device("cargo_pod").mass, 0.05))
	_check("Furniture 22 kg: 45 per pod; Control Systems 110.67 kg: 9 per pod", Bulk.per_pod("furniture") == 45 and Bulk.per_pod("control_systems") == 9)
	_check("Food needs radiation and climate: only a Specialty pod", Bulk.needs_class("food") == "specialty" and Bulk.room_for(g, "food") == 0)
	_check("Tycho (OKLG) trades Furniture, not D2O", Bulk.traded("furniture", "tycho") and not Bulk.traded("d2o", "tycho"))

	# 3) Buying by pod loads
	E.credits = 10000000
	var m0: float = P.mass()
	_check("D2O cannot be bought at Tycho", Bulk.buy("d2o", 1) == 0)
	_check("A pod load of Furniture: 45", Bulk.buy("furniture", 45) == 45)
	_check("Control Systems go into the second pod (standard goods fit any pod): 9", Bulk.buy("control_systems", 20) == 9)
	_check("Both pods full: no more room", Bulk.room_for(g, "furniture") == 0 and Bulk.pods_used(g.bulk) == 2)
	_check("Cargo mass 45 × 22 + 9 × 110.67 kg (%.3f t more)" % (P.mass() - m0), absf(P.mass() - m0 - 1.98603) < 0.001)
	_check("Specialty takes everything, one good per pod", Bulk.fits({"standard": 0, "climate": 0, "radiation": 0, "specialty": 2}, {"food": 5000, "luxury": 13})
		and not Bulk.fits({"standard": 0, "climate": 0, "radiation": 0, "specialty": 1}, {"food": 1, "luxury": 1}))

	# 4) Removal lock and selling
	_check("Uninstalling a full pod is refused (%s)" % R.reason("uninstall", cli.pos), R.reason("uninstall", cli.pos).begins_with("The cargo would not fit"))
	_check("Consumer Goods: consumed on L4 (+++) dearer than at Kármán (+) (%.2f vs %.2f)" % [Bulk.sell_price("consumer_goods", "l4"), Bulk.buy_price("consumer_goods", "karman")],
		Bulk.price("consumer_goods", "l4") / Bulk.price("consumer_goods", "karman") > 1.1)
	var cr: int = E.credits
	_check("Selling Control Systems at Tycho", Bulk.sell("control_systems", 99) == 9 and E.credits > cr and not g.bulk.has("control_systems"))
	_check("Now the climate pod can go", R.reason("uninstall", cli.pos) == "")

	# 5) Saving/loading: the cargo belongs to the ship
	SS.save_game()
	SS.load_game(true)
	var g2: ShipGrid = root.get_node("ShipSystem").grid
	_check("Saving/loading keeps the cargo (%s)" % str(g2.bulk), int(g2.bulk.get("furniture", 0)) == 45)

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
	_check("Cargo tab: pods, goods and buttons", texts.any(func(s): return String(s).begins_with("Cargo pods: 1 standard, 1 climate")) and texts.any(func(s): return String(s).begins_with("Furniture")) and texts.has("Buy a pod load"))
	ui.close_window()

	print("%d OK, %d failed" % [ok_count, fail_count])
	quit()
