## Holds the state of the running game and hands every
## simulation step to the individual systems (in a fixed order).
extends Node

## game minutes passed since the start of the game
var time: float = 0.0
## selected tool ("select", "floor", "wall", ...)
var tool: String = "select"
## view: "normal", "air", "power", "heat", "damage"
var view: String = "normal"
var selected = null

func _ready() -> void:
	# Only start once all autoloads are ready
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
	# Station at the airlock; the wreck is its own target next to Tycho
	StationSystem.build(PhysicsSystem.docked)
	if Config.ENABLE_WRECK:
		FleetSystem.add_site(PhysicsSystem.docked)
	# Default life story for Mira (can be changed on the start screen)
	var mira := CrewSystem.player()
	CharacterSystem.begin(mira)
	CharacterSystem.apply_career(mira, "shipyard")
	CharacterSystem.choose_hobby(mira, "tinkering")
	EconomySystem.credits += CharacterSystem.start_credits(mira)
	selected = mira
	EventBus.game_loaded.emit()
	EventBus.ship_changed.emit()

## One simulation step (dt in game minutes)
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
	return "Day %d  %02d:%02d:%02d" % [day, (secs / 3600) % 24, (secs / 60) % 60, secs % 60]

func toast(text: String, kind: String = "") -> void:
	EventBus.toast.emit(text, kind)
