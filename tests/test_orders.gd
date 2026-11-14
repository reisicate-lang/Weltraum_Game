## Tests: Orders menu after Ostranauts "Orders" 4 (action + filter, tile or area)
##   godot --headless --path . --script res://tests/boot.gd -- test_orders
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

func _pick(action: String, on: Array) -> void:
	Orders.action = action
	for f in Orders.FILTERS:
		Orders.filters[f] = f in on

func _initialize() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var g = root.get_node("ShipSystem").grid
	var CS = root.get_node("ShipConstructionSystem")
	var R = root.get_node("RemovalSystem")
	var ui = root.get_node("UIManager")

	# 0) Filter mapping as in the wiki
	_check("Filter: cable CONDUIT, wall/door/window WALL, floor FLOOR, air tank/fuel tank CAN, device EQUIP",
		Orders.filter_of("cable") == "CONDUIT" and Orders.filter_of("tile:wall") == "WALL" and Orders.filter_of("tile:door") == "WALL"
		and Orders.filter_of("tile:window") == "WALL" and Orders.filter_of("tile:floor") == "FLOOR" and Orders.filter_of("dev:airtank") == "CAN"
		and Orders.filter_of("dev:fueltank") == "CAN" and Orders.filter_of("dev:bed") == "EQUIP" and Orders.filter_of("dev:light") == "EQUIP")

	var bat: Vector2i = Vector2i(-1, -1)
	for i in g.devices:
		if g.devices[i].type == "battery":
			bat = g.pos(i)
	var bi: int = g.idx(bat)
	_check("Battery tile: cable, device, floor (%s)" % str(R.layers_at(bat)), R.layers_at(bat) == ["cable", "dev:battery", "tile:floor"])

	# 1) Only matching layers get the job
	_pick("UNIN", ["FLOOR"])
	_check("UNIN + only FLOOR: the floor under a device is not possible → no job", not CS.place("orders", bat) and not CS.jobs.has(bi))
	_pick("UNIN", ["EQUIP"])
	_check("UNIN + EQUIP: uninstall the battery", CS.place("orders", bat) and CS.jobs.has(bi) and CS.jobs[bi].kind == "uninstall" and CS.jobs[bi].target == "dev:battery")
	_pick("CANC", [])
	_check("CANC (without a filter): job gone", CS.place("orders", bat) and not CS.jobs.has(bi))
	_pick("UNIN", ["CONDUIT", "EQUIP"])
	_check("UNIN + CONDUIT + EQUIP: topmost matching layer = cable", CS.place("orders", bat) and CS.jobs[bi].target == "cable")
	_pick("CANC", [])
	CS.place("orders", bat)
	_pick("SCRA", ["EQUIP"])
	_check("SCRA = destroy (fast, scrap)", CS.place("orders", bat) and CS.jobs[bi].kind == "destroy" and CS.jobs[bi].target == "dev:battery")
	_pick("CANC", [])
	CS.place("orders", bat)
	_pick("DISM", ["EQUIP"])
	_check("DISM = Zerlegen (meiste Teile)", CS.place("orders", bat) and CS.jobs[bi].kind == "dismantle")
	_pick("CANC", [])
	CS.place("orders", bat)
	_pick("UNIN", [])
	_check("No filter active: nothing", not CS.place("orders", bat) and not CS.jobs.has(bi))

	# 2) Area: walls only
	var walls := 0
	var a := Vector2i(-1, -1)
	for i in g.tiles.size():
		if g.tiles[i] == ShipGrid.Tile.WALL and not g.foreign(i) and g.device_at(g.pos(i)) == null:
			a = g.pos(i)
			break
	var before: int = CS.jobs.size()
	_pick("UNIN", ["WALL"])
	var made := 0
	for y in range(a.y, a.y + 4):
		for x in range(a.x - 2, a.x + 3):
			var q := Vector2i(x, y)
			if g.in_bounds(q) and g.tiles[g.idx(q)] == ShipGrid.Tile.WALL:
				walls += 1
			if CS.place("orders", q):
				made += 1
	var all_walls := true
	for k in CS.jobs:
		if CS.jobs[k].kind == "uninstall" and not String(CS.jobs[k].target) in ["tile:wall", "tile:door", "tile:window"]:
			all_walls = false
	_check("Area with WALL: %d wall jobs (%d walls), walls only" % [made, walls], made > 0 and made <= walls and all_walls and CS.jobs.size() == before + made)
	_pick("CANC", [])
	for y in range(a.y, a.y + 4):
		for x in range(a.x - 2, a.x + 3):
			CS.place("orders", Vector2i(x, y))
	_check("CANC over the area: all gone again", CS.jobs.size() == before)

	# 3) REPR by filter
	var dev = g.device_at(bat)
	dev.cond = 50.0
	_pick("REPR", ["FLOOR"])
	_check("REPR + only FLOOR: the damaged battery stays", not CS.place("orders", bat) and not CS.jobs.has(bi))
	_pick("REPR", ["EQUIP"])
	_check("REPR + EQUIP: Reparaturauftrag", CS.place("orders", bat) and CS.jobs.has(bi) and CS.jobs[bi].kind == "repair")
	_pick("CANC", [])
	CS.place("orders", bat)
	dev.cond = 100.0

	# 4) HAUL only with LOOSE
	var spot := Vector2i(-1, -1)
	for i in g.tiles.size():
		if g.tiles[i] == ShipGrid.Tile.FLOOR and not g.foreign(i) and g.device_at(g.pos(i)) == null and not g.piles.has(i) and g.cables[i] == 0:
			spot = g.pos(i)
			break
	g.drop_items(spot, "plate", 1, 90.0)
	var si: int = -1
	for k in g.piles:
		if g.piles[k].count("plate") > 0:
			si = k
	var sp: Vector2i = g.pos(si)
	_pick("HAUL", ["WALL", "EQUIP"])
	_check("HAUL without LOOSE: nothing", not CS.place("orders", sp))
	_pick("HAUL", ["LOOSE"])
	_check("HAUL + LOOSE: haul job", CS.place("orders", sp) and CS.jobs.has(si) and CS.jobs[si].kind == "haul")
	_pick("MINE", ["WALL"])
	_check("MINE: a normal ship wall is not rock", not CS.place("orders", a))

	# 5) UI
	ui.set_tool("orders")
	_check("The “Orders” tool shows the action and filter bar", ui.orders_bar.visible and ui.order_buttons.size() == 8 and ui.filter_buttons.size() == 6)
	_check("LOAD is locked (no ship weapons)", ui.order_buttons.LOAD.disabled)
	ui.order_buttons.DISM.pressed.emit()
	_check("An action button sets the action", Orders.action == "DISM" and ui.order_buttons.DISM.button_pressed and not ui.order_buttons.HAUL.button_pressed)
	ui.filter_buttons.WALL.pressed.emit()
	_check("Filterknopf schaltet um", bool(Orders.filters.WALL) == false and not ui.filter_buttons.WALL.button_pressed)
	ui.set_tool("select")
	_check("Another tool hides the bar", not ui.orders_bar.visible)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
