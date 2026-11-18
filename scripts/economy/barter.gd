## Barter Zone after Ostranauts "Trading" 2.1 and "Salvaging" 3.3: marked floor tiles of your own
## ship. While the trade terminal is online, whatever lies there (piles and containers) can be
## sold without carrying it to the terminal, and purchases can be sent there.
## The wiki's hidden fee is only confirmed for cargo pods, which this game does not have: no fee.
class_name Barter
extends RefCounted

## One drag marks or unmarks: the first tile of the drag decides
static var _drag_frame := -1
static var _drag_mark := true

static func valid(g: ShipGrid, i: int) -> bool:
	return g.tiles[i] == ShipGrid.Tile.FLOOR and g.zone[i] == 0

static func can_place(p: Vector2i) -> bool:
	var g := ShipSystem.grid
	return g.in_bounds(p) and valid(g, g.idx(p))

## Tool: mark or unmark a tile
static func place(p: Vector2i) -> bool:
	if not can_place(p):
		return false
	var g := ShipSystem.grid
	var i := g.idx(p)
	var frame := Engine.get_process_frames()
	if frame != _drag_frame:
		_drag_frame = frame
		_drag_mark = not g.barter.has(i)
	if _drag_mark:
		g.barter[i] = true
	else:
		g.barter.erase(i)
	return true

## Marked tiles that are still your own floor
static func tiles(g: ShipGrid) -> Array:
	return g.barter.keys().filter(func(i): return valid(g, int(i)))

## Inventories in the zone: piles and containers (not the terminal, it is sold from anyway)
static func inventories(g: ShipGrid) -> Array:
	var out: Array = []
	for i in tiles(g):
		if g.piles.has(i) and not g.piles[i].items.is_empty():
			out.append(g.piles[i])
		var dev := g.device_at(g.pos(i))
		if dev != null and dev.inv != null and dev.type != "terminal" and not dev.unknown and dev.lock_level == 0 and not out.has(dev.inv):
			out.append(dev.inv)
	return out

## Tile for purchases: a marked tile without a device ("" = none)
static func drop_spot(g: ShipGrid) -> Vector2i:
	for i in tiles(g):
		if g.device_at(g.pos(i)) == null:
			return g.pos(i)
	return Vector2i(-1, -1)
