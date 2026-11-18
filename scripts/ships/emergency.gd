## Emergency items from the Ostranauts wiki:
## - Oxygen Candle: single use, generates oxygen for 60 minutes (wiki: Max. Timer 3600 s) on the
##   tile where it was struck. Amount our own choice: 6 kPa O₂ per minute on that tile, the
##   atmosphere spreads it.
## - "Ripley" Temporary Blister Seal Wall: seals a hull breach for 60 minutes (wiki: Max. Timer
##   3600 s). Repairing the sealed wall makes it permanent; otherwise the hole opens again.
class_name Emergency
extends RefCounted

const CANDLE_MINUTES := 60.0
const CANDLE_O2_PER_MIN := 6.0
const SEAL_MINUTES := 60.0
const SEAL_COND := 10.0

## Hull breach: own floor tile with space next to it
static func is_breach(g: ShipGrid, i: int) -> bool:
	if g.tiles[i] != ShipGrid.Tile.FLOOR or g.zone[i] != 0:
		return false
	var p := g.pos(i)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if g.in_bounds(p + d) and g.get_tile(p + d) == ShipGrid.Tile.SPACE:
			return true
	return false

## Nearest breach within 2 tiles of the character (-1 = none)
static func breach_near(c: CrewMember) -> int:
	var g := c.grid()
	var t := c.tile()
	for r in 3:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := t + Vector2i(dx, dy)
				if g.in_bounds(q) and is_breach(g, g.idx(q)):
					return g.idx(q)
	return -1

static func activate_candle(c: CrewMember) -> bool:
	if c.inv.count("oxygen_candle") <= 0:
		return false
	c.inv.take("oxygen_candle", 1)
	var g := c.grid()
	g.candles.append({"i": g.idx(c.tile()), "left": CANDLE_MINUTES})
	GameState.toast("%s strikes an oxygen candle: oxygen for 60 minutes." % c.display_name)
	return true

static func seal_breach(c: CrewMember) -> bool:
	var i := breach_near(c)
	if i < 0 or c.inv.count("ripley_seal") <= 0:
		GameState.toast("No hull breach within reach.")
		return false
	c.inv.take("ripley_seal", 1)
	var g := c.grid()
	var CS := ShipConstructionSystem
	if CS.jobs.has(i):
		CS.jobs.erase(i)   # the wall job: the seal stands there now, repairing it makes it permanent
	g.set_tile(g.pos(i), ShipGrid.Tile.WALL)
	g.cond[i] = SEAL_COND
	g.temp_seal[i] = GameState.time + SEAL_MINUTES
	EventBus.ship_changed.emit()
	GameState.toast("Hull breach sealed for 60 minutes. Repair the wall before the seal gives out.")
	return true

## Every step: candles release oxygen, seals give out
static func step(g: ShipGrid, dt: float) -> void:
	for k in range(g.candles.size() - 1, -1, -1):
		var cd: Dictionary = g.candles[k]
		var i := int(cd.i)
		if g.holds_air(i):
			g.o2[i] += CANDLE_O2_PER_MIN * minf(dt, float(cd.left))
		cd.left = float(cd.left) - dt
		if float(cd.left) <= 0.0:
			g.candles.remove_at(k)
	for i in g.temp_seal.keys():
		if GameState.time >= float(g.temp_seal[i]):
			g.temp_seal.erase(i)
			if g.tiles[i] == ShipGrid.Tile.WALL:
				g.set_tile(g.pos(i), ShipGrid.Tile.FLOOR)
				EventBus.ship_changed.emit()
				ShipConstructionSystem.place("wall", g.pos(i))
				GameState.toast("A temporary hull seal gave out: the breach is open again!", "bad")
