## Automatische Tests ohne Fenster:
##   godot --headless --path . --script res://tests/run_tests.gd
## Prüft Luft, Strom, Bedürfnisse, Bauen mit Material, Speichern/Laden.
extends SceneTree

var _failed := 0

func _check(name: String, ok: bool) -> void:
	print(("OK    " if ok else "FEHLER") + "  " + name)
	if not ok:
		_failed += 1

func _run(minutes: float) -> void:
	var gs = root.get_node("GameState")
	for i in int(minutes * 60.0):
		gs.step(1.0 / 60.0)

func _initialize() -> void:
	# Autoloads sind nach dem ersten Bild bereit
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var ship = root.get_node("ShipSystem")
	var crew = root.get_node("CrewSystem")
	var build = root.get_node("ShipConstructionSystem")
	var save = root.get_node("SaveSystem")
	var power = root.get_node("ShipPowerSystem")
	gs.new_game()

	_check("Gegenstände geladen", root.get_node("ItemSystem").items.size() >= 15)
	_check("Geräte geladen", root.get_node("ItemSystem").devices.size() >= 10)
	_check("Startschiff hat Geräte", ship.grid.devices.size() >= 10)

	# 1) Zwei Spieltage: Luft und Bedürfnisse bleiben stabil
	_run(48 * 60)
	var mira = crew.player()
	_check("Mira lebt nach 2 Tagen (Gesundheit %d)" % int(mira.health), mira.health > 50.0)
	_check("Strom läuft", not power.main_net().is_empty() and power.main_net().ok)
	var o2_ok := true
	for i in ship.grid.tiles.size():
		if ship.grid.holds_air(i) and ship.grid.o2[i] < 17.0:
			o2_ok = false
	_check("Überall genug Sauerstoff", o2_ok)

	# 2) Bauen mit Material: Wand in den Weltraum neben dem Schiff (erst Boden)
	var x0: int = (ship.grid.width - 16) / 2
	var y0: int = (ship.grid.height - 10) / 2
	var target := Vector2i(x0 + 13, y0 + 3)  # im Cockpit
	build.place("dev:bed", target)
	_run(30)
	_check("Bett im Cockpit gebaut", ship.grid.device_at(target) != null)

	# 3) Abreißen gibt Teile zurück
	build.place("remove", target)
	_run(30)
	_check("Bett abgerissen", ship.grid.device_at(target) == null)
	_check("Teile liegen herum", not ship.grid.piles.is_empty())

	# 4) Leck: Wand entfernen -> Luft entweicht
	var hole := Vector2i(x0 + 15, y0 + 2)
	ship.grid.set_tile(hole, 1)
	_run(20)
	var near: int = ship.grid.idx(Vector2i(x0 + 14, y0 + 2))
	_check("Luft entweicht durch das Loch (%.1f kPa)" % ship.grid.pressure(near), ship.grid.pressure(near) < 80.0)

	# 5) Speichern und Laden
	save.save_game(true)
	var t_before: float = gs.time
	var devs_before: int = ship.grid.devices.size()
	gs.new_game()
	save.load_game(true)
	_check("Zeit nach dem Laden gleich", absf(gs.time - t_before) < 0.001)
	_check("Geräte nach dem Laden gleich", ship.grid.devices.size() == devs_before)

	print("\n%d Fehler" % _failed)
	quit(1 if _failed > 0 else 0)
