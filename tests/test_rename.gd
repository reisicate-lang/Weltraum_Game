## Tests: renaming the ship and registering the name (Ostranauts Ship Building 1.4)
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
		print("FAIL    " + name)

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

	# 1) Renaming at the navigation console
	_check("Start: Rustbucket, registered", F.current_name == "Rustbucket" and F.registered_name == "Rustbucket")
	_check("Leerer Name abgelehnt", F.rename("   ") != "" and F.current_name == "Rustbucket")
	_check("Renaming: “Morning Star”", F.rename("  Morning Star ") == "" and F.current_name == "Morning Star" and F.registered_name == "Rustbucket")
	F.rename("X".repeat(80))
	_check("At most %d characters" % F.NAME_MAX, F.current_name.length() == F.NAME_MAX)
	F.rename("Morning Star")
	var helm = P.ship_devices("helm")[0]
	helm.broken = true
	PS.step(0.01)
	_check("Broken console: renaming locked", F.rename_block_reason() != "" and F.rename("Other") != "" and F.current_name == "Morning Star")
	helm.broken = false
	PS.step(0.01)

	# 2) Right-click menu at the console
	ui.open_object_menu(helm.pos)
	var k := -1
	for i in ui.object_menu.item_count:
		if ui.object_menu.get_item_text(i) == "Rename vessel…":
			k = ui.object_menu.get_item_id(i)
	_check("Menu entry “Rename vessel…”", k >= 0 and not ui.object_menu.is_item_disabled(ui.object_menu.get_item_index(k)))
	ui._on_object_menu(k)
	ui.object_menu.hide()
	_check("The dialog shows the current name", ui.rename_dialog != null and ui.rename_dialog.visible and ui.rename_edit.text == "Morning Star")
	ui.rename_edit.text = "Kestrel"
	ui.rename_dialog.confirmed.emit()
	ui.rename_dialog.hide()
	_check("Confirming renames", F.current_name == "Kestrel")

	# 3) Registering only at the shipyard (Ship Rating service)
	_check("Tycho: no shipyard → not registered", F.register_name() != "" and F.registered_name == "Rustbucket")
	var old_docked: String = P.docked
	P.docked = "karman"
	_check("Kármán-Ring (Werft): Name eingetragen", F.register_name() == "" and F.registered_name == "Kestrel")
	P.docked = old_docked

	# 4) Saving/loading
	F.rename("Dawn")
	var rid: String = F.registry_id
	SS.save_game()
	SS.load_game(true)
	_check("Saving/loading: the name and the register entry stay", F.current_name == "Dawn" and F.registered_name == "Kestrel")

	# 5) Hull registry ID: format like “J-YV16”, fixed
	var re := RegEx.new()
	re.compile("^[A-Z]-[A-Z]{2}[0-9]{2}$")
	_check("Hull ID %s in the format X-XX00" % rid, re.search(rid) != null)
	_check("Renaming and registering do not change it, neither does loading", F.registry_id == rid)
	F.ships.append({"id": 99, "name": "Old", "location": "tycho", "data": g.to_data()})
	var fd: Dictionary = F.to_data()
	fd.erase("registry_id")
	F.from_data(fd)
	var other: String = String(F.ships[F.ships.size() - 1].get("registry", ""))
	_check("Old save without an ID: new ones for the current and the stored ship (%s, %s)" % [F.registry_id, other], re.search(F.registry_id) != null and re.search(other) != null and other != F.registry_id)
	var ids := {}
	for n in 30:
		ids[F.new_registry_id()] = true
	_check("New IDs differ from existing ones", not ids.has(F.registry_id) and not ids.has(other))

	print("%d OK, %d failed" % [ok_count, fail_count])
	quit()
