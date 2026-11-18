## Asteroid Mining after the Ostranauts wiki page "Asteroid Mining": rock yields minerals as
## physical items (data/minerals.json). Values and weights from the wiki, yield weights our own
## choice. Full price at the faction kiosks (L4, Kármán Ring), reputation +1 per 12 000 Cr sold there.
class_name Mining
extends RefCounted

static var _data := {}

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/minerals.json", FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text()) if f != null else {"yield": {}}
	return _data

## Gott Mining Tool (Ostranauts wiki): needed for mining, every use adds 0.1 fatigue.
## In this game fatigue is the energy need (0–100): −1 energy per mined tile (our scale).
const TOOL := "mining_tool"
const FATIGUE := 1.0

static func tire(worker: CrewMember) -> void:
	if worker != null:
		worker.needs.sleep = maxf(0.0, worker.needs.sleep - FATIGUE)

static func is_mineral(type: String) -> bool:
	return type.begins_with("mineral_")

## One mined unit: [type, qty, condition]
static func roll() -> Array:
	var y: Dictionary = data().yield
	var total := 0.0
	for k in y:
		total += float(y[k])
	var r := randf() * total
	var pick := "mineral_regolith"
	for k in y:
		r -= float(y[k])
		if r <= 0.0:
			pick = k
			break
	var c: Array = data().get("cond", [40.0, 95.0])
	return [pick, 1, randf_range(float(c[0]), float(c[1]))]

static func is_kiosk(station: String) -> bool:
	return station in data().get("kiosks", [])

## Price factor for minerals at this station
static func price_factor(type: String, station: String) -> float:
	if not is_mineral(type) or is_kiosk(station):
		return 1.0
	return float(data().get("other_factor", 0.6))

## Reputation gain for a mineral sale at a kiosk
static func reputation_for(type: String, station: String, total: int) -> float:
	if not is_mineral(type) or not is_kiosk(station):
		return 0.0
	return float(total) / float(data().get("rep_per", 12000))
