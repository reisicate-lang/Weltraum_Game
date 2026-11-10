## Bergung: Zufällige Wracks an der Bergungsleine unterhalb des Schiffs.
## Jedes Wrack hat Räume, Lecks, beschädigte Geräte, Kisten mit
## unbekanntem Inhalt, Schrott und alte Kabel.
extends Node

const NAMES := ["MV Kestrel", "Frachter Nansen-4", "Tankschiff Halcyon", "Bergbauschlepper Ox-12",
	"Shuttle Meridian", "Kurierschiff Pallas", "Prospektor Vesna", "Versorger Hollis"]
const DEVICE_POOL := ["generator", "battery", "o2gen", "scrubber", "bed", "food", "airtank", "locker", "water", "sink", "pump", "solar", "charger"]
const LOOT := [["scrap", 6], ["plate", 5], ["copper", 5], ["circuit", 3], ["motor", 2], ["cell", 2], ["pipe", 4],
	["glass", 2], ["filter", 2], ["fabric", 3], ["ration", 4], ["fuelcan", 1], ["aircan", 1], ["watercan", 1], ["datachip", 1]]

var wreck_name := ""
var investigated := false
var cause := ""

## Mit welcher Andockschleuse das Wrack verbunden ist (Feld-Index) und wo seine Tür liegt
var port := -1
var entry := Vector2i(-1, -1)

## Freie Andockschleuse nach unten für ein Wrack (oder leer)
func free_port() -> Dictionary:
	var ports: Array = ShipSystem.free_ports(Vector2i(0, 1))
	return ports[0] if not ports.is_empty() else {}

## Wrack mit seiner Tür direkt unter die Schleuse hängen (Tür an Tür).
## Gibt false zurück, wenn keine freie Schleuse nach unten da ist oder kein Platz ist.
func generate() -> bool:
	if not Config.ENABLE_WRECK:
		return false
	var g := ShipSystem.grid
	var pt := free_port()
	if pt.is_empty():
		GameState.toast("Für ein Wrack fehlt eine freie Andockschleuse nach unten (in der unteren Außenwand).", "bad")
		return false
	var e: Vector2i = pt.pos + Vector2i(0, 1)
	var top := e.y
	var w := 0
	var h := 0
	var left := 0
	var found := false
	for attempt in 40:
		w = randi_range(15, 22) - attempt / 5
		h = randi_range(7, 10) - attempt / 10
		left = clampi(e.x - randi_range(3, w - 4), 1, g.width - w - 1)
		if e.x <= left or e.x >= left + w - 1 or top + h > g.height - 1:
			continue
		if _free_rect(g, left, top, w, h):
			found = true
			break
	if not found:
		GameState.toast("Kein Platz für das Wrack unter der Andockschleuse.", "bad")
		return false
	var inner: Array[Vector2i] = []
	for y in range(top, top + h):
		for x in range(left, left + w):
			var edge := x == left or y == top or x == left + w - 1 or y == top + h - 1
			_put(g, Vector2i(x, y), ShipGrid.Tile.WALL if edge else ShipGrid.Tile.FLOOR)
			if not edge:
				inner.append(Vector2i(x, y))
	_put(g, e, ShipGrid.Tile.DOOR)
	var doors: Array[Vector2i] = [e]
	_link(g, pt, e)
	# Innenwände
	var x := left + randi_range(4, 6)
	var splits := 0
	while x < left + w - 4 and splits < 2:
		if x != e.x:
			for y in range(top, top + h):
				_put(g, Vector2i(x, y), ShipGrid.Tile.WALL)
			var dy := randi_range(top + 2, top + h - 3)
			_put(g, Vector2i(x, dy), ShipGrid.Tile.DOOR if randf() < 0.7 else ShipGrid.Tile.FLOOR)
			doors.append(Vector2i(x, dy))
			splits += 1
		x += randi_range(5, 8)
	# Lecks in der Hülle
	var hull: Array[Vector2i] = []
	for y in range(top, top + h):
		for xx in range(left, left + w):
			var corner := (xx == left or xx == left + w - 1) and (y == top or y == top + h - 1)
			var edge := xx == left or y == top or xx == left + w - 1 or y == top + h - 1
			if edge and not corner and g.get_tile(Vector2i(xx, y)) == ShipGrid.Tile.WALL and absi(xx - e.x) > 1:
				hull.append(Vector2i(xx, y))
	for k in randi_range(1, 3):
		_put(g, hull.pick_random(), ShipGrid.Tile.FLOOR)
	# Abgestandene Luft
	for p in inner:
		var i := g.idx(p)
		if g.holds_air(i):
			g.o2[i] = 11.0; g.n2[i] = 55.0; g.co2[i] = 2.5
	# Plätze an den Wänden, nicht vor Türen
	var spots: Array[Vector2i] = []
	for p in inner:
		if g.get_tile(p) != ShipGrid.Tile.FLOOR:
			continue
		var near_door := false
		for d in doors:
			if absi(d.x - p.x) <= 1 and absi(d.y - p.y) <= 1:
				near_door = true
		if near_door:
			continue
		var at_wall := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if g.get_tile(p + d) == ShipGrid.Tile.WALL:
				at_wall = true
		if at_wall and not (g.get_tile(p + Vector2i(0, -1)) == ShipGrid.Tile.WALL and g.get_tile(p + Vector2i(0, 1)) == ShipGrid.Tile.WALL):
			spots.append(p)
	spots.shuffle()
	for k in randi_range(5, 9):
		if spots.is_empty():
			break
		var dev := g.place_device(DEVICE_POOL.pick_random(), spots.pop_back())
		dev.cond = randf_range(8.0, 75.0)
		dev.broken = randf() < 0.35
		dev.unknown = true
		if dev.data().stock >= 0.0:
			dev.stock = floorf(dev.data().stock * randf() * 0.3)
		dev.charge = 0.0
		if dev.type == "locker":
			dev.suit = {"o2": 0.0, "battery": 0.0} if randf() < 0.3 else null
	for k in randi_range(2, 4):
		if spots.is_empty():
			break
		var crate := g.place_device("crate", spots.pop_back())
		crate.cond = randf_range(30.0, 90.0)
		crate.unknown = true
		# Manche Kisten sind verschlossen: mehr Wertsachen, aber Hacken nötig
		if randf() < 0.35:
			crate.lock_level = randi_range(1, 3)
			for n in crate.lock_level:
				crate.inv.add(["datachip", "circuit", "cell", "boltgun", "contraband"].pick_random(), 1, randf_range(50.0, 95.0))
		for n in randi_range(2, 5):
			var l: Array = LOOT.pick_random()
			if l[0] == "datachip" and randf() < 0.6:
				continue
			crate.inv.add(l[0], randi_range(1, l[1]), randf_range(20.0, 95.0))
	# Schrott und Kabel
	var free := inner.filter(func(p): return g.walkable(p))
	for k in randi_range(2, 5):
		g.drop_items(free.pick_random(), ["scrap", "scrap", "copper", "pipe", "plate"].pick_random(), randi_range(1, 3), randf_range(15.0, 70.0))
	var cy := top + randi_range(1, h - 2)
	for cx in range(left + 1, left + w - 1):
		if randf() < 0.8:
			g.cables[g.idx(Vector2i(cx, cy))] = 1
	wreck_name = NAMES.pick_random()
	investigated = false
	cause = ["ein Reaktorbrand", "ein Treffer im Krieg", "eine Kollision mit Trümmern", "ein Hüllenbruch durch Materialermüdung", "Meuterei an Bord"].pick_random()
	EventBus.ship_changed.emit()
	return true

## Ist die Fläche frei (nur Weltraum, im Raster)?
func _free_rect(g: ShipGrid, left: int, top: int, w: int, h: int) -> bool:
	for y in range(top, top + h):
		for x in range(left, left + w):
			var q := Vector2i(x, y)
			if x < 1 or y < 1 or x > g.width - 2 or y > g.height - 2 or g.get_tile(q) != ShipGrid.Tile.SPACE or g.zone[g.idx(q)] != 0:
				return false
	return true

## Schleuse und Wracktür verbinden
func _link(g: ShipGrid, pt: Dictionary, e: Vector2i) -> void:
	port = int(pt.i)
	entry = e
	g.linked[port] = true

func _put(g: ShipGrid, p: Vector2i, t: int) -> void:
	g.set_tile(p, t)
	var i := g.idx(p)
	g.zone[i] = 1
	g.cond[i] = randf_range(25.0, 95.0)

func is_wreck(i: int) -> bool:
	return ShipSystem.grid.zone[i] == 1

## Asteroid: ein Brocken aus Fels (Wände), der beim Abreißen Eis und Erz gibt.
## Hängt unter einer freien Schleuse nach unten; direkt darunter ein Landeplatz.
func generate_asteroid() -> bool:
	if not Config.ENABLE_WRECK:
		return false
	var g := ShipSystem.grid
	var pt := free_port()
	if pt.is_empty():
		GameState.toast("Für den Asteroiden fehlt eine freie Andockschleuse nach unten.", "bad")
		return false
	var e: Vector2i = pt.pos + Vector2i(0, 1)
	var c := Vector2(e.x + randi_range(-2, 4), e.y + 5)
	var rx := randf_range(6.0, 10.0)
	var ry := randf_range(3.5, 5.0)
	for y in range(e.y, e.y + 11):
		for x in range(int(c.x - rx) - 1, int(c.x + rx) + 2):
			var p := Vector2i(x, y)
			if not g.in_bounds(p) or g.get_tile(p) != ShipGrid.Tile.SPACE or g.zone[g.idx(p)] != 0:
				continue
			var d := Vector2((x - c.x) / rx, (y - c.y) / ry).length() + randf_range(-0.12, 0.12)
			if d < 1.0:
				_put(g, p, ShipGrid.Tile.WALL)
	# Landeplatz direkt unter der Schleuse
	_put(g, e, ShipGrid.Tile.FLOOR)
	_link(g, pt, e)
	wreck_name = "Asteroid " + ["KX-7a", "KX-7b", "Brocken 12", "Splitter 4"].pick_random()
	investigated = true
	EventBus.ship_changed.emit()
	return true

func is_asteroid() -> bool:
	return wreck_name.begins_with("Asteroid")

## Darf das Wrack entfernt werden? (Niemand darf darauf stehen)
func clearable() -> bool:
	var g := ShipSystem.grid
	for c in CrewSystem.crew:
		if g.zone[g.idx(c.tile())] == 1:
			return false
	return true

func clear() -> void:
	var g := ShipSystem.grid
	for i in g.tiles.size():
		if g.zone[i] != 1:
			continue
		g.devices.erase(i)
		g.piles.erase(i)
		ShipConstructionSystem.jobs.erase(i)
		g.tiles[i] = ShipGrid.Tile.SPACE
		g.cables[i] = 0
		g.o2[i] = 0.0; g.n2[i] = 0.0; g.co2[i] = 0.0
		g.zone[i] = 0
	g.linked.erase(port)
	port = -1
	entry = Vector2i(-1, -1)
	wreck_name = ""
	EventBus.ship_changed.emit()

func to_data() -> Dictionary:
	return {"name": wreck_name, "investigated": investigated, "cause": cause, "port": port, "ex": entry.x, "ey": entry.y}

func from_data(d: Dictionary) -> void:
	wreck_name = String(d.get("name", ""))
	investigated = bool(d.get("investigated", false))
	cause = String(d.get("cause", ""))
	port = int(d.get("port", -1))
	entry = Vector2i(int(d.get("ex", -1)), int(d.get("ey", -1)))

func device_value(dev: Device) -> int:
	var base := 0.0
	var c := dev.data().cost
	for t in c:
		base += ItemSystem.item(t).value * c[t]
	return int(base * (0.3 + 0.7 * dev.cond / 100.0))

## Geschätzter Wert: Je besser die Betriebswirtschaft, desto genauer
func estimate_text(dev: Device) -> String:
	var v := device_value(dev)
	var acc := SkillSystem.appraisal()
	if acc >= 0.99:
		return "Bergungswert %d Cr" % v
	var spread := int(v * (0.5 - 0.45 * acc))
	return "Bergungswert ~%d–%d Cr" % [maxi(0, v - spread), v + spread]

## Restwert beim Verschrotten
func hull_value() -> int:
	var g := ShipSystem.grid
	var v := 0.0
	var plate := ItemSystem.item("plate").value
	for i in g.tiles.size():
		if g.zone[i] != 1:
			continue
		var t := g.tiles[i]
		if t == ShipGrid.Tile.WALL or t == ShipGrid.Tile.DOOR:
			v += plate * 2
		elif t == ShipGrid.Tile.FLOOR:
			v += plate
		if g.devices.has(i):
			v += device_value(g.devices[i])
			if g.devices[i].inv != null:
				v += EconomySystem.inv_value(g.devices[i].inv)
		if g.piles.has(i):
			v += EconomySystem.inv_value(g.piles[i])
	return int(v * Config.HULL_FACTOR)

## Forensik: Wrack untersuchen. Findet Ursache und manchmal ein Versteck.
func investigate(c: CrewMember) -> String:
	var g := ShipSystem.grid
	if wreck_name == "":
		return "Hier ist kein Wrack."
	if g.zone[g.idx(c.tile())] != 1:
		return c.display_name + " muss dafür auf dem Wrack sein."
	if investigated:
		return "Dieses Wrack wurde schon untersucht."
	investigated = true
	SkillSystem.train(c, "investigate", 20.0)
	var text := ""
	if SkillSystem.effect(c, "damage_insight") > 0.2:
		text = "%s findet heraus: Das Wrack ging durch %s verloren. " % [c.display_name, cause]
	else:
		text = "%s findet Spuren, kann sie aber nicht deuten. " % c.display_name
	var chance := 0.15 + SkillSystem.effect(c, "find_hidden")
	if SkillSystem.mastered(c, "forensic") or randf() < chance:
		g.drop_items(c.tile(), "datachip", randi_range(1, 2), randf_range(70.0, 100.0))
		text += "Unter einer Bodenplatte liegt ein Versteck mit Datenchips!"
	else:
		text += "Kein Versteck gefunden."
	return text

## Geräte in der Nähe eines Charakters werden erkannt
func reveal(c: CrewMember) -> void:
	for dev in ShipSystem.grid.devices.values():
		if dev.unknown and absf(dev.pos.x + 0.5 - c.pos.x) <= 2.5 and absf(dev.pos.y + 0.5 - c.pos.y) <= 2.5:
			dev.unknown = false
			SkillSystem.train(c, "appraise", 1.0)
