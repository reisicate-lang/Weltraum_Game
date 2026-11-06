## Ein eingebautes Gerät auf einem Feld des Schiffs (Zustand zur Laufzeit).
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

func _init(t: String, p: Vector2i) -> void:
	type = t
	pos = p
	var d := data()
	stock = d.stock
	if d.capacity > 0.0:
		charge = d.capacity * 0.5
	if d.storage > 0.0:
		inv = Inventory.new(INF, d.storage)

func data() -> DeviceData:
	return ItemSystem.device(type)

func needs_power() -> bool:
	return data().power < 0.0

## Kann ein Charakter das Gerät gerade benutzen?
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
	var parts: PackedStringArray = [d.display_name]
	if broken:
		parts.append("KAPUTT")
	elif cond < 100.0:
		parts.append("Zustand %d %%" % int(cond))
	if needs_power():
		parts.append("läuft" if powered else "kein Strom")
	if d.power > 0.0:
		parts.append("liefert %.1f kW" % d.power if producing else "liefert nichts")
	if d.capacity > 0.0:
		parts.append("%.1f / %.0f kWh" % [charge, d.capacity])
	if d.stock >= 0.0:
		parts.append("Vorrat: %d %s" % [int(stock), d.stock_unit])
	if inv != null:
		parts.append("%d / %d L belegt" % [int(inv.volume()), int(d.storage)])
	return " · ".join(parts)

func to_data() -> Dictionary:
	return {"type": type, "x": pos.x, "y": pos.y, "cond": cond, "broken": broken, "stock": stock,
		"charge": charge, "items": inv.to_data() if inv != null else []}

static func from_data(d: Dictionary) -> Device:
	var dev := Device.new(String(d.type), Vector2i(int(d.x), int(d.y)))
	dev.cond = float(d.cond)
	dev.broken = bool(d.broken)
	dev.stock = float(d.stock)
	dev.charge = float(d.charge)
	if dev.inv != null:
		dev.inv.from_data(d.items)
	return dev
