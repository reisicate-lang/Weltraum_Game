class_name DesignLoader
extends RefCounted
## Saved Godot scenes are the source of truth for newly created layouts.
const DEVICE_SCRIPT = preload("res://scripts/design/design_device.gd")
const ROOM_SCRIPT = preload("res://scripts/design/design_room.gd")
const ROOT := "res://designs/"

static func read_design(id: String) -> Dictionary:
	var path := ROOT + id + ".tscn"
	if not ResourceLoader.exists(path):
		return {}
	var packed = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if not packed is PackedScene:
		push_error("Cannot load design: " + path)
		return {}
	var scene: Node = packed.instantiate()
	var terrain := scene.get_node_or_null("Terrain") as TileMapLayer
	var cables := scene.get_node_or_null("Cables") as TileMapLayer
	if terrain == null or cables == null:
		push_error("Design needs Terrain and Cables TileMapLayers: " + path)
		scene.free()
		return {}
	var result := {"tiles": [], "devices": [], "rooms": [], "piles": scene.get_meta("piles", []),
		"name": scene.get_meta("display_name", id), "origin": scene.get_meta("grid_origin", Vector2i.ZERO), "rel": true, "scale": Config.GRID_SCALE}
	for cell in terrain.get_used_cells():
		var tile := terrain.get_cell_atlas_coords(cell).x + 1
		if tile < ShipGrid.Tile.FLOOR or tile > ShipGrid.Tile.WINDOW:
			continue
		var wired := int(cables.get_cell_source_id(cell) >= 0)
		result.tiles.append([cell.x, cell.y, tile, wired, 100.0, 21.0, 79.0, 0.0])
	for node in scene.find_children("*", "Node2D", true, false):
		if node.get_script() == DEVICE_SCRIPT and node.component != null:
			var pos := Vector2i((node.position / 16).round())
			var device := Device.new(node.component.id, pos)
			var state: Dictionary = device.to_data()
			if node.initial_state.get("type", "") == node.component.id:
				state.merge(node.initial_state, true)
			state.type = node.component.id
			state.x = pos.x
			state.y = pos.y
			state.rot = node.direction
			result.devices.append(state)
		elif node.get_script() == ROOM_SCRIPT:
			var offset := Vector2i((node.position / 16).round())
			result.rooms.append({"kind": node.kind, "inner": Rect2i(node.inner.position + offset, node.inner.size),
				"front": Rect2i(node.front.position + offset, node.front.size), "behind": Rect2i(node.behind.position + offset, node.behind.size),
				"desk": node.desk + offset, "door": node.door + offset})
	scene.free()
	return result

static func ship(id: String, fallback: ShipGrid) -> ShipGrid:
	var design := read_design("ships/" + id)
	if design.is_empty():
		return fallback
	var grid := ShipGrid.new(fallback.width, fallback.height)
	if not fits(design, grid, design.origin, Vector2i.RIGHT, Vector2i.DOWN):
		push_error("Ship design outside world bounds: " + id)
		return fallback
	apply(design, grid, design.origin, Vector2i.RIGHT, Vector2i.DOWN, 0)
	grid.coarse_map = fallback.coarse_map.duplicate()
	grid.coarse_width = fallback.coarse_width
	return grid

static func fits(design: Dictionary, grid: ShipGrid, origin: Vector2i, along: Vector2i, outward: Vector2i) -> bool:
	var occupied := {}
	for tile in design.tiles:
		var point: Vector2i = origin + along * int(tile[0]) + outward * int(tile[1])
		if not grid.in_bounds(point) or grid.get_tile(point) != ShipGrid.Tile.SPACE or grid.zone[grid.idx(point)] != 0:
			return false
		occupied[point] = true
	for data in design.devices:
		var point: Vector2i = origin + along * int(data.x) + outward * int(data.y)
		if not occupied.has(point):
			push_error("A design device is outside its painted layout: " + String(data.type))
			return false
	return not occupied.is_empty()

static func apply(design: Dictionary, grid: ShipGrid, origin: Vector2i, along: Vector2i, outward: Vector2i, zone: int) -> void:
	for tile in design.tiles:
		var point: Vector2i = origin + along * int(tile[0]) + outward * int(tile[1])
		grid.set_tile(point, int(tile[2]))
		var index := grid.idx(point)
		grid.zone[index] = zone
		grid.cables[index] = int(tile[3])
		grid.cond[index] = float(tile[4])
		if grid.holds_air(index):
			grid.fill_air(index)
	for data in design.devices:
		var state: Dictionary = data.duplicate(true)
		var point: Vector2i = origin + along * int(data.x) + outward * int(data.y)
		state.x = point.x
		state.y = point.y
		var local_dir: Vector2i = Device.PUSH_DIRS[int(state.rot) % 4]
		state.rot = Device.PUSH_DIRS.find(along * local_dir.x + outward * local_dir.y)
		grid.put_device(Device.from_data(state))
	for pile in design.piles:
		var point: Vector2i = origin + along * int(pile[0]) + outward * int(pile[1])
		if grid.in_bounds(point) and grid.get_tile(point) != ShipGrid.Tile.SPACE:
			var inventory := Inventory.new()
			inventory.from_data(pile[2])
			grid.piles[grid.idx(point)] = inventory

static func map_rect(rect: Rect2i, origin: Vector2i, along: Vector2i, outward: Vector2i) -> Rect2i:
	var a := origin + along * rect.position.x + outward * rect.position.y
	var end := rect.end - Vector2i.ONE
	var b := origin + along * end.x + outward * end.y
	return Rect2i(a.min(b), a.max(b) - a.min(b) + Vector2i.ONE)
