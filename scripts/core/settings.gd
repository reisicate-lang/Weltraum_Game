## Einstellungen (user://settings.json): Simulationstiefe, Autosave,
## Meteoriten. Simulationstiefe "einfach" rechnet Luft und Wärme seltener
## (schneller auf schwachen Rechnern), "genau" häufiger.
extends Node

const PATH := "user://settings.json"
const DEPTHS := {"einfach": 3.0, "normal": 1.0, "genau": 0.5}

var depth := "normal"
var autosave_seconds := 60.0
var meteors := true

func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(d) == TYPE_DICTIONARY:
			depth = String(d.get("depth", depth))
			autosave_seconds = float(d.get("autosave", autosave_seconds))
			meteors = bool(d.get("meteors", meteors))

func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"depth": depth, "autosave": autosave_seconds, "meteors": meteors}))
	f.close()

## Faktor für die Bündelung der Hintergrund-Simulation
func sim_factor() -> float:
	return float(DEPTHS.get(depth, 1.0))
