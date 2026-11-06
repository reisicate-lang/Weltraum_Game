## Speichern und Laden als JSON-Datei (user://savegame.json).
## Autosave jede Minute (echte Zeit).
extends Node

var _autosave := 0.0

func _process(delta: float) -> void:
	_autosave += delta
	if _autosave >= 60.0:
		_autosave = 0.0
		save_game(true)

func save_game(silent: bool = false) -> bool:
	var data := {
		"version": Config.SAVE_VERSION,
		"time": GameState.time,
		"ship": ShipSystem.grid.to_data(),
		"crew": CrewSystem.to_data(),
		"jobs": ShipConstructionSystem.to_data(),
		"economy": EconomySystem.to_data(),
	}
	var f := FileAccess.open(Config.SAVE_PATH, FileAccess.WRITE)
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
	return FileAccess.file_exists(Config.SAVE_PATH)

func load_game(silent: bool = false) -> bool:
	if not has_save():
		if not silent:
			GameState.toast("Es gibt noch keinen Spielstand.")
		return false
	var text := FileAccess.get_file_as_string(Config.SAVE_PATH)
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
	GameState.selected = CrewSystem.player()
	EventBus.game_loaded.emit()
	EventBus.ship_changed.emit()
	if not silent:
		GameState.toast("Spielstand geladen.")
	return true
