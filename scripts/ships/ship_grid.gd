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
## Türen: Lüftungsschlitz geschlossen (1) – dann ist die geschlossene Tür ganz dicht
var vent_closed := PackedByteArray()
var devices: Dictionary = {}  ## Feld-Index -> Device
## Andockschleusen, die gerade mit einer Station oder einem Wrack verbunden sind (Feld-Index -> true)
var linked: Dictionary = {}
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

## Gerät auf diesem Feld. Mehrfeldrige Geräte (Triebwerk 1×3) stehen nur einmal in
## devices (am Innenfeld); ihre übrigen Felder werden hier auf dieselbe Instanz abgebildet.
func device_at(p: Vector2i) -> Device:
	if not in_bounds(p):
		return null
	var d = devices.get(idx(p))
	if d != null:
		return d
	for k in range(1, MAX_DEVICE_LEN):
		for dir in Device.PUSH_DIRS:
			var q: Vector2i = p + dir * k
			if not in_bounds(q):
				continue
			var a = devices.get(idx(q))
			if a != null and a.data().length > k and q + a.outward() * k == p:
				return a
	return null

## Ist das Feld von einem Gerät belegt (auch von einem Teil eines Mehrfeld-Geräts)?
func occupied(p: Vector2i) -> bool:
	return device_at(p) != null

func put_device(dev: Device) -> void:
	devices[idx(dev.pos)] = dev

func remove_device(dev: Device) -> void:
	if devices.get(idx(dev.pos)) == dev:
		devices.erase(idx(dev.pos))

## Kann ein Gerät dieser Art mit dieser Drehung an p (Innenfeld) sitzen? "" = ja.
## 1×3: Innenfeld = freier Schiffsboden, Mitte = Außenwand (bleibt Wand und dicht),
## Außenfeld = freies All. ignore: dieses Gerät beim Belegt-Test übergehen.
func mount_reason(type: String, p: Vector2i, rot: int, ignore: Device = null) -> String:
	var n: int = ItemSystem.device(type).length
	var out: Vector2i = -Device.PUSH_DIRS[rot % 4]
	for k in n:
		if not in_bounds(p + out * k):
			return "Außerhalb."
	var busy := func(q: Vector2i) -> bool:
		var d := device_at(q)
		return d != null and d != ignore
	if get_tile(p) != Tile.FLOOR or zone[idx(p)] != 0:
		return "Das innere Feld muss freier Boden im eigenen Schiff sein."
	if busy.call(p):
		return "Das innere Feld ist belegt."
	if n < 3:
		return ""
	var mid := p + out
	var tip := p + out * 2
	if get_tile(mid) != Tile.WALL or zone[idx(mid)] != 0:
		return "Das mittlere Feld muss auf einer Wand des eigenen Schiffs sitzen (keine Tür, kein Fenster)."
	if busy.call(mid):
		return "Auf dieser Wand sitzt schon etwas."
	if get_tile(tip) != Tile.SPACE:
		return "Innenwand: Die Düse muss durch eine Außenwand ins freie All zeigen."
	if busy.call(tip) or zone[idx(tip)] != 0:
		return "Das Düsenfeld draußen ist belegt."
	return ""

func place_device(type: String, p: Vector2i, rot: int = 0) -> Device:
	var dev := Device.new(type, p)
	dev.rot = rot
	put_device(dev)
	return dev

## Umstellung: Wie viele alte 1×1-Geräte beim Laden umgebaut bzw. als Gegenstand abgelegt wurden
var migrated := {"converted": 0, "packed": 0}

func walkable(p: Vector2i) -> bool:
	var t := get_tile(p)
	if t != Tile.FLOOR and t != Tile.DOOR:
		return false
	var i := idx(p)
	# Eine Andockschleuse ist nur begehbar, solange sie angedockt ist
	return not devices.has(i) or (devices[i].type == "dockport" and linked.has(i))

func wall_like(p: Vector2i) -> bool:
	var t := get_tile(p)
	return t == Tile.WALL or t == Tile.DOOR or t == Tile.WINDOW

## Gehört das Feld nicht zum eigenen Schiff? (1 = Wrack, 3 = Station)
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
		"vents": _closed_vents(), "linked": linked.keys()}

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
	for dd in d.devices:
		var dev := Device.from_data(dd)
		# Alter Spielstand: Mehrfeld-Gerät (Triebwerk) war noch 1×1 → unten umstellen
		if dev.data().length > 1 and int(dd.get("shape", 1)) != dev.data().length:
			legacy.append(dev)
			continue
		g.devices[g.idx(dev.pos)] = dev
	for entry in d.piles:
		var inv := Inventory.new()
		inv.from_data(entry[1])
		g.piles[int(entry[0])] = inv
	for dev in legacy:
		g._migrate_legacy(dev)
	for i in d.get("vents", []):
		g.vent_closed[int(i)] = 1
	for i in d.get("linked", []):
		g.linked[int(i)] = true
	return g

## Altes 1×1-Triebwerk aus einem Spielstand: Passt die neue 1×3-Bauform genau hier
## (gleiche Schubrichtung, alle drei Felder gültig und frei), wird es direkt umgestellt.
## Sonst liegt es einmal als vollständiger Gegenstand (Zustand, Daten) auf seinem Feld
## bzw. dem nächsten freien Boden. Gespeichert wird danach die neue Form ("shape"),
## die Umstellung greift also nur einmal.
func _migrate_legacy(dev: Device) -> void:
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
