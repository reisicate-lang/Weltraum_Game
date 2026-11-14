## The ship as a grid of tiles.
## Every tile has a type, maybe a cable, maybe a device
## and its own air (O2, N2, CO2 in kPa).
class_name ShipGrid
extends RefCounted

enum Tile { SPACE = 0, FLOOR = 1, WALL = 2, DOOR = 3, WINDOW = 4 }

var width: int
var height: int
var tiles := PackedByteArray()
var cables := PackedByteArray()
var o2 := PackedFloat32Array()
var n2 := PackedFloat32Array()
var co2 := PackedFloat32Array()
var cond := PackedFloat32Array()
var door_open_until := PackedFloat64Array()
## Zone: 0 = your ship, 1 = wreck, 2 = salvage line
var zone := PackedByteArray()
## Temperature in °C and fire (1 = burning)
var temp := PackedFloat32Array()
var fire := PackedByteArray()
## Doors: vent closed (1) – then the closed door is fully airtight
var vent_closed := PackedByteArray()
var devices: Dictionary = {}  ## tile index -> Device
## Docking ports currently connected to a station or a wreck (tile index -> true)
var linked: Dictionary = {}
var piles: Dictionary = {}    ## tile index -> Inventory (pile on the floor)

func _init(w: int = Config.WORLD_W, h: int = Config.WORLD_H) -> void:
	width = w
	height = h
	var n := w * h
	tiles.resize(n); cables.resize(n)
	o2.resize(n); n2.resize(n); co2.resize(n); door_open_until.resize(n)
	cond.resize(n)
	cond.fill(100.0)
	zone.resize(n)
	temp.resize(n)
	temp.fill(Config.SPACE_TEMP)
	fire.resize(n)
	vent_closed.resize(n)

func idx(p: Vector2i) -> int:
	return p.y * width + p.x

func pos(i: int) -> Vector2i:
	return Vector2i(i % width, i / width)

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height

func get_tile(p: Vector2i) -> int:
	return tiles[idx(p)] if in_bounds(p) else Tile.SPACE

func set_tile(p: Vector2i, t: int) -> void:
	if not in_bounds(p):
		return
	var i := idx(p)
	tiles[i] = t
	cond[i] = 100.0
	fire[i] = 0
	if t == Tile.SPACE:
		cables[i] = 0
		o2[i] = 0.0; n2[i] = 0.0; co2[i] = 0.0

const MAX_DEVICE_LEN := 3

## Device on this tile. Multi-tile devices (thruster 1×3) are listed only once in
## devices (at the inner tile); their other tiles map to the same instance here.
func device_at(p: Vector2i) -> Device:
	if not in_bounds(p):
		return null
	var d = devices.get(idx(p))
	if d != null:
		return d
	# Multi-tile devices within 2 tiles (thruster 1×3, docking port 5×2)
	for dy in range(-MAX_DEVICE_LEN + 1, MAX_DEVICE_LEN):
		for dx in range(-MAX_DEVICE_LEN + 1, MAX_DEVICE_LEN):
			if dx == 0 and dy == 0:
				continue
			var q := p + Vector2i(dx, dy)
			if not in_bounds(q):
				continue
			var a = devices.get(idx(q))
			if a != null and a.data().length > 1 and a.cells().has(p):
				return a
	return null

# ---------------- Andockschleuse 5×2 ----------------

## Tiles of a docking port with outer door p and direction out (outwards): first p, then the
## other tiles of the outer row (in the wall) and the inner row behind it
static func dock_cells(p: Vector2i, out: Vector2i, w: int = 5) -> Array[Vector2i]:
	var along := Vector2i(out.y, out.x)
	var cells: Array[Vector2i] = [p]
	for k in 2:
		for u in range(-w / 2, w / 2 + 1):
			var q: Vector2i = p - out * k + along * u
			if q != p:
				cells.append(q)
	return cells

## Can a docking port sit here (p = outer door)? {"dir": outwards, "reason": ""}.
## Outer row: 5 wall tiles of a straight outer wall (the middle may already be a door), free outside;
## inner row: 5 free floor tiles; a free floor tile behind the inner door.
## allow_foreign: a station/wreck may already be attached outside (converting old saves).
func dock_check(p: Vector2i, ignore: Device = null, allow_foreign: bool = false) -> Dictionary:
	var why := "The docking port (5×2) needs a straight outer wall: 5 wall tiles, free space outside, 5 free floor tiles inside and room behind them."
	if not in_bounds(p) or zone[idx(p)] != 0 or (get_tile(p) != Tile.WALL and get_tile(p) != Tile.DOOR):
		return {"dir": Vector2i.ZERO, "reason": why}
	for d in Device.PUSH_DIRS:
		if _dock_fits(p, d, ignore, allow_foreign):
			return {"dir": d, "reason": ""}
	return {"dir": Vector2i.ZERO, "reason": why}

func _dock_fits(p: Vector2i, d: Vector2i, ignore: Device, allow_foreign: bool) -> bool:
	var along := Vector2i(d.y, d.x)
	var busy := func(q: Vector2i) -> bool:
		var dv := device_at(q)
		return dv != null and dv != ignore
	for u in range(-2, 3):
		var w := p + along * u
		var o := w + d
		var r := w - d
		if not in_bounds(o) or not in_bounds(r) or zone[idx(w)] != 0 or zone[idx(r)] != 0:
			return false
		var t := get_tile(w)
		if not (t == Tile.WALL or (u == 0 and t == Tile.DOOR)) or busy.call(w):
			return false
		var oz := zone[idx(o)]
		if not ((get_tile(o) == Tile.SPACE and oz == 0) or (allow_foreign and oz != 0)):
			return false
		if get_tile(r) != Tile.FLOOR or busy.call(r):
			return false
	var behind := p - d * 2
	return in_bounds(behind) and get_tile(behind) == Tile.FLOOR and zone[idx(behind)] == 0 and not busy.call(behind)

## Insert a docking port: set the tiles (outer door, inner door, side walls) and register the device
func apply_dock(dev: Device, d: Vector2i) -> void:
	dev.rot = Device.PUSH_DIRS.find(-d)
	var p := dev.pos
	var along := Vector2i(d.y, d.x)
	var behind := p - d * 2
	for u in range(-2, 3):
		var r := p - d + along * u
		if piles.has(idx(r)):
			var pile: Inventory = piles[idx(r)]
			piles.erase(idx(r))
			for it in pile.items:
				drop_items(behind, it.type, int(it.qty), float(it.cond), it.get("data"))
		if u != 0:
			set_tile(r, Tile.WALL)
	var inner := p - d
	set_tile(inner, Tile.DOOR)
	set_tile(p, Tile.DOOR)
	o2[idx(p)] = o2[idx(inner)]; n2[idx(p)] = n2[idx(inner)]; co2[idx(p)] = co2[idx(inner)]
	temp[idx(p)] = temp[idx(inner)]
	put_device(dev)

## Remove a docking port: the outer door becomes wall again, the inner row floor again
func remove_dock(dev: Device) -> void:
	var d := dev.outward()
	var p := dev.pos
	var along := Vector2i(d.y, d.x)
	var behind := p - d * 2
	remove_device(dev)
	linked.erase(idx(p))
	set_tile(p, Tile.WALL)
	for u in range(-2, 3):
		var r := p - d + along * u
		set_tile(r, Tile.FLOOR)
		var b := idx(behind)
		o2[idx(r)] = o2[b]; n2[idx(r)] = n2[b]; co2[idx(r)] = co2[b]; temp[idx(r)] = temp[b]

## Build a new docking port with outer door p (if it fits), otherwise null
func build_dock(p: Vector2i, allow_foreign: bool = false) -> Device:
	var chk := dock_check(p, null, allow_foreign)
	if chk.reason != "":
		return null
	var dev := Device.new("dockport", p)
	apply_dock(dev, chk.dir)
	return dev

## Is the tile occupied by a device (also by part of a multi-tile device)?
func occupied(p: Vector2i) -> bool:
	return device_at(p) != null

func put_device(dev: Device) -> void:
	devices[idx(dev.pos)] = dev

func remove_device(dev: Device) -> void:
	if devices.get(idx(dev.pos)) == dev:
		devices.erase(idx(dev.pos))

## Can a device of this type with this rotation sit at p (inner tile)? "" = yes.
## 1×3: inner tile = free ship floor, middle = outer wall (stays wall and airtight),
## outer tile = open space. ignore: skip this device in the occupied test.
func mount_reason(type: String, p: Vector2i, rot: int, ignore: Device = null) -> String:
	var n: int = ItemSystem.device(type).length
	var out: Vector2i = -Device.PUSH_DIRS[rot % 4]
	for k in n:
		if not in_bounds(p + out * k):
			return "Out of bounds."
	var busy := func(q: Vector2i) -> bool:
		var d := device_at(q)
		return d != null and d != ignore
	if get_tile(p) != Tile.FLOOR or zone[idx(p)] != 0:
		return "The inner tile must be free floor on your own ship."
	if busy.call(p):
		return "The inner tile is occupied."
	if n < 3:
		return ""
	var mid := p + out
	var tip := p + out * 2
	if get_tile(mid) != Tile.WALL or zone[idx(mid)] != 0:
		return "The middle tile must sit on a wall of your own ship (no door, no window)."
	if busy.call(mid):
		return "Something is already mounted on this wall."
	if get_tile(tip) != Tile.SPACE:
		return "Inner wall: the nozzle must point through an outer wall into open space."
	if busy.call(tip) or zone[idx(tip)] != 0:
		return "The nozzle tile outside is occupied."
	return ""

func place_device(type: String, p: Vector2i, rot: int = 0) -> Device:
	var dev := Device.new(type, p)
	dev.rot = rot
	put_device(dev)
	return dev

## Conversion: how many old 1×1 devices were rebuilt or dropped as items when loading
var migrated := {"converted": 0, "packed": 0, "refined": false, "modules": 0}
## After refine(): coarse tile index -> fine tile index (representative: wall tile, device or floor).
## Other systems use it to convert stored positions of old saves.
var coarse_map := PackedInt32Array()
var coarse_width := 0

func walkable(p: Vector2i) -> bool:
	var t := get_tile(p)
	if t != Tile.FLOOR and t != Tile.DOOR:
		return false
	var i := idx(p)
	# A docking port is only walkable while it is docked
	return not devices.has(i) or (devices[i].type == "dockport" and linked.has(i))

func wall_like(p: Vector2i) -> bool:
	var t := get_tile(p)
	return t == Tile.WALL or t == Tile.DOOR or t == Tile.WINDOW

## Does the tile not belong to your own ship? (1 = wreck, 3 = station)
func foreign(i: int) -> bool:
	return zone[i] == 1 or zone[i] == 3

func holds_air(i: int) -> bool:
	return tiles[i] == Tile.FLOOR or tiles[i] == Tile.DOOR

func door_open(i: int) -> bool:
	return door_open_until[i] > GameState.time

func pressure(i: int) -> float:
	return o2[i] + n2[i] + co2[i]

func fill_air(i: int) -> void:
	o2[i] = Config.AIR_O2; n2[i] = Config.AIR_N2; co2[i] = Config.AIR_CO2
	temp[i] = Config.ROOM_TEMP

func drop_items(p: Vector2i, type: String, qty: int, c: float, data = null) -> void:
	var i := idx(p)
	if not piles.has(i):
		piles[i] = Inventory.new()
	piles[i].add(type, qty, c, data)

func clean_piles() -> void:
	for i in piles.keys():
		if piles[i].items.is_empty():
			piles.erase(i)

func to_data() -> Dictionary:
	var devs: Array = []
	for d in devices.values():
		devs.append(d.to_data())
	var pl: Array = []
	for i in piles:
		pl.append([i, piles[i].to_data()])
	return {"w": width, "h": height, "tiles": Array(tiles), "cables": Array(cables),
		"o2": Array(o2), "n2": Array(n2), "co2": Array(co2), "cond": Array(cond), "zone": Array(zone), "temp": Array(temp), "devices": devs, "piles": pl,
		"vents": _closed_vents(), "linked": linked.keys(), "scale": Config.GRID_SCALE}

func _closed_vents() -> Array:
	var out: Array = []
	for i in vent_closed.size():
		if vent_closed[i] == 1:
			out.append(i)
	return out

static func from_data(d: Dictionary) -> ShipGrid:
	var g := ShipGrid.new(int(d.w), int(d.h))
	for i in g.tiles.size():
		g.tiles[i] = int(d.tiles[i]); g.cables[i] = int(d.cables[i])
		g.o2[i] = float(d.o2[i]); g.n2[i] = float(d.n2[i]); g.co2[i] = float(d.co2[i]); g.cond[i] = float(d.cond[i])
		g.zone[i] = int(d.zone[i]) if d.has("zone") else 0
		g.temp[i] = float(d.temp[i]) if d.has("temp") else (Config.ROOM_TEMP if g.holds_air(i) else Config.SPACE_TEMP)
	var legacy: Array[Device] = []
	var coarse := int(d.get("scale", 1)) < Config.GRID_SCALE
	for dd in d.devices:
		var dev := Device.from_data(dd)
		# Old save: multi-tile device (thruster, docking port) was still 1×1 → convert
		# below. Docking ports of coarse saves are only converted by refine() in the fine grid.
		if dev.data().length > 1 and int(dd.get("shape", 1)) != dev.data().length and not (coarse and dev.type == "dockport"):
			legacy.append(dev)
			continue
		g.devices[g.idx(dev.pos)] = dev
	for entry in d.piles:
		var inv := Inventory.new()
		inv.from_data(entry[1])
		g.piles[int(entry[0])] = inv
	for dev in legacy:
		g._migrate_legacy(dev)
	g._migrate_autodock()
	for i in d.get("vents", []):
		g.vent_closed[int(i)] = 1
	for i in d.get("linked", []):
		g.linked[int(i)] = true
	# Earlier save with twice as large tiles: convert to the fine grid
	if int(d.get("scale", 1)) < Config.GRID_SCALE:
		return refine(g)
	return g

## Old 1×1 thruster from a save: if the new 1×3 shape fits exactly here
## (same thrust direction, all three tiles valid and free), it is converted directly.
## Otherwise it is dropped once as a complete item (condition, data) on its tile
## or the nearest free floor. The new shape ("shape") is saved afterwards,
## so the conversion only happens once.
func _migrate_legacy(dev: Device) -> void:
	if dev.type == "dockport":
		_migrate_dock(dev)
		return
	if mount_reason(dev.type, dev.pos, dev.rot) == "":
		put_device(dev)
		migrated.converted += 1
		return
	var dd := dev.to_data()
	dd.unknown = false
	dd.lock = 0
	var spot := dev.pos
	if get_tile(spot) != Tile.FLOOR or occupied(spot):
		spot = _free_floor_near(dev.pos)
	drop_items(spot, "pk_" + dev.type, 1, dev.cond, dd)
	migrated.packed += 1

## Old 1-tile docking port (door in the outer wall) → 5×2 in the same place if there is room
## inside (coupling stays at the same outer door). Otherwise: close the wall and drop the port
## once aboard as a complete item.
func _migrate_dock(dev: Device) -> void:
	var chk := dock_check(dev.pos, dev, true)
	if chk.reason == "":
		apply_dock(dev, chk.dir)
		migrated.converted += 1
		return
	var dd := dev.to_data()
	dd.unknown = false
	dd.lock = 0
	linked.erase(idx(dev.pos))
	set_tile(dev.pos, Tile.WALL)
	drop_items(_free_floor_near(dev.pos), "pk_" + dev.type, 1, dev.cond, dd)
	migrated.packed += 1

## Former stand-alone auto-dock device → Autodock Module (condition is kept).
## It goes into the module bay of a navigation console in the same zone that has none yet; otherwise
## it is left once as an item in its place. So no module is duplicated.
func _migrate_autodock() -> void:
	for i in devices.keys():
		var dev: Device = devices[i]
		if dev.type != "autodock":
			continue
		remove_device(dev)
		var cond := 0.0 if dev.broken else dev.cond
		var placed := false
		for h in devices.values():
			if h.type == "helm" and h.inv != null and zone[idx(h.pos)] == zone[i] and not h.has_module_item("autodock"):
				placed = h.inv.add("mod_autodock", 1, cond) == 1
				if placed:
					break
		if not placed:
			drop_items(dev.pos if get_tile(dev.pos) == Tile.FLOOR else _free_floor_near(dev.pos), "mod_autodock", 1, cond)
		migrated.modules += 1

func _free_floor_near(p: Vector2i) -> Vector2i:
	for r in 12:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := p + Vector2i(dx, dy)
				if get_tile(q) == Tile.FLOOR and zone[idx(q)] == 0 and not occupied(q):
					return q
	return p


# ---------------- Refinement (halving the tiles of earlier saves) ----------------

const _PENDING := 255

static func _barrier(t: int) -> bool:
	return t == Tile.WALL or t == Tile.DOOR or t == Tile.WINDOW

## Finer grid from a coarse one (every tile becomes 2×2). The spatial layout is kept:
## - floor and space become 2×2 floor or space; air, temperature, condition, zone and cables are kept.
## - walls, doors and windows become a line 1 tile thick on the outer side
##   (towards space; inner walls on a fixed side). Neighbouring wall pieces are joined
##   without gaps, so the pressure hull stays airtight. The remaining sub-tiles become floor (inside)
##   or space (outside); enclosed pockets without an air connection become wall.
## - doors stay exactly one tile wide and walkable, docking ports sit on their door.
## - devices stay the same instances (condition, inventory); 1-tile devices on one of the four
##   sub-tiles, 1×3 thrusters through the new, thin wall. Piles are kept.
static func refine(c: ShipGrid) -> ShipGrid:
	var k := 2
	var g := ShipGrid.new(c.width * k, c.height * k)
	var n := c.tiles.size()
	g.migrated = c.migrated.duplicate()
	g.migrated.refined = true
	g.coarse_width = c.width
	g.coarse_map.resize(n)
	var orig_air := PackedByteArray()
	orig_air.resize(g.tiles.size())
	# 1) copy the tiles
	for i in n:
		var p := c.pos(i)
		var t := int(c.tiles[i])
		for sub in 4:
			var j := g.idx(Vector2i(p.x * k + sub % 2, p.y * k + sub / 2))
			g.tiles[j] = _PENDING if _barrier(t) else t
			g.zone[j] = c.zone[i]
			g.cond[j] = c.cond[i]
			g.temp[j] = c.temp[i]
			g.fire[j] = c.fire[i]
			if not _barrier(t):
				g.o2[j] = c.o2[i]; g.n2[j] = c.n2[i]; g.co2[j] = c.co2[i]
				orig_air[j] = 1 if t == Tile.FLOOR else 0
	# 2) wall line: one anchor tile per coarse wall piece, towards the outer side
	var anchor := PackedInt32Array()
	anchor.resize(n)
	anchor.fill(-1)
	# "Outside" seen from p: space, grid edge or another zone (wreck/station at the airlock).
	# So the airlock and the docked door still sit right next to each other after refining.
	var space_at := func(p: Vector2i, q: Vector2i) -> bool:
		return not c.in_bounds(q) or c.tiles[c.idx(q)] == Tile.SPACE or c.zone[c.idx(q)] != c.zone[c.idx(p)]
	for i in n:
		if not _barrier(c.tiles[i]):
			continue
		var p := c.pos(i)
		var ax := 1 if space_at.call(p, p + Vector2i(1, 0)) and not space_at.call(p, p + Vector2i(-1, 0)) else 0
		var ay := 1 if space_at.call(p, p + Vector2i(0, 1)) and not space_at.call(p, p + Vector2i(0, -1)) else 0
		var a := g.idx(Vector2i(p.x * k + ax, p.y * k + ay))
		anchor[i] = a
		g.tiles[a] = c.tiles[i]
		g.door_open_until[a] = c.door_open_until[i]
		g.vent_closed[a] = c.vent_closed[i]
		if c.tiles[i] == Tile.DOOR:
			g.o2[a] = c.o2[i]; g.n2[a] = c.n2[i]; g.co2[a] = c.co2[i]
			orig_air[a] = 1
	# Connections to neighbouring wall pieces to the right and below (L-shaped, 4-neighbourhood)
	for i in n:
		if anchor[i] < 0:
			continue
		var p := c.pos(i)
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var q: Vector2i = p + d
			if not c.in_bounds(q) or anchor[c.idx(q)] < 0 or c.zone[c.idx(q)] != c.zone[i]:
				continue
			var a := g.pos(anchor[i])
			var b := g.pos(anchor[c.idx(q)])
			var ct := Tile.WINDOW if c.tiles[i] == Tile.WINDOW and c.tiles[c.idx(q)] == Tile.WINDOW else Tile.WALL
			var cells: Array[Vector2i] = []
			if d.x == 1:
				for x in range(a.x, b.x + 1):
					cells.append(Vector2i(x, a.y))
				for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
					cells.append(Vector2i(b.x, y))
			else:
				for y in range(a.y, b.y + 1):
					cells.append(Vector2i(a.x, y))
				for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
					cells.append(Vector2i(x, b.y))
			for cell in cells:
				var j := g.idx(cell)
				if g.tiles[j] == _PENDING:
					g.tiles[j] = ct
	# 3) remaining sub-tiles: on the outer side of the wall line (towards space) → space, otherwise floor.
	#    Only within the same former tile, so a leak does not "run" along the wall
	#    and pull strips of space into rooms.
	var seen := PackedByteArray()
	seen.resize(g.tiles.size())
	var queue: Array[int] = []
	for j in g.tiles.size():
		if g.tiles[j] != _PENDING:
			continue
		var q := g.pos(j)
		var outside := q.x == 0 or q.y == 0 or q.x == g.width - 1 or q.y == g.height - 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var w: Vector2i = q + d
			if g.in_bounds(w) and g.tiles[g.idx(w)] == Tile.SPACE:
				outside = true
		if outside:
			seen[j] = 1
			queue.append(j)
	var head := 0
	while head < queue.size():
		var j := queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = g.pos(j) + d
			if not g.in_bounds(q):
				continue
			var jj := g.idx(q)
			if seen[jj] == 0 and g.tiles[jj] == _PENDING and q / k == g.pos(j) / k:
				seen[jj] = 1
				queue.append(jj)
	var new_floor: Array[int] = []
	for j in g.tiles.size():
		if g.tiles[j] != _PENDING:
			continue
		if seen[j] == 1:
			g.tiles[j] = Tile.SPACE
			g.cables[j] = 0
			g.temp[j] = Config.SPACE_TEMP
			g.zone[j] = 0
		else:
			g.tiles[j] = Tile.FLOOR
			new_floor.append(j)
	# Take air for new floor tiles from the adjacent room; pockets without a connection → wall
	var got := PackedByteArray()
	got.resize(g.tiles.size())
	var front: Array[int] = []
	for j in g.tiles.size():
		if orig_air[j] == 1:
			got[j] = 1
			front.append(j)
	var is_new := {}
	for j in new_floor:
		is_new[j] = true
	head = 0
	while head < front.size():
		var j := front[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = g.pos(j) + d
			if not g.in_bounds(q):
				continue
			var jj := g.idx(q)
			if got[jj] == 0 and is_new.has(jj):
				got[jj] = 1
				g.o2[jj] = g.o2[j]; g.n2[jj] = g.n2[j]; g.co2[jj] = g.co2[j]; g.temp[jj] = g.temp[j]
				front.append(jj)
	for j in new_floor:
		if got[j] == 0:
			g.tiles[j] = Tile.WALL
	# 4) representative tiles (coarse -> fine)
	for i in n:
		var p := c.pos(i)
		g.coarse_map[i] = anchor[i] if anchor[i] >= 0 else g.idx(p * k)
	# Cables: a simple line over the representative tiles, joined to neighbouring cables without gaps
	for i in n:
		if c.cables[i] == 0:
			continue
		var a := g.pos(g.coarse_map[i])
		if g.get_tile(a) != Tile.SPACE:
			g.cables[g.idx(a)] = 1
		var p := c.pos(i)
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var q: Vector2i = p + d
			if not c.in_bounds(q) or c.cables[c.idx(q)] == 0:
				continue
			var b := g.pos(g.coarse_map[c.idx(q)])
			var cells: Array[Vector2i] = []
			for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				cells.append(Vector2i(x, a.y))
			for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
				cells.append(Vector2i(b.x, y))
			for cell in cells:
				if g.get_tile(cell) != Tile.SPACE:
					g.cables[g.idx(cell)] = 1
	# 5) devices: the same instances. Multi-tile devices first (through the wall), then the rest.
	var order: Array = c.devices.keys()
	order.sort_custom(func(a, b): return int(c.devices[a].data().length > 1) > int(c.devices[b].data().length > 1))
	var docks: Array[Device] = []
	for ci in order:
		var dev: Device = c.devices[ci]
		var p := dev.pos
		if dev.type == "dockport":
			# Docking port: first place it on its door, convert to 5×2 after all devices
			var a := g.pos(anchor[ci]) if anchor[ci] >= 0 else p * k
			dev.pos = a
			g.put_device(dev)
			g.coarse_map[ci] = g.idx(a)
			if c.linked.has(ci):
				g.linked[g.idx(a)] = true
			docks.append(dev)
			continue
		if dev.data().length > 1:
			var mid := p + dev.outward()
			if c.in_bounds(mid) and anchor[c.idx(mid)] >= 0:
				var inner := g.pos(anchor[c.idx(mid)]) - dev.outward()
				if g.mount_reason(dev.type, inner, dev.rot) == "":
					dev.pos = inner
					g.put_device(dev)
					g.coarse_map[ci] = g.idx(inner)
					if c.cables[ci] == 1:
						g.cables[g.idx(inner)] = 1   # power connection as in the old place
					continue
			# no longer fits: drop it once aboard as a complete item
			dev.pos = g._free_floor_near(p * k)
			g._migrate_legacy(dev)
			continue
		var spot := Vector2i(-1, -1)
		if anchor[ci] >= 0:
			spot = g.pos(anchor[ci])           # e.g. a docking port on its door
		else:
			for sub in 4:
				var q := Vector2i(p.x * k + sub % 2, p.y * k + sub / 2)
				if g.get_tile(q) == Tile.FLOOR and not g.occupied(q):
					spot = q
					break
			if spot.x < 0:
				spot = g._free_floor_near(p * k)
		dev.pos = spot
		g.put_device(dev)
		if c.cables[ci] == 1 and g.cables[g.idx(spot)] == 0:
			# Device not on the cable line: lay a short piece to the representative tile
			var r := g.pos(g.coarse_map[ci])
			for x in range(mini(r.x, spot.x), maxi(r.x, spot.x) + 1):
				g.cables[g.idx(Vector2i(x, r.y))] = 1
			for y in range(mini(r.y, spot.y), maxi(r.y, spot.y) + 1):
				g.cables[g.idx(Vector2i(spot.x, y))] = 1
		g.coarse_map[ci] = g.idx(spot)
		if c.linked.has(ci):
			g.linked[g.idx(spot)] = true
	for dev in docks:
		g.remove_device(dev)
		g._migrate_dock(dev)
	# 6) piles onto a free sub-tile
	for ci in c.piles:
		var p := c.pos(ci)
		var spot := Vector2i(-1, -1)
		for sub in 4:
			var q := Vector2i(p.x * k + sub % 2, p.y * k + sub / 2)
			if g.get_tile(q) != Tile.SPACE and g.walkable(q):
				spot = q
				break
		if spot.x < 0:
			spot = p * k if c.tiles[ci] == Tile.SPACE else g._free_floor_near(p * k)
		var pile: Inventory = c.piles[ci]
		for it in pile.items:
			g.drop_items(spot, it.type, int(it.qty), float(it.cond), it.get("data"))
	return g

## Representative tile of a coarse tile after refine() (for stored positions)
func fine_of_coarse(cp: Vector2i) -> Vector2i:
	if coarse_map.is_empty() or coarse_width <= 0:
		return cp
	return pos(coarse_map[cp.y * coarse_width + cp.x])

## Stored character position (coarse tile units) into the fine grid: same place,
## on a walkable tile
func fine_pos(cpos: Vector2) -> Vector2:
	var f := cpos * 2.0
	var q := Vector2i(floori(f.x), floori(f.y))
	if walkable(q):
		return f
	for r in 4:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var w := q + Vector2i(dx, dy)
				if walkable(w):
					return Vector2(w) + Vector2(0.5, 0.5)
	return f
