## Air per tile (O₂, N₂, CO₂ in kPa). The gas values in the ShipGrid remain the
## only source for simulation, display and saves; rooms and leaks are
## derived from the geometry at any time.
##
## Edge rule (for all four edges of a tile, diagonals connect nothing):
##   - wall or window on one side               → blocked
##   - two air tiles (floor/door)                → free passage
##       … with a closed door in between         → door vent (weak),
##         or airtight if the vent is closed, or for an airlock door or station hatch
##   - air tile next to space or the grid edge  → vacuum edge (leak);
##     a closed door is always airtight towards space
## An uninstalled floor becomes space and so opens a leak in the middle of the room.
## An uninstalled wall becomes floor and is evaluated like any floor.
##
## Gas exchange: all flows of a sub-step are computed from the same state
## and applied afterwards (independent of order). Transfers conserve
## the amount per gas; losses only happen at vacuum edges (counted in `vented`).
extends Node

const E_BLOCK := 0   ## blocked
const E_FREE := 1    ## free passage
const E_VENT := 2    ## closed door with an open vent
const E_VAC := 3     ## vacuum edge (leak to space)
const MAX_SUBSTEPS := 4

## Gas lost to space (kPa sums) since the start of the game or in the last step
var vented := {"o2": 0.0, "n2": 0.0, "co2": 0.0}
var last_vented := 0.0

var _acc := 0.0
# Derived room structure (recomputed as soon as the grid, doors or vents change)
var _topo_key := ""
var room_id := PackedInt32Array()     ## tile -> room (-1: no room, e.g. door or wall)
var rooms: Array = []                 ## [{cells: Array[int], vac: int, links: {room: "open"/"vent"}, door_space: bool}]
var _air_cells := PackedInt32Array()
var _doors := PackedInt32Array()
var _cells_key := ""
# Precomputed edges (valid until the grid changes): pairs of two air tiles without a door
# are always free, an air tile without a door next to space/edge is always a leak. Everything with a door is
# re-evaluated in every sub-step (doors open and close, vents change).
var _free_a := PackedInt32Array()
var _free_b := PackedInt32Array()
var _vac_cell := PackedInt32Array()
var _vac_n := PackedInt32Array()
var _dyn_a := PackedInt32Array()
var _dyn_b := PackedInt32Array()

func step(dt: float) -> void:
	_acc += dt
	# Batching: at 1x about every 1.5 game seconds, less often at high speed
	var threshold := 0.025 * maxf(1.0, Config.SPEEDS[TimeSystem.speed_index] / 10.0) * Settings.sim_factor()
	if _acc < threshold:
		return
	var d := _acc
	_acc = 0.0
	simulate(d)

# ---------------- Kanten ----------------

## Kind of edge between tile a and tile b (b = -1: outside the grid)
func edge(g: ShipGrid, a: int, b: int) -> int:
	var a_air := g.holds_air(a)
	if b < 0:
		return E_VAC if a_air and not _closed_door(g, a) else E_BLOCK
	var ta := g.tiles[a]
	var tb := g.tiles[b]
	if ta == ShipGrid.Tile.WALL or tb == ShipGrid.Tile.WALL or ta == ShipGrid.Tile.WINDOW or tb == ShipGrid.Tile.WINDOW:
		return E_BLOCK
	var b_air := g.holds_air(b)
	if not a_air and not b_air:
		return E_BLOCK
	if a_air != b_air:
		var c := a if a_air else b
		return E_BLOCK if _closed_door(g, c) else E_VAC
	var res := E_FREE
	for d in [a, b]:
		if g.tiles[d] == ShipGrid.Tile.DOOR and not g.door_open(d):
			if sealed(g, d):
				return E_BLOCK
			res = E_VENT
	return res

func _closed_door(g: ShipGrid, i: int) -> bool:
	return g.tiles[i] == ShipGrid.Tile.DOOR and not g.door_open(i)

## Closed door fully airtight? (vent closed, airlock door, station hatch)
func sealed(g: ShipGrid, d: int) -> bool:
	return g.vent_closed[d] == 1 or AirlockSystem.is_lock_door(d) or StationSystem.is_hatch(d) \
		or (g.devices.has(d) and g.devices[d].type == "dockport")

## Neighbours of a tile (right, left, down, up); -1 = grid edge
func _neighbors(g: ShipGrid, i: int) -> Array[int]:
	var x := i % g.width
	var y := i / g.width
	return [i + 1 if x + 1 < g.width else -1, i - 1 if x > 0 else -1,
		i + g.width if y + 1 < g.height else -1, i - g.width if y > 0 else -1]

## Number of vacuum edges of a tile
func vacuum_edges(i: int) -> int:
	var g := ShipSystem.grid
	var n := 0
	for j in _neighbors(g, i):
		if edge(g, i, j) == E_VAC:
			n += 1
	return n

# ---------------- Simulation ----------------

## Collect the air tiles again when the grid has changed
func _ensure_cells(g: ShipGrid) -> void:
	var key := "%d:%d" % [g.get_instance_id(), hash(g.tiles)]
	if key == _cells_key:
		return
	_cells_key = key
	_air_cells = PackedInt32Array()
	_doors = PackedInt32Array()
	_free_a = PackedInt32Array(); _free_b = PackedInt32Array()
	_vac_cell = PackedInt32Array(); _vac_n = PackedInt32Array()
	_dyn_a = PackedInt32Array(); _dyn_b = PackedInt32Array()
	for i in g.tiles.size():
		if g.holds_air(i):
			_air_cells.append(i)
		if g.tiles[i] == ShipGrid.Tile.DOOR:
			_doors.append(i)
	for i in _air_cells:
		var i_door := g.tiles[i] == ShipGrid.Tile.DOOR
		var vac_here := 0
		for j in _neighbors(g, i):
			var j_air := j >= 0 and g.holds_air(j)
			if j_air and j < i:
				continue  # Pair of two air tiles only once (from the smaller index)
			var j_door := j >= 0 and g.tiles[j] == ShipGrid.Tile.DOOR
			if i_door or j_door:
				_dyn_a.append(i)
				_dyn_b.append(j)
				continue
			var e := edge(g, i, j)
			if e == E_FREE:
				_free_a.append(i)
				_free_b.append(j)
			elif e == E_VAC:
				vac_here += 1
		if vac_here > 0:
			_vac_cell.append(i)
			_vac_n.append(vac_here)

## dt in game minutes. Split into sub-steps so all time speeds compute the same.
func simulate(dt: float) -> void:
	var g := ShipSystem.grid
	_ensure_cells(g)
	var steps := dt / (1.0 / 3.0)
	var n := clampi(int(ceil(steps)), 1, MAX_SUBSTEPS)
	last_vented = 0.0
	for k in n:
		_substep(g, steps / n)

func _substep(g: ShipGrid, s: float) -> void:
	var k_free := minf(0.2, Config.DIFFUSION * s)
	var k_vent := minf(0.2, Config.DOOR_SLITS * s)
	var keep := pow(1.0 - Config.VENT_LOSS, s)
	var n := g.tiles.size()
	# State at the start of the sub-step: all flows are computed from it
	var o2 := g.o2.duplicate()
	var n2 := g.n2.duplicate()
	var co2 := g.co2.duplicate()
	var d_o2 := PackedFloat32Array()
	var d_n2 := PackedFloat32Array()
	var d_co2 := PackedFloat32Array()
	d_o2.resize(n); d_n2.resize(n); d_co2.resize(n)
	var vac := {}
	for p in _vac_cell.size():
		vac[_vac_cell[p]] = _vac_n[p]
	for p in _free_a.size():
		var i := _free_a[p]
		var j := _free_b[p]
		var f := (o2[i] - o2[j]) * k_free
		d_o2[i] -= f; d_o2[j] += f
		f = (n2[i] - n2[j]) * k_free
		d_n2[i] -= f; d_n2[j] += f
		f = (co2[i] - co2[j]) * k_free
		d_co2[i] -= f; d_co2[j] += f
	for p in _dyn_a.size():
		var i := _dyn_a[p]
		var j := _dyn_b[p]
		var e := edge(g, i, j)
		if e == E_VAC:
			vac[i] = vac.get(i, 0) + 1
		elif e == E_FREE or e == E_VENT:
			var k := k_free if e == E_FREE else k_vent
			var f := (o2[i] - o2[j]) * k
			d_o2[i] -= f; d_o2[j] += f
			f = (n2[i] - n2[j]) * k
			d_n2[i] -= f; d_n2[j] += f
			f = (co2[i] - co2[j]) * k
			d_co2[i] -= f; d_co2[j] += f
	for i in _air_cells:
		var a := maxf(0.0, o2[i] + d_o2[i])
		var b := maxf(0.0, n2[i] + d_n2[i])
		var c := maxf(0.0, co2[i] + d_co2[i])
		if vac.has(i):
			var kp := pow(keep, vac[i])
			vented.o2 += a * (1.0 - kp); vented.n2 += b * (1.0 - kp); vented.co2 += c * (1.0 - kp)
			last_vented += (a + b + c) * (1.0 - kp)
			a *= kp; b *= kp; c *= kp
		g.o2[i] = a; g.n2[i] = b; g.co2[i] = c

# ---------------- Rooms and vacuum paths ----------------

## Keep the room structure up to date (grid, open doors, vents)
func topology() -> void:
	var g := ShipSystem.grid
	_ensure_cells(g)
	var sig := PackedByteArray()
	for d in _doors:
		sig.append(1 if g.door_open(d) else 0)
		sig.append(g.vent_closed[d])
	var key := "%s|%d|%d|%d|%d" % [_cells_key, hash(sig), StationSystem.hatch, AirlockSystem.locks.size(), hash(g.linked.keys())]
	if key == _topo_key:
		return
	_topo_key = key
	room_id = PackedInt32Array()
	room_id.resize(g.tiles.size())
	room_id.fill(-1)
	rooms.clear()
	# Group floor tiles into rooms over free edges (doors stay borders)
	for start in _air_cells:
		if room_id[start] != -1 or g.tiles[start] == ShipGrid.Tile.DOOR:
			continue
		var r := rooms.size()
		var room := {"cells": [], "vac": 0, "links": {}, "door_space": false}
		rooms.append(room)
		var stack: Array[int] = [start]
		room_id[start] = r
		while not stack.is_empty():
			var i: int = stack.pop_back()
			room.cells.append(i)
			for j in _neighbors(g, i):
				var e := edge(g, i, j)
				if e == E_VAC:
					room.vac += 1
				elif e == E_FREE and g.tiles[j] != ShipGrid.Tile.DOOR and room_id[j] == -1:
					room_id[j] = r
					stack.append(j)
	# Doors connect rooms: open = flow, closed with a vent = weak, airtight = nothing
	for d in _doors:
		var kind := "open" if g.door_open(d) else ("" if sealed(g, d) else "vent")
		var sides: Array[int] = []
		var to_space := false
		for j in _neighbors(g, d):
			var e := edge(g, d, j)
			if e == E_VAC:
				to_space = true
			elif (e == E_FREE or e == E_VENT) and j >= 0 and room_id[j] >= 0 and not room_id[j] in sides:
				sides.append(room_id[j])
		if kind == "":
			continue
		for a in sides:
			if to_space and kind == "open":
				rooms[a].door_space = true
			for b in sides:
				if a != b:
					var old: String = rooms[a].links.get(b, "")
					rooms[a].links[b] = "open" if (kind == "open" or old == "open") else "vent"

func room_of(i: int) -> int:
	topology()
	return room_id[i] if i >= 0 and i < room_id.size() else -1

## Vacuum path of a room: "direct" (its own leak edge), "door" (through open doors),
## "vent" (only weakly through door vents) or "" (airtight)
func room_leak(r: int) -> String:
	topology()
	if r < 0 or r >= rooms.size():
		return ""
	if rooms[r].vac > 0 or rooms[r].door_space:
		return "direct"
	if _reaches_leak(r, false):
		return "door"
	if _reaches_leak(r, true):
		return "vent"
	return ""

func _reaches_leak(start: int, with_vents: bool) -> bool:
	var seen := {start: true}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var r: int = queue.pop_front()
		if rooms[r].vac > 0 or rooms[r].door_space:
			return true
		for o in rooms[r].links:
			if not seen.has(o) and (with_vents or rooms[r].links[o] == "open"):
				seen[o] = true
				queue.append(o)
	return false

## Average pressure of a room in kPa
func room_pressure(r: int) -> float:
	topology()
	if r < 0 or r >= rooms.size() or rooms[r].cells.is_empty():
		return 0.0
	var g := ShipSystem.grid
	var s := 0.0
	for i in rooms[r].cells:
		s += g.pressure(i)
	return s / rooms[r].cells.size()

## Sum per gas over tiles: Vector3(O₂, N₂, CO₂)
func gas_sum(cells: Array) -> Vector3:
	var g := ShipSystem.grid
	var v := Vector3.ZERO
	for i in cells:
		v += Vector3(g.o2[i], g.n2[i], g.co2[i])
	return v

## Open/close the vent of a door
func set_vent(i: int, closed: bool) -> void:
	ShipSystem.grid.vent_closed[i] = 1 if closed else 0

func describe(i: int) -> String:
	var g := ShipSystem.grid
	if not g.holds_air(i):
		return ""
	var text := "O₂ %.1f kPa · CO₂ %.2f kPa · pressure %d kPa" % [g.o2[i], g.co2[i], int(g.pressure(i))]
	var r := room_of(i)
	if r >= 0:
		var leak := room_leak(r)
		text += " · room avg %d kPa" % int(room_pressure(r))
		match leak:
			"direct": text += " · LEAK"
			"door": text += " · leak through an open door"
			"vent": text += " · weak gas path through a door vent"
	elif g.tiles[i] == ShipGrid.Tile.DOOR and g.vent_closed[i] == 1:
		text += " · vent closed"
	return text
