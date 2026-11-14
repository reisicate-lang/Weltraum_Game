## Space flight: the ship is a point in a scaled-down Earth–Moon system
## with position, velocity and heading. Earth and Moon pull
## on it. Thrusters accelerate in the facing direction (inertia!).
## Units: km, km/s, seconds. Data: res://data/space.json
extends Node

var space: Dictionary = {}
var locations: Array = []

## Ship state
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var angle := 0.0
var docked := "tycho"
var travel: Dictionary = {}     ## {to, t0, t1, from}
var autodock: Dictionary = {}   ## {to, t0, t1}
var match_target := ""          ## Geschwindigkeit an dieses Ziel angleichen
var thrust := 0.0               ## forward (+1) / back (-1), relative to the heading
var strafe := 0.0               ## right (+1) / left (-1), relative to the heading
var rot_input := 0.0            ## Rotation thrust: clockwise (+1) / counter-clockwise (-1)
var rot_stop := false           ## Brake the rotation (counter-thrust of the RCS)
var ang_vel := 0.0              ## Angular velocity in rad/s (kept without counter-thrust)
var target := ""                ## selected target (place) for display and docking
## Matching: current thrust input of the matching (for display and flames)
var match_input := Vector2.ZERO
## Tile of the navigation console where the pilot is standing (NO_HELM = nobody is flying).
## Only a position, no device instance; not saved.
const NO_HELM := Vector2i(-1, -1)
var helm_at := NO_HELM
var aligning := false            ## "Align": rotate onto align_angle with rotation thrust
var align_angle := 0.0
var _helm_fail_warned := false
const MATCH_DEADBAND := 0.00005  ## 0.05 m/s: below this the matching does not fire
var crashed := false
var _warned := false
## Lock against immediately docking again at the same place (technical decision):
## after undocking, no docking at this place for REDOCK_LOCK_SECS game seconds
const REDOCK_LOCK_SECS := 15.0
const UNDOCK_PUSH := 0.003          ## Push-off when undocking in km/s (3 m/s, far below collide_speed)
var undock_lock_id := ""
## The trajectory is kept in double precision internally: Vector2 only has 32 bits, at
## 60 000 km that is a ~4 m grid. Many small steps (1×) would otherwise
## add up to large errors. pos/vel stay the readable values.
var _px := 0.0
var _py := 0.0
var _vx := 0.0
var _vy := 0.0
var _p32 := Vector2.INF
var _v32 := Vector2.INF
var undock_lock_until := 0.0
var _no_fuel_warned := false


func _ready() -> void:
	var f := FileAccess.open("res://data/space.json", FileAccess.READ)
	space = JSON.parse_string(f.get_as_text())
	locations = space.locations.duplicate()

## Additional places (wrecks as their own targets, see FleetSystem.sites) on top of the fixed places
func set_extra_locations(extra: Array) -> void:
	locations = space.locations.duplicate()
	locations.append_array(extra)

func reset() -> void:
	ship_log.clear()
	prox_muted = false
	undock_lock_id = ""
	undock_lock_until = 0.0
	docked = "tycho"
	travel = {}
	autodock = {}
	match_target = ""
	stop_inputs()
	helm_at = NO_HELM
	angle = 0.0          # new game: nose forward (do not inherit it from the previous game)
	ang_vel = 0.0
	target = ""
	crashed = false
	var s := loc_state(loc("tycho"), 0.0)
	pos = s.pos
	vel = s.vel

func loc(id: String) -> Dictionary:
	for l in locations:
		if l.id == id:
			return l
	return {}

# ---------------- Nav console: PROX WARN and ship logs (Ostranauts Flying 2.1) ----------------

## Closer than this to another object → PROX WARN (km)
const PROX_KM := 5.0
const LOG_MAX := 50
var prox_muted := false
## Ship logs: docking and collision events [{t: game minutes, text}]
var ship_log: Array = []

func log_event(text: String) -> void:
	ship_log.append({"t": GameState.time, "text": text})
	if ship_log.size() > LOG_MAX:
		ship_log = ship_log.slice(ship_log.size() - LOG_MAX)

## Nearest object within 5 km while not docked: {id, name, dist} or empty
func proximity() -> Dictionary:
	if docked != "":
		return {}
	var n := nearest()
	if n.is_empty() or float(n.dist) >= PROX_KM:
		return {}
	return {"id": n.id, "name": loc(n.id).name, "dist": float(n.dist)}

## Warning text for the console ("" = no warning or muted)
func prox_warning() -> String:
	if prox_muted:
		return ""
	var p := proximity()
	return "" if p.is_empty() else "PROX WARN: %s, %.1f km" % [p.name, p.dist]

func secs() -> float:
	return GameState.time * 60.0

func _body(name: String) -> Dictionary:
	return space[name]

## Position and velocity of a place (stations orbit Earth or Moon)
func loc_state(l: Dictionary, t: float) -> Dictionary:
	# Wreck next to a place: fixed offset, moves with that place
	if l.has("near"):
		var base := loc(String(l.near))
		if not base.is_empty():
			var st := loc_state(base, t)
			return {"pos": st.pos + Vector2(float(l.off[0]), float(l.off[1])), "vel": st.vel}
	if l.has("body"):
		var b := _body(l.body)
		var r: float = l.radius
		var w := sqrt(float(b.gm) / pow(r, 3.0))
		var a: float = l.phase + w * t
		return {"pos": Vector2(b.x, b.y) + Vector2(cos(a), sin(a)) * r, "vel": Vector2(-sin(a), cos(a)) * r * w}
	return {"pos": Vector2(l.x, l.y), "vel": Vector2.ZERO}

func gravity(p: Vector2) -> Vector2:
	var a := Vector2.ZERO
	for n in ["earth", "moon"]:
		var b := _body(n)
		var d := Vector2(b.x, b.y) - p
		var r2 := d.length_squared()
		a += d.normalized() * float(b.gm) / r2
	return a

# ---------------- Ship ----------------

func ship_devices(type: String) -> Array:
	var g := ShipSystem.grid
	var out: Array = []
	for i in g.devices:
		if g.devices[i].type == type and not g.foreign(i):
			out.append(g.devices[i])
	return out

## Mass in tonnes: hull tiles (Config.TILE_MASS), devices (DeviceData.mass,
## e.g. thruster 1.5 t), cargo in containers and loose cargo on your own
## ship floor. Every piece of cargo counts exactly once: moving it between your own container
## and your own floor does not change the mass. Foreign zones (wreck, station) and
## piles in space next to the hull do not count. What a character carries aboard (pack,
## hands, a carried device) also counts exactly once – with the same
## weight as in the inventory (ItemData.weight, uninstalled devices = device mass).
## If it leaves the ship (station, wreck), its share drops out.
func mass() -> float:
	var g := ShipSystem.grid
	var m := 0.0
	for i in g.tiles.size():
		if g.tiles[i] != 0 and not g.foreign(i):
			m += float(Config.TILE_MASS.get(g.tiles[i], 0.2))
	for i in g.devices:
		if g.foreign(i):
			continue
		m += g.devices[i].data().mass
		if g.devices[i].inv != null:
			m += g.devices[i].inv.weight() / 1000.0
	for i in g.piles:
		if _own_floor(g, i):
			m += g.piles[i].weight() / 1000.0
	for c in CrewSystem.crew:
		if c.away_until > GameState.time or not g.in_bounds(c.tile()) or not _own_floor(g, g.idx(c.tile())):
			continue
		m += c.inv.weight() / 1000.0
		if c.carrying != null:
			m += c.carrying.data().mass + (c.carrying.inv.weight() / 1000.0 if c.carrying.inv != null else 0.0)
	return m

## Is a pile on your own ship floor? (own tile, not space)
func _own_floor(g: ShipGrid, i: int) -> bool:
	return not g.foreign(i) and g.tiles[i] != ShipGrid.Tile.SPACE

func fuel() -> float:
	var s := 0.0
	for t in ship_devices("fueltank"):
		if not t.broken:
			s += t.stock
	return s

func use_fuel(amount: float) -> void:
	for t in ship_devices("fueltank"):
		if amount <= 0.0:
			break
		if t.broken:
			continue
		var n := minf(t.stock, amount)
		t.stock -= n
		amount -= n

## Active thrusters: installed, powered, not broken
func active_thrusters() -> Array:
	return ship_devices("thruster").filter(func(t): return t.powered and not t.broken)

func working_thrusters() -> int:
	return active_thrusters().size()

## Available thrust of the thrusters in one direction (ship coordinates:
## (1,0) forward towards the nose, (0,1) to the right, (-1,0) backward, (0,-1) to the left).
## Thrusters facing the same way add up their thrust.
func thrust_dir(d: Vector2i) -> float:
	var s := 0.0
	for t in active_thrusters():
		if t.push_dir() == d:
			s += t.data().thrust
	return s

## Forward thrust (main thrusters)
func max_thrust() -> float:
	return thrust_dir(Vector2i(1, 0))

## Which thruster directions an input requests (ship coordinates).
## Without an argument: the current inputs (keys or matching).
func _requested(inp = null) -> Dictionary:
	var v: Vector2 = inp if inp != null else _input_now()
	return {Vector2i(1, 0): maxf(0.0, v.x), Vector2i(-1, 0): maxf(0.0, -v.x),
		Vector2i(0, 1): maxf(0.0, v.y), Vector2i(0, -1): maxf(0.0, -v.y)}

## Effective translation input: keys take priority, otherwise the matching
func _input_now() -> Vector2:
	if thrust != 0.0 or strafe != 0.0:
		return Vector2(thrust, strafe)
	return match_input

## Thrust vector in ship coordinates (kN) from thrusters and RCS for an input
func thrust_vector_local(inp = null) -> Vector2:
	var v: Vector2 = inp if inp != null else _input_now()
	var f := v * rcs_thrust()
	var req := _requested(v)
	for t in active_thrusters():
		var d: Vector2i = t.push_dir()
		if req[d] > 0.0:
			f += Vector2(d) * t.data().thrust * req[d]
	return f

## Is a thruster firing in this direction right now? (for the display)
func firing(d: Vector2i) -> bool:
	return docked == "" and manual_ok() and _requested()[d] > 0.0

## RCS: every ship has it as long as the navigation console has power
## (Ostranauts: all ships have RCS, some also have a main drive).
func rcs_thrust() -> float:
	return float(space.rcs_thrust) * pilot_factor() if helm_ok() else 0.0

## Accelerations in km/s² (main drive, RCS) = thrust (kN) ÷ mass (t) ÷ 1000
func main_accel() -> float:
	return max_thrust() / maxf(1.0, mass()) / 1000.0

## Acceleration the current inputs are producing right now (km/s², ship coordinates)
func accel_local() -> Vector2:
	return thrust_vector_local() / maxf(1.0, mass()) / 1000.0

func rcs_accel() -> float:
	return rcs_thrust() / maxf(1.0, mass()) / 1000.0

## Set all flight inputs to zero (thrust ends when leaving the controls)
func stop_inputs() -> void:
	thrust = 0.0
	strafe = 0.0
	rot_input = 0.0
	rot_stop = false
	aligning = false

## "Align": turn the ship to this direction with the RCS (brakes in time).
## Q, E or R abort it. Only at the operated, powered console.
func start_align(a: float) -> void:
	var why := pilot_block_reason()
	if why != "":
		GameState.toast(why, "bad")
		return
	align_angle = wrapf(a, -PI, PI)
	aligning = true

## Does the ship have any powered, intact navigation console? (undocking, fast travel, display)
func helm_ok() -> bool:
	for h in ship_devices("helm"):
		if h.powered and not h.broken:
			return true
	return false

## The navigation console where the pilot stands (or null)
func operated_helm() -> Device:
	if helm_at == NO_HELM:
		return null
	var g := ShipSystem.grid
	var d := g.device_at(helm_at)
	if d == null or d.type != "helm" or d.unknown or g.foreign(g.idx(helm_at)):
		return null
	return d

## Who is flying right now? The character at the operated console (your character first), otherwise null
func pilot_crew() -> CrewMember:
	var h := operated_helm()
	if h == null:
		return null
	var p := CrewSystem.player()
	if p != null and not p.unconscious and p.can_reach(h.pos):
		return p
	for c in CrewSystem.crew:
		if not c.unconscious and c.can_reach(h.pos):
			return c
	return null

## Piloting factor (1 + Piloting of the flying character): docking limits, RCS thrust, rotation
func pilot_factor() -> float:
	return 1.0 + SkillSystem.piloting(pilot_crew())

## Rotational acceleration while steering (with the Piloting factor); 0 without an operated, intact console
func rot_accel() -> float:
	return float(space.rot_accel) * pilot_factor() if manual_ok() else 0.0

## Docking limits (distance, speed) with the Piloting factor
func dock_factor() -> float:
	return pilot_factor()

## Why a navigation console cannot be flown ("" = it can)
func helm_block_reason(h: Device) -> String:
	if h == null:
		return "Nobody is at a navigation console."
	if h.broken:
		return "This navigation console is broken."
	if not h.powered:
		return "This navigation console has no power."
	return ""

## Reason why the pilot cannot give flight commands right now (undocking, fast travel,
## Auto-Dock): it needs the operated console, intact and powered. "" = possible.
func pilot_block_reason() -> String:
	if ship_devices("helm").is_empty():
		return "No navigation console aboard."
	var h := operated_helm()
	if h == null:
		return "Only possible at the navigation console: go to the cockpit first (N)."
	var why := helm_block_reason(h)
	if why != "":
		return why + (" Repair it first." if h.broken else "")
	return ""

## Console that started a fast travel or an Auto-Dock ({hx, hy} in the order):
## "" = still fine. Older saves without a console entry: any powered console.
func _cmd_helm_reason(d: Dictionary) -> String:
	if not d.has("hx"):
		return "" if helm_ok() else "No navigation console with power."
	var h := ShipSystem.grid.device_at(Vector2i(int(d.hx), int(d.hy)))
	if h == null or h.type != "helm":
		return "The navigation console is gone."
	return helm_block_reason(h)

## Manual flight (thrust, turning, matching) only through the operated console,
## and only if exactly this console is intact and powered.
func manual_ok() -> bool:
	return helm_block_reason(operated_helm()) == ""

## Auto-Dock is unlocked when a working Autodock Module sits in the module bay of the
## operated console (intact, powered). Modules elsewhere (pack, floor,
## another console) do not count; several identical modules unlock the same function.
func autodock_ok() -> bool:
	return autodock_block_reason() == ""

## Reason why Auto-Dock is locked here ("" = unlocked)
func autodock_block_reason() -> String:
	var why := pilot_block_reason()
	if why != "":
		return why
	return module_block_reason(operated_helm(), "autodock")

## Is a working module of this kind in console h? "" = yes, otherwise the reason
func module_block_reason(h: Device, kind: String) -> String:
	if h == null:
		return "The navigation console is gone."
	if not h.module(kind).is_empty():
		return ""
	var name := module_name(kind)
	if h.has_module_item(kind):
		return "The %s in this navigation console is broken." % name
	return "No %s in this navigation console. Put the module in the module bay (E at the console)." % name

## Display name of the module for a function (e.g. "Autodock Module")
func module_name(kind: String) -> String:
	for id in ItemSystem.items:
		if ItemSystem.item(id).helm_module == kind:
			return ItemSystem.item(id).display_name
	return kind

## Can a running Auto-Dock manoeuvre continue? (console, power, module in the starting console)
func _autodock_reason() -> String:
	var why := _cmd_helm_reason(autodock)
	if why != "" or not autodock.has("hx"):
		return why
	return module_block_reason(ShipSystem.grid.device_at(Vector2i(int(autodock.hx), int(autodock.hy))), "autodock")

## The pilot skill saves fuel (see SkillSystem)
func fuel_factor() -> float:
	return SkillSystem.pilot_fuel_factor()

# ---------------- Simulation ----------------

func step(dt: float) -> void:
	if crashed:
		return
	var s := dt * 60.0
	var t := secs()
	if docked != "":
		var st := loc_state(loc(docked), t)
		pos = st.pos
		vel = st.vel
		return
	if not travel.is_empty() and _cmd_helm_reason(travel) != "":
		# Console failed: the trip ends, the ship keeps flying at travel speed
		var dest_now: Vector2 = loc_state(loc(travel.to), t).pos
		vel = (dest_now - travel.from) / maxf(1.0, travel.t1 - travel.t0)
		GameState.toast("Fast travel aborted: %s The ship keeps flying at %.2f km/s." % [_cmd_helm_reason(travel), vel.length()], "bad")
		travel = {}
		return
	if not autodock.is_empty() and _autodock_reason() != "":
		# Abort in a controlled way: free flight with the reached heading and velocity,
		# no coupling
		GameState.toast("Auto-Dock aborted: " + _autodock_reason(), "bad")
		autodock = {}
		return
	if not travel.is_empty():
		var f := minf(1.0, (t - travel.t0) / (travel.t1 - travel.t0))
		var to: Vector2 = loc_state(loc(travel.to), t).pos
		pos = travel.from.lerp(to, f)
		angle = (to - travel.from).angle()
		if f >= 1.0:
			var dest: String = travel.to
			travel = {}
			GameState.toast("Arrived: " + loc(dest).name)
			dock(dest, true)
		return
	if not autodock.is_empty():
		var st := loc_state(loc(autodock.to), t)
		var f := minf(1.0, (t - autodock.t0) / (autodock.t1 - autodock.t0))
		pos = pos.lerp(st.pos, f)
		vel = vel.lerp(st.vel, f)
		if f >= 1.0:
			var dest: String = autodock.to
			autodock = {}
			if not dock(dest, true):
				GameState.toast("Auto-Dock: coupling failed, the ship is drifting free.", "bad")
		return
	# Was pos/vel set from outside (undocking, loading, collision)? Then take it over.
	if pos != _p32:
		_px = pos.x
		_py = pos.y
	if vel != _v32:
		_vx = vel.x
		_vy = vel.y
	var acc := gravity(pos)
	# If the operated console fails, thrust, rotation thrust and matching stop at once.
	# The existing motion (velocity, rotation) continues physically.
	var manual := manual_ok()
	if not manual and (thrust != 0.0 or strafe != 0.0 or rot_input != 0.0 or rot_stop or aligning or match_target != ""):
		var why := helm_block_reason(operated_helm())
		if match_target != "":
			GameState.toast("Matching stopped: " + why, "bad")
		elif helm_at != NO_HELM and not _helm_fail_warned:
			GameState.toast("Thrust stopped: " + why, "bad")
		_helm_fail_warned = helm_at != NO_HELM
		stop_inputs()
		match_target = ""
	elif manual:
		_helm_fail_warned = false
	_rotate(s, dt)
	# Manual thrust takes priority. Without keys an active matching uses
	# the same thrusters and RCS to reach the target velocity.
	match_input = Vector2.ZERO
	if (thrust != 0.0 or strafe != 0.0) and manual:
		acc += _thrust_accel(dt, Vector2(thrust, strafe))
	elif match_target != "":
		match_input = _match_input(s)
		if match_input != Vector2.ZERO:
			acc += _thrust_accel(dt, match_input)
	# Semi-implicit Euler method: stable for orbits
	_vx += acc.x * s
	_vy += acc.y * s
	_px += _vx * s
	_py += _vy * s
	pos = Vector2(_px, _py)
	vel = Vector2(_vx, _vy)
	_p32 = pos
	_v32 = vel
	_check_hazards()

## Thrust relative to the heading: sum of the thrust vectors of all active thrusters
## whose direction matches the input (W forward, S back, D right, A left), plus
## RCS. Acceleration = total thrust ÷ ship mass. Uses fuel.
func _thrust_accel(dt: float, inp: Vector2) -> Vector2:
	var req := _requested(inp)
	var engines := 0.0
	for t in active_thrusters():
		engines += req[t.push_dir()]
	var rcs_part := absf(inp.x) + absf(inp.y)
	var need := (float(space.burn) * engines + float(space.rcs_burn) * rcs_part) * dt * fuel_factor()
	var f := thrust_vector_local(inp)
	if fuel() < need or f == Vector2.ZERO:
		if not _no_fuel_warned:
			_no_fuel_warned = true
			GameState.toast("No fuel!" if fuel() < need else "No thruster for this direction and no RCS!", "bad")
		return Vector2.ZERO
	use_fuel(need)
	_no_fuel_warned = false
	SkillSystem.train_all_at("helm", "pilot", dt * 0.5)
	return (f / maxf(1.0, mass()) / 1000.0).rotated(angle)

## Matching: input (forward/back, right/left, each -1..1) that removes as much of the relative velocity
## to the target as possible in this step – without turning the ship.
## Uses the thrusters of that direction plus RCS on each axis. Below the
## dead band MATCH_DEADBAND it does not fire (our own choice).
func _match_input(s: float) -> Vector2:
	var dv: Vector2 = rel_to(match_target).vel - Vector2(_vx, _vy)
	if dv.length() < MATCH_DEADBAND:
		return Vector2.ZERO
	var local := dv.rotated(-angle)
	var m := maxf(1.0, mass()) * 1000.0
	var out := Vector2.ZERO
	for axis in 2:
		var want: float = local[axis]
		if absf(want) < MATCH_DEADBAND * 0.5:
			continue
		var d := Vector2i(int(signf(want)), 0) if axis == 0 else Vector2i(0, int(signf(want)))
		var a_max := (thrust_dir(d) + rcs_thrust()) / m
		if a_max <= 0.0:
			continue
		out[axis] = signf(want) * minf(1.0, absf(want) / s / a_max)
	return out

## Rotation with momentum: rotation thrust accelerates the turn, without counter-thrust
## the ship keeps turning. R brakes the rotation. A rotation does not change the flight direction.
func _rotate(s: float, dt: float) -> void:
	var acc := rot_accel()
	var want := ang_vel
	var settle := false
	if rot_input != 0.0 or rot_stop:
		aligning = false
	if rot_input != 0.0:
		want = clampf(ang_vel + rot_input * acc * s, -float(space.rot_max), float(space.rot_max))
	elif rot_stop:
		want = move_toward(ang_vel, 0.0, acc * s)
	elif aligning and acc > 0.0:
		# Align: accelerate, then brake so that the rotation ends at the target
		var err := wrapf(align_angle - angle, -PI, PI)
		if absf(err) <= maxf(0.002, absf(ang_vel) * s) and absf(ang_vel) <= acc * s:
			want = 0.0
			settle = true
		else:
			var goal := signf(err) * minf(float(space.rot_max), sqrt(2.0 * acc * absf(err)))
			want = move_toward(ang_vel, goal, acc * s)
	if want != ang_vel:
		var need := float(space.rcs_burn) * 0.5 * dt * fuel_factor()
		if fuel() >= need:
			use_fuel(need)
			ang_vel = want
		else:
			settle = false
	if settle:
		angle = align_angle
		aligning = false
		return
	angle = wrapf(angle + ang_vel * s, -PI, PI)

# ---------------- Approach: alignment and closing ----------------

## How well does a free docking port point at the target? {ok, deg, angle}
## angle = ship heading at which the best airlock points exactly at the target.
func dock_alignment(id: String) -> Dictionary:
	var r := rel_to(id)
	var to_target: Vector2 = r.pos - pos
	var best := {"ok": false, "deg": 180.0, "angle": angle, "port": false, "dir": Vector2.ZERO}
	var ports: Array = ShipSystem.free_ports() if ShipSystem.grid != null else []
	for p in ports:
		var d := Vector2(p.dir)
		var dev := rad_to_deg(absf(d.rotated(angle).angle_to(to_target))) if to_target.length() > 0.0001 else 0.0
		if dev < best.deg:
			best = {"ok": dev <= float(space.dock_align_deg) or to_target.length() < 0.02, "deg": dev,
				"angle": wrapf(to_target.angle() - d.angle(), -PI, PI), "port": true, "dir": d.rotated(angle), "i": int(p.i)}
	return best

## Approach data for the target: distance, relative velocity, closing, stopping distances
func approach(id: String) -> Dictionary:
	var r := rel_to(id)
	var to_target: Vector2 = r.pos - pos
	var vrel: Vector2 = vel - r.vel
	var dist := to_target.length()
	var closing := vrel.dot(to_target / dist) if dist > 0.000001 else 0.0
	var arcs := (rcs_thrust() + thrust_dir(Vector2i(-1, 0))) / maxf(1.0, mass()) / 1000.0
	var amain := main_accel() + rcs_accel()
	return {"dist": dist, "vrel": vrel, "speed": vrel.length(), "closing": closing,
		"brake_rcs": closing * closing / (2.0 * arcs) if closing > 0.0 and arcs > 0.0 else 0.0,
		"brake_main": closing * closing / (2.0 * amain) if closing > 0.0 and amain > 0.0 else 0.0,
		"eta": dist / closing if closing > 0.000001 else -1.0}

func _check_hazards() -> void:
	var e := _body("earth")
	var m := _body("moon")
	var alt_e := pos.distance_to(Vector2(e.x, e.y)) - float(e.r)
	var alt_m := pos.distance_to(Vector2(m.x, m.y)) - float(m.r)
	if alt_e < float(space.warn_alt) and not _warned:
		_warned = true
		GameState.toast("Warning: Earth's gravity is pulling the ship in! Burn away from it.", "bad")
	if alt_e > float(space.warn_alt) * 1.5:
		_warned = false
	if alt_e < float(space.crash_alt) or alt_m < float(space.moon_crash_alt):
		crashed = true
		TimeSystem.set_speed(0)
		var text := "Earth never let your ship go. It burned up entering the atmosphere." if alt_e < float(space.crash_alt) else "Your ship crashed into the lunar surface."
		EconomySystem.game_over.emit("Crashed", text)
		return
	for l in locations:
		if l.kind != "station":
			continue
		var st := loc_state(l, secs())
		if pos.distance_to(st.pos) < 0.05 and vel.distance_to(st.vel) > float(space.collide_speed):
			var hits := mini(6, int(ceil(vel.distance_to(st.vel) / float(space.collide_speed))))
			for k in hits:
				DamageSystem.strike()
			log_event("Collision with %s at %.0f m/s (%d hull hits)" % [l.name, vel.distance_to(st.vel) * 1000.0, hits])
			vel = st.vel
			GameState.toast("Collision with " + l.name + "! The hull is damaged.", "bad")

# ---------------- Docking, travel ----------------

func rel_to(id: String) -> Dictionary:
	var st := loc_state(loc(id), secs())
	return {"dist": pos.distance_to(st.pos), "speed": vel.distance_to(st.vel), "pos": st.pos, "vel": st.vel}

func nearest() -> Dictionary:
	var best := {}
	for l in locations:
		var r := rel_to(l.id)
		if best.is_empty() or r.dist < best.dist:
			best = r
			best.id = l.id
	return best

## Is docking at this place locked right now because of a fresh undock?
func redock_locked(id: String) -> bool:
	return id == undock_lock_id and secs() < undock_lock_until

func redock_wait(id: String) -> float:
	return maxf(0.0, undock_lock_until - secs()) if id == undock_lock_id else 0.0

## Reason why you cannot dock here ("" = possible)
func dock_block_reason(id: String) -> String:
	var why := pilot_block_reason()
	if why != "":
		return why
	why = xpdr_dock_reason(id)
	if why != "":
		return why
	if redock_locked(id):
		return "Just undocked. Docking at %s is possible again in %d s." % [loc(id).name, int(ceil(redock_wait(id)))]
	var r := rel_to(id)
	var m := dock_factor()
	if r.dist >= float(space.dock_dist) * m:
		return "Too far away to dock (%d m, must be under %d m)." % [int(r.dist * 1000.0), int(float(space.dock_dist) * m * 1000.0)]
	if r.speed >= float(space.dock_speed) * m:
		return "Too fast to dock (%.1f m/s, must be under %.0f m/s)." % [r.speed * 1000.0, float(space.dock_speed) * m * 1000.0]
	var al := dock_alignment(id)
	if not al.port:
		return "No free docking port."
	if not al.ok:
		return "The docking port does not face the target (%d° off, %d° allowed). Turn with Q/E." % [int(al.deg), int(space.dock_align_deg)]
	return ""

func can_dock(id: String) -> bool:
	if pilot_block_reason() != "" or redock_locked(id) or xpdr_dock_reason(id) != "":
		return false
	var r := rel_to(id)
	# Piloting (Spaceship Piloting): larger docking limits
	var m := dock_factor()
	if not (r.dist < float(space.dock_dist) * m and r.speed < float(space.dock_speed) * m):
		return false
	# The airlock must face the target (Ostranauts: line up the docking rings)
	return dock_alignment(id).ok

func dock(id: String, force: bool = false) -> bool:
	if not force and not can_dock(id):
		return false
	if docked == id:
		return true
	# Some stations only accept ships with a transponder and antenna (Ostranauts Ship Ownership)
	var xwhy := xpdr_dock_reason(id)
	if xwhy != "":
		GameState.toast(xwhy, "bad")
		return false
	# Docking only with a docking port (door to door, no corridors)
	if ShipSystem.ports().is_empty():
		GameState.toast("No docking port: ships dock at the outer door of an airlock (a room with a pump and a door to space).", "bad")
		return false
	# Clamps at the aligned port: that is where the passage is created
	var al := dock_alignment(id)
	ShipSystem.dock_pref = int(al.get("i", -1))
	if String(loc(id).get("kind", "")) == "station" and Config.ENABLE_STATION and not StationSystem.build(id):
		return false
	# Wreck as its own target: only attach it to the port now (no wreck zone at the ship before)
	if String(loc(id).get("kind", "")) == "wreck" and Config.ENABLE_WRECK and not FleetSystem.attach_site(loc(id)):
		return false
	docked = id
	stop_inputs()
	ang_vel = 0.0
	match_target = ""
	FleetSystem.arrive(loc(id))
	EconomySystem.check_permit_on_dock(loc(id))
	NPCSystem.on_docked(id)
	SkillSystem.train_all_at("helm", "dock", 0.3 if force else 8.0)
	log_event("Docked: " + loc(id).name)
	GameState.toast("Docked at: " + loc(id).name)
	if String(loc(id).get("kind", "")) == "station" and not xpdr_faults().is_empty():
		GameState.toast("Security Services (N.A.S.S.) take a closer look at your unidentified ship (%s)." % ", ".join(xpdr_faults()), "bad")
	return true

# ---------------- Transponder and antenna (Ostranauts Ship Ownership) ----------------

## State of a part: "" = fine, otherwise "missing", "damaged" or "unpowered"
func _part_fault(type: String) -> String:
	var best := "missing"
	for d in ship_devices(type):
		if d.broken:
			best = "damaged" if best == "missing" else best
		elif not d.powered:
			best = "unpowered"
		else:
			return ""
	return best

## Warnings of the navigation console: ["XPDR FAULT", "ANT FAULT"] (empty = all fine)
func xpdr_faults() -> Array:
	var out: Array = []
	if _part_fault("transponder") != "":
		out.append("XPDR FAULT")
	if _part_fault("antenna") != "":
		out.append("ANT FAULT")
	return out

## Reason why this station refuses docking ("" = allowed)
func xpdr_dock_reason(id: String) -> String:
	if not bool(loc(id).get("requires_xpdr", false)):
		return ""
	var x := _part_fault("transponder")
	var a := _part_fault("antenna")
	if x == "" and a == "":
		return ""
	var parts: PackedStringArray = []
	if x != "":
		parts.append("transponder %s" % x)
	if a != "":
		parts.append("antenna %s" % a)
	return "%s only accepts ships with a working transponder and antenna (%s)." % [loc(id).name, ", ".join(parts)]

## Reason that prevents undocking ("" = undocking possible)
func undock_block_reason() -> String:
	if docked == "":
		return "The ship is not docked."
	if crashed:
		return "The ship is destroyed."
	var why := pilot_block_reason()
	if why != "":
		return why
	var g := ShipSystem.grid
	var on_wreck: PackedStringArray = []
	var on_station: PackedStringArray = []
	var in_hatch: PackedStringArray = []
	for c in CrewSystem.crew:
		var i := g.idx(c.tile())
		if g.zone[i] == 1:
			on_wreck.append(c.display_name)
		elif g.zone[i] == StationSystem.ZONE:
			on_station.append(c.display_name)
		elif StationSystem.is_hatch(i):
			in_hatch.append(c.display_name)
	if not on_wreck.is_empty():
		return "Still on the wreck: %s. Bring everyone back aboard first." % ", ".join(on_wreck)
	if not on_station.is_empty():
		return "Still on the station: %s. Bring everyone back aboard first." % ", ".join(on_station)
	if not in_hatch.is_empty():
		return "%s is standing in the hatch to the station." % ", ".join(in_hatch)
	return ""

## Undocking through the controls (button, key U): always reports success or the reason
func request_undock() -> bool:
	if docked == "":
		GameState.toast(undock_block_reason())
		return false
	return undock()

## Undock. Not being docked counts as done (for travel).
func undock() -> bool:
	if docked == "":
		return true
	var why := undock_block_reason()
	if why != "":
		GameState.toast(why, "bad")
		return false
	var from := docked
	# Without a jump: take over exactly the position and motion of the place, the heading stays
	var st := loc_state(loc(from), secs())
	pos = st.pos
	vel = st.vel
	thrust = 0.0
	match_target = ""
	StationSystem.clear()
	FleetSystem.leave(loc(from))
	docked = ""
	# Remove and seal former docking ports (5×2) after releasing
	ShipSystem.retire_legacy_ports()
	# Gentle push backwards
	vel += Vector2.from_angle(angle + PI) * UNDOCK_PUSH
	undock_lock_id = from
	undock_lock_until = secs() + REDOCK_LOCK_SECS
	log_event("Undocked: " + loc(from).name)
	GameState.toast("Undocked from %s. The ship is drifting free – steer from the navigation console (WASD)." % loc(from).name)
	return true

func start_autodock() -> void:
	var why := autodock_block_reason()
	if why != "":
		GameState.toast(why, "bad")
		return
	if docked != "":
		GameState.toast("The ship is already docked.")
		return
	if ShipSystem.free_ports().is_empty():
		GameState.toast("No free docking port for Auto-Dock.", "bad")
		return
	var n := nearest()
	if redock_locked(n.id):
		GameState.toast(dock_block_reason(n.id))
		return
	if xpdr_dock_reason(n.id) != "":
		GameState.toast(xpdr_dock_reason(n.id), "bad")
		return
	if n.dist > float(space.autodock_dist) or n.speed > float(space.autodock_speed):
		GameState.toast("Too far away or too fast for Auto-Dock.")
		return
	var need: float = (5.0 + n.speed * 60.0) * fuel_factor()
	if fuel() < need:
		GameState.toast("Not enough fuel to dock.", "bad")
		return
	use_fuel(need)
	var t_dock: float = 300.0 + n.dist * 5.0
	autodock = {"to": n.id, "t0": secs(), "t1": secs() + t_dock, "hx": helm_at.x, "hy": helm_at.y}
	GameState.toast("Auto-Dock running: " + loc(n.id).name)

func travel_info(id: String) -> Dictionary:
	var r := rel_to(id)
	var tf := SkillSystem.travel_factor()
	return {"dist": r.dist, "fuel": r.dist * float(space.travel_fuel_per_km) * fuel_factor() * tf, "secs": (r.dist / float(space.travel_speed) + 600.0) * tf}

func travel_to(id: String) -> void:
	var why := pilot_block_reason()
	if why != "":
		GameState.toast(why, "bad")
		return
	if docked == id:
		return
	if xpdr_dock_reason(id) != "":
		GameState.toast(xpdr_dock_reason(id), "bad")
		return
	var info := travel_info(id)
	if max_thrust() <= 0.0:
		GameState.toast("No thrusters with power.", "bad")
		return
	if fuel() < info.fuel:
		GameState.toast("Not enough fuel (%d needed)." % int(ceil(info.fuel)), "bad")
		return
	if not undock():
		return
	use_fuel(info.fuel)
	travel = {"to": id, "t0": secs(), "t1": secs() + info.secs, "from": pos, "hx": helm_at.x, "hy": helm_at.y}
	SkillSystem.train_all_at("helm", "navigate", 10.0)
	SkillSystem.train_all_at("helm", "pilot", 5.0)
	GameState.toast("Fast travel to %s: %.1f hours." % [loc(id).name, info.secs / 3600.0])

func status() -> String:
	if docked != "":
		return "Docked at: " + loc(docked).name
	if not travel.is_empty():
		return "En route to " + loc(travel.to).name
	if not autodock.is_empty():
		return "Docking at: " + loc(autodock.to).name
	return "In free flight"

## Station where the ship is docked right now (otherwise empty)
func station() -> Dictionary:
	if docked == "":
		return {}
	var l := loc(docked)
	return l if l.kind == "station" else {}

func to_data() -> Dictionary:
	return {"x": pos.x, "y": pos.y, "vx": vel.x, "vy": vel.y, "angle": angle, "docked": docked,
		"travel": _travel_data(),
		"autodock": autodock, "lock_id": undock_lock_id, "lock_until": undock_lock_until, "ang_vel": ang_vel, "target": target,
		"ship_log": ship_log, "prox_muted": prox_muted}

func _travel_data() -> Dictionary:
	if travel.is_empty():
		return {}
	var out := {"to": travel.to, "t0": travel.t0, "t1": travel.t1, "fx": travel.from.x, "fy": travel.from.y}
	if travel.has("hx"):
		out.hx = travel.hx
		out.hy = travel.hy
	return out

func from_data(d: Dictionary) -> void:
	pos = Vector2(d.x, d.y); vel = Vector2(d.vx, d.vy); angle = float(d.angle); docked = String(d.docked)
	travel = {}
	if not d.travel.is_empty():
		travel = {"to": d.travel.to, "t0": float(d.travel.t0), "t1": float(d.travel.t1), "from": Vector2(d.travel.fx, d.travel.fy)}
		if d.travel.has("hx"):
			travel.hx = int(d.travel.hx)
			travel.hy = int(d.travel.hy)
	autodock = d.autodock
	undock_lock_id = String(d.get("lock_id", ""))
	undock_lock_until = float(d.get("lock_until", 0.0))
	ang_vel = float(d.get("ang_vel", 0.0))
	target = String(d.get("target", ""))
	ship_log.assign(d.get("ship_log", []))
	prox_muted = bool(d.get("prox_muted", false))
	stop_inputs()
	helm_at = NO_HELM
	crashed = false
	match_target = ""
	match_input = Vector2.ZERO
