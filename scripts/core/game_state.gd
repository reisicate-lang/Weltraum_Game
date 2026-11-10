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
	StationSystem.reset()
	ShipSystem.create_start_ship()
	ShipConstructionSystem.jobs.clear()
	EconomySystem.reset()
	PhysicsSystem.reset()
	FleetSystem.reset()
	SalvageSystem.clear()
	CrewSystem.create_start_crew()
	NPCSystem.reset()
	WaterSystem.reset()
	QuestSystem.reset()
	GoalSystem.reset()
	DialogueSystem.reset()
	# Erst die Station an die Schleuse, dann das Wrack (es weicht der Station aus)
	StationSystem.build(PhysicsSystem.docked)
	SalvageSystem.generate()
	# Standard-Lebenslauf für Mira (im Startbildschirm änderbar)
	var mira := CrewSystem.player()
	CharacterSystem.begin(mira)
	CharacterSystem.apply_career(mira, "school")
	CharacterSystem.apply_career(mira, "shipyard")
	CharacterSystem.choose_hobby(mira, "tinkering")
	EconomySystem.credits += CharacterSystem.start_credits(mira)
	selected = mira
	EventBus.game_loaded.emit()
	EventBus.ship_changed.emit()

## Ein Simulationsschritt (dt in Spielminuten)
func step(dt: float) -> void:
	time += dt
	PhysicsSystem.step(dt)
	ShipPowerSystem.step(dt)
	AirlockSystem.step(dt)
	OxygenSystem.step(dt)
	AtmosphereSystem.step(dt)
	TemperatureSystem.step(dt)
	WaterSystem.step(dt)
	DamageSystem.step(dt)
	CrewSystem.step(dt)
	StationSystem.step(dt)
	EconomySystem.step(dt)
	QuestSystem.step(dt)
	GoalSystem.step(dt)

func clock_text() -> String:
	var secs := int((Config.START_MINUTES + time) * 60.0)
	var day := secs / 86400 + 1
	return "Tag %d  %02d:%02d:%02d" % [day, (secs / 3600) % 24, (secs / 60) % 60, secs % 60]

func toast(text: String, kind: String = "") -> void:
	EventBus.toast.emit(text, kind)
