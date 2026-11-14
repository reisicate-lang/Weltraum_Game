## An installed device on a tile of the ship (runtime state).
class_name Device
extends RefCounted

var type: String
var pos: Vector2i
var powered := false
var producing := false
var net := -1
var cond := 100.0
var broken := false
var stock := -1.0
var charge := 0.0
var claimed_by := -1
var inv: Inventory = null
## Suit locker: stored space suit {"o2", "battery"} or null
var suit = null
## Airlock pump: stored air (kPa)
var store := 0.0
## Wreck devices are unknown until someone gets close
var unknown := false
## Lock: 0 = open, 1–3 = security level (hacking needed)
var lock_level := 0
## Growing and meat vat
var growth := 0.0
var tended_at := 0.0
var genemod := false
## Rotation in 90° steps (0 = pushes the ship forward towards the nose, 1 = to the right,
## 2 = backward, 3 = to the left). Only for rotatable devices such as thrusters.
var rot := 0
## Power switch: on = conducts like a cable, off = splits the networks
var switch_on := true

const PUSH_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## Which way the device pushes the ship (ship coordinates: x = nose, y = right)
func push_dir() -> Vector2i:
	return PUSH_DIRS[rot % 4]

## Mounting direction from inside to outside (towards the nozzle); against the thrust direction
func outward() -> Vector2i:
	return -push_dir()

## All tiles of the device, pos first.
## Thruster 1×3: pos is the inner tile, then outwards (inside, wall, nozzle).
## Docking port 5×2: pos is the outer door; outer row in the wall, the inner row behind it.
func cells() -> Array[Vector2i]:
	if data().width > 1:
		return ShipGrid.dock_cells(pos, outward(), data().width)
	var out: Array[Vector2i] = []
	for k in maxi(1, data().length):
		out.append(pos + outward() * k)
	return out

func _init(t: String, p: Vector2i) -> void:
	type = t
	pos = p
	var d := data()
	stock = d.stock
	if d.capacity > 0.0:
		charge = d.capacity * 0.5
	if d.storage > 0.0:
		inv = Inventory.new(INF, d.storage)
		inv.only_modules = t == "helm"
	if t == "locker":
		suit = {"o2": 100.0, "battery": 100.0}
	if t == "pump":
		store = 1000.0

func data() -> DeviceData:
	return ItemSystem.device(type)

## Working navigation console module of this kind in the module bay ({} = none)
func module(kind: String) -> Dictionary:
	if inv == null or not inv.only_modules:
		return {}
	for it in inv.items:
		if ItemSystem.item(it.type).helm_module == kind and float(it.cond) > 0.0:
			return it
	return {}

## Is a module of this kind (even a broken one) in the bay?
func has_module_item(kind: String) -> bool:
	if inv == null or not inv.only_modules:
		return false
	for it in inv.items:
		if ItemSystem.item(it.type).helm_module == kind:
			return true
	return false

func needs_power() -> bool:
	return data().power < 0.0

## Can a character use the device right now?
func usable() -> bool:
	if broken:
		return false
	if data().stock >= 0.0 and stock <= 0.0:
		return false
	if needs_power() and not powered:
		return false
	return true

func status_text() -> String:
	var d := data()
	if unknown:
		return "Crate · contents unknown (move closer)" if inv != null else "Unknown device (move closer)"
	var parts: PackedStringArray = [d.display_name]
	if lock_level > 0:
		parts.append("locked (level %d)" % lock_level)
	if broken:
		parts.append("KAPUTT")
	elif cond < 100.0:
		parts.append("condition %d %%" % int(cond))
	if needs_power():
		parts.append("running" if powered else "no power")
	if d.power > 0.0:
		parts.append("producing %.1f kW" % d.power if producing else ("must stand outside in vacuum" if type == "solar" else "producing nothing"))
	if type == "locker":
		parts.append("Suit: O₂ %d %%, battery %d %%" % [int(suit.o2), int(suit.battery)] if suit != null else "empty (suit is in use)")
	if type == "pump":
		parts.append("storage %d kPa" % int(store))
	if type in ["hydro", "autofarm", "meatvat"]:
		parts.append("growth %d %%" % int(growth * 100.0) + (" · gene mod" if genemod else ""))
	if type == "hydro":
		parts.append("gepflegt" if GameState.time - tended_at < 1440.0 else "needs care")
	if d.capacity > 0.0:
		var cap := ShipPowerSystem.capacity_of(self)
		parts.append("%.1f / %.0f kWh" % [charge, cap] + ("" if cap >= d.capacity else " (rated %.0f)" % d.capacity))
	if d.stock >= 0.0:
		parts.append("stock: %d %s" % [int(stock), d.stock_unit])
	if inv != null:
		parts.append("%d / %d L used" % [int(inv.volume()), int(d.storage)])
	if ShipSystem.grid != null and ShipSystem.grid.zone[ShipSystem.grid.idx(pos)] == 1:
		parts.append(SalvageSystem.estimate_text(self))
	return " · ".join(parts)

func to_data() -> Dictionary:
	return {"type": type, "x": pos.x, "y": pos.y, "cond": cond, "broken": broken, "stock": stock,
		"charge": charge, "items": inv.to_data() if inv != null else [], "suit": suit, "store": store, "unknown": unknown, "lock": lock_level,
		"growth": growth, "tended_at": tended_at, "genemod": genemod, "rot": rot, "shape": data().length, "switch": switch_on}

static func from_data(d: Dictionary) -> Device:
	var dev := Device.new(String(d.type), Vector2i(int(d.x), int(d.y)))
	dev.cond = float(d.cond)
	dev.broken = bool(d.broken)
	dev.stock = float(d.stock)
	dev.charge = float(d.charge)
	if dev.inv != null:
		dev.inv.from_data(d.items)
	dev.suit = d.get("suit")
	dev.store = float(d.get("store", 0.0))
	dev.unknown = bool(d.get("unknown", false))
	dev.lock_level = int(d.get("lock", 0))
	dev.growth = float(d.get("growth", 0.0))
	dev.tended_at = float(d.get("tended_at", 0.0))
	dev.genemod = bool(d.get("genemod", false))
	dev.switch_on = bool(d.get("switch", true))
	dev.rot = int(d.get("rot", 0))
	return dev
