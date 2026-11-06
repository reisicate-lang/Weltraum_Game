## Temperatur und Feuer.
## - Jedes Luftfeld hat eine Temperatur. Wärme verteilt sich, geht an das
##   All verloren (besonders durch Fenster) und kommt von Heizungen und
##   Generatoren. Vakuum ist eiskalt.
## - Feuer braucht Sauerstoff: es verbraucht O2, erzeugt CO2 und Hitze,
##   beschädigt Geräte und springt über. Ohne Luft (Vakuum) erlischt es.
extends Node

var _acc := 0.0

func step(dt: float) -> void:
	_acc += dt
	if _acc < 0.1:
		return
	var d := _acc
	_acc = 0.0
	_simulate(d)

func _simulate(dt: float) -> void:
	var g := ShipSystem.grid
	var w := g.width
	var dirs := [1, -1, w, -w]
	for i in g.tiles.size():
		if not g.holds_air(i):
			g.temp[i] = Config.SPACE_TEMP
			continue
		var t := g.temp[i]
		# Dünne Luft hält kaum Wärme
		var p := g.pressure(i)
		if p < 20.0:
			t += (Config.SPACE_TEMP - t) * minf(1.0, dt * 0.2)
		# Wärmeaustausch mit Nachbarn
		for d in dirs:
			var j: int = i + d
			if j < 0 or j >= g.tiles.size():
				continue
			if g.holds_air(j):
				t += (g.temp[j] - t) * minf(0.2, 0.1 * dt)
			elif g.tiles[j] == ShipGrid.Tile.SPACE:
				t += (Config.SPACE_TEMP - t) * minf(0.5, Config.HEAT_LOSS * dt * 3.0)
			elif g.tiles[j] == ShipGrid.Tile.WINDOW:
				t += (Config.SPACE_TEMP - t) * minf(0.2, Config.HEAT_LOSS * dt)
			else:
				t += (Config.SPACE_TEMP - t) * minf(0.1, Config.HEAT_LOSS * dt * 0.003)  # gut gedämmte Wand
		g.temp[i] = t
	# Wärmequellen
	for i in g.devices:
		var dev: Device = g.devices[i]
		if dev.broken:
			continue
		# Heizung wärmt alle Luftfelder im Umkreis von 5 Feldern, der Generator etwas im Umkreis von 2
		var radius := 5 if dev.type == "heater" and dev.powered else (2 if dev.type == "generator" and dev.producing else 0)
		if radius == 0:
			continue
		var rate := Config.HEATER_RATE if dev.type == "heater" else 0.3
		var p := g.pos(i)
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var q := p + Vector2i(dx, dy)
				if not g.in_bounds(q):
					continue
				var j := g.idx(q)
				if g.holds_air(j) and g.pressure(j) > 20.0 and g.temp[j] < Config.ROOM_TEMP:
					g.temp[j] = minf(Config.ROOM_TEMP, g.temp[j] + rate * dt)
	_fire(g, dt)

# ---------------- Feuer ----------------

func ignite(i: int) -> void:
	var g := ShipSystem.grid
	if g.holds_air(i) and g.o2[i] >= Config.FIRE_O2_MIN and g.fire[i] == 0:
		g.fire[i] = 1
		GameState.toast("Feuer an Bord!", "bad")
		ShipConstructionSystem.place("extinguish", g.pos(i))

func extinguish(i: int) -> void:
	ShipSystem.grid.fire[i] = 0

func burning_count() -> int:
	var n := 0
	for f in ShipSystem.grid.fire:
		n += f
	return n

func _fire(g: ShipGrid, dt: float) -> void:
	# Kaputte Generatoren und Batterien können sich entzünden
	for i in g.devices:
		var dev: Device = g.devices[i]
		if dev.broken and dev.type in ["generator", "battery", "heater"] and g.zone[i] == 0 and randf() < 0.002 * dt:
			ignite(i)
	for i in g.tiles.size():
		if g.fire[i] == 0:
			continue
		if not g.holds_air(i) or g.o2[i] < Config.FIRE_O2_MIN:
			g.fire[i] = 0  # erstickt
			continue
		var burn := minf(g.o2[i], 2.0 * dt)
		g.o2[i] -= burn
		g.co2[i] += burn
		g.temp[i] = minf(300.0, g.temp[i] + 15.0 * dt)
		if g.devices.has(i):
			var dev: Device = g.devices[i]
			dev.cond = maxf(0.0, dev.cond - 5.0 * dt)
			if dev.cond <= 0.0:
				dev.broken = true
		for d in [1, -1, g.width, -g.width]:
			var j: int = i + d
			if j >= 0 and j < g.tiles.size() and g.fire[j] == 0 and g.holds_air(j) and randf() < Config.FIRE_SPREAD * dt * 60.0 / 60.0:
				ignite(j)
