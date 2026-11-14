## Tests: room types after Ostranauts "Rooms", value factor in the ship value, Ship Rating W-X-Y-ZZZZ
##   godot --headless --path . --script res://tests/boot.gd -- test_rooms
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

## Own small grid with one room: inner area w × h, ring of walls, air (or vacuum)
func _room(w: int, h: int, devs: Array, air: bool = true) -> ShipGrid:
	var g := ShipGrid.new(w + 6, h + 6)
	for y in range(2, h + 4):
		for x in range(2, w + 4):
			var i := g.idx(Vector2i(x, y))
			var inner := x >= 3 and x < w + 3 and y >= 3 and y < h + 3
			g.tiles[i] = ShipGrid.Tile.FLOOR if inner else ShipGrid.Tile.WALL
			if inner and air:
				g.fill_air(i)
	var k := 0
	for t in devs:
		g.place_device(t, Vector2i(3 + k % w, 3 + k / w))
		k += 1
	return g

func _type(devs: Array, w: int = 4, h: int = 4, air: bool = true) -> Dictionary:
	var rooms := RoomTypes.classify(_room(w, h, devs, air))
	return rooms[0] if rooms.size() == 1 else {"id": "none(%d)" % rooms.size(), "modifier": 0.0, "name": "-"}

func _is(name: String, devs: Array, id: String, mod: float, w: int = 4, h: int = 4, air: bool = true) -> void:
	var r := _type(devs, w, h, air)
	_check("%s → %s ×%.2f (%s)" % [name, id, mod, r.name], r.id == id and is_equal_approx(r.modifier, mod))

func _initialize() -> void:
	await process_frame
	await process_frame
	root.get_node("Settings").meteors = false
	root.get_node("GameState").new_game()
	var F = root.get_node("FleetSystem")
	var ui = root.get_node("UIManager")

	# 1) Order of the wiki table: the first matching row wins
	_is("Generator (IC Reactor) + navigation console", ["generator", "helm"], "reactor_room", 1.6)
	_is("Navigation console alone", ["helm"], "bridge_closed", 1.5)
	_is("Navigation console + bed (forbidden in the closed one)", ["helm", "bed"], "bridge_open", 1.3)
	_is("Schleusenpumpe (Docking System)", ["pump"], "airlock", 1.5, 3, 1)
	_is("Airlock pump + battery", ["pump", "battery"], "engineering", 1.4)
	_is("Battery", ["battery"], "engineering", 1.4)
	_is("Lufttank (Canister)", ["airtank"], "engineering", 1.4)
	_is("Vorratsschrank (Fridge) + Waschbecken", ["food", "sink"], "wellness", 1.9)
	_is("Training rig + sink + bed (bed forbidden)", ["trainer", "sink", "bed"], "blank", 1.0)
	_is("Table + fridge + terminal (≥ 10 tiles)", ["table", "food", "terminal"], "recreational", 1.9, 5, 2)
	_is("Table + fridge + terminal in 9 tiles", ["table", "food", "terminal"], "blank", 1.0, 3, 3)
	_is("Luxury Quarters (12 tiles)", ["bed", "crate", "crate", "light", "chair"], "luxury_quarters", 2.0, 4, 3)
	_is("Toilette + Waschbecken", ["toilet", "sink"], "bathroom", 1.8, 2, 2)
	_is("Toilet + sink in 2 tiles (minimum size 4)", ["toilet", "sink"], "blank", 1.0, 2, 1)
	_is("Galley: table, 4 chairs, fridge", ["table", "chair", "chair", "chair", "chair", "food"], "galley", 1.8, 3, 2)
	_is("Basic Quarters: bed, crate, light (8 tiles)", ["bed", "crate", "light"], "basic_quarters", 1.8, 4, 2)
	_is("Basic Quarters + Toilette (verboten)", ["bed", "crate", "light", "toilet"], "blank", 1.0, 4, 2)
	_is("4 chairs in 16 tiles", ["chair", "chair", "chair", "chair"], "passenger_small", 1.4)
	_is("8 chairs in 32 tiles", ["chair", "chair", "chair", "chair", "chair", "chair", "chair", "chair"], "passenger_medium", 1.6, 8, 4)
	_is("6 Lufttanks: Engineering kommt vor Gas Cargo", ["airtank", "airtank", "airtank", "airtank", "airtank", "airtank"], "engineering", 1.4)
	_is("6 Kisten (Cargo Containers)", ["crate", "crate", "crate", "crate", "crate", "crate"], "cargo", 1.2, 3, 2)
	_is("6 crates without air: Cargo Space (Exterior)", ["crate", "crate", "crate", "crate", "crate", "crate"], "cargo_exterior", 1.05, 3, 2, false)
	_is("Navigation console without air", ["helm"], "unpressurized", 1.0, 4, 4, false)
	_is("Empty room with air", [], "blank", 1.0)
	# Open to space: no room
	var og := _room(4, 4, ["helm"])
	og.tiles[og.idx(Vector2i(2, 4))] = ShipGrid.Tile.SPACE
	_check("Hole in the wall: no enclosed room", RoomTypes.classify(og).is_empty())
	# A door as a border: two rooms
	var dg := _room(5, 2, ["helm"])
	for y in range(2, 6):
		dg.tiles[dg.idx(Vector2i(5, y))] = ShipGrid.Tile.WALL
	dg.tiles[dg.idx(Vector2i(5, 3))] = ShipGrid.Tile.DOOR
	_check("A door separates two rooms", RoomTypes.classify(dg).size() == 2)

	# 2) Ship value: the room factor multiplies installed devices, loose items do not count
	var eng := _room(4, 4, ["battery"])
	var dev_v: float = root.get_node("SalvageSystem").device_value(eng.devices.values()[0]) * 1.5
	var v_room: int = F.ship_value(eng)
	eng.tiles[eng.idx(Vector2i(2, 4))] = ShipGrid.Tile.SPACE
	var v_open: int = F.ship_value(eng)
	var expect := int(dev_v * 0.4) + 45   # + 45 Cr for the wall piece that the hole replaces
	_check("Engineering ×1,4: Wert +%d Cr (erwartet %d)" % [v_room - v_open, expect], absi(v_room - v_open - expect) <= 2)

	# 3) Ship Rating W-X-Y-ZZZZ
	_check("Zustand: 100 A, 97 B, 90 C, 60 D, 40 E", ShipRating.condition_rank(100.0) == "A" and ShipRating.condition_rank(97.0) == "B"
		and ShipRating.condition_rank(90.0) == "C" and ShipRating.condition_rank(60.0) == "D" and ShipRating.condition_rank(40.0) == "E")
	_check("Thrust: 250 A, 500 B, 700 C, 1500 D, 1600 E, without a thruster E", ShipRating.thrust_rank(250.0, 1) == "A" and ShipRating.thrust_rank(1000.0, 2) == "B"
		and ShipRating.thrust_rank(700.0, 1) == "C" and ShipRating.thrust_rank(1500.0, 1) == "D" and ShipRating.thrust_rank(1600.0, 1) == "E" and ShipRating.thrust_rank(10.0, 0) == "E")
	_check("Size: 249 Small, 900 Medium, 1600 Lunamax, 2300 Ceresmax, 3000 Titanmax, 3700 Very Large, 3701 Ultra Large",
		ShipRating.size_class(249) == "Small" and ShipRating.size_class(900) == "Medium" and ShipRating.size_class(1600) == "Lunamax"
		and ShipRating.size_class(2300) == "Ceresmax" and ShipRating.size_class(3000) == "Titanmax" and ShipRating.size_class(3700) == "Very Large" and ShipRating.size_class(3701) == "Ultra Large")
	var rg := _room(4, 4, ["helm"])
	_check("6×6 grid with a bridge: %s" % ShipRating.rating(rg), ShipRating.rating(rg) == "A-1-E-0036")
	rg.cond[rg.idx(Vector2i(3, 3))] = 0.0
	_check("One tile broken: condition %.1f %% → B" % ShipRating.condition(rg), ShipRating.rating(rg).begins_with("B-"))
	var g = root.get_node("ShipSystem").grid
	var r: String = ShipRating.rating(g, root.get_node("PhysicsSystem").mass() * 1000.0)
	_check("Starter ship: %s, 3 different rooms" % r, r.split("-").size() == 4 and r.split("-")[1] == "3" and r.split("-")[3].length() == 4)

	# 4) Anzeige
	var rt: String = ui.rooms_text(g)
	_check("Room list of the starter ship: %s" % rt, rt.contains("Airlock ×1.50") and rt.contains("Reactor Room ×1.60") and rt.contains("Bridge (Open) ×1.30"))
	_check("Bewertungszeile: %s" % ui.ship_rating_text(g, 1000.0), ui.ship_rating_text(g, 1000.0).begins_with("Ship Rating ") and ui.ship_rating_text(g, 1000.0).contains("Ship value"))
	var all_ok := true
	for t in ["chair", "table", "toilet", "light"]:
		all_ok = all_ok and root.get_node("ItemSystem").device(t) != null and root.get_node("ItemSystem").device(t).id == t
	_check("New furniture Chair, Table, Toilet, Light can be built", all_ok)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
