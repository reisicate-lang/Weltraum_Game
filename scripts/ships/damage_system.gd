## Schäden: Verschleiß laufender Geräte, Mikrometeoriten auf die
## Außenhülle und automatische Reparatur-Aufträge.
extends Node

## Einschlag-Blitze zum Zeichnen: [{pos, start_ms}]
var effects: Array[Dictionary] = []
var _scan := 0.0

func step(dt: float) -> void:
	var g := ShipSystem.grid
	# Verschleiß
	for i in g.devices:
		var dev: Device = g.devices[i]
		var running := (dev.needs_power() and dev.powered) or dev.producing
		if dev.data().wears and running and not dev.broken:
			# Meister in Elektrotechnik/Maschinenbau halbieren den Verschleiß
			var wear := Config.WEAR_PER_DAY
			var tech := dev.data().tech
			if (tech == "electrical" and SkillSystem.any_mastered("electrical")) or (tech == "mechanical" and SkillSystem.any_mastered("mechanical")):
				wear *= 0.5
			dev.cond -= wear * dt / 1440.0
			if dev.cond <= 0.0:
				dev.cond = 0.0
				dev.broken = true
				if not g.foreign(i):
					GameState.toast(dev.data().display_name + " ist kaputt gegangen!", "bad")
	# Mikrometeoriten
	if Settings.meteors and GameState.time / 1440.0 >= Config.FIRST_METEOR_DAY and randf() < Config.METEORS_PER_DAY * dt / 1440.0:
		strike()
	_scan -= dt
	if _scan <= 0.0:
		_scan = 1.0
		_auto_repair()

## Ein Mikrometeorit trifft eine zufällige Stelle der Außenhülle
func strike() -> void:
	var g := ShipSystem.grid
	var hull: Array[Vector2i] = []
	for i in g.tiles.size():
		var t := g.tiles[i]
		if (t != ShipGrid.Tile.WALL and t != ShipGrid.Tile.DOOR) or g.foreign(i):
			continue
		var p := g.pos(i)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if g.get_tile(p + d) == ShipGrid.Tile.SPACE:
				hull.append(p)
				break
	if hull.is_empty():
		return
	var p: Vector2i = hull.pick_random()
	var i := g.idx(p)
	var was_door := g.tiles[i] == ShipGrid.Tile.DOOR
	g.cond[i] -= randf_range(35.0, 80.0)
	effects.append({"pos": p, "start": Time.get_ticks_msec()})
	for dev in g.devices.values():
		if absi(dev.pos.x - p.x) <= 2 * Config.GRID_SCALE and absi(dev.pos.y - p.y) <= 2 * Config.GRID_SCALE and not dev.broken:
			dev.cond = maxf(0.0, dev.cond - randf() * 30.0)
			if dev.cond <= 0.0:
				dev.broken = true
	# Einschläge können Feuer auslösen (auf einem Nachbarfeld mit Luft)
	if randf() < 0.2:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Variant = p + d
			if g.in_bounds(q) and g.holds_air(g.idx(q)) and g.pressure(g.idx(q)) > 50.0:
				TemperatureSystem.ignite(g.idx(q))
				break
	if g.cond[i] <= 0.0:
		g.set_tile(p, ShipGrid.Tile.FLOOR)
		EventBus.ship_changed.emit()
		ShipConstructionSystem.place("door" if was_door else "wall", p)
		GameState.toast("Hüllenbruch! Ein Mikrometeorit hat ein Loch geschlagen.", "bad")
		QuestSystem.claim_damage("Hüllenbruch")
	else:
		GameState.toast("Mikrometeorit-Einschlag! Die Hülle ist beschädigt.", "bad")

func needs_repair(p: Vector2i) -> bool:
	var g := ShipSystem.grid
	if not g.in_bounds(p):
		return false
	# Mehrfeld-Gerät: sein Zustand gilt am Innenfeld; Wand und Düsenfeld haben ihren eigenen
	var dev := g.device_at(p)
	if dev != null and dev.pos == p:
		return dev.cond < 100.0
	var t := g.get_tile(p)
	return (t == ShipGrid.Tile.WALL or t == ShipGrid.Tile.DOOR) and g.cond[g.idx(p)] < 100.0

func repair(p: Vector2i) -> void:
	var g := ShipSystem.grid
	var dev := g.device_at(p)
	if dev != null and dev.pos == p:
		dev.cond = 100.0
		dev.broken = false
	else:
		g.cond[g.idx(p)] = 100.0

func _auto_repair() -> void:
	var g := ShipSystem.grid
	var CS := ShipConstructionSystem
	for i in g.tiles.size():
		var t := g.tiles[i]
		if g.foreign(i):
			continue  # Wracks und Stationen werden nicht repariert
		if (t == ShipGrid.Tile.WALL or t == ShipGrid.Tile.DOOR) and g.cond[i] < Config.AUTO_REPAIR_AT and not CS.jobs.has(i):
			CS.place("repair", g.pos(i))
	for i in g.devices:
		if not g.foreign(i) and g.devices[i].cond < Config.AUTO_REPAIR_AT and not CS.jobs.has(i):
			CS.place("repair", g.pos(i))
	CS.scan_refills()
