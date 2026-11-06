## Das Schiff als Raster aus Feldern.
## Jedes Feld hat eine Bauart, evtl. ein Kabel, evtl. ein Gerät
## und seine eigene Luft (O2, N2, CO2 in kPa).
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
## Bereich: 0 = dein Schiff, 1 = Wrack, 2 = Bergungsleine
var zone := PackedByteArray()
## Temperatur in °C und Feuer (1 = brennt)
var temp := PackedFloat32Array()
var fire := PackedByteArray()
var devices: Dictionary = {}  ## Feld-Index -> Device
var piles: Dictionary = {}    ## Feld-Index -> Inventory (Haufen auf dem Boden)

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

func device_at(p: Vector2i) -> Device:
	return devices.get(idx(p)) if in_bounds(p) else null

func walkable(p: Vector2i) -> bool:
	var t := get_tile(p)
	return (t == Tile.FLOOR or t == Tile.DOOR) and not devices.has(idx(p))

func wall_like(p: Vector2i) -> bool:
	var t := get_tile(p)
	return t == Tile.WALL or t == Tile.DOOR or t == Tile.WINDOW

func holds_air(i: int) -> bool:
	return tiles[i] == Tile.FLOOR or tiles[i] == Tile.DOOR

func door_open(i: int) -> bool:
	return door_open_until[i] > GameState.time

func pressure(i: int) -> float:
	return o2[i] + n2[i] + co2[i]

func fill_air(i: int) -> void:
	o2[i] = Config.AIR_O2; n2[i] = Config.AIR_N2; co2[i] = Config.AIR_CO2
	temp[i] = Config.ROOM_TEMP

func place_device(type: String, p: Vector2i) -> Device:
	var dev := Device.new(type, p)
	devices[idx(p)] = dev
	return dev

func drop_items(p: Vector2i, type: String, qty: int, c: float) -> void:
	var i := idx(p)
	if not piles.has(i):
		piles[i] = Inventory.new()
	piles[i].add(type, qty, c)

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
		"o2": Array(o2), "n2": Array(n2), "co2": Array(co2), "cond": Array(cond), "zone": Array(zone), "temp": Array(temp), "devices": devs, "piles": pl}

static func from_data(d: Dictionary) -> ShipGrid:
	var g := ShipGrid.new(int(d.w), int(d.h))
	for i in g.tiles.size():
		g.tiles[i] = int(d.tiles[i]); g.cables[i] = int(d.cables[i])
		g.o2[i] = float(d.o2[i]); g.n2[i] = float(d.n2[i]); g.co2[i] = float(d.co2[i]); g.cond[i] = float(d.cond[i])
		g.zone[i] = int(d.zone[i]) if d.has("zone") else 0
		g.temp[i] = float(d.temp[i]) if d.has("temp") else (Config.ROOM_TEMP if g.holds_air(i) else Config.SPACE_TEMP)
	for dd in d.devices:
		var dev := Device.from_data(dd)
		g.devices[g.idx(dev.pos)] = dev
	for entry in d.piles:
		var inv := Inventory.new()
		inv.from_data(entry[1])
		g.piles[int(entry[0])] = inv
	return g
