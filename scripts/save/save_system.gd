## Speichern und Laden als JSON-Datei (user://savegame.json).
## Autosave jede Minute (echte Zeit).
extends Node

var _autosave := 0.0
## Aktueller Speicherplatz (1–3)
var slot := 1

func path(s: int = -1) -> String:
	return "user://savegame_%d.json" % (slot if s < 0 else s)

func _process(delta: float) -> void:
	_autosave += delta
	if _autosave >= Settings.autosave_seconds:
		_autosave = 0.0
		save_game(true)

## Kurzinfo zu einem Speicherplatz (für das Menü)
func slot_info(s: int) -> String:
	if not FileAccess.file_exists(path(s)):
		return "leer"
	var d = JSON.parse_string(FileAccess.get_file_as_string(path(s)))
	if typeof(d) != TYPE_DICTIONARY:
		return "beschädigt"
	return "Tag %d · %d Cr · %s" % [int(float(d.time) / 1440.0) + 1, int(d.economy.credits), String(d.fleet.current_name)]

func save_game(silent: bool = false) -> bool:
	var data := {
		"version": Config.SAVE_VERSION,
		"time": GameState.time,
		"ship": ShipSystem.grid.to_data(),
		"crew": CrewSystem.to_data(),
		"jobs": ShipConstructionSystem.to_data(),
		"economy": EconomySystem.to_data(),
		"physics": PhysicsSystem.to_data(),
		"fleet": FleetSystem.to_data(),
		"wastewater": WaterSystem.wastewater,
		"quests": QuestSystem.to_data(),
	}
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f == null:
		if not silent:
			GameState.toast("Speichern hat nicht geklappt.", "bad")
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	if not silent:
		GameState.toast("Spiel gespeichert.")
	return true

func has_save() -> bool:
	return FileAccess.file_exists(path())

func load_game(silent: bool = false) -> bool:
	if not has_save():
		if not silent:
			GameState.toast("Es gibt noch keinen Spielstand.")
		return false
	var text := FileAccess.get_file_as_string(path())
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != Config.SAVE_VERSION:
		if not silent:
			GameState.toast("Der Spielstand passt nicht zu dieser Version.", "bad")
		return false
	GameState.time = float(data.time)
	ShipSystem.grid = ShipGrid.from_data(data.ship)
	CrewSystem.from_data(data.crew)
	ShipConstructionSystem.from_data(data.jobs)
	EconomySystem.from_data(data.economy)
	PhysicsSystem.from_data(data.physics)
	FleetSystem.from_data(data.fleet)
	WaterSystem.wastewater = float(data.get("wastewater", 0.0))
	if data.has("quests"):
		QuestSystem.from_data(data.quests)
	GameState.selected = CrewSystem.player()
	EventBus.game_loaded.emit()
	EventBus.ship_changed.emit()
	if not silent:
		GameState.toast("Spielstand geladen.")
	return true
