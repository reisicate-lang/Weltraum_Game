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
var migrated := {"converted": 0, "packed": 0, "refined": false}
## Nach refine(): grober Feld-Index -> feiner Feld-Index (Vertreter: Wandfeld, Gerät oder Boden).
## Damit rechnen andere Systeme gespeicherte Positionen alter Spielstände um.
var coarse_map := PackedInt32Array()
var coarse_width := 0

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
	# Früherer Spielstand mit doppelt so großen Feldern: ins feine Raster überführen
	if int(d.get("scale", 1)) < Config.GRID_SCALE:
		return refine(g)
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


# ---------------- Verfeinerung (Felder früherer Spielstände halbieren) ----------------

const _PENDING := 255

static func _barrier(t: int) -> bool:
	return t == Tile.WALL or t == Tile.DOOR or t == Tile.WINDOW

## Feineres Raster aus einem groben (jedes Feld wird 2×2). Räumliche Anordnung bleibt:
## - Boden und All werden 2×2 Boden bzw. All, Luft, Temperatur, Zustand, Zone, Kabel bleiben.
## - Wände, Türen und Fenster werden zu einer 1 Feld dicken Linie auf der Außenseite
##   (zum All hin; Innenwände an einer festen Seite). Benachbarte Wandstücke werden lückenlos
##   verbunden, die Druckhülle bleibt also dicht. Die übrigen Teilfelder werden Boden (innen)
##   oder All (außen); abgeschlossene Taschen ohne Luftanschluss werden Wand.
## - Türen bleiben genau ein Feld breit und begehbar, Andockschleusen sitzen auf ihrer Tür.
## - Geräte bleiben dieselben Instanzen (Zustand, Inventar); 1-Feld-Geräte auf einem der vier
##   Teilfelder, Triebwerke 1×3 durch die neue, dünne Wand. Haufen bleiben erhalten.
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
	# 1) Felder übernehmen
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
	# 2) Wandlinie: ein Ankerfeld je grobem Wandstück, zur Außenseite hin
	var anchor := PackedInt32Array()
	anchor.resize(n)
	anchor.fill(-1)
	# „Außen“ von p aus: All, Rasterrand oder ein anderer Bereich (Wrack/Station an der Schleuse).
	# So sitzen Schleuse und angedockte Tür nach dem Verfeinern weiter direkt aneinander.
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
	# Verbindungen zu Nachbar-Wandstücken rechts und unten (L-förmig, 4er-Nachbarschaft)
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
	# 3) Restliche Teilfelder: auf der Außenseite der Wandlinie (am All) → All, sonst Boden.
	#    Nur innerhalb desselben früheren Feldes, damit ein Leck nicht entlang der Wand
	#    „durchläuft“ und Streifen aus All in Räume zieht.
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
	# Luft für neue Bodenfelder vom angrenzenden Raum übernehmen; Taschen ohne Anschluss → Wand
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
	# 4) Vertreterfelder (grob -> fein)
	for i in n:
		var p := c.pos(i)
		g.coarse_map[i] = anchor[i] if anchor[i] >= 0 else g.idx(p * k)
	# Kabel: eine einfache Linie über die Vertreterfelder, zu Nachbarkabeln lückenlos verbunden
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
	# 5) Geräte: dieselben Instanzen. Erst Mehrfeld-Geräte (durch die Wand), dann die übrigen.
	var order: Array = c.devices.keys()
	order.sort_custom(func(a, b): return int(c.devices[a].data().length > 1) > int(c.devices[b].data().length > 1))
	for ci in order:
		var dev: Device = c.devices[ci]
		var p := dev.pos
		if dev.data().length > 1:
			var mid := p + dev.outward()
			if c.in_bounds(mid) and anchor[c.idx(mid)] >= 0:
				var inner := g.pos(anchor[c.idx(mid)]) - dev.outward()
				if g.mount_reason(dev.type, inner, dev.rot) == "":
					dev.pos = inner
					g.put_device(dev)
					g.coarse_map[ci] = g.idx(inner)
					if c.cables[ci] == 1:
						g.cables[g.idx(inner)] = 1   # Stromanschluss wie am alten Platz
					continue
			# passt nicht mehr: einmal als vollständiger Gegenstand an Bord ablegen
			dev.pos = g._free_floor_near(p * k)
			g._migrate_legacy(dev)
			continue
		var spot := Vector2i(-1, -1)
		if anchor[ci] >= 0:
			spot = g.pos(anchor[ci])           # z. B. Andockschleuse auf ihrer Tür
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
			# Gerät nicht auf der Kabellinie: kurzes Stück zum Vertreterfeld legen
			var r := g.pos(g.coarse_map[ci])
			for x in range(mini(r.x, spot.x), maxi(r.x, spot.x) + 1):
				g.cables[g.idx(Vector2i(x, r.y))] = 1
			for y in range(mini(r.y, spot.y), maxi(r.y, spot.y) + 1):
				g.cables[g.idx(Vector2i(spot.x, y))] = 1
		g.coarse_map[ci] = g.idx(spot)
		if c.linked.has(ci):
			g.linked[g.idx(spot)] = true
	# 6) Haufen auf ein freies Teilfeld
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

## Vertreter-Feld eines groben Feldes nach refine() (für gespeicherte Positionen)
func fine_of_coarse(cp: Vector2i) -> Vector2i:
	if coarse_map.is_empty() or coarse_width <= 0:
		return cp
	return pos(coarse_map[cp.y * coarse_width + cp.x])

## Gespeicherte Figurenposition (grobe Feld-Einheiten) ins feine Raster: gleiche Stelle,
## auf ein begehbares Feld
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
