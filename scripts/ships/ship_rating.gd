## Schiffsbewertung nach Ostranauts „Ship Building“ 2.2: W-X-Y-ZZZZ =
## Zustand – Anzahl verschiedener Raumtypen – Schub (Masse je Triebwerk) – Größe (Breite × Länge).
class_name ShipRating
extends RefCounted

const SIZE_CLASSES := [[250, "Small"], [900, "Medium"], [1600, "Lunamax"], [2300, "Ceresmax"],
	[3000, "Titanmax"], [3700, "Very Large"]]

## Durchschnittszustand aller eingebauten Teile (Geräte und Rumpffelder) in %
static func condition(g: ShipGrid) -> float:
	var sum := 0.0
	var n := 0
	for i in g.tiles.size():
		if g.tiles[i] != ShipGrid.Tile.SPACE and not g.foreign(i):
			sum += g.cond[i]
			n += 1
	for i in g.devices:
		if not g.foreign(i):
			sum += 0.0 if g.devices[i].broken else g.devices[i].cond
			n += 1
	return sum / n if n > 0 else 0.0

static func condition_rank(c: float) -> String:
	if c >= 99.95:
		return "A"
	if c >= 95.0:
		return "B"
	if c >= 80.0:
		return "C"
	if c >= 50.0:
		return "D"
	return "E"

## Masse je Triebwerk in kg → A (< 300) bis E (> 1500); ohne Triebwerk E
static func thrust_rank(mass_kg: float, thrusters: int) -> String:
	if thrusters <= 0:
		return "E"
	var m := mass_kg / thrusters
	if m < 300.0:
		return "A"
	if m <= 500.0:
		return "B"
	if m <= 750.0:
		return "C"
	if m <= 1500.0:
		return "D"
	return "E"

## Fläche des umschließenden Rechtecks aller eigenen Felder (Breite × Länge)
static func area(g: ShipGrid) -> int:
	var lo := Vector2i(g.width, g.height)
	var hi := Vector2i(-1, -1)
	for i in g.tiles.size():
		if g.tiles[i] != ShipGrid.Tile.SPACE and not g.foreign(i):
			var p := g.pos(i)
			lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
			hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
	if hi.x < 0:
		return 0
	return (hi.x - lo.x + 1) * (hi.y - lo.y + 1)

static func size_class(a: int) -> String:
	if a < 250:
		return "Small"
	for sc in SIZE_CLASSES:
		if a <= int(sc[0]):
			return sc[1]
	return "Ultra Large"

## Masse ohne Ladung (für gespeicherte Schiffe): Rumpffelder und Geräte, in kg
static func dry_mass_kg(g: ShipGrid) -> float:
	var m := 0.0
	for i in g.tiles.size():
		if g.tiles[i] != 0 and not g.foreign(i):
			m += float(Config.TILE_MASS.get(g.tiles[i], 0.2))
	for i in g.devices:
		if not g.foreign(i):
			m += g.devices[i].data().mass
	return m * 1000.0

## Bewertung als Text, z. B. "C-3-E-0960". mass_kg < 0: Trockenmasse des Rasters
static func rating(g: ShipGrid, mass_kg: float = -1.0) -> String:
	var thr := 0
	for i in g.devices:
		if g.devices[i].type == "thruster" and not g.foreign(i) and not g.devices[i].broken:
			thr += 1
	var m := mass_kg if mass_kg >= 0.0 else dry_mass_kg(g)
	return "%s-%d-%s-%04d" % [condition_rank(condition(g)), RoomTypes.unique_count(g), thrust_rank(m, thr), mini(area(g), 9999)]
