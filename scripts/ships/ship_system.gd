## Verwaltet das aktuelle Schiff (ShipGrid) und die Wegfindung darauf.
extends Node

var grid: ShipGrid
var astar := AStarGrid2D.new()
var _astar_dirty := true

func _ready() -> void:
	EventBus.ship_changed.connect(func(): _astar_dirty = true)

## Baut das Startschiff "Rostlaube" in die Mitte des Rasters.
func create_start_ship() -> void:
	grid = ShipGrid.new()
	var T := ShipGrid.Tile
	var sw := 16
	var sh := 10
	var x0 := (grid.width - sw) / 2
	var y0 := (grid.height - sh) / 2
	for y in range(y0, y0 + sh):
		for x in range(x0, x0 + sw):
			var edge := x == x0 or y == y0 or x == x0 + sw - 1 or y == y0 + sh - 1
			grid.set_tile(Vector2i(x, y), T.WALL if edge else T.FLOOR)
	# Trennwand zum Cockpit und Wohnkabine oben links
	var mid := x0 + 10
	for y in range(y0, y0 + sh):
		grid.set_tile(Vector2i(mid, y), T.WALL)
	grid.set_tile(Vector2i(mid, y0 + 6), T.DOOR)
	for x in range(x0, mid + 1):
		grid.set_tile(Vector2i(x, y0 + 4), T.WALL)
	grid.set_tile(Vector2i(x0 + 8, y0 + 4), T.DOOR)
	grid.set_tile(Vector2i(x0, y0 + 7), T.DOOR)  # Außentür

	# Einrichtung
	grid.place_device("bed", Vector2i(x0 + 1, y0 + 1))
	grid.place_device("sink", Vector2i(x0 + 3, y0 + 1))
	grid.place_device("food", Vector2i(x0 + 5, y0 + 1))
	grid.place_device("water", Vector2i(x0 + 6, y0 + 1))
	grid.place_device("o2gen", Vector2i(x0 + 9, y0 + 1))
	grid.place_device("scrubber", Vector2i(x0 + 9, y0 + 3))
	grid.place_device("generator", Vector2i(x0 + 1, y0 + 5))
	grid.place_device("battery", Vector2i(x0 + 2, y0 + 5))
	grid.place_device("airtank", Vector2i(x0 + 7, y0 + 5))
	var c1 := grid.place_device("crate", Vector2i(x0 + 14, y0 + 8))
	var c2 := grid.place_device("crate", Vector2i(x0 + 13, y0 + 8))
	c1.inv.add("plate", 12, 80); c1.inv.add("copper", 8, 90); c1.inv.add("circuit", 3, 70); c1.inv.add("pipe", 4, 85)
	c2.inv.add("ration", 10); c2.inv.add("watercan", 3); c2.inv.add("fuelcan", 2); c2.inv.add("filter", 2, 90)

	# Kabel
	for x in range(x0 + 1, x0 + 15):
		grid.cables[grid.idx(Vector2i(x, y0 + 5))] = 1
	for y in range(y0 + 1, y0 + 6):
		grid.cables[grid.idx(Vector2i(x0 + 9, y))] = 1

	for i in grid.tiles.size():
		if grid.holds_air(i):
			grid.fill_air(i)
	EventBus.ship_changed.emit()

func spawn_point() -> Vector2i:
	return Vector2i((grid.width - 16) / 2 + 4, (grid.height - 10) / 2 + 7)

# ---------------- Wegfindung (AStarGrid2D) ----------------

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

## Weg von a nach b (ohne Startfeld). Leeres Array = kein Weg.
func find_path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	if _astar_dirty:
		_rebuild_astar()
	var out: Array[Vector2i] = []
	if not grid.walkable(b) or not grid.in_bounds(a):
		return out
	if a == b:
		return out
	# Steht der Charakter gerade auf einem blockierten Feld, kurz freigeben
	var was_solid := astar.is_point_solid(a)
	astar.set_point_solid(a, false)
	var path := astar.get_id_path(a, b)
	astar.set_point_solid(a, was_solid)
	for k in range(1, path.size()):
		out.append(path[k])
	return out

## Sucht unter mehreren Zielfeldern das nächste, neben dem man stehen kann.
## Antwort: {"target": Vector2i, "path": Array[Vector2i], "ok": bool}
func nearest_adjacent(from: Vector2i, targets: Array) -> Dictionary:
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
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
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
