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
## Anzugschrank: gelagerter Raumanzug {"o2", "battery"} oder null
var suit = null
## Schleusenpumpe: gespeicherte Luft (kPa)
var store := 0.0
## Wrack-Geräte sind unbekannt, bis jemand nah herangeht
var unknown := false
## Schloss: 0 = offen, 1–3 = Sicherheitsstufe (Hacken nötig)
var lock_level := 0
## Anbau und Fleischtank
var growth := 0.0
var tended_at := 0.0
var genemod := false

func _init(t: String, p: Vector2i) -> void:
	type = t
	pos = p
	var d := data()
	stock = d.stock
	if d.capacity > 0.0:
		charge = d.capacity * 0.5
	if d.storage > 0.0:
		inv = Inventory.new(INF, d.storage)
	if t == "locker":
		suit = {"o2": 100.0, "battery": 100.0}
	if t == "pump":
		store = 1000.0

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
	if unknown:
		return "Kiste · Inhalt unbekannt (näher herangehen)" if inv != null else "Unbekanntes Gerät (näher herangehen)"
	var parts: PackedStringArray = [d.display_name]
	if lock_level > 0:
		parts.append("verschlossen (Stufe %d)" % lock_level)
	if broken:
		parts.append("KAPUTT")
	elif cond < 100.0:
		parts.append("Zustand %d %%" % int(cond))
	if needs_power():
		parts.append("läuft" if powered else "kein Strom")
	if d.power > 0.0:
		parts.append("liefert %.1f kW" % d.power if producing else ("muss draußen im Vakuum stehen" if type == "solar" else "liefert nichts"))
	if type == "locker":
		parts.append("Anzug: O₂ %d %%, Akku %d %%" % [int(suit.o2), int(suit.battery)] if suit != null else "leer (Anzug ist unterwegs)")
	if type == "pump":
		parts.append("Speicher %d kPa" % int(store))
	if type in ["hydro", "autofarm", "meatvat"]:
		parts.append("Wachstum %d %%" % int(growth * 100.0) + (" · Gen-Mod" if genemod else ""))
	if type == "hydro":
		parts.append("gepflegt" if GameState.time - tended_at < 1440.0 else "braucht Pflege")
	if d.capacity > 0.0:
		parts.append("%.1f / %.0f kWh" % [charge, d.capacity])
	if d.stock >= 0.0:
		parts.append("Vorrat: %d %s" % [int(stock), d.stock_unit])
	if inv != null:
		parts.append("%d / %d L belegt" % [int(inv.volume()), int(d.storage)])
	if ShipSystem.grid != null and ShipSystem.grid.zone[ShipSystem.grid.idx(pos)] == 1:
		parts.append(SalvageSystem.estimate_text(self))
	return " · ".join(parts)

func to_data() -> Dictionary:
	return {"type": type, "x": pos.x, "y": pos.y, "cond": cond, "broken": broken, "stock": stock,
		"charge": charge, "items": inv.to_data() if inv != null else [], "suit": suit, "store": store, "unknown": unknown, "lock": lock_level,
		"growth": growth, "tended_at": tended_at, "genemod": genemod}

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
	return dev
