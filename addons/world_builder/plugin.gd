@tool
extends EditorPlugin

const DEVICE = preload("res://scripts/design/design_device.gd")
var dock: VBoxContainer
var status: Label
var autosave: CheckBox
var designs: ItemList
var components: OptionButton
var timer: Timer
var known_hashes := {}
var component_paths: Array[String] = []
const BACKUPS := "user://design_backups/"

func _enter_tree() -> void:
	dock = VBoxContainer.new()
	dock.name = "Schiffe und Orte"
	designs = ItemList.new()
	designs.custom_minimum_size = Vector2(230, 180)
	designs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock.add_child(designs)
	_refresh()
	designs.item_activated.connect(func(index): EditorInterface.open_scene_from_path(designs.get_item_metadata(index)))
	var help := Label.new()
	help.text = "Ort doppelklicken. Terrain zum Malen auswählen.\nKacheln: Boden · Wand · Tür · Fenster\nCables zum Verlegen von Kabeln auswählen.\nGeräte verschieben oder mit Strg+D duplizieren.\nRaster: 16 px. Speichern: Strg+S."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(help)
	components = OptionButton.new()
	for file in DirAccess.get_files_at("res://resources/components"):
		if file.ends_with(".tres"):
			component_paths.append("res://resources/components/" + file)
			components.add_item(file.get_basename())
	dock.add_child(components)
	var add_button := Button.new()
	add_button.text = "Gerät hinzufügen"
	add_button.pressed.connect(_add_device)
	dock.add_child(add_button)
	autosave = CheckBox.new()
	autosave.text = "Automatisch speichern (30 Sekunden)"
	autosave.button_pressed = true
	dock.add_child(autosave)
	var save := Button.new()
	save.text = "Alle Szenen speichern und sichern"
	save.pressed.connect(_save_designs)
	dock.add_child(save)
	var backup := Button.new()
	backup.text = "Sicherungsordner öffnen"
	backup.pressed.connect(func(): OS.shell_open(ProjectSettings.globalize_path(BACKUPS)))
	dock.add_child(backup)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Gespeicherte Entwürfe werden vom Spiel geladen."
	dock.add_child(status)
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)
	timer = Timer.new()
	timer.wait_time = 30
	timer.timeout.connect(func():
		if autosave.button_pressed and not EditorInterface.is_playing_scene():
			_save_designs())
	add_child(timer)
	timer.start()
	scene_saved.connect(_scene_saved)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BACKUPS))
	for index in designs.item_count:
		_scene_saved(designs.get_item_metadata(index))
	call_deferred("_open_initial")

func _open_initial() -> void:
	if not EditorInterface.get_open_scenes().has("res://designs/ships/rostlaube.tscn"):
		EditorInterface.open_scene_from_path("res://designs/ships/rostlaube.tscn")

func _refresh() -> void:
	designs.clear()
	for folder in ["ships", "places"]:
		for file in DirAccess.get_files_at("res://designs/" + folder):
			if file.ends_with(".tscn"):
				var path: String = "res://designs/" + folder + "/" + file
				designs.add_item(("Schiff · " if folder == "ships" else "Ort · ") + file.get_basename())
				designs.set_item_metadata(designs.item_count - 1, path)
				known_hashes[path] = FileAccess.get_sha256(path)

func _save_designs() -> void:
	if EditorInterface.is_playing_scene():
		return
	for path in EditorInterface.get_open_scenes():
		if path.begins_with("res://designs/") and known_hashes.has(path) and known_hashes[path] != FileAccess.get_sha256(path):
			status.text = "Datei extern geändert. Szene in Godot neu laden und prüfen: " + path.get_file()
			return
	EditorInterface.save_all_scenes()
	status.text = "Gespeichert und lokal gesichert · " + Time.get_time_string_from_system()
	_refresh()

func _scene_saved(path: String) -> void:
	if not path.begins_with("res://designs/"):
		return
	var digest := FileAccess.get_sha256(path)
	known_hashes[path] = digest
	var folder := BACKUPS + path.trim_prefix("res://designs/").get_basename() + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var target := folder + digest + ".tscn"
	if not FileAccess.file_exists(target):
		var error := DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(target))
		if error != OK:
			push_error("Design backup failed: " + error_string(error))
			status.text = "Sicherung fehlgeschlagen: " + error_string(error)

func _add_device() -> void:
	var scene := EditorInterface.get_edited_scene_root()
	if scene == null or not scene.scene_file_path.begins_with("res://designs/"):
		status.text = "Zuerst einen Schiff- oder Ortsentwurf öffnen."
		return
	var parent := scene.get_node_or_null("Devices")
	if parent == null:
		return
	var device := Node2D.new()
	device.set_script(DEVICE)
	device.component = load(component_paths[components.selected])
	device.name = device.component.id
	var terrain := scene.get_node("Terrain") as TileMapLayer
	device.position = Vector2(terrain.get_used_rect().get_center()) * 16
	var undo := get_undo_redo()
	undo.create_action("Gerät hinzufügen")
	undo.add_do_method(parent, "add_child", device, true)
	undo.add_do_property(device, "owner", scene)
	undo.add_do_reference(device)
	undo.add_undo_method(parent, "remove_child", device)
	undo.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(device)
	EditorInterface.edit_node(device)

func _exit_tree() -> void:
	remove_control_from_docks(dock)
	dock.queue_free()
	timer.queue_free()
