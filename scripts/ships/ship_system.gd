## Manages the current ship (ShipGrid) and pathfinding on it.
extends Node

var grid: ShipGrid
var astar := AStarGrid2D.new()
## Mapping of the starter ship template (former tiles) onto the fine grid, see template_cell
var template_map := PackedInt32Array()
var template_w := 0
var _astar_dirty := true

func _ready() -> void:
	EventBus.ship_changed.connect(func(): _astar_dirty = true)

## Builds the starter ship "Rustbucket" in the middle of the grid. The template is described in
## the tiles of earlier versions (twice as large) and is transferred to the fine grid with
## ShipGrid.refine – exactly like an old save.
func create_start_ship() -> void:
	grid = ShipGrid.new(Config.WORLD_W / Config.GRID_SCALE, Config.WORLD_H / Config.GRID_SCALE)
	var T := ShipGrid.Tile
	var sw := 16
	var sh := 10
	var x0 := (grid.width - sw) / 2
	var y0 := (grid.height - sh) / 2
	for y in range(y0, y0 + sh):
		for x in range(x0, x0 + sw):
			var edge := x == x0 or y == y0 or x == x0 + sw - 1 or y == y0 + sh - 1
			grid.set_tile(Vector2i(x, y), T.WALL if edge else T.FLOOR)
	# Partition to the cockpit and the cabin at the top left
	var mid := x0 + 10
	for y in range(y0, y0 + sh):
		grid.set_tile(Vector2i(mid, y), T.WALL)
	grid.set_tile(Vector2i(mid, y0 + 6), T.DOOR)
	for x in range(x0, mid + 1):
		grid.set_tile(Vector2i(x, y0 + 4), T.WALL)
	grid.set_tile(Vector2i(x0 + 8, y0 + 4), T.DOOR)
	grid.set_tile(Vector2i(x0, y0 + 7), T.DOOR)  # inner door of the airlock
	# Airlock on the left (2x2 inside) with an outer door
	for y in range(y0 + 5, y0 + 9):
		for x in range(x0 - 3, x0):
			var edge := x == x0 - 3 or y == y0 + 5 or y == y0 + 8
			grid.set_tile(Vector2i(x, y), T.WALL if edge else T.FLOOR)
	grid.set_tile(Vector2i(x0 - 3, y0 + 7), T.DOOR)
	# Station and wreck dock at the outer door of the airlock on the left

	# Furnishing
	grid.place_device("bed", Vector2i(x0 + 1, y0 + 1))
	grid.place_device("sink", Vector2i(x0 + 3, y0 + 1))
	grid.place_device("food", Vector2i(x0 + 5, y0 + 1))
	grid.place_device("water", Vector2i(x0 + 6, y0 + 1))
	grid.place_device("o2gen", Vector2i(x0 + 9, y0 + 1))
	grid.place_device("scrubber", Vector2i(x0 + 9, y0 + 3))
	grid.place_device("generator", Vector2i(x0 + 1, y0 + 5))
	grid.place_device("battery", Vector2i(x0 + 2, y0 + 5))
	grid.place_device("airtank", Vector2i(x0 + 7, y0 + 5))
	# Flight system
	grid.place_device("helm", Vector2i(x0 + 14, y0 + 1))
	# Transponder and antenna on the navigation console line (Ostranauts Ship Ownership)
	grid.place_device("transponder", Vector2i(x0 + 14, y0 + 3))
	grid.place_device("antenna", Vector2i(x0 + 14, y0 + 4))
	grid.place_device("fueltank", Vector2i(x0 + 11, y0 + 1))
	# Two thrusters (1×3) through the rear outer wall: inside in the cabin,
	# nozzle out the back into space, thrust forward
	grid.place_device("thruster", Vector2i(x0 + 1, y0 + 2), 0)
	grid.place_device("thruster", Vector2i(x0 + 1, y0 + 3), 0)
	for y in range(y0 + 2, y0 + 5):
		grid.cables[grid.idx(Vector2i(x0 + 1, y))] = 1
	for y in range(y0 + 1, y0 + 5):
		grid.cables[grid.idx(Vector2i(x0 + 14, y))] = 1
	for y in range(y0 + 6, y0 + 9):
		grid.cables[grid.idx(Vector2i(x0 + 11, y))] = 1
	grid.cables[grid.idx(Vector2i(x0 + 12, y0 + 8))] = 1
	grid.place_device("heater", Vector2i(x0 + 8, y0 + 1))
	grid.cables[grid.idx(Vector2i(x0 + 8, y0 + 1))] = 1
	grid.place_device("heater", Vector2i(x0 + 13, y0 + 1))
	grid.cables[grid.idx(Vector2i(x0 + 13, y0 + 1))] = 1
	grid.place_device("terminal", Vector2i(x0 + 12, y0 + 5))
	grid.place_device("workbench", Vector2i(x0 + 13, y0 + 5))
	grid.place_device("locker", Vector2i(x0 + 1, y0 + 8))
	grid.place_device("charger", Vector2i(x0 + 2, y0 + 8))
	grid.place_device("pump", Vector2i(x0 - 1, y0 + 6))
	var c1 := grid.place_device("crate", Vector2i(x0 + 14, y0 + 8))
	var c2 := grid.place_device("crate", Vector2i(x0 + 13, y0 + 8))
	c1.inv.add("plate", 12, 80); c1.inv.add("copper", 8, 90); c1.inv.add("circuit", 3, 70); c1.inv.add("pipe", 4, 85)
	c2.inv.add("ration", 10); c2.inv.add("watercan", 3); c2.inv.add("fuelcan", 2); c2.inv.add("filter", 2, 90)

	# Cables
	for x in range(x0 + 1, x0 + 15):
		grid.cables[grid.idx(Vector2i(x, y0 + 5))] = 1
	for y in range(y0 + 1, y0 + 6):
		grid.cables[grid.idx(Vector2i(x0 + 9, y))] = 1
	for y in range(y0 + 6, y0 + 9):
		grid.cables[grid.idx(Vector2i(x0 + 1, y))] = 1
	grid.cables[grid.idx(Vector2i(x0 + 2, y0 + 8))] = 1
	grid.cables[grid.idx(Vector2i(x0 - 1, y0 + 5))] = 1
	grid.cables[grid.idx(Vector2i(x0, y0 + 5))] = 1
	grid.cables[grid.idx(Vector2i(x0 - 1, y0 + 6))] = 1
	for i in grid.tiles.size():
		if grid.holds_air(i):
			grid.fill_air(i)
	grid = ShipGrid.refine(grid)
	# Navigation console with the Autodock Module in the module bay (formerly a separate device in the cockpit)
	for dev in grid.devices.values():
		if dev.type == "helm":
			dev.inv.add("mod_autodock", 1, 100.0)
			break
	template_map = grid.coarse_map.duplicate()
	template_w = grid.coarse_width
	grid = DesignLoader.ship("rostlaube", grid)
	EventBus.ship_changed.emit()

# ---------------- Andockschleusen ----------------

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## The tile belongs to the interior of your own ship (floor with an air connection)
func _interior(p: Vector2i) -> bool:
	if not grid.in_bounds(p):
		return false
	var i := grid.idx(p)
	return grid.tiles[i] == ShipGrid.Tile.FLOOR and grid.zone[i] == 0

## Outward direction for an airlock on tile p, otherwise Vector2i.ZERO.
## Valid: interior on one side, space (or station/wreck) opposite,
## wall to the left and right – i.e. in the middle of an outer wall.
func port_dir(p: Vector2i) -> Vector2i:
	for d in DIRS:
		var outside: Vector2i = p + d
		if not _interior(p - d) or not grid.in_bounds(outside):
			continue
		var oi := grid.idx(outside)
		if grid.tiles[oi] != ShipGrid.Tile.SPACE and not grid.foreign(oi):
			continue
		var side := Vector2i(d.y, d.x)
		if grid.wall_like(p + side) and grid.wall_like(p - side):
			return d
	return Vector2i.ZERO

## Docking ports of your own ship: [{pos, dir, i}]
## Docking ports: the outer doors of the airlocks (a room with a pump and a door to space).
## Station and wreck couple door to door at such an outer door, in any direction.
## Former docking port devices only count while the ship has no airlock.
## pos = outer door, dir = outwards, i = tile index. The port chosen when clamping comes first.
func ports() -> Array:
	var out: Array = []
	if grid == null:
		return out
	AirlockSystem.ensure()
	for di in AirlockSystem.door_lock:
		var e: Dictionary = AirlockSystem.door_lock[di]
		var o: int = e.outside
		if o < 0 or grid.zone[di] != 0:
			continue
		if grid.tiles[o] == ShipGrid.Tile.SPACE or grid.foreign(o):
			out.append({"pos": grid.pos(di), "dir": grid.pos(o) - grid.pos(di), "i": di})
	# Former docking ports (5×2): only without an airlock, or while they are still coupled
	# or a loaded save couples there again (dock_pref)
	var no_lock := out.is_empty()
	for i in grid.devices:
		var dev: Device = grid.devices[i]
		if dev.type == "dockport" and grid.zone[i] == 0 and (no_lock or grid.linked.has(i) or i == dock_pref):
			var d := dev.outward()
			var o2 := dev.pos + d
			if grid.in_bounds(o2) and (grid.get_tile(o2) == ShipGrid.Tile.SPACE or grid.foreign(grid.idx(o2))):
				out.append({"pos": dev.pos, "dir": d, "i": i})
	if dock_pref >= 0:
		out.sort_custom(func(a, b): return int(a.i == dock_pref) > int(b.i == dock_pref))
	return out

## Port aligned when clamping (tile index), used first
var dock_pref := -1

## Remove former docking port devices (5×2) as soon as they are no longer coupled and the
## ship has an airlock as its port: the outer door becomes wall, the inner row floor – airtight.
func retire_legacy_ports() -> int:
	if grid == null:
		return 0
	var has_lock_port := false
	AirlockSystem.ensure()
	for di in AirlockSystem.door_lock:
		var o: int = AirlockSystem.door_lock[di].outside
		if o >= 0 and grid.zone[di] == 0 and (grid.tiles[o] == ShipGrid.Tile.SPACE or grid.foreign(o)):
			has_lock_port = true
	if not has_lock_port:
		return 0
	var n := 0
	for dev in grid.devices.values():
		if dev.type == "dockport" and grid.zone[grid.idx(dev.pos)] == 0 and not grid.linked.has(grid.idx(dev.pos)):
			grid.remove_dock(dev)
			n += 1
	if n > 0:
		EventBus.ship_changed.emit()
		GameState.toast("Old docking port removed, outer wall sealed. Ships now dock at the airlock.")
	return n

## Free (unconnected) airlocks, optionally only in one direction
func free_ports(dir := Vector2i.ZERO) -> Array:
	return ports().filter(func(p): return not grid.linked.has(p.i) and (dir == Vector2i.ZERO or p.dir == dir))

## Tile of the starter ship template (coordinates of the former, twice as large tiles) in the
## fine grid: wall piece → its wall line, device → its tile, floor → top-left sub-tile
func template_cell(cp: Vector2i) -> Vector2i:
	if template_w <= 0:
		return cp * Config.GRID_SCALE
	return grid.pos(template_map[cp.y * template_w + cp.x])

## Crew start position: middle of the former tile (4, 7) of the ship template, on walkable floor
func spawn_point() -> Vector2i:
	var k := Config.GRID_SCALE
	var cw := grid.width / k
	var ch := grid.height / k
	var p := Vector2i(((cw - 16) / 2 + 4) * k + 1, ((ch - 10) / 2 + 7) * k + 1)
	if grid.walkable(p):
		return p
	for r in 6:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if grid.walkable(p + Vector2i(dx, dy)):
					return p + Vector2i(dx, dy)
	for i in grid.tiles.size():
		if grid.zone[i] == 0 and grid.walkable(grid.pos(i)):
			return grid.pos(i)
	return p

# ---------------- Pathfinding (AStarGrid2D) ----------------

func _rebuild_astar() -> void:
	astar.region = Rect2i(0, 0, grid.width, grid.height)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in grid.height:
		for x in grid.width:
			var p := Vector2i(x, y)
			astar.set_point_solid(p, not grid.walkable(p))
	_astar_dirty = false

## Path from a to b (without the start tile). Empty array = no path.
func find_path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	if _astar_dirty:
		_rebuild_astar()
	var out: Array[Vector2i] = []
	if not grid.walkable(b) or not grid.in_bounds(a):
		return out
	if a == b:
		return out
	# If the character is standing on a blocked tile, free it briefly
	var was_solid := astar.is_point_solid(a)
	astar.set_point_solid(a, false)
	var path := astar.get_id_path(a, b)
	astar.set_point_solid(a, was_solid)
	for k in range(1, path.size()):
		out.append(path[k])
	return out

## Finds the nearest of several target tiles that you can stand next to.
## Result: {"target": Vector2i, "path": Array[Vector2i], "ok": bool}
## reach: how far away you may work (1 = right next to it, 2 = with a long tool)
func nearest_adjacent(from: Vector2i, targets: Array, reach: int = 1) -> Dictionary:
	var best := {"ok": false}
	var best_len := INF
	var sorted := targets.duplicate()
	sorted.sort_custom(func(a, b): return Vector2(a - from).length() < Vector2(b - from).length())
	var tries := 0
	for t in sorted:
		if tries > 12:
			break
		if Vector2(t - from).length() - 1.5 > best_len:
			break
		var offsets: Array[Vector2i] = []
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				if dx != 0 or dy != 0:
					offsets.append(Vector2i(dx, dy))
		offsets.sort_custom(func(a, b): return a.length_squared() < b.length_squared())
		for d in offsets:
			var spot: Vector2i = t + d
			if not grid.walkable(spot):
				continue
			var path: Array[Vector2i] = []
			if spot != from:
				path = find_path(from, spot)
				if path.is_empty():
					continue
			if path.size() < best_len:
				best_len = path.size()
				best = {"ok": true, "target": t, "path": path}
		tries += 1
	return best
