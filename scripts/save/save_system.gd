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
		"xpdr": true,
		"quests": QuestSystem.to_data(),
		"goals": GoalSystem.to_data(),
		"station": StationSystem.to_data(),
		"salvage": SalvageSystem.to_data(),
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

## Früherer Spielstand (doppelt so große Felder): gespeicherte Positionen ins feine Raster.
## Das Schiff selbst hat ShipGrid.from_data schon verfeinert (coarse_map: grob -> fein).
func _upscale_positions(data: Dictionary) -> void:
	var g := ShipSystem.grid
	var cw := g.coarse_width
	for c in data.crew:
		var fp := g.fine_pos(Vector2(float(c.x), float(c.y)))
		c.x = fp.x
		c.y = fp.y
	for j in data.jobs:
		var p := g.fine_of_coarse(Vector2i(int(j.x), int(j.y)))
		j.x = p.x
		j.y = p.y
		if j.has("tx"):
			var t := g.fine_of_coarse(Vector2i(int(j.tx), int(j.ty)))
			j.tx = t.x
			j.ty = t.y
	var sv: Dictionary = data.get("salvage", {})
	if int(sv.get("port", -1)) >= 0:
		sv.port = g.coarse_map[int(sv.port)]
	if int(sv.get("ex", -1)) >= 0:
		var e := g.fine_of_coarse(Vector2i(int(sv.ex), int(sv.ey)))
		sv.ex = e.x
		sv.ey = e.y
	var st: Dictionary = data.get("station", {})
	if int(st.get("hatch", -1)) >= 0 and int(st.hatch) < g.coarse_map.size():
		st.hatch = g.coarse_map[int(st.hatch)]
	if cw > 0:
		GameState.toast("Älterer Spielstand: Raster verfeinert (jedes Feld ist jetzt 2×2 Felder).")

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
	var legacy := int(data.ship.get("scale", 1)) < Config.GRID_SCALE
	ShipSystem.grid = ShipGrid.from_data(data.ship)
	if legacy:
		_upscale_positions(data)
	CrewSystem.from_data(data.crew)
	ShipConstructionSystem.from_data(data.jobs)
	EconomySystem.from_data(data.economy)
	PhysicsSystem.from_data(data.physics)
	FleetSystem.from_data(data.fleet)
	WaterSystem.wastewater = float(data.get("wastewater", 0.0))
	if data.has("quests"):
		QuestSystem.from_data(data.quests)
	if data.has("goals"):
		GoalSystem.from_data(data.goals)
	SalvageSystem.from_data(data.get("salvage", {}))
	FleetSystem.migrate_docking()
	if not bool(data.get("xpdr", false)):
		_migrate_xpdr()
	StationSystem.from_data(data.get("station", {}))
	GameState.selected = CrewSystem.player()
	EventBus.game_loaded.emit()
	EventBus.ship_changed.emit()
	if not silent:
		GameState.toast("Spielstand geladen.")
	return true

## Ältere Spielstände: Transponder und Antenne gab es noch nicht. Fehlen sie am eigenen Schiff,
## liegen beide als einbaubare Teile an Bord (Ostranauts Ship Ownership: manche Stationen
## lassen nur Schiffe mit beidem andocken).
func _migrate_xpdr() -> void:
	var missing: PackedStringArray = []
	for t in ["transponder", "antenna"]:
		if PhysicsSystem.ship_devices(t).is_empty():
			ShipSystem.grid.drop_items(ShipSystem.spawn_point(), "pk_" + t, 1, 100.0)
			missing.append(ItemSystem.device(t).display_name)
	if not missing.is_empty():
		GameState.toast("New: %s are on board as parts. Install them (right-click a cabled floor tile) – some stations only accept ships with both." % " and ".join(missing))
