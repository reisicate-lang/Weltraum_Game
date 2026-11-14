## Verwaltet das aktuelle Schiff (ShipGrid) und die Wegfindung darauf.
extends Node

var grid: ShipGrid
var astar := AStarGrid2D.new()
## Abbildung der Startschiff-Vorlage (frühere Felder) aufs feine Raster, siehe template_cell
var template_map := PackedInt32Array()
var template_w := 0
var _astar_dirty := true

func _ready() -> void:
	EventBus.ship_changed.connect(func(): _astar_dirty = true)

## Baut das Startschiff "Rostlaube" in die Mitte des Rasters. Die Vorlage ist in den
## Feldern früherer Versionen beschrieben (doppelt so groß) und wird mit ShipGrid.refine
## ins feine Raster übertragen – genauso wie ein alter Spielstand.
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
	# Trennwand zum Cockpit und Wohnkabine oben links
	var mid := x0 + 10
	for y in range(y0, y0 + sh):
		grid.set_tile(Vector2i(mid, y), T.WALL)
	grid.set_tile(Vector2i(mid, y0 + 6), T.DOOR)
	for x in range(x0, mid + 1):
		grid.set_tile(Vector2i(x, y0 + 4), T.WALL)
	grid.set_tile(Vector2i(x0 + 8, y0 + 4), T.DOOR)
	grid.set_tile(Vector2i(x0, y0 + 7), T.DOOR)  # Innentür der Schleuse
	# Luftschleuse links (2x2 innen) mit Außentür
	for y in range(y0 + 5, y0 + 9):
		for x in range(x0 - 3, x0):
			var edge := x == x0 - 3 or y == y0 + 5 or y == y0 + 8
			grid.set_tile(Vector2i(x, y), T.WALL if edge else T.FLOOR)
	grid.set_tile(Vector2i(x0 - 3, y0 + 7), T.DOOR)
	# Angedockt wird an der Außentür der Luftschleuse links (Station und Wrack)

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
	# Flugsystem
	grid.place_device("helm", Vector2i(x0 + 14, y0 + 1))
	# Transponder und Antenne an der Steuerpult-Leitung (Ostranauts Ship Ownership)
	grid.place_device("transponder", Vector2i(x0 + 14, y0 + 3))
	grid.place_device("antenna", Vector2i(x0 + 14, y0 + 4))
	grid.place_device("fueltank", Vector2i(x0 + 11, y0 + 1))
	# Zwei Triebwerke (1×3) durch die hintere Außenwand: innen in der Wohnkabine,
	# Düse hinten ins All, Schub nach vorn
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

	# Kabel
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
	# Steuerpult mit Autodock-Modul im Modulfach (früher ein eigenes Gerät im Cockpit)
	for dev in grid.devices.values():
		if dev.type == "helm":
			dev.inv.add("mod_autodock", 1, 100.0)
			break
	template_map = grid.coarse_map.duplicate()
	template_w = grid.coarse_width
	EventBus.ship_changed.emit()

# ---------------- Andockschleusen ----------------

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Feld gehört zum Innenraum des eigenen Schiffs (Boden mit Luftverbindung)
func _interior(p: Vector2i) -> bool:
	if not grid.in_bounds(p):
		return false
	var i := grid.idx(p)
	return grid.tiles[i] == ShipGrid.Tile.FLOOR and grid.zone[i] == 0

## Richtung nach außen für eine Schleuse auf Feld p, sonst Vector2i.ZERO.
## Gültig: auf der einen Seite Innenraum, gegenüber All (oder Station/Wrack),
## links und rechts Wand – also mitten in einer Außenwand.
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

## Andockschleusen des eigenen Schiffs: [{pos, dir, i}]
## Andockports: die Außentüren der Luftschleusen (Raum mit Pumpe, Tür zum All).
## Station und Wrack koppeln Tür an Tür an einer solchen Außentür, egal in welche Richtung.
## Frühere Andockschleusen-Geräte zählen nur noch, solange das Schiff keine Luftschleuse hat.
## pos = Außentür, dir = nach außen, i = Feld-Index. Der beim Klammern gewählte Port zuerst.
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
	# Frühere Andockschleusen (5×2): nur ohne Luftschleuse, oder solange sie noch gekoppelt
	# sind bzw. ein geladener Spielstand dort wieder ankoppelt (dock_pref)
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

## Beim Klammern ausgerichteter Port (Feld-Index), wird bevorzugt belegt
var dock_pref := -1

## Frühere Andockschleusen-Geräte (5×2) entfernen, sobald sie nicht mehr gekoppelt sind und das
## Schiff eine Luftschleuse als Port hat: Außentür wird Wand, Innenreihe Boden – dicht.
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

## Freie (nicht verbundene) Schleusen, optional nur in eine Richtung
func free_ports(dir := Vector2i.ZERO) -> Array:
	return ports().filter(func(p): return not grid.linked.has(p.i) and (dir == Vector2i.ZERO or p.dir == dir))

## Feld der Startschiff-Vorlage (Koordinaten der früheren, doppelt so großen Felder) im
## feinen Raster: Wandstück → seine Wandlinie, Gerät → sein Feld, Boden → linkes oberes Teilfeld
func template_cell(cp: Vector2i) -> Vector2i:
	if template_w <= 0:
		return cp * Config.GRID_SCALE
	return grid.pos(template_map[cp.y * template_w + cp.x])

## Startplatz der Crew: Mitte des früheren Feldes (4, 7) der Schiffsvorlage, auf begehbarem Boden
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
	return p

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
## reach: wie weit entfernt man arbeiten darf (1 = direkt daneben, 2 = mit langem Werkzeug)
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
