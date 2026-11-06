## Hält den Zustand des laufenden Spiels und verteilt jeden
## Simulationsschritt an die einzelnen Systeme (in fester Reihenfolge).
extends Node

## vergangene Spielminuten seit Spielbeginn
var time: float = 0.0
## gewähltes Werkzeug ("select", "floor", "wall", ...)
var tool: String = "select"
## Ansicht: "normal", "air", "power"
var view: String = "normal"
var selected = null

func _ready() -> void:
	# Erst starten, wenn alle Autoloads bereit sind
	call_deferred("new_game")

func new_game() -> void:
	time = 0.0
	ShipSystem.create_start_ship()
	ShipConstructionSystem.jobs.clear()
	CrewSystem.create_start_crew()
	selected = CrewSystem.player()
	EventBus.game_loaded.emit()
	EventBus.ship_changed.emit()

## Ein Simulationsschritt (dt in Spielminuten)
func step(dt: float) -> void:
	time += dt
	ShipPowerSystem.step(dt)
	OxygenSystem.step(dt)
	AtmosphereSystem.step(dt)
	CrewSystem.step(dt)

func clock_text() -> String:
	var secs := int((Config.START_MINUTES + time) * 60.0)
	var day := secs / 86400 + 1
	return "Tag %d  %02d:%02d:%02d" % [day, (secs / 3600) % 24, (secs / 60) % 60, secs % 60]

func toast(text: String, kind: String = "") -> void:
	EventBus.toast.emit(text, kind)
