## A character (player character or crew). Order of what it does:
##   1. walk order from the player
##   2. bad air: hold breath, then flee
##   3. ongoing activity (eating, sleeping, washing ...)
##   4. fulfil needs when they are too low
##   5. work through build plans (fetch material, build)
class_name CrewMember
extends RefCounted

var id: int
var display_name: String
var color: Color
var pos := Vector2(0.5, 0.5)        ## Position in Feldern (Mitte = +0.5)
var facing := 0.0
var path: Array[Vector2i] = []
var order = null                    ## Vector2i or null
var job = null                      ## Dictionary or null
var fetch = null                    ## {"pos": Vector2i, "inv": Inventory} or null
var activity = null                 ## {"need": String, "dev": Device, "timer": float} or {"flee": true}
var needs := {"food": 95.0, "water": 100.0, "sleep": 75.0, "hygiene": 80.0, "air": 100.0}
var health := 100.0
var unconscious := false
var is_player := false
var manual_until := 0.0             ## real time (ms) until which it is steered by hand
var manual_last := -100000.0        ## real time (ms) of the last WASD step
var resume_job = null               ## job interrupted by WASD (stays reserved for this character)
var _job_cmd := false               ## job ordered via "Resume Task" (runs even without auto mode)
var task := "Waiting"
var inv := Inventory.new(Config.CARRY_WEIGHT, Config.CARRY_VOLUME)
var suit = null                     ## worn space suit {"o2", "battery"} or null
var carrying: Device = null         ## carried device
var waiting := false                ## wartet an einer Schleuse
## --- Charakterentwicklung ---
var skills: Dictionary = {}         ## skill_id -> {"p": percent, "xp": experience, "hist": [...]}
var traits: Array[String] = []
var hobbies: Array[String] = []
var recent_actions: Dictionary = {} ## action -> recently practised minutes (repetition gives less)
var last_trained := ""
var stress := 10.0                  ## 0 = relaxed, 100 = breakdown
var body_temp := 37.0               ## body temperature in °C
var relations: Dictionary = {}      ## other crew ID (text) -> relationship -100..100
var age := 18
var history: Array[String] = []     ## Lebenslauf
var contacts: Array[String] = []
var enemies: Array[String] = []
var salary := 0                     ## credits per day (crew)
var away_until := 0.0               ## out on the station until (game time)
## work assignment: which kinds of work this character takes on
## Auto mode: does the character choose jobs, needs and free time on its own? (default: on)
var auto_mode := true
var work_prefs := {"build": true, "repair": true, "remove": true, "haul": true, "refill": true, "craft": true, "hack": true, "eva": true}
var _search_cooldown := 0.0
var _flee_cooldown := 0.0
var _warned := {}

func _init(i: int, n: String, c: Color, tile: Vector2i) -> void:
	inv.hands = true   # plus exactly one uninstalled device in the hands
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

## With a long tool, repairs also work from 2 tiles away
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

## May a walk order (click) start yet? Only MANUAL_WALK_DELAY real seconds
## after the last WASD step; an earlier click is queued until then.
func walk_ready() -> bool:
	return Time.get_ticks_msec() >= manual_last + Config.MANUAL_WALK_DELAY * 1000.0

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

## Stop remembering the interrupted job (release the reservation)
func _drop_resume() -> void:
	if resume_job != null and not is_same(job, resume_job) and int(resume_job.claimed_by) == id:
		resume_job.claimed_by = -1
	resume_job = null

## Can the interrupted job be continued? {"why": "" or a short English message, "path": path}
func resume_route() -> Dictionary:
	var CS := ShipConstructionSystem
	if resume_job == null:
		return {"why": "No interrupted task."}
	var j: Dictionary = resume_job
	if not is_same(CS.jobs.get(grid().idx(CS.pos_of(j))), j):
		return {"why": "Task is already finished or cancelled.", "gone": true}
	if j.kind in RemovalSystem.KINDS and not RemovalSystem.target_ok(j):
		return {"why": "Target was removed.", "gone": true}
	if int(j.claimed_by) != -1 and int(j.claimed_by) != id:
		return {"why": "Task was taken over by someone else.", "gone": true}
	if unconscious:
		return {"why": "Cannot work right now."}
	if not RemovalSystem.worker_ok(self, j):
		return {"why": "The right tool is missing."}
	var res := ShipSystem.nearest_adjacent(tile(), [CS.pos_of(j)], _reach(j))
	if not res.ok:
		return {"why": "Target is unreachable."}
	# Path or work site in vacuum: only with a space suit (as with the normal job choice)
	if not suit_ok():
		var hostile := not safe_air(grid().idx(tile())) or grid().get_tile(CS.target_of(j)) == ShipGrid.Tile.SPACE
		for q in res.path:
			if not safe_air(grid().idx(q)):
				hostile = true
		if hostile:
			return {"why": "A space suit is needed for this task."}
	return {"why": "", "path": res.path}

## "Resume Task": take over the same job again right away (without the walk delay after WASD).
## Empty = taken over, otherwise a short English message. Never creates a new job.
func resume_task() -> String:
	var r := resume_route()
	if r.why != "":
		if r.get("gone", false):
			resume_job = null
		return r.why
	var j: Dictionary = resume_job
	resume_job = null
	stop_activity()
	order = null
	if job != null and not is_same(job, j):
		release_job()
	job = j
	job.claimed_by = id
	job.retry_at = 0.0
	path = r.path
	_job_cmd = true
	manual_until = 0.0
	var CS := ShipConstructionSystem
	if not job.paid and not CS.missing(CS.remaining_cost(job), inv).is_empty():
		if not _start_fetch():
			job.retry_at = GameState.time + 0.5
			release_job()
			return "Materials are missing."
	return ""

func release_job() -> void:
	if carrying != null:
		drop_carried()
	fetch = null
	if job != null:
		job.claimed_by = -1
		# Interrupted hauling: the things stay in the pack
		if job.kind == "haul" and job.phase == "deliver":
			ShipConstructionSystem.jobs.erase(grid().idx(ShipConstructionSystem.pos_of(job)))
	job = null
	_job_cmd = false
	path.clear()

func stop_activity() -> void:
	if activity != null and activity.has("dev"):
		activity.dev.claimed_by = -1
	activity = null
	path.clear()

## Set a carried device down nearby
func drop_carried() -> void:
	var g := grid()
	var dev := carrying
	carrying = null
	if job != null and job.kind == "move":
		ShipConstructionSystem.jobs.erase(g.idx(ShipConstructionSystem.pos_of(job)))
		job = null
	var spot := ShipConstructionSystem.drop_spot(tile())
	dev.pos = spot
	g.put_device(dev)
	EventBus.ship_changed.emit()
	push_out_if_stuck()

## Switch auto mode on or off.
## Off: stop at once. The current job is released through the existing cancel logic
## (it stays open, progress and paid material stay with the job,
## carried devices are set down); free time/need walks and the path are dropped.
## On: re-evaluate all available jobs at once.
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
		task = "Standing – auto mode off"
	else:
		_search_cooldown = 0.0
		for j in ShipConstructionSystem.jobs.values():
			if j.claimed_by == -1:
				j.retry_at = 0.0

func cancel_all() -> void:
	_drop_resume()
	if job != null:
		var j: Dictionary = job
		release_job()
		ShipConstructionSystem.cancel(j)
	stop_activity()
	order = null

# ---------------- Bewegung ----------------

func _turn_to(angle: float, amount: float) -> void:
	facing = rotate_toward(facing, angle, amount)

## Walks the path. false = path blocked.
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

## Speed factor: slower in vacuum (weightlessness outside), unless you know how
func move_factor() -> float:
	var g := grid()
	if g.pressure(g.idx(tile())) < 5.0:
		return clampf(0.6 + SkillSystem.effect(self, "eva_speed") * 0.8, 0.6, 1.1)
	return 1.0

## Direct control with WASD (dist in tiles)
func manual_move(dir: Vector2, dist: float) -> void:
	if unconscious or dir == Vector2.ZERO:
		return
	dist *= move_factor()
	if move_factor() < 1.0 or grid().pressure(grid().idx(tile())) < 5.0:
		SkillSystem.train(self, "eva_move", dist / Config.WALK_SPEED * 2.0)
	if order != null or job != null or activity != null:
		# Remember the current job (progress stays in the job); not while carrying or delivering
		var keep = null
		if job != null and carrying == null and not (job.kind in ["haul", "move"] and job.get("phase", "") == "deliver"):
			keep = job
		release_job()
		stop_activity()
		order = null
		if keep != null:
			if not is_same(resume_job, keep):
				_drop_resume()
			resume_job = keep
			keep.claimed_by = id
	manual_last = Time.get_ticks_msec()
	manual_until = manual_last + 8000
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
	# Axes separately: this way you slide along walls
	var moved_x := false
	var moved_y := false
	if fits.call(pos + Vector2(dir.x * dist, 0)):
		pos.x += dir.x * dist
		moved_x = dir.x != 0.0
	if fits.call(pos + Vector2(0, dir.y * dist)):
		pos.y += dir.y * dist
		moved_y = dir.y != 0.0
	# Entry help for doors (1 tile wide): stuck on an edge, but the tile
	# in front is walkable → slide sideways to its centre
	if absf(dir.x) > 0.5 and not moved_x:
		var ahead := Vector2i(floori(pos.x + signf(dir.x) * (r + 0.5)), floori(pos.y))
		if g.walkable(ahead):
			var cy := float(ahead.y) + 0.5
			var ny := move_toward(pos.y, cy, dist)
			if fits.call(Vector2(pos.x, ny)):
				pos.y = ny
	if absf(dir.y) > 0.5 and not moved_y:
		var ahead := Vector2i(floori(pos.x), floori(pos.y + signf(dir.y) * (r + 0.5)))
		if g.walkable(ahead):
			var cx := float(ahead.x) + 0.5
			var nx := move_toward(pos.x, cx, dist)
			if fits.call(Vector2(nx, pos.y)):
				pos.x = nx

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

# ---------------- Body ----------------

func _update_body(dt: float) -> void:
	var g := grid()
	var i := g.idx(tile())
	var sleeping: bool = activity != null and activity.get("need", "") == "sleep" and path.is_empty()
	var in_suit := suit_ok()
	if suit != null:
		suit.battery = maxf(0.0, suit.battery - Config.SUIT_BATTERY_USE * dt)
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
		var tf := TraitSystem.factor(self, "hunger") if k == "food" else (TraitSystem.factor(self, "thirst") if k == "water" else 1.0)
		needs[k] -= Config.NEEDS[k].decay * h * slow * tf
	if not sleeping:
		needs.sleep -= Config.NEEDS.sleep.decay * h
	for k in needs:
		needs[k] = clampf(needs[k], 0.0, 100.0)
	var damage := 0.0
	if needs.food <= 0.0: damage += 2.0
	if needs.water <= 0.0: damage += 4.0
	if needs.air < 25.0: damage += 600.0
	if not in_suit and g.holds_air(i) and g.co2[i] > Config.CO2_BAD: damage += 3.0
	# Body temperature: cold (without a suit), heat from fire
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
		GameState.toast(display_name + " is unconscious!", "bad")
	elif unconscious and health >= 10.0 and needs.air >= 40.0:
		unconscious = false
		GameState.toast(display_name + " is conscious again.")
	_warn("air", needs.air < 40.0, display_name + " can barely breathe!", needs.air > 95.0)
	_warn("health", health < 30.0, display_name + " is in very bad shape.", health > 50.0)
	_warn("cold", body_temp < 35.5, display_name + " is freezing. A heater or a thermal jacket helps.", body_temp > 36.5)
	if suit != null:
		var low := minf(suit.o2, suit.battery)
		_warn("suit", low < Config.SUIT_RETURN_AT, "The space suit of " + display_name + " is running low.", low > 60.0)

## Stress rises with poor needs, danger and debt; it drops while sleeping and in free time
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
	# A look out of the window calms
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		if grid().get_tile(tile() + d) == ShipGrid.Tile.WINDOW:
			fall += 1.5
			break
	if activity != null and activity.get("kind", "") in ["hobby", "trainer"]:
		fall += 6.0
	stress = clampf(stress + (rise - fall) * h, 0.0, 100.0)
	if stress >= 100.0 and not _warned.get("breakdown", false):
		_warned["breakdown"] = true
		GameState.toast(display_name + " has a breakdown and needs rest.", "bad")
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
		task = "Unconscious"
		return
	if away_until > GameState.time:
		task = "Out on the station"
		return
	# After WASD: self-control stays off briefly, but a walk order already starts
	# after MANUAL_WALK_DELAY real seconds (a queued click then starts on its own)
	if is_manual() and order != null and UIManager.pilot != self and walk_ready():
		manual_until = 0.0
	if is_manual():
		task = "Flying the ship" if UIManager.pilot == self else ("About to walk" if order != null else "Controlled by you")
		return
	# 1) Laufbefehl
	if order != null:
		if path.is_empty():
			order = null
		else:
			task = "Walking"
			if not follow_path(dt):
				path = ShipSystem.find_path(tile(), order)
				if path.is_empty():
					order = null
			return
	# 2) bad air
	var g := grid()
	var i := g.idx(tile())
	_flee_cooldown -= dt
	if not suit_ok() and not safe_air(i) and (needs.air < 50.0 or g.fire[i] == 1 or g.temp[i] >= 50.0) and not (activity != null and activity.has("flee")) and _flee_cooldown <= 0.0:
		_flee_cooldown = 0.05
		release_job()
		stop_activity()
		if _start_flee():
			return
	# Auto mode off: only emergency escape, otherwise stand still and warn if needed
	if not auto_mode:
		if activity != null and activity.has("flee"):
			_do_activity(dt)
			return
		if activity != null:
			stop_activity()
		if job == null or not _job_cmd:
			_job_cmd = false
			task = "Standing – auto mode off"
			for k in ["food", "water", "sleep", "hygiene"]:
				_warn("auto-" + k, needs[k] < Config.NEEDS[k].at, "%s: %s – auto mode is off." % [display_name, Config.NEEDS[k].name], needs[k] >= Config.NEEDS[k].at)
			return
	# 3) activity (free time is interrupted for work)
	if activity != null and activity.get("kind", "") in ["study", "hobby", "trainer"] and _has_open_job():
		stop_activity()
	if activity != null:
		_do_activity(dt)
		return
	_search_cooldown -= dt
	var check := _search_cooldown <= 0.0
	if check:
		_search_cooldown = 0.05
		# Suit almost empty: recharge or take it off
		if suit != null and minf(suit.o2, suit.battery) < Config.SUIT_RETURN_AT and carrying == null:
			release_job()
			if suit.o2 >= Config.SUIT_RETURN_AT and _start_device("recharge", func(d): return d.type == "charger" and d.charge > 0.05):
				return
			if _start_device("suit_off", func(d): return d.type == "locker" and d.suit == null and not d.broken):
				return
		SalvageSystem.reveal(self)
		if carrying == null and auto_mode and _start_need():
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
			task = "Waiting for the airlock" if waiting else "Going to: " + ShipConstructionSystem.label(job)
			if not follow_path(dt):
				release_job()
			return
		elif is_next_to(jp, _reach(job)):
			if not job.paid:
				# Drop the material brought along at the build site (heavy parts in several trips)
				var CSy := ShipConstructionSystem
				var rem := CSy.remaining_cost(job)
				var keys := rem.keys()
				for type in keys:
					var n := mini(int(rem[type]), inv.count(type))
					if n <= 0:
						continue
					var got := inv.take(type, n)
					# Installing: remember exactly this uninstalled part (condition, data)
					if job.kind == "install" and not got.is_empty():
						job.packed = got[0]
					if not job.has("delivered"):
						job.delivered = {}
					job.delivered[type] = int(job.delivered.get(type, 0)) + n
				if not CSy.remaining_cost(job).is_empty():
					if not _start_fetch():
						job.retry_at = GameState.time + 0.5
						release_job()
					return
				# Masters of assembly sometimes save a part (it goes back into the pack)
				var all_keys := CSy.cost(job).keys()
				if not all_keys.is_empty() and int(CSy.cost(job)[all_keys[0]]) > 1 and SkillSystem.mastered(self, "construction") and randf() < 0.25:
					inv.add(all_keys[0], 1, 80.0)
				job.paid = true
			_turn_to((Vector2(jp) + Vector2(0.5, 0.5) - pos).angle(), 0.3)
			task = ShipConstructionSystem.label(job)
			# Object gone meanwhile? Then remove the job, without a result
			if job.kind in RemovalSystem.KINDS and not RemovalSystem.target_ok(job):
				RemovalSystem.drop_stale(job)
				job = null
				return
			# Destroying: single hits instead of steady progress
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
	task = "Cannot reach any build plan" if not ShipConstructionSystem.jobs.is_empty() else "Waiting"
	if check and stress >= 95.0:
		task = "Breakdown: needs rest"
		return
	if check and auto_mode:
		_assign_job()
		if job == null and activity == null and suit == null:
			_start_free_time()
		# Nothing to do: take off the space suit again
		if job == null and activity == null and suit != null:
			_start_device("suit_off", func(d): return d.type == "locker" and d.suit == null and not d.broken)

## Is there an open job this character would take?
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
		"repair", "debug": return "repair"
		"remove", "uninstall", "dismantle", "destroy": return "remove"
		"install", "rotate": return "build"
		"haul", "move": return "haul"
		"refill": return "refill"
		"craft": return "craft"
		"hack": return "hack"
	return "build"

## Free time: reading, hobby, training rig
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
			g.remove_device(dev)
			carrying = dev
			job.phase = "deliver"
			job.progress = 0.0
			EventBus.ship_changed.emit()
			var res := ShipSystem.nearest_adjacent(tile(), [CS.target_of(job)])
			if not res.ok:
				GameState.toast(display_name + " cannot reach the target and sets the device down.")
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
			g.put_device(dev2)
			EventBus.ship_changed.emit()
		else:
			carrying = dev2
			drop_carried()
		return
	var finished: Dictionary = job
	job = null
	CS.complete(finished, tile(), self)

## Hauling: pick up piles, bring them to the nearest cargo crate on the ship
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
			GameState.toast(display_name + " cannot carry any more.")
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
			GameState.toast("No cargo crate with free space on the ship.", "bad")
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

## Hacking a locked container
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
		GameState.toast("%s cracked the lock." % display_name)
	else:
		GameState.toast("%s fails at the lock (level %d). Needs more practice in Hacking and Software." % [display_name, dev.lock_level], "bad")

## Go to a suitable device (suit locker, charger)
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
		# Tool needed? Only those who have it in their pack
		if not RemovalSystem.worker_ok(self, j):
			continue
		# Target already gone? Remove the job
		if j.kind in RemovalSystem.KINDS and not RemovalSystem.target_ok(j):
			RemovalSystem.drop_stale(j)
			continue
		var ok := true
		var c := CS.remaining_cost(j)
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
	# Repairs: also try with a larger reach
	if not res.ok:
		var rep_targets: Array = targets.filter(func(p): return by_pos[p].kind == "repair")
		if not rep_targets.is_empty():
			res = ShipSystem.nearest_adjacent(tile(), rep_targets, 2)
	if not res.ok:
		for j in by_pos.values():
			j.retry_at = GameState.time + 0.5
		return
	var chosen: Dictionary = by_pos[res.target]
	# Does the path lead through vacuum? Then fetch a space suit first.
	if not suit_ok():
		var hostile := not safe_air(grid().idx(tile()))
		for q in res.path:
			if not safe_air(grid().idx(q)):
				hostile = true
		if chosen.kind == "move":
			var tq := Vector2i(int(chosen.tx), int(chosen.ty))
			if not safe_air(grid().idx(tq)):
				hostile = true
		# Work outside in space (e.g. building a floor in front of the airlock): suit needed
		if grid().get_tile(ShipConstructionSystem.target_of(chosen)) == ShipGrid.Tile.SPACE:
			hostile = true
		if hostile and not work_prefs.get("eva", true):
			chosen.retry_at = GameState.time + 0.5
			return
		if hostile:
			if _start_device("suit_up", func(d): return d.type == "locker" and d.suit != null and not d.broken):
				return
			chosen.retry_at = GameState.time + 1.0
			_warn("need-suit", true, display_name + " needs a space suit for this work.", false)
			return
	if is_same(chosen, resume_job):
		resume_job = null
	else:
		_drop_resume()
	job = chosen
	job.claimed_by = id
	path = res.path
	if not job.paid and not CS.missing(CS.remaining_cost(job), inv).is_empty():
		if not _start_fetch():
			job.retry_at = GameState.time + 0.5
			release_job()

func _start_fetch() -> bool:
	var CS := ShipConstructionSystem
	var miss := CS.missing(CS.remaining_cost(job), inv)
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
		task = "Fetching material"
		if not follow_path(dt):
			release_job()
		return
	if not can_reach(fetch.pos):
		release_job()
		return
	var miss := CS.missing(CS.remaining_cost(job), inv)
	var moved := 0
	for type in miss:
		moved += fetch.inv.move_to(inv, type, miss[type])
	grid().clean_piles()
	fetch = null
	var still := CS.missing(CS.remaining_cost(job), inv)
	# Pack full but carrying something: first go to the build site and drop it, then fetch more
	var full := moved > 0 and still.keys().all(func(t): return inv.room(t) <= 0)
	if not still.is_empty() and not full:
		if not _start_fetch():
			GameState.toast(display_name + ": not enough material (or too heavy).", "bad")
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
	# In a suit (EVA), eating and drinking only interrupt when it becomes urgent
	var margin := 30.0 if suit != null else 0.0
	for k in Config.NEEDS:
		if needs[k] < Config.NEEDS[k].at - (margin if k in ["food", "water"] else 0.0):
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
				display_name + ": " + Config.NEEDS[need].name + ", but nothing suitable is reachable.", needs[need] >= Config.NEEDS[need].at)
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
		task = "Reading: " + ItemSystem.item(activity.book).display_name
		activity.timer += dt
		SkillSystem.study(self, activity.book, dt)
		if activity.timer >= 30.0 or SkillSystem.readable_book(self) != activity.book:
			stop_activity()
		return
	if akind == "hobby":
		var names: PackedStringArray = []
		for h in hobbies:
			names.append(HobbySystem.get_hobby(h).hobby_name)
		task = "Free time: " + ", ".join(names)
		activity.timer += dt
		HobbySystem.practice(self, dt)
		if activity.timer >= 30.0 or stress <= 5.0:
			stop_activity()
		return
	if activity.has("flee"):
		task = "Looking for air to breathe"
		activity.timer = float(activity.get("timer", 0.0)) + dt
		# Already in breathable air, or too long (e.g. waiting at an airlock that does not open): end the escape
		if safe_air(grid().idx(tile())) and needs.air >= 50.0 or activity.timer > 3.0:
			stop_activity()
			return
		if path.is_empty() or not follow_path(dt):
			stop_activity()
		return
	var dev: Device = activity.dev
	if grid().device_at(dev.pos) != dev:
		stop_activity()
		return
	if not path.is_empty():
		task = "Waiting for the airlock" if waiting else "Going to: " + dev.data().display_name
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
				task = "Training" + (" with a weapon" if w != "" else "")
				SkillSystem.train(self, {"armed": "train_combat_armed", "ranged": "train_shooting"}.get(w, "train_combat"), dt)
				stress = maxf(0.0, stress - 8.0 * dt / 60.0)
				if activity.timer >= 30.0:
					stop_activity()
			"suit_up":
				task = "Putting on a space suit"
				if dev.suit == null:
					stop_activity()
				elif activity.timer >= 0.5:
					suit = dev.suit
					dev.suit = null
					stop_activity()
					_search_cooldown = 0.0
			"suit_off":
				task = "Taking off the space suit"
				if dev.suit != null or suit == null:
					stop_activity()
				elif activity.timer >= 0.5:
					dev.suit = suit
					suit = null
					SkillSystem.train(self, "suit_maintenance", 2.0)
					stop_activity()
			"recharge":
				task = "Charging suit"
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
		needs.sleep = minf(100.0, needs.sleep + def.gain / 60.0 * dt * TraitSystem.factor(self, "sleep_gain"))
		if needs.sleep >= 100.0:
			stop_activity()
		return
	if activity.timer >= def.use_time:
		var gain: float = def.gain
		if need == "food":
			# Cooking: a meal satisfies more and lowers stress
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
	task = "No breathable air within reach!"
	return false

# ---------------- Saving ----------------

func to_data() -> Dictionary:
	return {"id": id, "name": display_name, "color": color.to_html(), "x": pos.x, "y": pos.y,
		"needs": needs.duplicate(), "health": health, "unconscious": unconscious,
		"is_player": is_player, "items": inv.to_data(), "suit": suit,
		"skills": skills, "traits": traits, "hobbies": hobbies, "stress": stress, "age": age, "history": history,
		"contacts": contacts, "enemies": enemies, "salary": salary, "work_prefs": work_prefs, "last_trained": last_trained,
		"careers": get_meta("careers", []), "risk_tokens": get_meta("risk_tokens", {}), "body_temp": body_temp, "relations": relations, "auto": auto_mode}

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
	c.traits.assign(TraitSystem.migrate(d.get("traits", [])))
	c.hobbies.assign(d.get("hobbies", []))
	c.stress = float(d.get("stress", 10.0))
	c.age = int(d.get("age", 18))
	c.history.assign(d.get("history", []))
	c.contacts.assign(d.get("contacts", []))
	c.set_meta("risk_tokens", d.get("risk_tokens", {}))
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
