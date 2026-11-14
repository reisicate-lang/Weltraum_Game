## Temperature and fire.
## - Every air tile has a temperature. Heat spreads, is lost to
##   space (especially through windows) and comes from heaters and
##   generators. Vacuum is ice cold.
## - Fire needs oxygen: it uses O2, produces CO2 and heat,
##   damages devices and spreads. Without air (vacuum) it goes out.
extends Node

var _acc := 0.0

func step(dt: float) -> void:
	_acc += dt
	if _acc < 0.1 * Settings.sim_factor():
		return
	var d := _acc
	_acc = 0.0
	_simulate(d)

# Air tiles and their neighbours, classified in advance (again as soon as the grid changes):
# neighbour kind 0 = air, 1 = space, 2 = window, 3 = wall
var _key := ""
var _cells := PackedInt32Array()
var _nb := PackedInt32Array()     ## 4 neighbours per air tile (-1 = none)
var _kind := PackedByteArray()

func _prepare(g: ShipGrid) -> void:
	var key := "%d:%d" % [g.get_instance_id(), hash(g.tiles)]
	if key == _key:
		return
	_key = key
	_cells = PackedInt32Array()
	_nb = PackedInt32Array()
	_kind = PackedByteArray()
	var w := g.width
	var n := g.tiles.size()
	for i in n:
		if not g.holds_air(i):
			g.temp[i] = Config.SPACE_TEMP
			continue
		_cells.append(i)
		for d in [1, -1, w, -w]:
			var j: int = i + d
			if j < 0 or j >= n:
				_nb.append(-1)
				_kind.append(0)
				continue
			_nb.append(j)
			if g.holds_air(j):
				_kind.append(0)
			elif g.tiles[j] == ShipGrid.Tile.SPACE:
				_kind.append(1)
			elif g.tiles[j] == ShipGrid.Tile.WINDOW:
				_kind.append(2)
			else:
				_kind.append(3)

func _simulate(dt: float) -> void:
	var g := ShipSystem.grid
	_prepare(g)
	var k_air := minf(0.2, 0.1 * dt)
	var k_space := minf(0.5, Config.HEAT_LOSS * dt * 3.0)
	var k_window := minf(0.2, Config.HEAT_LOSS * dt)
	var k_wall := minf(0.1, Config.HEAT_LOSS * dt * 0.003)   # well insulated wall
	var k_thin := minf(1.0, dt * 0.2)
	var space_t := Config.SPACE_TEMP
	for c in _cells.size():
		var i := _cells[c]
		var t := g.temp[i]
		# Thin air holds hardly any heat
		if g.o2[i] + g.n2[i] + g.co2[i] < 20.0:
			t += (space_t - t) * k_thin
		# Heat exchange with neighbours
		for e in 4:
			var j := _nb[c * 4 + e]
			if j < 0:
				continue
			match _kind[c * 4 + e]:
				0: t += (g.temp[j] - t) * k_air
				1: t += (space_t - t) * k_space
				2: t += (space_t - t) * k_window
				_: t += (space_t - t) * k_wall
		g.temp[i] = t
	# Heat sources
	for i in g.devices:
		var dev: Device = g.devices[i]
		if dev.broken:
			continue
		# A heater warms all air tiles within 5 tiles, the generator a little within 2
		var K := Config.GRID_SCALE   # the same visible area as before (5 and 2 of the large tiles)
		var radius := 5 * K if dev.type == "heater" and dev.powered else (2 * K if dev.type == "generator" and dev.producing else 0)
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
		GameState.toast("Fire on board!", "bad")
		QuestSystem.claim_damage("Fire")
		ShipConstructionSystem.place("extinguish", g.pos(i))

func extinguish(i: int) -> void:
	ShipSystem.grid.fire[i] = 0

func burning_count() -> int:
	var n := 0
	for f in ShipSystem.grid.fire:
		n += f
	return n

func _fire(g: ShipGrid, dt: float) -> void:
	# Broken generators and batteries can catch fire
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
