## Tests: Schiff umbenennen und Namen registrieren (Ostranauts Ship Building 1.4)
##   godot --headless --path . --script res://tests/boot.gd -- test_rename
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _initialize() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var SS = root.get_node("SaveSystem")
	SS.slot = 953
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var F = root.get_node("FleetSystem")
	var P = root.get_node("PhysicsSystem")
	var PS = root.get_node("ShipPowerSystem")
	var ui = root.get_node("UIManager")
	var g = root.get_node("ShipSystem").grid
	PS._dirty = true
	PS.step(0.01)

	# 1) Umbenennen an der Navigationskonsole
	_check("Start: Rostlaube, registriert", F.current_name == "Rostlaube" and F.registered_name == "Rostlaube")
	_check("Leerer Name abgelehnt", F.rename("   ") != "" and F.current_name == "Rostlaube")
	_check("Umbenennen: „Morning Star“", F.rename("  Morning Star ") == "" and F.current_name == "Morning Star" and F.registered_name == "Rostlaube")
	F.rename("X".repeat(80))
	_check("Höchstens %d Zeichen" % F.NAME_MAX, F.current_name.length() == F.NAME_MAX)
	F.rename("Morning Star")
	var helm = P.ship_devices("helm")[0]
	helm.broken = true
	PS.step(0.01)
	_check("Kaputte Konsole: Umbenennen gesperrt", F.rename_block_reason() != "" and F.rename("Other") != "" and F.current_name == "Morning Star")
	helm.broken = false
	PS.step(0.01)

	# 2) Rechtsklick-Menü an der Konsole
	ui.open_object_menu(helm.pos)
	var k := -1
	for i in ui.object_menu.item_count:
		if ui.object_menu.get_item_text(i) == "Rename vessel…":
			k = ui.object_menu.get_item_id(i)
	_check("Menüeintrag „Rename vessel…“", k >= 0 and not ui.object_menu.is_item_disabled(ui.object_menu.get_item_index(k)))
	ui._on_object_menu(k)
	ui.object_menu.hide()
	_check("Dialog zeigt den aktuellen Namen", ui.rename_dialog != null and ui.rename_dialog.visible and ui.rename_edit.text == "Morning Star")
	ui.rename_edit.text = "Kestrel"
	ui.rename_dialog.confirmed.emit()
	ui.rename_dialog.hide()
	_check("Bestätigen benennt um", F.current_name == "Kestrel")

	# 3) Registrieren nur an der Werft (Ship Rating service)
	_check("Tycho: keine Werft → nicht registriert", F.register_name() != "" and F.registered_name == "Rostlaube")
	var old_docked: String = P.docked
	P.docked = "karman"
	_check("Kármán-Ring (Werft): Name eingetragen", F.register_name() == "" and F.registered_name == "Kestrel")
	P.docked = old_docked

	# 4) Speichern/Laden
	F.rename("Dawn")
	SS.save_game()
	SS.load_game(true)
	_check("Speichern/Laden: Name und Registereintrag bleiben", F.current_name == "Dawn" and F.registered_name == "Kestrel")

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
