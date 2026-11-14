## Orders menu after Ostranauts "Orders" 4: one action and object filters, applied to
## a tile or a dragged area. Only objects that match an active filter get
## the job (e.g. UNIN with WALL + FLOOR only uninstalls walls and floors).
## A tile holds at most one job: of several matching layers the topmost gets it
## (cable → device → floor/wall), as with the right-click selection.
class_name Orders
extends RefCounted

const ACTIONS := ["CANC", "UNIN", "SCRA", "REPR", "DISM", "HAUL", "MINE", "LOAD"]
const ACTION_HINTS := {
	"CANC": "Removes all orders from the tile, including build orders",
	"UNIN": "Uninstalls installed items",
	"SCRA": "Scrap: quickly breaks down an item",
	"REPR": "Repairs damaged items and restores worn items",
	"DISM": "Carefully dismantles objects to recover maximum components",
	"HAUL": "Marks loose items for transport to the nearest cargo crate",
	"MINE": "Marks asteroid rock for excavation",
	"LOAD": "Reload ship-mounted weapons (no ship weapons in this game yet)",
}
const FILTERS := ["WALL", "FLOOR", "CONDUIT", "CAN", "EQUIP", "LOOSE"]
const FILTER_HINTS := {"WALL": "All walls (also doors and windows)", "FLOOR": "All floors", "CONDUIT": "All conduits (cables)",
	"CAN": "All canisters (air tank, fuel tank)", "EQUIP": "All equipment, incl. furniture and lights", "LOOSE": "Anything uninstalled (loose piles)"}
## action → removal kind in RemovalSystem
const REMOVAL := {"UNIN": "uninstall", "SCRA": "destroy", "DISM": "dismantle"}
const CANISTERS := ["airtank", "fueltank"]

static var action := "UNIN"
static var filters := {"WALL": true, "FLOOR": true, "CONDUIT": true, "CAN": true, "EQUIP": true, "LOOSE": true}

## Filter of a layer ("cable", "dev:airtank", "tile:wall" …)
static func filter_of(key: String) -> String:
	if key == "cable":
		return "CONDUIT"
	if key.begins_with("dev:"):
		return "CAN" if key.substr(4) in CANISTERS else "EQUIP"
	if key == "tile:floor":
		return "FLOOR"
	if key in ["tile:wall", "tile:door", "tile:window"]:
		return "WALL"
	return ""

static func matches(key: String) -> bool:
	var f := filter_of(key)
	return f != "" and bool(filters.get(f, false))

## Rough preview (without tool and path checks): is there a matching target here?
static func has_target(p: Vector2i) -> bool:
	var g := ShipSystem.grid
	if not g.in_bounds(p):
		return false
	var i := g.idx(p)
	match action:
		"CANC":
			return ShipConstructionSystem.jobs.has(i) or (g.device_at(p) != null and ShipConstructionSystem.jobs.has(g.idx(g.device_at(p).pos)))
		"UNIN", "SCRA", "DISM":
			return RemovalSystem.layers_at(p).any(func(k): return k != "tile:rock" and matches(k))
		"REPR":
			return DamageSystem.needs_repair(p)
		"HAUL":
			return bool(filters.LOOSE) and g.piles.has(i)
		"MINE":
			return RemovalSystem.key_at(p) == "tile:rock"
	return false

## Apply the action to a tile. Returns true if a job was created or removed.
static func apply(p: Vector2i) -> bool:
	var g := ShipSystem.grid
	if not g.in_bounds(p):
		return false
	var i := g.idx(p)
	var CS := ShipConstructionSystem
	match action:
		"CANC":
			# all jobs of the tile, build plans too; a device can have its job at its anchor tile
			var done := false
			for k in [i, g.idx(RemovalSystem.anchor(p)) if g.device_at(p) != null else i]:
				if CS.jobs.has(k):
					CS.cancel(CS.jobs[k])
					done = true
			return done
		"UNIN", "SCRA", "DISM":
			for key in RemovalSystem.layers_at(p):
				if key == "tile:rock" or not matches(key):
					continue
				if RemovalSystem.reason(REMOVAL[action], p, key) == "" and RemovalSystem.order(REMOVAL[action], p, key) == "":
					return true
			return false
		"REPR":
			if not CS.can_place("repair", p):
				return false
			var dev := g.device_at(p)
			var ok := false
			if dev != null and dev.cond < 100.0:
				ok = matches("dev:" + dev.type)
			if not ok and g.cond[i] < 100.0:
				ok = matches(RemovalSystem.tile_key_at(p))
			return ok and CS.place("repair", p)
		"HAUL":
			return bool(filters.LOOSE) and CS.can_place("haul", p) and CS.place("haul", p)
		"MINE":
			if RemovalSystem.key_at(p) != "tile:rock":
				return false
			return RemovalSystem.reason("dismantle", p, "tile:rock") == "" and RemovalSystem.order("dismantle", p, "tile:rock") == ""
	return false
