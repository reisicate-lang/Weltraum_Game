## Luft pro Feld. Luft verteilt sich zu den Nachbarn, Wände halten
## sie auf, geschlossene Türen fast. Grenzt Luft an den Weltraum,
## entweicht sie. Läuft gebündelt mit begrenzter Rate (Leistung).
extends Node

var _acc := 0.0

func step(dt: float) -> void:
	_acc += dt
	# Bündeln: bei 1x etwa alle 1,5 Spielsekunden, bei hoher Geschwindigkeit seltener
	var threshold := 0.025 * maxf(1.0, Config.SPEEDS[TimeSystem.speed_index] / 10.0)
	if _acc < threshold:
		return
	var d := _acc
	_acc = 0.0
	_simulate(d)

func _simulate(dt: float) -> void:
	var g := ShipSystem.grid
	var steps := dt / (1.0 / 3.0)
	var keep := pow(1.0 - Config.VENT_LOSS, steps)
	var w := g.width
	var h := g.height
	for y in h:
		for x in w:
			var i := y * w + x
			if not g.holds_air(i):
				continue
			# Rand der Welt zählt als Weltraum
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				_vent(g, i, keep)
			if x + 1 < w:
				_pair(g, i, i + 1, steps, keep)
			if y + 1 < h:
				_pair(g, i, i + w, steps, keep)
	# Paare, bei denen das linke/obere Feld keine Luft hat, aber das rechte/untere schon
	for y in h:
		for x in w:
			var i := y * w + x
			if g.holds_air(i):
				continue
			if x + 1 < w and g.holds_air(i + 1):
				_pair(g, i, i + 1, steps, keep)
			if y + 1 < h and g.holds_air(i + w):
				_pair(g, i, i + w, steps, keep)

func _flow(g: ShipGrid, a: int, b: int) -> float:
	var ta := g.tiles[a]
	var tb := g.tiles[b]
	if ta == ShipGrid.Tile.WALL or tb == ShipGrid.Tile.WALL or ta == ShipGrid.Tile.WINDOW or tb == ShipGrid.Tile.WINDOW:
		return 0.0
	var a_air := g.holds_air(a)
	var b_air := g.holds_air(b)
	if not a_air and not b_air:
		return 0.0
	var a_closed := ta == ShipGrid.Tile.DOOR and not g.door_open(a)
	var b_closed := tb == ShipGrid.Tile.DOOR and not g.door_open(b)
	if not a_air or not b_air:
		return 0.0 if (a_closed or b_closed) else -1.0  # -1 = Leck ins All
	# Schleusentüren sind ganz dicht, normale Türen haben Lüftungsschlitze
	if (a_closed and AirlockSystem.is_lock_door(a)) or (b_closed and AirlockSystem.is_lock_door(b)):
		return 0.0
	if a_closed or b_closed:
		return Config.DOOR_SLITS
	return Config.DIFFUSION

func _pair(g: ShipGrid, a: int, b: int, steps: float, keep: float) -> void:
	var k := _flow(g, a, b)
	if k == 0.0:
		return
	if k < 0.0:
		_vent(g, a if g.holds_air(a) else b, keep)
		return
	k = minf(0.25, k * steps)
	var d := (g.o2[a] - g.o2[b]) * k
	g.o2[a] -= d; g.o2[b] += d
	d = (g.n2[a] - g.n2[b]) * k
	g.n2[a] -= d; g.n2[b] += d
	d = (g.co2[a] - g.co2[b]) * k
	g.co2[a] -= d; g.co2[b] += d

func _vent(g: ShipGrid, i: int, keep: float) -> void:
	g.o2[i] *= keep; g.n2[i] *= keep; g.co2[i] *= keep

func describe(i: int) -> String:
	var g := ShipSystem.grid
	if not g.holds_air(i):
		return ""
	return "O₂ %.1f kPa · CO₂ %.2f kPa · Druck %d kPa" % [g.o2[i], g.co2[i], int(g.pressure(i))]
