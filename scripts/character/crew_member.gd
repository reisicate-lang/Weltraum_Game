## Ein Charakter (Spielerfigur oder Crew). Reihenfolge, was er tut:
##   1. Laufbefehl vom Spieler
##   2. Schlechte Luft: Luft anhalten, dann fliehen
##   3. Laufende Tätigkeit (essen, schlafen, waschen ...)
##   4. Bedürfnisse erfüllen, wenn sie zu niedrig sind
##   5. Baupläne abarbeiten (Material holen, bauen)
class_name CrewMember
extends RefCounted

var id: int
var display_name: String
var color: Color
var pos := Vector2(0.5, 0.5)        ## Position in Feldern (Mitte = +0.5)
var facing := 0.0
var path: Array[Vector2i] = []
var order = null                    ## Vector2i oder null
var job = null                      ## Dictionary oder null
var fetch = null                    ## {"pos": Vector2i, "inv": Inventory} oder null
var activity = null                 ## {"need": String, "dev": Device, "timer": float} oder {"flee": true}
var needs := {"food": 85.0, "water": 80.0, "sleep": 75.0, "hygiene": 80.0, "air": 100.0}
var health := 100.0
var unconscious := false
var is_player := false
var manual_until := 0.0             ## echte Zeit (ms), bis wann von Hand gesteuert
var task := "Wartet"
var inv := Inventory.new(Config.CARRY_WEIGHT, Config.CARRY_VOLUME)
var suit = null                     ## getragener Raumanzug {"o2", "battery"} oder null
var carrying: Device = null         ## getragenes Gerät
var waiting := false                ## wartet an einer Schleuse
var _search_cooldown := 0.0
var _flee_cooldown := 0.0
var _warned := {}

func _init(i: int, n: String, c: Color, tile: Vector2i) -> void:
	id = i
	display_name = n
	color = c
	pos = Vector2(tile) + Vector2(0.5, 0.5)

func tile() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))

func grid() -> ShipGrid:
	return ShipSystem.grid

func is_next_to(p: Vector2i, reach: int = 1) -> bool:
	var t := tile()
	return absi(t.x - p.x) <= reach and absi(t.y - p.y) <= reach and t != p

## Reparaturen gehen mit langem Werkzeug auch aus 2 Feldern Entfernung
func _reach(j: Dictionary) -> int:
	return 2 if j.kind == "repair" else 1

func can_reach(p: Vector2i) -> bool:
	var t := tile()
	return absi(t.x - p.x) <= 1 and absi(t.y - p.y) <= 1

func safe_air(i: int) -> bool:
	return grid().holds_air(i) and grid().o2[i] >= Config.O2_LOW

func suit_ok() -> bool:
	return suit != null and suit.o2 > 0.0 and suit.battery > 0.0

func is_manual() -> bool:
	return is_player and Time.get_ticks_msec() < manual_until

# ---------------- Befehle ----------------

func order_move(target: Vector2i) -> bool:
	if unconscious:
		return false
	var p := ShipSystem.find_path(tile(), target)
	if p.is_empty() and tile() != target:
		return false
	release_job()
	stop_activity()
	order = target
	path = p
	return true

func release_job() -> void:
	if carrying != null:
		drop_carried()
	fetch = null
	if job != null:
		job.claimed_by = -1
	job = null
	path.clear()

func stop_activity() -> void:
	if activity != null and activity.has("dev"):
		activity.dev.claimed_by = -1
	activity = null
	path.clear()

## Getragenes Gerät in der Nähe abstellen
func drop_carried() -> void:
	var g := grid()
	var dev := carrying
	carrying = null
	if job != null and job.kind == "move":
		ShipConstructionSystem.jobs.erase(g.idx(ShipConstructionSystem.pos_of(job)))
		job = null
	var spot := ShipConstructionSystem.drop_spot(tile())
	dev.pos = spot
	g.devices[g.idx(spot)] = dev
	EventBus.ship_changed.emit()
	push_out_if_stuck()

func cancel_all() -> void:
	if job != null:
		var j: Dictionary = job
		release_job()
		ShipConstructionSystem.cancel(j)
	stop_activity()
	order = null

# ---------------- Bewegung ----------------

func _turn_to(angle: float, amount: float) -> void:
	facing = rotate_toward(facing, angle, amount)

## Läuft den Weg ab. false = Weg blockiert.
func follow_path(dt: float) -> bool:
	var g := grid()
	var move := Config.WALK_SPEED * dt
	while move > 0.0 and not path.is_empty():
		var next: Vector2i = path[0]
		if not g.walkable(next):
			return false
		var ni := g.idx(next)
		var ci := g.idx(tile())
		waiting = false
		if g.tiles[ni] == ShipGrid.Tile.DOOR and ni != ci:
			if not AirlockSystem.can_pass(ni):
				waiting = true
				return true
			g.door_open_until[ni] = GameState.time + 0.05
		if g.tiles[ci] == ShipGrid.Tile.DOOR:
			g.door_open_until[ci] = GameState.time + 0.05
		var target := Vector2(next) + Vector2(0.5, 0.5)
		var to := target - pos
		var d := to.length()
		if d > 0.0001:
			_turn_to(to.angle(), 12.0 * dt * 60.0)
		if d <= move:
			pos = target
			move -= d
			path.remove_at(0)
		else:
			pos += to / d * move
			move = 0.0
	return true

## Direkte Steuerung mit WASD (dist in Feldern)
func manual_move(dir: Vector2, dist: float) -> void:
	if unconscious or dir == Vector2.ZERO:
		return
	if order != null or job != null or activity != null:
		release_job()
		stop_activity()
		order = null
	manual_until = Time.get_ticks_msec() + 8000
	path.clear()
	dir = dir.normalized()
	facing = dir.angle()
	var g := grid()
	var r := 0.27
	var fits := func(p: Vector2) -> bool:
		for o in [Vector2(-r, -r), Vector2(r, -r), Vector2(-r, r), Vector2(r, r)]:
			var t := Vector2i(floori(p.x + o.x), floori(p.y + o.y))
			if not g.walkable(t):
				return false
			var ti := g.idx(t)
			if g.tiles[ti] == ShipGrid.Tile.DOOR and ti != g.idx(tile()):
				if not AirlockSystem.can_pass(ti):
					return false
				g.door_open_until[ti] = GameState.time + 0.05
		return true
	# Achsen getrennt: so gleitet man an Wänden entlang
	if fits.call(pos + Vector2(dir.x * dist, 0)):
		pos.x += dir.x * dist
	if fits.call(pos + Vector2(0, dir.y * dist)):
		pos.y += dir.y * dist

func push_out_if_stuck() -> void:
	var g := grid()
	var t := tile()
	if g.walkable(t):
		return
	for r in range(1, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := t + Vector2i(dx, dy)
				if g.walkable(q):
					pos = Vector2(q) + Vector2(0.5, 0.5)
					path.clear()
					return

# ---------------- Körper ----------------

func _update_body(dt: float) -> void:
	var g := grid()
	var i := g.idx(tile())
	var sleeping: bool = activity != null and activity.get("need", "") == "sleep" and path.is_empty()
	var in_suit := suit_ok()
	if suit != null:
		suit.battery = maxf(0.0, suit.battery - Config.SUIT_BATTERY_USE * dt)
		if in_suit:
			suit.o2 = maxf(0.0, suit.o2 - Config.SUIT_O2_USE * dt)
	if in_suit:
		needs.air += 30.0 * dt
	else:
		var o2 := 0.0
		if g.holds_air(i):
			var used := minf(g.o2[i], Config.BREATH_O2 * dt)
			g.o2[i] -= used
			g.co2[i] += used
			o2 = g.o2[i]
		if o2 < Config.O2_LOW:
			needs.air -= (Config.O2_LOW - o2) / Config.O2_LOW * 40.0 * dt
		else:
			needs.air += 30.0 * dt
	var h := dt / 60.0
	var slow := 0.5 if sleeping else 1.0
	for k in ["food", "water", "hygiene"]:
		needs[k] -= Config.NEEDS[k].decay * h * slow
	if not sleeping:
		needs.sleep -= Config.NEEDS.sleep.decay * h
	for k in needs:
		needs[k] = clampf(needs[k], 0.0, 100.0)
	var damage := 0.0
	if needs.food <= 0.0: damage += 2.0
	if needs.water <= 0.0: damage += 4.0
	if needs.air < 25.0: damage += 600.0
	if not in_suit and g.holds_air(i) and g.co2[i] > Config.CO2_BAD: damage += 3.0
	health = clampf(health - damage * h if damage > 0.0 else health + 1.5 * h, 0.0, 100.0)
	if not unconscious and (health <= 0.0 or needs.air < 10.0):
		unconscious = true
		release_job()
		stop_activity()
		order = null
		GameState.toast(display_name + " ist bewusstlos!", "bad")
	elif unconscious and health >= 10.0 and needs.air >= 40.0:
		unconscious = false
		GameState.toast(display_name + " ist wieder bei Bewusstsein.")
	_warn("air", needs.air < 40.0, display_name + " bekommt kaum Luft!", needs.air > 95.0)
	_warn("health", health < 30.0, display_name + " geht es sehr schlecht.", health > 50.0)
	if suit != null:
		var low := minf(suit.o2, suit.battery)
		_warn("suit", low < Config.SUIT_RETURN_AT, "Der Raumanzug von " + display_name + " wird knapp.", low > 60.0)

func _warn(key: String, cond: bool, text: String, clear: bool) -> void:
	if cond and not _warned.get(key, false):
		_warned[key] = true
		GameState.toast(text, "bad")
	if clear:
		_warned[key] = false

# ---------------- Verhalten ----------------

func update(dt: float) -> void:
	_update_body(dt)
	if unconscious:
		task = "Bewusstlos"
		return
	if is_manual():
		task = "Wird von dir gesteuert"
		return
	# 1) Laufbefehl
	if order != null:
		if path.is_empty():
			order = null
		else:
			task = "Läuft"
			if not follow_path(dt):
				path = ShipSystem.find_path(tile(), order)
				if path.is_empty():
					order = null
			return
	# 2) Schlechte Luft
	var g := grid()
	var i := g.idx(tile())
	_flee_cooldown -= dt
	if not suit_ok() and not safe_air(i) and needs.air < 50.0 and not (activity != null and activity.has("flee")) and _flee_cooldown <= 0.0:
		_flee_cooldown = 0.05
		release_job()
		stop_activity()
		if _start_flee():
			return
	# 3) Tätigkeit
	if activity != null:
		_do_activity(dt)
		return
	_search_cooldown -= dt
	var check := _search_cooldown <= 0.0
	if check:
		_search_cooldown = 0.05
		# Anzug fast leer: aufladen oder ablegen
		if suit != null and minf(suit.o2, suit.battery) < Config.SUIT_RETURN_AT and carrying == null:
			release_job()
			if suit.o2 >= Config.SUIT_RETURN_AT and _start_device("recharge", func(d): return d.type == "charger" and d.charge > 0.05):
				return
			if _start_device("suit_off", func(d): return d.type == "locker" and d.suit == null and not d.broken):
				return
		if carrying == null and _start_need():
			return
	# 5) Bauplan
	if job != null:
		var jp := ShipConstructionSystem.target_of(job)
		if not is_same(ShipConstructionSystem.jobs.get(g.idx(ShipConstructionSystem.pos_of(job))), job):
			release_job()
		elif fetch != null:
			_do_fetch(dt)
			return
		elif not path.is_empty():
			task = "Wartet auf Schleuse" if waiting else "Geht zu: " + ShipConstructionSystem.label(job)
			if not follow_path(dt):
				release_job()
			return
		elif is_next_to(jp, _reach(job)):
			if not job.paid:
				var c := ShipConstructionSystem.cost(job)
				if not ShipConstructionSystem.missing(c, inv).is_empty():
					if not _start_fetch():
						job.retry_at = GameState.time + 0.5
						release_job()
					return
				for type in c:
					inv.take(type, int(c[type]))
				job.paid = true
			_turn_to((Vector2(jp) + Vector2(0.5, 0.5) - pos).angle(), 0.3)
			task = ShipConstructionSystem.label(job)
			job.progress += dt
			if job.progress >= job.need:
				_finish_job()
			return
		else:
			release_job()
	task = "Kann keinen Bauplan erreichen" if not ShipConstructionSystem.jobs.is_empty() else "Wartet"
	if check:
		_assign_job()
		# Nichts zu tun: Raumanzug wieder ablegen
		if job == null and activity == null and suit != null:
			_start_device("suit_off", func(d): return d.type == "locker" and d.suit == null and not d.broken)

func _finish_job() -> void:
	var CS := ShipConstructionSystem
	var g := grid()
	if job.kind == "move":
		if job.phase == "pickup":
			var dev := g.device_at(CS.pos_of(job))
			if dev == null:
				CS.jobs.erase(g.idx(CS.pos_of(job)))
				job = null
				return
			g.devices.erase(g.idx(dev.pos))
			carrying = dev
			job.phase = "deliver"
			job.progress = 0.0
			EventBus.ship_changed.emit()
			var res := ShipSystem.nearest_adjacent(tile(), [CS.target_of(job)])
			if not res.ok:
				GameState.toast(display_name + " kommt nicht zum Ziel und stellt das Gerät ab.")
				drop_carried()
				return
			path = res.path
			return
		var done: Dictionary = job
		job = null
		CS.jobs.erase(g.idx(CS.pos_of(done)))
		var dst := CS.target_of(done)
		var dev2 := carrying
		carrying = null
		if g.get_tile(dst) == ShipGrid.Tile.FLOOR and g.device_at(dst) == null:
			dev2.pos = dst
			g.devices[g.idx(dst)] = dev2
			EventBus.ship_changed.emit()
		else:
			carrying = dev2
			drop_carried()
		return
	var finished: Dictionary = job
	job = null
	CS.complete(finished, tile())

## Zu einem passenden Gerät gehen (Anzugschrank, Ladestation)
func _start_device(kind: String, filter: Callable) -> bool:
	var targets: Array = []
	var by_pos := {}
	for dev in grid().devices.values():
		if filter.call(dev) and (dev.claimed_by == -1 or dev.claimed_by == id):
			targets.append(dev.pos)
			by_pos[dev.pos] = dev
	var res := ShipSystem.nearest_adjacent(tile(), targets)
	if not res.ok:
		return false
	stop_activity()
	var dev: Device = by_pos[res.target]
	dev.claimed_by = id
	activity = {"kind": kind, "dev": dev, "timer": 0.0}
	path = res.path
	return true

func _assign_job() -> void:
	var CS := ShipConstructionSystem
	var targets: Array = []
	var by_pos := {}
	for j in CS.jobs.values():
		if j.claimed_by != -1 and j.claimed_by != id:
			continue
		if j.retry_at > GameState.time:
			continue
		if j.kind == "move" and j.phase == "deliver":
			continue
		var ok := true
		var c := CS.cost(j)
		for type in c:
			if inv.count(type) + CS.available(type) < int(c[type]):
				ok = false
		j.missing = not ok
		if not ok:
			continue
		var p := CS.pos_of(j)
		targets.append(p)
		by_pos[p] = j
	if targets.is_empty():
		return
	var res := ShipSystem.nearest_adjacent(tile(), targets)
	# Reparaturen: auch mit größerer Reichweite versuchen
	if not res.ok:
		var rep_targets: Array = targets.filter(func(p): return by_pos[p].kind == "repair")
		if not rep_targets.is_empty():
			res = ShipSystem.nearest_adjacent(tile(), rep_targets, 2)
	if not res.ok:
		for j in by_pos.values():
			j.retry_at = GameState.time + 0.5
		return
	var chosen: Dictionary = by_pos[res.target]
	# Führt der Weg durchs Vakuum? Dann erst einen Raumanzug holen.
	if not suit_ok():
		var hostile := not safe_air(grid().idx(tile()))
		for q in res.path:
			if not safe_air(grid().idx(q)):
				hostile = true
		if chosen.kind == "move":
			var tq := Vector2i(int(chosen.tx), int(chosen.ty))
			if not safe_air(grid().idx(tq)):
				hostile = true
		if hostile:
			if _start_device("suit_up", func(d): return d.type == "locker" and d.suit != null and not d.broken):
				return
			chosen.retry_at = GameState.time + 1.0
			_warn("need-suit", true, display_name + " braucht einen Raumanzug für diese Arbeit.", false)
			return
	job = chosen
	job.claimed_by = id
	path = res.path
	if not job.paid and not CS.missing(CS.cost(job), inv).is_empty():
		if not _start_fetch():
			job.retry_at = GameState.time + 0.5
			release_job()

func _start_fetch() -> bool:
	var CS := ShipConstructionSystem
	var miss := CS.missing(CS.cost(job), inv)
	var srcs: Array = []
	var by_pos := {}
	for s in CS.sources():
		for type in miss:
			if s.inv.count(type) > 0:
				srcs.append(s.pos)
				by_pos[s.pos] = s
				break
	var res := ShipSystem.nearest_adjacent(tile(), srcs)
	if not res.ok:
		return false
	fetch = by_pos[res.target]
	path = res.path
	return true

func _do_fetch(dt: float) -> void:
	var CS := ShipConstructionSystem
	if not path.is_empty():
		task = "Holt Material"
		if not follow_path(dt):
			release_job()
		return
	if not can_reach(fetch.pos):
		release_job()
		return
	var miss := CS.missing(CS.cost(job), inv)
	for type in miss:
		fetch.inv.move_to(inv, type, miss[type])
	grid().clean_piles()
	fetch = null
	if not CS.missing(CS.cost(job), inv).is_empty():
		if not _start_fetch():
			GameState.toast(display_name + ": Nicht genug Material (oder zu schwer).", "bad")
			job.retry_at = GameState.time + 1.0
			release_job()
		return
	var res := ShipSystem.nearest_adjacent(tile(), [CS.pos_of(job)])
	if not res.ok:
		release_job()
		return
	path = res.path

func _start_need() -> bool:
	var g := grid()
	var order_needs: Array = []
	for k in Config.NEEDS:
		if needs[k] < Config.NEEDS[k].at:
			order_needs.append(k)
	order_needs.sort_custom(func(a, b): return needs[a] < needs[b])
	for need in order_needs:
		var targets: Array = []
		var by_pos := {}
		for dev in g.devices.values():
			if dev.data().need == need and dev.usable() and (dev.claimed_by == -1 or dev.claimed_by == id):
				targets.append(dev.pos)
				by_pos[dev.pos] = dev
		var res := ShipSystem.nearest_adjacent(tile(), targets)
		if not res.ok:
			_warn("no-" + need, needs[need] < Config.NEEDS[need].at - 15.0,
				display_name + ": " + Config.NEEDS[need].name + ", aber nichts Passendes erreichbar.", needs[need] >= Config.NEEDS[need].at)
			continue
		release_job()
		var dev: Device = by_pos[res.target]
		dev.claimed_by = id
		activity = {"need": need, "dev": dev, "timer": 0.0}
		path = res.path
		return true
	return false

func _do_activity(dt: float) -> void:
	if activity.has("flee"):
		task = "Sucht Luft zum Atmen"
		if path.is_empty() or not follow_path(dt):
			stop_activity()
		return
	var dev: Device = activity.dev
	if grid().device_at(dev.pos) != dev:
		stop_activity()
		return
	if not path.is_empty():
		task = "Wartet auf Schleuse" if waiting else "Geht zu: " + dev.data().display_name
		if not follow_path(dt):
			stop_activity()
		return
	if not is_next_to(dev.pos):
		stop_activity()
		return
	var kind: String = activity.get("kind", "need")
	if kind != "need":
		activity.timer += dt
		match kind:
			"suit_up":
				task = "Zieht Raumanzug an"
				if dev.suit == null:
					stop_activity()
				elif activity.timer >= 0.5:
					suit = dev.suit
					dev.suit = null
					stop_activity()
					_search_cooldown = 0.0
			"suit_off":
				task = "Zieht Raumanzug aus"
				if dev.suit != null or suit == null:
					stop_activity()
				elif activity.timer >= 0.5:
					dev.suit = suit
					suit = null
					stop_activity()
			"recharge":
				task = "Lädt Anzug"
				if suit == null:
					stop_activity()
					return
				var add := minf(Config.SUIT_CHARGE * dt, 100.0 - suit.battery)
				var kwh := add / 100.0 * Config.SUIT_KWH_PER_100
				if dev.charge < kwh:
					stop_activity()
					return
				dev.charge -= kwh
				suit.battery += add
				if suit.battery >= 99.9:
					stop_activity()
		return
	if not dev.usable():
		stop_activity()
		return
	var need: String = activity.need
	var def: Dictionary = Config.NEEDS[need]
	task = def.verb
	activity.timer += dt
	if need == "sleep":
		needs.sleep = minf(100.0, needs.sleep + def.gain / 60.0 * dt)
		if needs.sleep >= 100.0:
			stop_activity()
		return
	if activity.timer >= def.use_time:
		needs[need] = minf(100.0, needs[need] + def.gain)
		if dev.data().stock >= 0.0:
			dev.stock = maxf(0.0, dev.stock - def.use)
		stop_activity()

func _start_flee() -> bool:
	var g := grid()
	var targets: Array = []
	var t := tile()
	for r in range(1, 25):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := t + Vector2i(dx, dy)
				if g.in_bounds(q) and g.walkable(q) and g.o2[g.idx(q)] >= Config.O2_OK:
					targets.append(q)
		if targets.size() > 4:
			break
	for q in targets:
		var p := ShipSystem.find_path(t, q)
		if not p.is_empty():
			activity = {"flee": true}
			path = p
			return true
	task = "Keine Atemluft erreichbar!"
	return false

# ---------------- Speichern ----------------

func to_data() -> Dictionary:
	return {"id": id, "name": display_name, "color": color.to_html(), "x": pos.x, "y": pos.y,
		"needs": needs.duplicate(), "health": health, "unconscious": unconscious,
		"is_player": is_player, "items": inv.to_data(), "suit": suit}

static func from_data(d: Dictionary) -> CrewMember:
	var c := CrewMember.new(int(d.id), String(d.name), Color.html(String(d.color)), Vector2i.ZERO)
	c.pos = Vector2(float(d.x), float(d.y))
	for k in d.needs:
		c.needs[k] = float(d.needs[k])
	c.health = float(d.health)
	c.unconscious = bool(d.unconscious)
	c.is_player = bool(d.is_player)
	c.inv.from_data(d.items)
	c.suit = d.get("suit")
	return c
