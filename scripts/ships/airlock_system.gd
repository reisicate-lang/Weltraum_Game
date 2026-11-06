## Luftschleusen: Ein kleiner geschlossener Raum mit Schleusenpumpe.
## Eine Schleusentür geht erst auf, wenn der Druck in der Schleuse zum
## Druck hinter der Tür passt. Die Pumpe speichert abgepumpte Luft.
extends Node

var locks: Array[Dictionary] = []
var door_lock: Dictionary = {}  ## Tür-Index -> {"lock": Dictionary, "outside": int}
var _dirty := true

func _ready() -> void:
	EventBus.ship_changed.connect(func(): _dirty = true)

func _rebuild() -> void:
	var g := ShipSystem.grid
	locks.clear()
	door_lock.clear()
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for start in g.devices:
		var pump: Device = g.devices[start]
		if pump.type != "pump":
			continue
		var tiles: Array[int] = []
		var seen := {start: true}
		var stack: Array[int] = [start]
		var ok := true
		while not stack.is_empty() and ok:
			var j: int = stack.pop_back()
			tiles.append(j)
			if tiles.size() > Config.AIRLOCK_MAX_SIZE:
				ok = false
				break
			for d in dirs:
				var q: Vector2i = g.pos(j) + d
				if not g.in_bounds(q) or g.get_tile(q) == ShipGrid.Tile.SPACE:
					ok = false
					break
				var n := g.idx(q)
				if g.tiles[n] == ShipGrid.Tile.FLOOR and not seen.has(n):
					seen[n] = true
					stack.append(n)
		if not ok:
			continue
		var lock := {"pump": pump, "tiles": tiles, "doors": [], "target": 0.0, "request_until": -1.0}
		for j in tiles:
			for d in dirs:
				var dp: Vector2i = g.pos(j) + d
				var di := g.idx(dp)
				if g.get_tile(dp) != ShipGrid.Tile.DOOR or door_lock.has(di):
					continue
				var op: Vector2i = dp + d
				door_lock[di] = {"lock": lock, "outside": g.idx(op) if g.in_bounds(op) else -1}
				lock.doors.append(di)
		locks.append(lock)
	_dirty = false

func ensure() -> void:
	if _dirty:
		_rebuild()

func is_lock_tile(i: int) -> bool:
	ensure()
	for l in locks:
		if i in l.tiles:
			return true
	return false

func is_lock_door(i: int) -> bool:
	ensure()
	return door_lock.has(i)

func pressure(lock: Dictionary) -> float:
	var g := ShipSystem.grid
	var s := 0.0
	for j in lock.tiles:
		s += g.pressure(j)
	return s / lock.tiles.size()

func _pump_works(lock: Dictionary) -> bool:
	return lock.pump.powered and not lock.pump.broken

## Darf jemand jetzt durch diese Tür? Wenn nicht, wird gepumpt.
func can_pass(i: int) -> bool:
	ensure()
	if not door_lock.has(i):
		return true
	var g := ShipSystem.grid
	var e: Dictionary = door_lock[i]
	var lock: Dictionary = e.lock
	if g.door_open(i):
		return true
	for d in lock.doors:
		if d != i and g.door_open(d):
			return false
	if not _pump_works(lock):
		return true  # Notöffnung ohne Pumpe
	var outside: int = e.outside
	var target := g.pressure(outside) if outside >= 0 and g.holds_air(outside) else 0.0
	lock.target = target
	lock.request_until = GameState.time + 0.1
	return absf(pressure(lock) - target) < Config.AIRLOCK_TOLERANCE

func step(dt: float) -> void:
	ensure()
	var g := ShipSystem.grid
	for lock in locks:
		if lock.request_until < GameState.time or not _pump_works(lock):
			continue
		var pump: Device = lock.pump
		var n: int = lock.tiles.size()
		var avg := pressure(lock)
		var diff: float = lock.target - avg
		if absf(diff) < 1.0:
			continue
		var amount := minf(Config.AIRLOCK_PUMP_RATE * dt, absf(diff) * n)
		if diff < 0.0:
			var f := minf(1.0, amount / maxf(0.001, avg * n))
			for j in lock.tiles:
				g.o2[j] -= g.o2[j] * f
				g.n2[j] -= g.n2[j] * f
				g.co2[j] -= g.co2[j] * f
			pump.store = minf(Config.AIRLOCK_STORE_MAX, pump.store + amount)
		else:
			var add := minf(amount, pump.store)
			pump.store -= add
			for j in lock.tiles:
				g.o2[j] += add / n * 0.21
				g.n2[j] += add / n * 0.79

func is_pumping(pump: Device) -> bool:
	ensure()
	for l in locks:
		if l.pump == pump:
			return l.request_until >= GameState.time and pump.powered
	return false
