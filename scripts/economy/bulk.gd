## Bulk Trading after the Ostranauts wiki pages "Bulk Trading" and "Cargo Pod": abstract trade
## goods (not inventory items) in installed cargo pods. Each pod holds ONE good, at most 1000 kg.
## Four pods: Standard (no protection), Climate-Controlled, Radiation-shielded, Specialty (both).
## Goods, prices, masses, needed protection and the station market from the wiki
## (data/bulk_goods.json); the wiki stations are mapped to this game's stations.
## The cargo belongs to the ship: ShipGrid.bulk {good id: units}.
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

## Pod class a good needs: both protections → specialty, one → that one, none → standard
static func needs_class(id: String) -> String:
	var n: Array = good(id).get("needs", [])
	if n.has("radiation") and n.has("climate"):
		return "specialty"
	if n.has("radiation"):
		return "radiation"
	if n.has("climate"):
		return "climate"
	return "standard"

## Units of a good that fill one pod (1000 kg ÷ unit mass, rounded down)
static func per_pod(id: String) -> int:
	return maxi(1, int(floor(float(data().get("pod_capacity_kg", 1000)) / maxf(0.001, float(good(id).get("mass_kg", 1.0))))))

static func pods_needed(id: String, n: int) -> int:
	return int(ceil(float(n) / per_pod(id))) if n > 0 else 0

## Working pods of your own ship by protection
static func pods(g: ShipGrid) -> Dictionary:
	var out := {"standard": 0, "climate": 0, "radiation": 0, "specialty": 0}
	for i in g.devices:
		var dev: Device = g.devices[i]
		if POD_PROTECTION.has(dev.type) and not g.foreign(i) and not dev.broken:
			out[POD_PROTECTION[dev.type]] += 1
	return out

static func pod_count(g: ShipGrid) -> int:
	var n := 0
	for k in pods(g).values():
		n += int(k)
	return n

static func pods_used(cargo: Dictionary) -> int:
	var n := 0
	for id in cargo:
		n += pods_needed(id, int(cargo[id]))
	return n

static func units(cargo: Dictionary) -> int:
	var n := 0
	for k in cargo.values():
		n += int(k)
	return n

## Does the cargo fit into these pods? Each good fills whole pods; goods needing protection go
## first into the pods made for them, Specialty takes everything.
static func fits(p: Dictionary, cargo: Dictionary) -> bool:
	var need := {"standard": 0, "climate": 0, "radiation": 0, "specialty": 0}
	for id in cargo:
		need[needs_class(id)] += pods_needed(id, int(cargo[id]))
	var spec: int = int(p.specialty) - int(need.specialty)
	if spec < 0:
		return false
	var rad_free: int = int(p.radiation) - int(need.radiation)
	if rad_free < 0:
		spec += rad_free
		rad_free = 0
	var cli_free: int = int(p.climate) - int(need.climate)
	if cli_free < 0:
		spec += cli_free
		cli_free = 0
	if spec < 0:
		return false
	return int(p.standard) + rad_free + cli_free + spec >= int(need.standard)

## How many more units of this good fit aboard (binary search)
static func room_for(g: ShipGrid, id: String) -> int:
	var p := pods(g)
	var have := int(g.bulk.get(id, 0))
	var lo := 0
	var hi := per_pod(id) * maxi(1, pod_count(g))
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		var cargo: Dictionary = g.bulk.duplicate()
		cargo[id] = have + mid
		if fits(p, cargo):
			lo = mid
		else:
			hi = mid - 1
	return lo

static func wiki_station(station: String) -> String:
	return String(data().get("station_map", {}).get(station, ""))

## Market sign of the good at a station ("" = not traded there)
static func market_sign(id: String, station: String) -> String:
	return String(good(id).get("markets", {}).get(wiki_station(station), ""))

static func traded(id: String, station: String) -> bool:
	return market_sign(id, station) != ""

## Price at a station: wiki price × station sign (producers cheaper, consumers dearer) × daily
## variance (wiki: ±19 %; deterministic, no saving needed)
static func price(id: String, station: String) -> float:
	var gd := good(id)
	if gd.is_empty() or not traded(id, station):
		return 0.0
	var f: float = 1.0 + float(data().get("signs", {}).get(market_sign(id, station), 0.0))
	var day := int(GameState.time / 1440.0)
	var drift: float = float(data().get("variance", 0.19)) * sin(float(hash(id + station) % 1000) + day * 1.3)
	return float(gd.price) * f * (1.0 + drift)

static func buy_price(id: String, station: String) -> float:
	return price(id, station) * (1.0 + float(data().get("spread", 0.1)) * 0.5) * Residency.bulk_factor(station, false)

static func sell_price(id: String, station: String) -> float:
	return price(id, station) * (1.0 - float(data().get("spread", 0.1)) * 0.5) * Residency.bulk_factor(station, true)

static func _station() -> String:
	return String(PhysicsSystem.station().get("id", ""))

## "" = trading possible here
static func block_reason(g: ShipGrid) -> String:
	if not EconomySystem.terminal_online():
		return "Bulk trading needs the trade terminal online at a station (Cargo Kiosk)."
	if pod_count(g) == 0:
		return "No cargo pod installed. Buy one in the market and install it."
	return ""

static func buy(id: String, qty: int) -> int:
	var g := ShipSystem.grid
	var why := block_reason(g)
	if why == "" and not traded(id, _station()):
		why = "%s is not traded here." % good(id).get("name", id)
	if why != "":
		GameState.toast(why, "bad")
		return 0
	var pr := buy_price(id, _station())
	var n := mini(mini(qty, int(floor(EconomySystem.credits / maxf(0.0001, pr)))), room_for(g, id))
	if n <= 0:
		GameState.toast("Not enough credits." if EconomySystem.credits < pr else "No suitable pod left for %s (needs a %s pod)." % [good(id).name, needs_class(id)])
		return 0
	var cost := int(ceil(n * pr))
	EconomySystem.credits -= cost
	g.bulk[id] = int(g.bulk.get(id, 0)) + n
	EconomySystem.book("Bulk purchase: %s ×%d" % [good(id).name, n], -cost)
	return n

static func sell(id: String, qty: int) -> int:
	var g := ShipSystem.grid
	if not EconomySystem.terminal_online():
		GameState.toast("Bulk trading needs the trade terminal online at a station (Cargo Kiosk).", "bad")
		return 0
	if not traded(id, _station()):
		GameState.toast("%s is not traded here." % good(id).get("name", id), "bad")
		return 0
	var n := mini(qty, int(g.bulk.get(id, 0)))
	if n <= 0:
		return 0
	var gain := int(n * sell_price(id, _station()))
	EconomySystem.credits += gain
	g.bulk[id] = int(g.bulk[id]) - n
	if int(g.bulk[id]) <= 0:
		g.bulk.erase(id)
	EconomySystem.book("Bulk sale: %s ×%d" % [good(id).name, n], gain)
	return n

## Mass of the cargo in t
static func mass(g: ShipGrid) -> float:
	var kg := 0.0
	for id in g.bulk:
		kg += int(g.bulk[id]) * float(good(id).get("mass_kg", 0.0))
	return kg / 1000.0

## Removing this pod would leave cargo without room: reason ("" = fine)
static func remove_reason(g: ShipGrid, dev: Device) -> String:
	if dev == null or not POD_PROTECTION.has(dev.type) or g.bulk.is_empty() or dev.broken:
		return ""
	var p := pods(g)
	p[POD_PROTECTION[dev.type]] -= 1
	return "" if fits(p, g.bulk) else "The cargo would not fit without this pod. Sell the bulk goods first."
