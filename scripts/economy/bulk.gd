## Bulk Trading after Ostranauts "Trading" 5: abstract trade goods (not inventory items) in
## installed cargo pods. Four pod types: Standard (no protection), Climate-Controlled,
## Radiation-Shielded, Specialty (both). Goods and prices: data/bulk_goods.json (own choice,
## the wiki names none). The cargo belongs to the ship: ShipGrid.bulk {good id: units}.
## The trade terminal of a station is the Cargo Kiosk.
class_name Bulk
extends RefCounted

const POD_PROTECTION := {"cargo_pod": "standard", "cargo_pod_climate": "climate",
	"cargo_pod_radiation": "radiation", "cargo_pod_specialty": "specialty"}

static var _data := {}

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/bulk_goods.json", FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text()) if f != null else {"goods": []}
	return _data

static func goods() -> Array:
	return data().get("goods", [])

static func good(id: String) -> Dictionary:
	for gd in goods():
		if gd.id == id:
			return gd
	return {}

static func units_per_pod() -> int:
	return int(data().get("units_per_pod", 10))

## Working pods of your own ship by protection
static func pods(g: ShipGrid) -> Dictionary:
	var out := {"standard": 0, "climate": 0, "radiation": 0, "specialty": 0}
	for i in g.devices:
		var dev: Device = g.devices[i]
		if POD_PROTECTION.has(dev.type) and not g.foreign(i) and not dev.broken:
			out[POD_PROTECTION[dev.type]] += 1
	return out

static func capacity(g: ShipGrid) -> int:
	var n := 0
	for k in pods(g).values():
		n += int(k)
	return n * units_per_pod()

static func units(cargo: Dictionary) -> int:
	var n := 0
	for k in cargo.values():
		n += int(k)
	return n

## Does the cargo fit into these pods? Special goods go first into the pods made for them,
## the rest into any free space (Specialty takes everything).
static func fits(p: Dictionary, cargo: Dictionary) -> bool:
	var u := units_per_pod()
	var need := {"standard": 0, "climate": 0, "radiation": 0, "specialty": 0}
	for id in cargo:
		need[String(good(id).get("needs", "standard"))] += int(cargo[id])
	var spec: int = int(p.specialty) * u - int(need.specialty)
	if spec < 0:
		return false
	var rad_free: int = int(p.radiation) * u - int(need.radiation)
	if rad_free < 0:
		spec += rad_free
		rad_free = 0
	var cli_free: int = int(p.climate) * u - int(need.climate)
	if cli_free < 0:
		spec += cli_free
		cli_free = 0
	if spec < 0:
		return false
	return int(p.standard) * u + rad_free + cli_free + spec >= int(need.standard)

## How many more units of this good fit aboard
static func room_for(g: ShipGrid, id: String) -> int:
	var p := pods(g)
	var cargo: Dictionary = g.bulk.duplicate()
	var n := 0
	while n < 1000:
		cargo[id] = int(cargo.get(id, 0)) + 1
		if not fits(p, cargo):
			break
		n += 1
	return n

## Mid price at a station; it drifts a little every day (deterministic, no saving needed)
static func price(id: String, station: String) -> float:
	var gd := good(id)
	if gd.is_empty():
		return 0.0
	var f: float = float(gd.get("stations", {}).get(station, 1.0))
	var day := int(GameState.time / 1440.0)
	var drift: float = float(data().get("drift", 0.08)) * sin(float(hash(id + station) % 1000) + day * 1.3)
	return float(gd.base) * f * (1.0 + drift)

static func buy_price(id: String, station: String) -> int:
	return int(ceil(price(id, station) * (1.0 + float(data().get("spread", 0.12)) * 0.5)))

static func sell_price(id: String, station: String) -> int:
	return int(price(id, station) * (1.0 - float(data().get("spread", 0.12)) * 0.5))

static func _station() -> String:
	return String(PhysicsSystem.station().get("id", ""))

## "" = trading possible here
static func block_reason(g: ShipGrid) -> String:
	if not EconomySystem.terminal_online():
		return "Bulk trading needs the trade terminal online at a station (Cargo Kiosk)."
	if capacity(g) == 0:
		return "No cargo pod installed. Buy one in the market and install it."
	return ""

static func buy(id: String, qty: int) -> int:
	var g := ShipSystem.grid
	var why := block_reason(g)
	if why != "":
		GameState.toast(why, "bad")
		return 0
	var pr := buy_price(id, _station())
	var n := mini(mini(qty, EconomySystem.credits / maxi(1, pr)), room_for(g, id))
	if n <= 0:
		GameState.toast("Not enough credits." if EconomySystem.credits < pr else "No suitable pod space left for %s (needs: %s)." % [good(id).name, good(id).needs])
		return 0
	EconomySystem.credits -= n * pr
	g.bulk[id] = int(g.bulk.get(id, 0)) + n
	EconomySystem.book("Bulk purchase: %s ×%d" % [good(id).name, n], -n * pr)
	return n

static func sell(id: String, qty: int) -> int:
	var g := ShipSystem.grid
	if not EconomySystem.terminal_online():
		GameState.toast("Bulk trading needs the trade terminal online at a station (Cargo Kiosk).", "bad")
		return 0
	var n := mini(qty, int(g.bulk.get(id, 0)))
	if n <= 0:
		return 0
	var pr := sell_price(id, _station())
	EconomySystem.credits += n * pr
	g.bulk[id] = int(g.bulk[id]) - n
	if int(g.bulk[id]) <= 0:
		g.bulk.erase(id)
	EconomySystem.book("Bulk sale: %s ×%d" % [good(id).name, n], n * pr)
	return n

## Mass of the cargo in t
static func mass(g: ShipGrid) -> float:
	return units(g.bulk) * float(data().get("unit_mass_t", 0.1))

## Removing this pod would leave cargo without room: reason ("" = fine)
static func remove_reason(g: ShipGrid, dev: Device) -> String:
	if dev == null or not POD_PROTECTION.has(dev.type) or g.bulk.is_empty() or dev.broken:
		return ""
	var p := pods(g)
	p[POD_PROTECTION[dev.type]] -= 1
	return "" if fits(p, g.bulk) else "The cargo would not fit without this pod. Sell the bulk goods first."
