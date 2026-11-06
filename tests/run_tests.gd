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
		# Nur Räume mit Druck zählen (der Außensteg ist absichtlich Vakuum)
		if ship.grid.holds_air(i) and ship.grid.pressure(i) > 50.0 and ship.grid.o2[i] < 17.0:
			o2_ok = false
	_check("Überall genug Sauerstoff", o2_ok)

	# 2) Bauen mit Material (Wrack weg, sonst holt Mira Stoff aus dem Wrack)
	root.get_node("SalvageSystem").clear()
	var x0: int = (ship.grid.width - 16) / 2
	var y0: int = (ship.grid.height - 10) / 2
	var target := Vector2i(x0 + 13, y0 + 3)  # im Cockpit
	build.place("dev:bed", target)
	_run(10)
	_check("Bett ohne Stoff wird nicht gebaut (Material fehlt)", ship.grid.device_at(target) == null)
	build.place("cancel", target)
	build.place("dev:crate", target)
	_run(30)
	_check("Frachtkiste im Cockpit gebaut", ship.grid.device_at(target) != null)

	# 3) Abreißen gibt Teile zurück
	build.place("remove", target)
	_run(30)
	_check("Kiste abgerissen", ship.grid.device_at(target) == null)
	_check("Teile liegen herum", not ship.grid.piles.is_empty())

	# 4) Leck: Wand entfernen -> Luft entweicht
	var hole := Vector2i(x0 + 15, y0 + 2)
	ship.grid.set_tile(hole, 1)
	_run(20)
	var near: int = ship.grid.idx(Vector2i(x0 + 14, y0 + 2))
	_check("Luft entweicht durch das Loch (%.1f kPa)" % ship.grid.pressure(near), ship.grid.pressure(near) < 80.0)

	# 5) Außeneinsatz: Boden draußen neben dem Steg bauen -> Raumanzug, Schleuse
	gs.new_game()
	root.get_node("DamageSystem").effects.clear()
	var steg := Vector2i(x0 - 5, y0 + 4)
	build.place("floor", steg)
	mira = crew.player()
	var saw_suit := false
	var saw_wait := false
	for k in 60 * 12:
		gs.step(1.0 / 60.0)
		if mira.suit != null:
			saw_suit = true
		if mira.waiting:
			saw_wait = true
	_check("Mira zieht einen Raumanzug an", saw_suit)
	_check("Mira wartet an der Schleuse", saw_wait)
	_check("Boden draußen gebaut", ship.grid.get_tile(steg) == 1)
	_run(10)
	_check("Mira legt den Anzug danach ab", mira.suit == null)
	_check("Mira ist gesund (%d)" % int(mira.health), mira.health > 80.0)
	var inside: int = ship.grid.idx(Vector2i(x0 + 4, y0 + 6))
	_check("Schiff hat noch Druck (%d kPa)" % int(ship.grid.pressure(inside)), ship.grid.pressure(inside) > 85.0)

	# 6) Gerät versetzen
	var charger_from := Vector2i(x0 + 2, y0 + 8)
	var charger_to := Vector2i(x0 + 6, y0 + 7)
	build.place_move(charger_from, charger_to)
	_run(5)
	_check("Ladestation versetzt", ship.grid.device_at(charger_to) != null and ship.grid.device_at(charger_to).type == "charger")

	# 7) Meteoriteneinschläge und automatische Reparatur
	var dmg = root.get_node("DamageSystem")
	for k in 8:
		dmg.strike()
	var damaged := 0
	for i in ship.grid.tiles.size():
		if ship.grid.cond[i] < 100.0 and ship.grid.zone[i] == 0 and ship.grid.tiles[i] >= 2:
			damaged += 1
	_check("Einschläge beschädigen die Hülle (%d Felder)" % damaged, damaged > 0)
	_run(120)
	var still := 0
	for i in ship.grid.tiles.size():
		if ship.grid.cond[i] < Config.AUTO_REPAIR_AT and ship.grid.tiles[i] >= 2 and ship.grid.zone[i] == 0:
			still += 1
	_check("Stark Beschädigtes wurde repariert (übrig: %d)" % still, still == 0)

	# 8) Bergung und Handel: Wrack ausschlachten, einsammeln, verkaufen
	gs.new_game()
	var econ = root.get_node("EconomySystem")
	var salv = root.get_node("SalvageSystem")
	_check("Wrack erzeugt: " + salv.wreck_name, salv.wreck_name != "")
	var wreck_devs: Array = []
	for i in ship.grid.devices:
		if ship.grid.zone[i] == 1 and ship.grid.devices[i].type != "crate":
			wreck_devs.append(ship.grid.pos(i))
	_check("Wrack hat Geräte (%d)" % wreck_devs.size(), wreck_devs.size() >= 3)
	for p in wreck_devs.slice(0, 3):
		build.place("remove", p)
	_run(60)
	var wreck_piles: Array = []
	for i in ship.grid.piles:
		if ship.grid.zone[i] == 1:
			wreck_piles.append(ship.grid.pos(i))
	_check("Abgerissene Wrackteile liegen herum (%d Haufen)" % wreck_piles.size(), wreck_piles.size() > 0)
	for p in wreck_piles:
		build.place("haul", p)
	_run(150)
	var left := 0
	for i in ship.grid.piles:
		if ship.grid.zone[i] == 1:
			left += 1
	_check("Haufen eingesammelt (übrig: %d)" % left, left <= 1)
	var term = econ.terminal()
	var moved := 0
	for dev in ship.grid.devices.values():
		if dev.type == "crate" and ship.grid.zone[ship.grid.idx(dev.pos)] == 0:
			for it in dev.inv.items.duplicate():
				if it.type in ["scrap", "plate", "copper", "motor", "circuit", "cell", "pipe"]:
					moved += dev.inv.move_to(term.inv, it.type, it.qty)
	var cr0: int = econ.credits
	econ.sell_all()
	_check("Verkauf bringt Geld (%d -> %d Cr)" % [cr0, econ.credits], econ.credits > cr0)
	econ.buy("fuelcan", 1)
	_check("Kaufen legt Ware ins Terminal", term.inv.count("fuelcan") >= 1)
	var old_name: String = salv.wreck_name
	econ.credits = 5000
	econ.buy_claim()
	_check("Neues Bergungsrecht: neues Wrack", salv.wreck_name != "" and econ.credits == 5000 - Config.CLAIM_FEE)
	econ.credits = 0
	gs.time = econ.next_payment + 0.01
	econ.step(0.0)
	_check("Verpasste Rate wird gezählt", econ.strikes == 1)
	econ.credits = 2000

	# 9) Werkbank: Schrott einschmelzen
	var bench_crate = null
	for dev in ship.grid.devices.values():
		if dev.type == "crate" and ship.grid.zone[ship.grid.idx(dev.pos)] == 0:
			bench_crate = dev
	bench_crate.inv.add("scrap", 6, 50.0)
	var crafted := [false]
	root.get_node("EventBus").toast.connect(func(t, _k): if t.begins_with("Werkbank"): crafted[0] = true)
	econ.craft("plate")
	_run(60)
	_check("Werkbank hat eine Platte hergestellt", crafted[0])

	# 10) Speichern und Laden
	save.save_game(true)
	var t_before: float = gs.time
	var devs_before: int = ship.grid.devices.size()
	gs.new_game()
	save.load_game(true)
	_check("Zeit nach dem Laden gleich", absf(gs.time - t_before) < 0.001)
	_check("Geräte nach dem Laden gleich", ship.grid.devices.size() == devs_before)
	_check("Geld nach dem Laden gleich", econ.credits == 2000 and econ.strikes == 1)

	print("\n%d Fehler" % _failed)
	quit(1 if _failed > 0 else 0)
