## Tests: emergency items and micrometeorites after the Ostranauts wiki (Oxygen Candle, "Ripley"
## Temporary Blister Seal Wall, game speed back to ×1 on a strike)
##   godot --headless --path . --script res://tests/boot.gd -- test_emergency
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
	SS.slot = 965
	root.get_node("Settings").meteors = false
	gs.new_game()
	var TS = root.get_node("TimeSystem")
	TS.set_speed(0)
	var IS = root.get_node("ItemSystem")
	var g: ShipGrid = root.get_node("ShipSystem").grid
	var mira: CrewMember = root.get_node("CrewSystem").player()
	var CS = root.get_node("ShipConstructionSystem")
	var DS = root.get_node("DamageSystem")

	_check("Wiki values: Oxygen Candle 360 Cr 1.8 kg, Ripley seal 79 Cr 4 kg", IS.item("oxygen_candle").value == 360 and is_equal_approx(IS.item("oxygen_candle").weight, 1.8)
		and IS.item("ripley_seal").value == 79 and is_equal_approx(IS.item("ripley_seal").weight, 4.0))

	# 1) Oxygen candle: 60 minutes of oxygen where it was struck
	mira.inv.add("oxygen_candle", 1, 100.0)
	var ti: int = g.idx(mira.tile())
	g.o2[ti] = 5.0
	_check("Activating uses up the candle", Emergency.activate_candle(mira) and mira.inv.count("oxygen_candle") == 0 and g.candles.size() == 1)
	Emergency.step(g, 1.0)
	_check("One minute: +6 kPa O₂ on its tile (%.1f)" % g.o2[ti], is_equal_approx(g.o2[ti], 11.0))
	Emergency.step(g, 70.0)
	_check("After 60 minutes it is spent", g.candles.is_empty())

	# 2) Ripley seal on a hull breach
	var hull := -1
	for i in g.tiles.size():
		if g.tiles[i] == ShipGrid.Tile.WALL and g.zone[i] == 0 and g.device_at(g.pos(i)) == null:
			var p := g.pos(i)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if g.get_tile(p + d) == ShipGrid.Tile.SPACE:
					hull = i
		if hull >= 0:
			break
	g.set_tile(g.pos(hull), ShipGrid.Tile.FLOOR)
	CS.place("wall", g.pos(hull))
	_check("A breach: floor next to space", Emergency.is_breach(g, hull))
	mira.pos = Vector2(g.pos(hull)) + Vector2(0.5, 0.5)
	mira.inv.add("ripley_seal", 2, 100.0)
	_check("Sealing: wall again for 60 minutes, low condition", Emergency.seal_breach(mira) and g.tiles[hull] == ShipGrid.Tile.WALL and g.temp_seal.has(hull) and g.cond[hull] < 50.0)
	gs.time += 61.0
	Emergency.step(g, 0.0)
	_check("Not repaired in time: the breach opens again", g.tiles[hull] == ShipGrid.Tile.FLOOR and not g.temp_seal.has(hull) and CS.jobs.has(hull))
	Emergency.seal_breach(mira)
	DS.repair(g.pos(hull))
	gs.time += 61.0
	Emergency.step(g, 0.0)
	_check("Repaired in time: the wall stays", g.tiles[hull] == ShipGrid.Tile.WALL and not g.temp_seal.has(hull))

	# 3) Micrometeorite: fast-forward back to ×1, a pause stays
	TS.set_speed(4)
	DS.strike()
	_check("Strike at ×8: speed back to ×1", TS.speed_index == 1)
	TS.set_speed(0)
	DS.strike()
	_check("Strike while paused: stays paused", TS.speed_index == 0)

	# Hypoxia (wiki: below 20 kPa) only warns; suffocation starts below 16 kPa
	mira.pos = Vector2(root.get_node("ShipSystem").spawn_point()) + Vector2(0.5, 0.5)
	var mt: int = g.idx(mira.tile())
	g.o2[mt] = 17.0
	mira.needs.air = 100.0
	mira._update_body(5.0)
	_check("17 kPa O₂: hypoxia warning only, the air need holds (%.0f)" % mira.needs.air, mira.needs.air >= 99.0 and mira.safe_air(mt))
	g.o2[mt] = 10.0
	mira._update_body(1.0)
	_check("10 kPa O₂: suffocating (%.0f)" % mira.needs.air, mira.needs.air < 90.0 and not mira.safe_air(mt))
	g.o2[mt] = 21.0
	mira.needs.air = 100.0

	# Halvorson Fire Extinguisher (wiki: 240 Cr, 2.5 kg, bludgeoning tool): fires out 3× faster
	var SKS = root.get_node("SkillSystem")
	var removed: Array = []
	for d in root.get_node("PhysicsSystem").ship_devices("extinguisher"):
		removed.append(d)
		g.remove_device(d)
	var fjob := {"kind": "extinguish", "x": mira.tile().x, "y": mira.tile().y}
	mira.inv.take("fire_extinguisher", 99)
	var bare: float = SKS.work_speed(mira, fjob)
	mira.inv.add("fire_extinguisher", 1, 100.0)
	var with_ext: float = SKS.work_speed(mira, fjob)
	_check("Fire Extinguisher: 240 Cr, 2.5 kg, a melee weapon; extinguishing ×3 (%.2f → %.2f)" % [bare, with_ext], IS.item("fire_extinguisher").value == 240
		and is_equal_approx(IS.item("fire_extinguisher").weight, 2.5) and IS.item("fire_extinguisher").weapon == "armed" and is_equal_approx(with_ext, bare * 3.0))
	mira.inv.take("fire_extinguisher", 99)
	for d in removed:
		g.put_device(d)

	# 4) Saving/loading keeps candles and seals
	mira.inv.add("oxygen_candle", 1, 100.0)
	Emergency.activate_candle(mira)
	g.temp_seal[hull] = gs.time + 30.0
	SS.save_game()
	SS.load_game(true)
	var g2: ShipGrid = root.get_node("ShipSystem").grid
	_check("Saving/loading keeps the burning candle and the seal", g2.candles.size() == 1 and g2.temp_seal.has(hull))

	print("%d OK, %d failed" % [ok_count, fail_count])
	quit()
