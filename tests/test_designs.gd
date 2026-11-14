extends "res://tests/test_base.gd"

var failures := 0

func check(condition: bool, description: String) -> void:
	print("OK " if condition else "FAIL ", description)
	if not condition:
		failures += 1

func _initialize() -> void:
	await process_frame
	var ship = root.get_node("ShipSystem")
	var station = root.get_node("StationSystem")
	var fleet = root.get_node("FleetSystem")
	var physics = root.get_node("PhysicsSystem")
	var salvage = root.get_node("SalvageSystem")
	root.get_node("TimeSystem").set_process(false)
	for folder in ["ships", "places"]:
		for file in DirAccess.get_files_at("res://designs/" + folder):
			if file.ends_with(".tscn"):
				var design := DesignLoader.read_design(folder + "/" + file.get_basename())
				check(not design.is_empty() and not design.tiles.is_empty(), "Loads " + file)
	for location in physics.space.locations:
		station.clear()
		salvage.clear()
		ship.create_start_ship()
		if location.kind == "station":
			check(station.build(location.id), "Dock at " + location.id)
			check(not station.rooms.is_empty(), "Service rooms in " + location.id)
		else:
			fleet.arrive(location)
			check(salvage.port >= 0, "Visit " + location.id)
			if location.kind == "asteroid":
				check(salvage.is_asteroid() and salvage.investigated, "Asteroid keeps mining behavior")
	station.clear()
	salvage.clear()
	ship.create_start_ship()
	check(fleet.attach_site(fleet.add_site("tycho")), "New wreck uses design")
	var scene: Node = load("res://designs/ships/rostlaube.tscn").instantiate()
	var terrain := scene.get_node("Terrain") as TileMapLayer
	var origin: Vector2i = scene.get_meta("grid_origin", Vector2i.ZERO)
	var cell := Vector2i(64, 44)
	terrain.set_cell(cell - origin, 0, Vector2i(3, 0))
	var device: Node2D = scene.get_node("Devices").get_child(0)
	var moved := Vector2i(65, 45)
	terrain.set_cell(moved - origin, 0, Vector2i(0, 0))
	device.position = Vector2(moved - origin) * 16
	var packed := PackedScene.new()
	packed.pack(scene)
	var path := "res://designs/ships/__roundtrip_test.tscn"
	check(not FileAccess.file_exists(path), "Temporary test path is unused")
	if FileAccess.file_exists(path):
		scene.free()
		get_tree().quit(1)
		return
	check(ResourceSaver.save(packed, path) == OK, "Save edited Godot scene")
	var edited := DesignLoader.ship("__roundtrip_test", ShipGrid.new())
	check(edited.get_tile(cell) == ShipGrid.Tile.WINDOW, "Painted tile reaches simulation")
	check(edited.devices.has(edited.idx(moved)), "Moved device reaches simulation")
	var restored := ShipGrid.from_data(edited.to_data())
	check(restored.get_tile(cell) == ShipGrid.Tile.WINDOW, "Authored tile survives game save")
	check(restored.devices.has(restored.idx(moved)), "Moved device survives game save")
	DirAccess.remove_absolute(path)
	scene.free()
	print("Design test failures: ", failures)
	get_tree().quit(1 if failures else 0)

