## Settings (user://settings.json): simulation depth, autosave,
## meteorites. Simulation depth "simple" computes air and heat less often
## (faster on weak computers), "precise" more often.
extends Node

const PATH := "user://settings.json"
const DEPTHS := {"simple": 3.0, "normal": 1.0, "precise": 0.5}
## Older settings files: German level names
const OLD_DEPTHS := {"einfach": "simple", "genau": "precise"}

var depth := "normal"
var autosave_seconds := 60.0
var meteors := true
## Debt paused: no instalments, no penalty interest, no repossession (for testing; can be switched off in the ⚙ menu)
var debt_paused := true

func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(d) == TYPE_DICTIONARY:
			depth = String(d.get("depth", depth))
			depth = String(OLD_DEPTHS.get(depth, depth))
			autosave_seconds = float(d.get("autosave", autosave_seconds))
			meteors = bool(d.get("meteors", meteors))
			debt_paused = bool(d.get("debt_paused", debt_paused))

func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"depth": depth, "autosave": autosave_seconds, "meteors": meteors, "debt_paused": debt_paused}))
	f.close()

## Factor for batching the background simulation
func sim_factor() -> float:
	return float(DEPTHS.get(depth, 1.0))
