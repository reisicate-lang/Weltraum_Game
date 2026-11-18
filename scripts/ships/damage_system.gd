## Damage: wear of running devices, micrometeorites on the
## outer hull and automatic repair jobs.
extends Node

## Impact flashes for drawing: [{pos, start_ms}]
var effects: Array[Dictionary] = []
var _scan := 0.0

func step(dt: float) -> void:
	var g := ShipSystem.grid
	# Wear
	for i in g.devices:
		var dev: Device = g.devices[i]
		var running := (dev.needs_power() and dev.powered) or dev.producing
		if dev.data().wears and running and not dev.broken:
			var wear := Config.WEAR_PER_DAY
			dev.cond -= wear * dt / 1440.0
			if dev.cond <= 0.0:
				dev.cond = 0.0
				dev.broken = true
				if not g.foreign(i):
					GameState.toast(dev.data().display_name + " broke down!", "bad")
	# Micrometeorites
	if Settings.meteors and GameState.time / 1440.0 >= Config.FIRST_METEOR_DAY and randf() < Config.METEORS_PER_DAY * dt / 1440.0:
		strike()
	_scan -= dt
	if _scan <= 0.0:
		_scan = 1.0
		_auto_repair()

## A micrometeorite hits a random spot of the outer hull
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
	# Ostranauts: a micrometeorite strike sets fast-forward back to ×1 (a pause stays a pause)
	if TimeSystem.speed_index > 1:
		TimeSystem.set_speed(1)
	var was_door := g.tiles[i] == ShipGrid.Tile.DOOR
	g.cond[i] -= randf_range(35.0, 80.0)
	effects.append({"pos": p, "start": Time.get_ticks_msec()})
	for dev in g.devices.values():
		if absi(dev.pos.x - p.x) <= 2 * Config.GRID_SCALE and absi(dev.pos.y - p.y) <= 2 * Config.GRID_SCALE and not dev.broken:
			dev.cond = maxf(0.0, dev.cond - randf() * 30.0)
			dev.damaged = true
			if dev.cond <= 0.0:
				dev.broken = true
	# Impacts can start fires (on a neighbouring tile with air)
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
		GameState.toast("Hull breach! A micrometeorite punched a hole.", "bad")
		QuestSystem.claim_damage("Hull breach")
	else:
		GameState.toast("Micrometeorite impact! The hull is damaged.", "bad")

func needs_repair(p: Vector2i) -> bool:
	var g := ShipSystem.grid
	if not g.in_bounds(p):
		return false
	# Multi-tile device: its condition counts at the inner tile; the wall and nozzle tiles have their own
	var dev := g.device_at(p)
	if dev != null and dev.pos == p:
		return dev.cond < 100.0 and dev.data().repairable
	var t := g.get_tile(p)
	return (t == ShipGrid.Tile.WALL or t == ShipGrid.Tile.DOOR) and g.cond[g.idx(p)] < 100.0

## Components a repair needs (Ostranauts Salvaging 3.2): worn = only time and work;
## damaged = its most valuable component other than plates, plus scrap
## (wiki: "keep motors and scrap stockpiled to repair" RCS thrusters)
func repair_parts(dev: Device) -> Dictionary:
	if dev == null or not dev.damaged:
		return {}
	var best := ""
	var c := dev.data().cost
	for t in c:
		if t != "plate" and ItemSystem.item(t) != null and (best == "" or ItemSystem.item(t).value > ItemSystem.item(best).value):
			best = t
	if best == "":
		best = "plate"
	return {best: 1, "scrap": 1}

func parts_text(dev: Device) -> String:
	var parts: PackedStringArray = []
	var need := repair_parts(dev)
	for t in need:
		parts.append("%d× %s" % [int(need[t]), ItemSystem.item(t).display_name])
	return ", ".join(parts)

func repair(p: Vector2i) -> void:
	var g := ShipSystem.grid
	var dev := g.device_at(p)
	if dev != null and dev.pos == p:
		dev.cond = 100.0
		dev.broken = false
		dev.damaged = false
	else:
		g.cond[g.idx(p)] = 100.0
		g.temp_seal.erase(g.idx(p))   # a repaired "Ripley" seal becomes a proper wall

func _auto_repair() -> void:
	var g := ShipSystem.grid
	var CS := ShipConstructionSystem
	for i in g.tiles.size():
		var t := g.tiles[i]
		if g.foreign(i):
			continue  # Wrecks and stations are not repaired
		if (t == ShipGrid.Tile.WALL or t == ShipGrid.Tile.DOOR) and g.cond[i] < Config.AUTO_REPAIR_AT and not CS.jobs.has(i):
			CS.place("repair", g.pos(i))
	for i in g.devices:
		if not g.foreign(i) and g.devices[i].cond < Config.AUTO_REPAIR_AT and g.devices[i].data().repairable and not CS.jobs.has(i):
			CS.place("repair", g.pos(i))
	CS.scan_refills()
