## Automatische Tests ohne Fenster:
##   godot --headless --path . --script res://tests/boot.gd -- run_tests
## Prüft Luft, Strom, Bedürfnisse, Bauen mit Material, Speichern/Laden.
extends "res://tests/test_base.gd"

var _failed := 0

func _check(name: String, ok: bool) -> void:
	print(("OK    " if ok else "FEHLER") + "  " + name)
	if not ok:
		_failed += 1

func _run(minutes: float) -> void:
	var gs = root.get_node("GameState")
	for i in int(minutes * 60.0):
		gs.step(1.0 / 60.0)

## Lange Phasen schneller: 5 Spielsekunden pro Schritt (statt 1). Nur für
## Ruhe- und Arbeitsphasen, nicht für Flugbahn-Prüfungen.
func _run_coarse(minutes: float, step_s: float = 5.0) -> void:
	var gs = root.get_node("GameState")
	for i in int(minutes * 60.0 / step_s):
		gs.step(step_s / 60.0)

func _initialize() -> void:
	# Autoloads sind nach dem ersten Bild bereit
	await process_frame
	await process_frame
	# Eigener Speicherplatz: Tests überschreiben keine echten Spielstände und laufen parallel
	root.get_node("SaveSystem").slot = 901
	# Diese Tests prüfen auch die (vorübergehend abgeschaltete) Station und das Wrack
	Config.ENABLE_STATION = true
	Config.ENABLE_WRECK = true
	var gs = root.get_node("GameState")
	var ship = root.get_node("ShipSystem")
	var crew = root.get_node("CrewSystem")
	var build = root.get_node("ShipConstructionSystem")
	var save = root.get_node("SaveSystem")
	var power = root.get_node("ShipPowerSystem")
	# Meteoriten werden in test_systems geprüft; hier stören sie die Stabilitätsprüfung
	root.get_node("Settings").meteors = false
	gs.new_game()

	_check("Gegenstände geladen", root.get_node("ItemSystem").items.size() >= 15)
	_check("Geräte geladen", root.get_node("ItemSystem").devices.size() >= 10)
	_check("Startschiff hat Geräte", ship.grid.devices.size() >= 10)

	# 1) Zwei Spieltage: Luft und Bedürfnisse bleiben stabil
	_run_coarse(48 * 60, 15.0)   # zwei Tage Stabilität: grobe Schritte reichen
	var mira = crew.player()
	_check("Mira lebt nach 2 Tagen (Gesundheit %d)" % int(mira.health), mira.health > 50.0)
	_check("Strom läuft", not power.main_net().is_empty() and power.main_net().ok)
	var o2_ok := true
	for i in ship.grid.tiles.size():
		# Nur das eigene Schiff mit Druck zählen (Wrack und Station haben eigene Luft)
		if ship.grid.zone[i] == 0 and ship.grid.holds_air(i) and ship.grid.pressure(i) > 50.0 and ship.grid.o2[i] < 17.0:
			o2_ok = false
	_check("Überall genug Sauerstoff", o2_ok)

	# 2) Bauen mit Material (Wrack weg, sonst holt Mira Stoff aus dem Wrack)
	root.get_node("SalvageSystem").clear()
	var x0: int = (ship.grid.width / Config.GRID_SCALE - 16) / 2
	var y0: int = (ship.grid.height / Config.GRID_SCALE - 10) / 2
	var target := C(x0 + 13, y0 + 3)  # im Cockpit
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

	# 4) Leck: Außenwand oben im Cockpit entfernen -> Luft entweicht
	# (rechts liegt die angedockte Station direkt an der Wand)
	var hole := C(x0 + 14, y0)
	ship.grid.set_tile(hole, 1)
	_run(20)
	var near: int = ship.grid.idx(C(x0 + 14, y0 + 1))
	_check("Luft entweicht durch das Loch (%.1f kPa)" % ship.grid.pressure(near), ship.grid.pressure(near) < 80.0)

	# 5) Außeneinsatz: Boden draußen vor der Luftschleuse bauen -> Raumanzug, Schleuse
	gs.new_game()
	root.get_node("DamageSystem").effects.clear()
	root.get_node("StationSystem").clear()   # an der Luftschleuse hängt sonst die Station
	var steg := C(x0 - 3, y0 + 7) + Vector2i(-1, 0)   # direkt vor der Außentür der Luftschleuse
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
	var inside: int = ship.grid.idx(C(x0 + 4, y0 + 6))
	_check("Schiff hat noch Druck (%d kPa)" % int(ship.grid.pressure(inside)), ship.grid.pressure(inside) > 85.0)

	# 6) Gerät versetzen
	var charger_from := C(x0 + 2, y0 + 8)
	var charger_to := C(x0 + 6, y0 + 7)
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
	_run_coarse(120)
	var still := 0
	for i in ship.grid.tiles.size():
		if ship.grid.cond[i] < Config.AUTO_REPAIR_AT and ship.grid.tiles[i] >= 2 and ship.grid.zone[i] == 0:
			still += 1
	_check("Stark Beschädigtes wurde repariert (übrig: %d)" % still, still == 0)

	# 8) Bergung und Handel: Wrack ausschlachten, einsammeln, verkaufen
	gs.new_game()
	var econ = root.get_node("EconomySystem")
	var salv = root.get_node("SalvageSystem")
	# Ein Port: Station lösen, Wrack ankoppeln (sonst liegt es als eigenes Ziel neben Tycho)
	root.get_node("StationSystem").clear()
	salv.generate()
	_check("Wrack erzeugt: " + salv.wreck_name, salv.wreck_name != "")
	var wreck_devs: Array = []
	for i in ship.grid.devices:
		if ship.grid.zone[i] == 1 and ship.grid.devices[i].type != "crate":
			wreck_devs.append(ship.grid.pos(i))
	_check("Wrack hat Geräte (%d)" % wreck_devs.size(), wreck_devs.size() >= 3)
	for p in wreck_devs.slice(0, 3):
		build.place("remove", p)
	_run_coarse(60)
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
	var sites_before: int = root.get_node("FleetSystem").sites.size()
	econ.buy_claim()
	_check("Neues Bergungsrecht: neues Wrackziel neben der Station", root.get_node("FleetSystem").sites.size() == sites_before + 1 and econ.credits == 5000 - Config.CLAIM_FEE)
	econ.credits = 0
	root.get_node("Settings").debt_paused = false
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
	root.get_node("EventBus").toast.connect(func(t, _k): if t.begins_with("Workbench"): crafted[0] = true)
	econ.craft("plate")
	_run_coarse(60)
	_check("Werkbank hat eine Platte hergestellt", crafted[0])

	# 10) Raumflug: abdocken, Umlaufbahn, Schub, andocken, reisen, Flotte, Absturz
	var phys = root.get_node("PhysicsSystem")
	var fleet = root.get_node("FleetSystem")
	_run(0.1)
	_check("Angedockt an Tycho, Steuerpult hat Strom", phys.docked == "tycho" and phys.helm_ok())
	_check("Schub vorhanden (%d kN)" % int(phys.max_thrust()), phys.max_thrust() >= 80.0)
	var wreck_before: String = salv.wreck_name
	seat_pilot()   # Pilot am Steuerpult (Flugbefehle nur dort)
	_check("Abdocken klappt", phys.undock())
	_check("Wrack bleibt beim Abdocken an Tycho", salv.wreck_name == "")
	var moon := Vector2(60000, 0)
	var d0: float = phys.pos.distance_to(moon)
	_run_coarse(120)
	_check("Schiff bleibt im Mondorbit (%d km statt %d km)" % [int(phys.pos.distance_to(moon)), int(d0)], absf(phys.pos.distance_to(moon) - d0) < 400.0)
	var f0: float = phys.fuel()
	var v0: Vector2 = phys.vel
	phys.helm_at = phys.ship_devices("helm")[0].pos   # Pilot steht am Steuerpult
	phys.thrust = 1.0
	_run(1)
	phys.thrust = 0.0
	_check("Schub verändert die Geschwindigkeit (%.3f km/s)" % (phys.vel - v0).length(), (phys.vel - v0).length() > 0.05)
	_check("Schub verbraucht Treibstoff (%.1f)" % (f0 - phys.fuel()), f0 - phys.fuel() > 1.0)
	# nah heran, angleichen, andocken
	var tp: Dictionary = phys.rel_to("tycho")
	phys.pos = tp.pos + Vector2(0.1, 0)
	phys.vel = tp.vel + Vector2(0.03, 0)
	# Nase gegen die Flugrichtung (wie ein Pilot mit Q/E), dann angleichen: Haupttriebwerk bremst mit
	phys.angle = PI
	phys.ang_vel = 0.0
	phys.match_target = "tycho"
	_run(0.5)
	_check("Geschwindigkeit angeglichen (%.4f km/s)" % phys.rel_to("tycho").speed, phys.rel_to("tycho").speed < 0.006)
	# nach dem Angleichen langsam heranschweben (wie mit kurzem Schub)
	phys.pos = phys.rel_to("tycho").pos + Vector2(0.1, 0)
	phys.angle = phys.dock_alignment("tycho").angle   # Schleuse zum Ziel drehen
	_check("Manuell angedockt", phys.dock("tycho"))
	_check("Wrack nicht mehr an Tycho, sondern eigenes Ziel (%s)" % wreck_before, salv.wreck_name == "" and fleet.sites.any(func(x): return x.wreck_name == wreck_before))
	# Schnellreise
	var info: Dictionary = phys.travel_info("karman")
	seat_pilot()   # Pilot am Steuerpult (Flugbefehle nur dort)
	phys.travel_to("karman")
	_run_coarse(info.secs / 60.0 + 1.0)
	_check("Schnellreise zum Kármán-Ring", phys.docked == "karman")
	_check("Handel am Kármán-Ring möglich", econ.terminal_online())
	_check("Crew lebt nach der Reise (%d)" % int(crew.player().health), crew.player().health > 50.0)
	# Flotte
	econ.credits = 50000
	fleet.buy("lumen")
	_check("Shuttle gekauft", fleet.ships.size() == 1)
	fleet.switch_to(int(fleet.ships[0].id))
	_check("An Bord der Lumen", fleet.current_name == "Shuttle Lumen")
	_run(2)
	_check("Lumen: Steuerpult und Triebwerk laufen", phys.helm_ok() and phys.max_thrust() > 0.0)
	_check("Mira atmet auf der Lumen (%d)" % int(crew.player().needs.air), crew.player().needs.air > 90.0)
	fleet.switch_to(int(fleet.ships[0].id))
	_check("Zurück auf der Rostlaube", fleet.current_name == "Rustbucket")
	_run(0.1)
	seat_pilot()   # Pilot am Steuerpult (Flugbefehle nur dort)
	phys.travel_to("debris")
	_run(phys.travel_info("debris").secs / 60.0 + 30.0)
	_check("Im Trümmerfeld gibt es ein Gratis-Wrack", phys.docked == "debris" and salv.wreck_name != "")
	_check("Im Trümmerfeld kein Handel", not econ.terminal_online())

	# 11) Speichern und Laden
	var credits_before: int = econ.credits
	save.save_game(true)
	var t_before: float = gs.time
	var devs_before: int = ship.grid.devices.size()
	gs.new_game()
	save.load_game(true)
	_check("Zeit nach dem Laden gleich", absf(gs.time - t_before) < 0.001)
	_check("Geräte nach dem Laden gleich", ship.grid.devices.size() == devs_before)
	_check("Geld nach dem Laden gleich", econ.credits == credits_before)
	_check("Ort nach dem Laden gleich", phys.docked == "debris" and fleet.ships.size() == 1)

	# 12) Absturz: Schiff knapp über der Erde ohne Geschwindigkeit
	phys.docked = ""
	phys.pos = Vector2(7000, 0)
	phys.vel = Vector2.ZERO
	var over := [false]
	econ.game_over.connect(func(_t, _x): over[0] = true)
	_run(30)
	_check("Absturz an der Erde", phys.crashed and over[0])

	print("\n%d Fehler" % _failed)
	quit(1 if _failed > 0 else 0)
