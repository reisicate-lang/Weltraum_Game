## Lädt alle Gegenstände (ItemData) und Geräte (DeviceData) aus den
## Resource-Ordnern. Neue Sorten brauchen keine Code-Änderung:
## einfach eine .tres-Datei in den Ordner legen.
extends Node

const ITEM_DIR := "res://resources/items/"
const DEVICE_DIR := "res://resources/components/"

var items: Dictionary = {}    ## id -> ItemData
var devices: Dictionary = {}  ## id -> DeviceData

func _ready() -> void:
	_load_dir(ITEM_DIR, items)
	_load_dir(DEVICE_DIR, devices)
	# Mods: eigene .tres-Dateien in user://mods/items/ und user://mods/components/
	_load_dir("user://mods/items/", items, true)
	_load_dir("user://mods/components/", devices, true)

func _load_dir(path: String, into: Dictionary, optional: bool = false) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		if not optional:
			push_error("Folder missing: " + path)
		return
	for file in dir.get_files():
		# Im exportierten Spiel heißen die Dateien *.tres.remap
		var f := file.trim_suffix(".remap")
		if not f.ends_with(".tres"):
			continue
		var res = load(path + f)
		if res != null and "id" in res:
			into[res.id] = res

func item(id: String) -> ItemData:
	return items.get(id)

func device(id: String) -> DeviceData:
	return devices.get(id)

func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in cost:
		parts.append("%d× %s" % [cost[k], item(k).display_name])
	return "Cost: " + ", ".join(parts)
