## Tests: multi-tile furniture (Rack 1x2, Rack 1x4 from the Ostranauts wiki): placement on free
## floor over all tiles, rotation, occupied tiles block walking, build job, uninstall, rooms, saving
##   godot --headless --path . --script res://tests/boot.gd -- test_racks
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
	SS.slot = 967
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var IS = root.get_node("ItemSystem")
	var g: ShipGrid = root.get_node("ShipSystem").grid
	var CS = root.get_node("ShipConstructionSystem")

	_check("Wiki values: Rack 1x2 882 Cr 14 kg, Rack 1x4 1300 Cr 28 kg, rotatable",
		IS.device("rack_1x2").item_value == 882 and is_equal_approx(IS.device("rack_1x2").mass, 0.014) and IS.device("rack_1x4").item_value == 1300
		and is_equal_approx(IS.device("rack_1x4").mass, 0.028) and IS.device("rack_1x4").length == 4 and IS.device("rack_1x4").rotatable)

	# A free floor run of 4 tiles in some direction
	var spot := Vector2i(-1, -1)
	var rot := 0
	for i in g.tiles.size():
		var p := g.pos(i)
		for r in 4:
			if g.mount_reason("rack_1x4", p, r) == "":
				spot = p
				rot = r
				break
		if spot.x >= 0:
			break
	_check("Found free floor for a Rack 1x4 (%s, rotation %d)" % [str(spot), rot], spot.x >= 0)
	var rack: Device = g.place_device("rack_1x4", spot, rot)
	var cells: Array = rack.cells()
	_check("The rack covers 4 tiles", cells.size() == 4)
	var all_found := true
	var blocked := true
	for c in cells:
		all_found = all_found and g.device_at(c) == rack
		blocked = blocked and not g.walkable(c)
	_check("Every tile finds the rack and is not walkable", all_found and blocked)
	_check("A second rack on top is refused", g.mount_reason("rack_1x2", cells[2], rot) != "")
	_check("Wall or space in the way: refused", g.mount_reason("rack_1x4", Vector2i(0, 0), 0) != "")
	rack.inv.add("plate", 10, 100.0)
	_check("Rack 1x4 holds 2400 L", is_equal_approx(rack.data().storage, 2400.0) and rack.inv.count("plate") == 10)

	# Uninstall from an outer tile, then the tiles are free again
	var R = root.get_node("RemovalSystem")
	_check("Right-click on the last tile selects the rack", R.anchor(cells[3]) == rack.pos)
	g.remove_device(rack)
	var free_again := true
	for c in cells:
		free_again = free_again and g.walkable(c)
	_check("Removed: all tiles walkable again", free_again)

	# Build job with rotation
	CS.build_rot = rot
	_check("Build plan for a Rack 1x2", CS.place("dev:rack_1x2", spot))
	var job: Dictionary = CS.jobs[g.idx(spot)]
	_check("The job keeps the rotation", int(job.get("rot", -1)) == rot)
	CS.cancel(job)

	# Rooms and saving
	var r2: Device = g.place_device("rack_1x2", spot, rot)
	_check("Rack 1x2 counts as a cargo container", RoomTypes.tags_of("rack_1x2").has("cargo_container"))
	SS.save_game()
	SS.load_game(true)
	var g2: ShipGrid = root.get_node("ShipSystem").grid
	var back = g2.device_at(r2.cells()[1])
	_check("Saving/loading: the rack stays over 2 tiles", back != null and back.type == "rack_1x2" and not g2.walkable(r2.cells()[1]))

	print("%d OK, %d failed" % [ok_count, fail_count])
	quit()
