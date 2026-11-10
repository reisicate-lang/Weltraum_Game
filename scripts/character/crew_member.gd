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
## --- Charakterentwicklung ---
var skills: Dictionary = {}         ## skill_id -> {"p": Prozent, "xp": Erfahrung, "hist": [...]}
var traits: Array[String] = []
var hobbies: Array[String] = []
var recent_actions: Dictionary = {} ## Aktion -> kürzlich geübte Minuten (Wiederholung bringt weniger)
var last_trained := ""
var stress := 10.0                  ## 0 = entspannt, 100 = Zusammenbruch
var body_temp := 37.0               ## Körpertemperatur in °C
var relations: Dictionary = {}      ## andere Crew-ID (Text) -> Beziehung -100..100
var age := 18
var history: Array[String] = []     ## Lebenslauf
var contacts: Array[String] = []
var enemies: Array[String] = []
var salary := 0                     ## Credits pro Tag (Crew)
var away_until := 0.0               ## auf der Station unterwegs bis (Spielzeit)
## Aufgabenverteilung: welche Arbeiten dieser Charakter übernimmt
## Auto-Modus: wählt die Figur selbst Aufträge, Bedürfnisse und Freizeit? (Standard: an)
var auto_mode := true
var work_prefs := {"build": true, "repair": true, "remove": true, "haul": true, "refill": true, "craft": true, "hack": true, "eva": true}
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
	return grid().holds_air(i) and grid().o2[i] >= Config.O2_LOW and grid().fire[i] == 0 and grid().temp[i] < 50.0

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
		# Unterbrochenes Einsammeln: die Sachen bleiben im Gepäck
		if job.kind == "haul" and job.phase == "deliver":
			ShipConstructionSystem.jobs.erase(grid().idx(ShipConstructionSystem.pos_of(job)))
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

## Auto-Modus ein- oder ausschalten.
## Aus: sofort anhalten. Laufender Auftrag wird über die vorhandene Abbruchlogik
## freigegeben (bleibt offen, Fortschritt und bezahltes Material bleiben beim Auftrag,
## getragene Geräte werden abgestellt), Freizeit/Bedürfnis-Gang und Laufweg verworfen.
## Ein: sofort alle verfügbaren Aufträge neu bewerten.
func set_auto(on: bool) -> void:
	if auto_mode == on:
		return
	auto_mode = on
	if not on:
		release_job()
		if activity != null and not activity.has("flee"):
			stop_activity()
		order = null
		path.clear()
		waiting = false
		task = "Steht – Auto-Modus aus"
	else:
		_search_cooldown = 0.0
		for j in ShipConstructionSystem.jobs.values():
			if j.claimed_by == -1:
				j.retry_at = 0.0

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
	var move := Config.WALK_SPEED * dt * move_factor()
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

## Tempo-Faktor: im Vakuum (Schwerelosigkeit draußen) langsamer, außer man kann es
func move_factor() -> float:
	var g := grid()
	if g.pressure(g.idx(tile())) < 5.0:
		return clampf(0.6 + SkillSystem.effect(self, "eva_speed") * 0.8, 0.6, 1.1)
	return 1.0

## Direkte Steuerung mit WASD (dist in Feldern)
func manual_move(dir: Vector2, dist: float) -> void:
	if unconscious or dir == Vector2.ZERO:
		return
	dist *= move_factor()
	if move_factor() < 1.0 or grid().pressure(grid().idx(tile())) < 5.0:
		SkillSystem.train(self, "eva_move", dist / Config.WALK_SPEED * 2.0)
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
		var bat_f := 0.7 if SkillSystem.mastered(self, "eva") else 1.0
		suit.battery = maxf(0.0, suit.battery - Config.SUIT_BATTERY_USE * dt * bat_f)
		if in_suit:
			suit.o2 = maxf(0.0, suit.o2 - Config.SUIT_O2_USE * dt * (1.0 - minf(0.5, SkillSystem.effect(self, "suit_o2_saving"))))
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
		needs[k] -= Config.NEEDS[k].decay * h * slow * (TraitSystem.factor(self, "hunger") if k == "food" else 1.0)
	if not sleeping:
		needs.sleep -= Config.NEEDS.sleep.decay * h
	for k in needs:
		needs[k] = clampf(needs[k], 0.0, 100.0)
	var damage := 0.0
	if needs.food <= 0.0: damage += 2.0
	if needs.water <= 0.0: damage += 4.0
	if needs.air < 25.0: damage += 600.0
	if not in_suit and g.holds_air(i) and g.co2[i] > Config.CO2_BAD: damage += 3.0
	# Körpertemperatur: Kälte (ohne Anzug), Hitze durch Feuer
	var tt: float = g.temp[i] if g.holds_air(i) else Config.SPACE_TEMP
	if in_suit or suit != null:
		tt = Config.ROOM_TEMP
	var insulation := 0.5 if inv.count("thermojacket") > 0 else 1.0
	if tt < 12.0:
		body_temp -= (12.0 - tt) / 30.0 * h * insulation
	elif tt > 45.0:
		body_temp += (tt - 45.0) / 20.0 * h
	else:
		body_temp += (37.0 - body_temp) * minf(1.0, h * 2.0)
	body_temp = clampf(body_temp, 25.0, 43.0)
	if body_temp < 35.0:
		damage += (35.0 - body_temp) * 8.0
	if body_temp > 39.5:
		damage += (body_temp - 39.5) * 15.0
	if g.fire[i] == 1:
		damage += 60.0
	damage /= TraitSystem.factor(self, "toughness")
	health = clampf(health - damage * h if damage > 0.0 else health + 1.5 * h * TraitSystem.factor(self, "recovery"), 0.0, 100.0)
	_update_stress(dt, sleeping)
	SkillSystem.decay_recent(self, dt)
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
	_warn("cold", body_temp < 35.5, display_name + " friert. Eine Heizung oder Thermojacke hilft.", body_temp > 36.5)
	if suit != null:
		var low := minf(suit.o2, suit.battery)
		_warn("suit", low < Config.SUIT_RETURN_AT, "Der Raumanzug von " + display_name + " wird knapp.", low > 60.0)

## Stress steigt bei schlechten Bedürfnissen, Gefahr und Schulden; sinkt im Schlaf und in der Freizeit
func _update_stress(dt: float, sleeping: bool) -> void:
	var h := dt / 60.0
	var rise := 0.0
	for k in ["food", "water", "sleep", "hygiene"]:
		if needs[k] < 25.0:
			rise += 4.0
	if needs.air < 60.0:
		rise += 30.0
	if health < 50.0:
		rise += 6.0
	if job != null:
		rise += 0.5
	rise /= TraitSystem.factor(self, "stress_resist")
	var fall := 4.0 if sleeping else 1.0
	# Blick aus dem Fenster beruhigt
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		if grid().get_tile(tile() + d) == ShipGrid.Tile.WINDOW:
			fall += 1.5
			break
	if activity != null and activity.get("kind", "") in ["hobby", "trainer"]:
		fall += 6.0
	stress = clampf(stress + (rise - fall) * h, 0.0, 100.0)
	if stress >= 100.0 and not _warned.get("breakdown", false):
		_warned["breakdown"] = true
		GameState.toast(display_name + " hat einen Nervenzusammenbruch und braucht Ruhe.", "bad")
		release_job()
	if stress < 60.0:
		_warned["breakdown"] = false

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
	if away_until > GameState.time:
		task = "Auf der Station unterwegs"
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
	if not suit_ok() and not safe_air(i) and (needs.air < 50.0 or g.fire[i] == 1 or g.temp[i] >= 50.0) and not (activity != null and activity.has("flee")) and _flee_cooldown <= 0.0:
		_flee_cooldown = 0.05
		release_job()
		stop_activity()
		if _start_flee():
			return
	# Auto-Modus aus: nur noch Notfall-Flucht, sonst stehen bleiben und bei Bedarf warnen
	if not auto_mode:
		if activity != null and activity.has("flee"):
			_do_activity(dt)
			return
		if activity != null:
			stop_activity()
		task = "Steht – Auto-Modus aus"
		for k in ["food", "water", "sleep", "hygiene"]:
			_warn("auto-" + k, needs[k] < Config.NEEDS[k].at, "%s: %s – der Auto-Modus ist aus." % [display_name, Config.NEEDS[k].name], needs[k] >= Config.NEEDS[k].at)
		return
	# 3) Tätigkeit (Freizeit wird für Arbeit unterbrochen)
	if activity != null and activity.get("kind", "") in ["study", "hobby", "trainer"] and _has_open_job():
		stop_activity()
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
		SalvageSystem.reveal(self)
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
				var keys := c.keys()
				for type in keys:
					var n := int(c[type])
					# Meister der Montage sparen manchmal ein Teil
					if type == keys[0] and n > 1 and SkillSystem.mastered(self, "construction") and randf() < 0.25:
						n -= 1
					var got := inv.take(type, n)
					# Einbau: genau dieses abgebaute Stück merken (Zustand, Daten)
					if job.kind == "install" and not got.is_empty():
						job.packed = got[0]
				job.paid = true
			_turn_to((Vector2(jp) + Vector2(0.5, 0.5) - pos).angle(), 0.3)
			task = ShipConstructionSystem.label(job)
			# Objekt inzwischen weg? Dann Auftrag auflösen, ohne Ergebnis
			if job.kind in RemovalSystem.KINDS and not RemovalSystem.target_ok(job):
				RemovalSystem.drop_stale(job)
				job = null
				return
			# Zerstören: einzelne Schläge statt gleichmäßigem Fortschritt
			if job.kind == "destroy":
				if RemovalSystem.work_destroy(job, self, dt):
					_finish_job()
				return
			job.progress += dt * SkillSystem.work_speed(self, job)
			SkillSystem.train_job(self, job, dt)
			if job.progress >= job.need:
				_finish_job()
			return
		else:
			release_job()
	task = "Kann keinen Bauplan erreichen" if not ShipConstructionSystem.jobs.is_empty() else "Wartet"
	if check and stress >= 95.0:
		task = "Zusammenbruch: braucht Ruhe"
		return
	if check:
		_assign_job()
		if job == null and activity == null and suit == null:
			_start_free_time()
		# Nichts zu tun: Raumanzug wieder ablegen
		if job == null and activity == null and suit != null:
			_start_device("suit_off", func(d): return d.type == "locker" and d.suit == null and not d.broken)

## Gibt es einen offenen Auftrag, den dieser Charakter übernehmen würde?
func _has_open_job() -> bool:
	for j in ShipConstructionSystem.jobs.values():
		if j.claimed_by == -1 and j.retry_at <= GameState.time and not j.get("missing", false) and work_prefs.get(_pref_of(j), true) and RemovalSystem.worker_ok(self, j):
			return true
	return false

func _pref_of(j: Dictionary) -> String:
	match j.kind:
		"build", "cable", "device": return "build"
		"tend", "harvest": return "refill"
		"extinguish": return "repair"
		"repair": return "repair"
		"remove", "uninstall", "dismantle", "destroy": return "remove"
		"install": return "build"
		"haul", "move": return "haul"
		"refill": return "refill"
		"craft": return "craft"
		"hack": return "hack"
	return "build"

## Freizeit: Lesen, Hobby, Trainingsgerät
func _start_free_time() -> void:
	if needs.sleep < 40.0 or needs.food < 50.0:
		return
	var book := SkillSystem.readable_book(self)
	if book != "":
		activity = {"kind": "study", "book": book, "timer": 0.0}
		return
	var trainer_ok := false
	for dev in grid().devices.values():
		if dev.type == "trainer" and grid().zone[grid().idx(dev.pos)] == 0:
			trainer_ok = true
	if trainer_ok and (stress > 25.0 or "fitness" in hobbies):
		if _start_device("trainer", func(d): return d.type == "trainer"):
			return
	if not hobbies.is_empty() and stress > 15.0:
		activity = {"kind": "hobby", "timer": 0.0}

func _finish_job() -> void:
	var CS := ShipConstructionSystem
	var g := grid()
	if job.kind == "haul":
		_finish_haul()
		return
	if job.kind == "hack":
		_finish_hack()
		return
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
	CS.complete(finished, tile(), self)

## Einsammeln: Haufen aufheben, in die nächste Frachtkiste im Schiff bringen
func _finish_haul() -> void:
	var CS := ShipConstructionSystem
	var g := grid()
	var src := CS.pos_of(job)
	if job.phase == "pickup":
		var pile: Inventory = g.piles.get(g.idx(src))
		if pile == null:
			CS.jobs.erase(g.idx(src))
			job = null
			return
		var carry: Array = []
		if g.zone[g.idx(src)] == 1:
			GoalSystem.junk += 1
		for it in pile.items.duplicate():
			if pile.move_to(inv, it.type, it.qty) > 0:
				carry.append(it.type)
		g.clean_piles()
		if carry.is_empty():
			GameState.toast(display_name + " kann nichts mehr tragen.")
			CS.jobs.erase(g.idx(src))
			job = null
			return
		var targets: Array = []
		for dev in g.devices.values():
			if dev.type == "crate" and g.zone[g.idx(dev.pos)] == 0:
				for t in carry:
					if dev.inv.room(t) > 0:
						targets.append(dev.pos)
						break
		var res := ShipSystem.nearest_adjacent(tile(), targets)
		if not res.ok:
			GameState.toast("Keine Frachtkiste mit freiem Platz im Schiff.", "bad")
			CS.jobs.erase(g.idx(src))
			job = null
			return
		job.carry = carry
		job.phase = "deliver"
		job.tx = res.target.x
		job.ty = res.target.y
		job.progress = 0.0
		path = res.path
		return
	var done: Dictionary = job
	job = null
	CS.jobs.erase(g.idx(src))
	var crate := g.device_at(Vector2i(int(done.tx), int(done.ty)))
	if crate != null and crate.inv != null:
		for t in done.carry:
			inv.move_to(crate.inv, t, 9999)
	if g.piles.has(g.idx(src)):
		CS.place("haul", src)

## Hacken eines verschlossenen Behälters
func _finish_hack() -> void:
	var CS := ShipConstructionSystem
	var p := CS.pos_of(job)
	CS.jobs.erase(grid().idx(p))
	job = null
	var dev := grid().device_at(p)
	if dev == null or dev.lock_level <= 0:
		return
	if SkillSystem.hack_value(self) >= SkillSystem.hack_needed(dev.lock_level):
		dev.lock_level = 0
		GameState.toast("%s hat das Schloss geknackt." % display_name)
	else:
		GameState.toast("%s scheitert am Schloss (Stufe %d). Mehr Übung in Hacken und Software nötig." % [display_name, dev.lock_level], "bad")

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
		if (j.kind == "move" or j.kind == "haul") and j.phase == "deliver":
			continue
		if not work_prefs.get(_pref_of(j), true):
			continue
		# Werkzeug nötig? Nur wer es im Gepäck hat
		if not RemovalSystem.worker_ok(self, j):
			continue
		# Ziel schon verschwunden? Auftrag auflösen
		if j.kind in RemovalSystem.KINDS and not RemovalSystem.target_ok(j):
			RemovalSystem.drop_stale(j)
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
		# Arbeit draußen im All (z. B. Boden vor der Luftschleuse bauen): Anzug nötig
		if grid().get_tile(ShipConstructionSystem.target_of(chosen)) == ShipGrid.Tile.SPACE:
			hostile = true
		if hostile and not work_prefs.get("eva", true):
			chosen.retry_at = GameState.time + 0.5
			return
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
	var akind: String = activity.get("kind", "")
	if akind == "study":
		task = "Liest: " + ItemSystem.item(activity.book).display_name
		activity.timer += dt
		SkillSystem.study(self, activity.book, dt)
		if activity.timer >= 30.0 or SkillSystem.readable_book(self) != activity.book:
			stop_activity()
		return
	if akind == "hobby":
		var names: PackedStringArray = []
		for h in hobbies:
			names.append(HobbySystem.get_hobby(h).hobby_name)
		task = "Freizeit: " + ", ".join(names)
		activity.timer += dt
		HobbySystem.practice(self, dt)
		if activity.timer >= 30.0 or stress <= 5.0:
			stop_activity()
		return
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
			"trainer":
				var w := ""
				for it in inv.items:
					w = ItemSystem.item(it.type).weapon if ItemSystem.item(it.type).weapon != "" else w
				task = "Trainiert" + (" mit Waffe" if w != "" else "")
				SkillSystem.train(self, {"armed": "train_combat_armed", "ranged": "train_shooting"}.get(w, "train_combat"), dt)
				stress = maxf(0.0, stress - 8.0 * dt / 60.0)
				if activity.timer >= 30.0:
					stop_activity()
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
					SkillSystem.train(self, "suit_maintenance", 2.0)
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
		var gain: float = def.gain
		if need == "food":
			# Kochen: Mahlzeit sättigt mehr und senkt Stress
			gain *= 1.0 + SkillSystem.effect(self, "meal_bonus")
			stress = maxf(0.0, stress - 3.0 - SkillSystem.effect(self, "meal_mood") * 15.0)
			SkillSystem.train(self, "cook", def.use_time)
		needs[need] = minf(100.0, needs[need] + gain)
		if dev.data().stock >= 0.0:
			dev.stock = maxf(0.0, dev.stock - def.use)
			if need in ["water", "hygiene"]:
				WaterSystem.add_waste(def.use)
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
		"is_player": is_player, "items": inv.to_data(), "suit": suit,
		"skills": skills, "traits": traits, "hobbies": hobbies, "stress": stress, "age": age, "history": history,
		"contacts": contacts, "enemies": enemies, "salary": salary, "work_prefs": work_prefs, "last_trained": last_trained,
		"careers": get_meta("careers", []), "body_temp": body_temp, "relations": relations, "auto": auto_mode}

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
	c.skills = d.get("skills", {})
	c.traits.assign(d.get("traits", []))
	c.hobbies.assign(d.get("hobbies", []))
	c.stress = float(d.get("stress", 10.0))
	c.age = int(d.get("age", 18))
	c.history.assign(d.get("history", []))
	c.contacts.assign(d.get("contacts", []))
	c.enemies.assign(d.get("enemies", []))
	c.salary = int(d.get("salary", 0))
	c.last_trained = String(d.get("last_trained", ""))
	if d.has("work_prefs"):
		c.work_prefs = d.work_prefs
	c.set_meta("careers", d.get("careers", []))
	c.body_temp = float(d.get("body_temp", 37.0))
	c.relations = d.get("relations", {})
	c.auto_mode = bool(d.get("auto", true))
	return c
