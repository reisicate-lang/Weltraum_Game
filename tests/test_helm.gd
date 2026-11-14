## Tests: manual flight is bound to the navigation console where the pilot stands
##   godot --headless --path . --script res://tests/boot.gd -- test_helm
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var gs
var P
var ui
var ship
var mira
var toasts: Array[String] = []

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

## One frame at ×1 with held keys, the way scenes/main/main.gd processes them:
## Only in the cockpit (and as long as the pilot stays at the console) do W/S/A/D/Q/E set inputs.
func _frame(w: float = 0.0, q: bool = false) -> void:
	if ui.nav_open and ui.keep_pilot():
		P.thrust = w
		P.rot_input = -1.0 if q else 0.0
	gs.step(1.0 / 60.0 / 60.0)
	ui._check_helm_walk()

## Frames like TimeSystem at ×factor (without keys)
func _frames_f(n: int, factor: float) -> void:
	for f in n:
		if ui.nav_open:
			ui.keep_pilot()
		var total := (1.0 / 60.0) * factor / 60.0
		var steps := int(ceil(total / (1.0 / 60.0)))
		for k in steps:
			gs.step(total / steps)

func _frames(n: int, w: float = 0.0, q: bool = false) -> void:
	for k in n:
		_frame(w, q)

func _vrel() -> Vector2:
	return (P.vel - P.rel_to("l4").vel) * 1000.0

## Velocity change from gravity alone over n frames (to subtract)
func _grav(n: int) -> Vector2:
	return P.gravity(P.pos) * 1000.0 * (n / 60.0)

func _park() -> void:
	var st: Dictionary = P.loc_state(P.loc("l4"), P.secs())
	P.pos = st.pos + Vector2(3.0, 0)
	P.vel = st.vel
	P.angle = 0.0
	P.ang_vel = 0.0
	P.stop_inputs()
	P.match_target = ""
	P.target = "l4"

func _power() -> void:
	root.get_node("EventBus").ship_changed.emit()
	root.get_node("ShipPowerSystem").step(0.0)

## Freies, begehbares Nachbarfeld eines Pults
func _beside(h) -> Vector2:
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var p: Vector2i = h.pos + d
		if ship.grid.walkable(p) and ship.grid.device_at(p) == null:
			return Vector2(p) + Vector2(0.5, 0.5)
	return Vector2(h.pos) + Vector2(0.5, 1.5)

func _cut(h) -> void:
	ship.grid.cables[ship.grid.idx(h.pos)] = 0
	_power()

func _wire(h) -> void:
	ship.grid.cables[ship.grid.idx(h.pos)] = 1
	_power()

## "Align" and "Match" buttons of the target list currently shown
## (old rows are only queued for deletion after the rebuild)
func _nav_buttons() -> Array:
	var out: Array = []
	for row in ui.nav_side.get_children():
		if row.is_queued_for_deletion():
			continue
		for b in row.find_children("*", "Button", true, false):
			if b.text == "Align" or b.text == "Match":
				out.append(b)
	return out

func _initialize() -> void:
	await process_frame
	await process_frame
	root.get_node("SaveSystem").slot = 918
	gs = root.get_node("GameState")
	P = root.get_node("PhysicsSystem")
	ui = root.get_node("UIManager")
	ship = root.get_node("ShipSystem")
	root.get_node("Settings").meteors = false
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(String(t)))
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.char_ui.creation.visible = false
	mira = root.get_node("CrewSystem").player()
	for k in 3:
		gs.step(1.0 / 60.0)              # distribute power
	seat_pilot()
	P.request_undock()
	P.helm_at = P.NO_HELM                  # nobody at the console again
	for k in 60 * 20:
		gs.step(1.0 / 60.0 / 60.0)
	var g = ship.grid
	_check("Free in space (%s)" % P.undock_block_reason(), P.docked == "")

	# Second console far away from the first, on a cable tile (so with power)
	var near = P.ship_devices("helm")[0]
	var far_pos := Vector2i(-1, -1)
	var best := 0.0
	for i in g.tiles.size():
		var p: Vector2i = g.pos(i)
		if g.zone[i] == 0 and g.tiles[i] == ShipGrid.Tile.FLOOR and g.cables[i] == 1 and not g.devices.has(i) and not g.piles.has(i):
			var d := Vector2(p).distance_to(Vector2(near.pos))
			if d > best:
				best = d
				far_pos = p
	var far = g.place_device("helm", far_pos)
	_power()
	_check("Two consoles, both powered and intact (distance %.0f tiles)" % best, near.powered and far.powered and best >= 4.0)

	# 1) Reachable console broken or without power, the distant one works
	for mode in ["broken", "unpowered"]:
		_park()
		mira.pos = _beside(near)
		mira.path.clear()
		mira.order = null
		if mode == "broken":
			near.broken = true
		else:
			_cut(near)
		_check("1 (%s): console reachable by the pilot, other console powered" % mode, mira.can_reach(near.pos) and not mira.can_reach(far.pos) and far.powered and not far.broken and P.helm_ok())
		var v0 := _vrel()
		var f0: float = P.fuel()
		toasts.clear()
		ui.toggle_nav(true)                 # N
		_check("1 (%s): N is refused (%s)" % [mode, toasts[-1] if not toasts.is_empty() else ""], not ui.nav_open and P.helm_at == P.NO_HELM and not toasts.is_empty() and ("broken" in toasts[-1] or "power" in toasts[-1]))
		ui.request_flight(near)             # click on the console
		_check("1 (%s): click is refused" % mode, not ui.nav_open and not ui._helm_walk)
		_frames(120, 1.0, true)             # hold W and Q
		_check("1 (%s): W/Q produce no thrust and no rotation" % mode, (_vrel() - v0 - _grav(120)).length() < 0.01 and P.ang_vel == 0.0 and P.fuel() == f0)
		# Even if the cockpit were open at this console: physics gives no thrust,
		# although the other console has power (formerly any powered console was enough).
		P.helm_at = near.pos
		P.thrust = 1.0
		P.rot_input = -1.0
		v0 = _vrel()
		for k in 120:
			gs.step(1.0 / 60.0 / 60.0)
		_check("1 (%s): physics at the bound console: no thrust, no rotation" % mode, (_vrel() - v0 - _grav(120)).length() < 0.01 and P.ang_vel == 0.0 and P.thrust == 0.0 and P.fuel() == f0)
		P.helm_at = P.NO_HELM
		near.broken = false
		_wire(near)

	# 2) Switch to the working console, fly, then its power fails while W is held
	_park()
	mira.pos = _beside(near)
	near.broken = true                      # the near console stays broken
	ui.request_flight(far)                  # click on the distant console: Mira walks there
	_check("2: Mira walks to the working console", ui._helm_walk and not ui.nav_open)
	for k in 60 * 60:
		_frame()
		if ui.nav_open:
			break
	_check("2: In the cockpit at the distant console", ui.nav_open and P.helm_at == far.pos and mira.can_reach(far.pos))
	near.broken = false                     # now both consoles are fine
	_park()
	var v1 := _vrel()
	var f1: float = P.fuel()
	_frames(120, 1.0)                       # W 2 s
	var dv := _vrel() - v1 - _grav(120)
	var a_exp: float = (P.max_thrust() + P.rcs_thrust()) / P.mass()   # m/s²
	_check("2: W gives thrust (%.2f m/s, expected %.2f)" % [dv.length(), a_exp * 2.0], absf(dv.length() - a_exp * 2.0) < 0.1 and P.fuel() < f1)
	_frames(30, 0.0, true)                  # Q 0,5 s
	var w_q: float = P.ang_vel
	_check("2: Q dreht (%.3f rad/s)" % w_q, w_q < -0.1)
	P.ang_vel = 0.0
	# hold W, then power fails at the operated console; the other console still has power
	_frames(30, 1.0)
	P.rot_input = 0.0
	toasts.clear()
	_cut(far)
	_check("2: Operated console without power, the other powered", not far.powered and near.powered and not near.broken and P.helm_ok())
	_frame(1.0)
	var v_cut := _vrel()
	var f_cut: float = P.fuel()
	var vel_cut: Vector2 = P.vel
	_frames(120, 1.0, true)                 # W and Q still held
	_check("2: Thrust ends (Δv %.4f m/s, fuel %.3f)" % [(_vrel() - v_cut - _grav(120)).length(), f_cut - P.fuel()],
		(_vrel() - v_cut - _grav(120)).length() < 0.01 and P.fuel() == f_cut and P.thrust == 0.0)
	_check("2: Existing motion stays (%.2f m/s)" % (vel_cut.length() * 1000.0), vel_cut.length() > 0.0 and absf((P.vel - vel_cut).length() * 1000.0 - _grav(120).length()) < 0.01 and _vrel().length() > 1.0)
	_check("2: No rotation without a powered console", P.ang_vel == 0.0)
	_check("2: Message “Thrust stopped” (%s)" % ", ".join(toasts), toasts.any(func(t): return t.begins_with("Thrust stopped")))
	_check("2: Cockpit shows the reason", P.helm_block_reason(P.operated_helm()) == "This navigation console has no power.")
	# A rotation that is already running keeps turning
	_wire(far)
	_frames(30, 0.0, true)
	var w0: float = P.ang_vel
	_cut(far)
	var a0: float = P.angle
	_frames(60, 0.0, true)
	_check("2: Ongoing rotation continues without power (%.3f rad/s)" % P.ang_vel, P.ang_vel == w0 and absf(P.angle - a0) > 0.01)
	P.ang_vel = 0.0
	# Matching ends on the failure even though the other console has power
	_wire(far)
	_park()
	P.vel += Vector2(0.01, 0)
	ui.toggle_match()
	_frames(30)
	_check("2: Matching runs at the operated console", P.match_target == "l4")
	toasts.clear()
	_cut(far)
	var vm := _vrel()
	_frames(60)
	_check("2: Angleichen endet beim Ausfall (%s)" % ", ".join(toasts), P.match_target == "" and toasts.any(func(t): return t.begins_with("Matching stopped")) and (_vrel() - vm - _grav(60)).length() < 0.01)
	ui.toggle_match()
	_check("2: Matching cannot be switched on without power", P.match_target == "")
	_wire(far)
	ui.leave_flight()
	_check("2: Leaving the cockpit frees the console", P.helm_at == P.NO_HELM)

	# 4) Undocking, fast travel and Auto-Dock only at the operated, intact, powered console
	P.dock("l4", true)
	for k in 60 * 20:
		gs.step(1.0 / 60.0 / 60.0)          # the lock against docking again plays no role here
	mira.pos = _beside(near)
	mira.path.clear()
	mira.order = null
	_check("4: Docked at L4, both consoles fine, nobody at a console", P.docked == "l4" and P.helm_at == P.NO_HELM and P.helm_ok())
	toasts.clear()
	_check("4: Without a pilot at the console: undocking refused (%s)" % P.undock_block_reason(), not P.request_undock() and P.docked == "l4" and "cockpit" in toasts[-1])
	P.travel_to("karman")
	_check("4: … Schnellreise verweigert", P.travel.is_empty() and P.docked == "l4" and "cockpit" in toasts[-1])
	P.start_autodock()
	_check("4: … Auto-Dock verweigert", P.autodock.is_empty() and "cockpit" in toasts[-1])
	for mode in ["broken", "unpowered"]:
		if mode == "broken":
			near.broken = true
		else:
			_cut(near)
		P.helm_at = near.pos                # pilot stands at the near console
		toasts.clear()
		_check("4 (%s): undocking refused although the other console works (%s)" % [mode, P.undock_block_reason()], P.helm_ok() and not P.request_undock() and P.docked == "l4" and ("broken" in toasts[-1] or "power" in toasts[-1]))
		P.travel_to("karman")
		_check("4 (%s): Schnellreise verweigert" % mode, P.travel.is_empty() and P.docked == "l4")
		P.start_autodock()
		_check("4 (%s): Auto-Dock verweigert (%s)" % [mode, toasts[-1]], P.autodock.is_empty() and ("broken" in toasts[-1] or "power" in toasts[-1]))
		near.broken = false
		_wire(near)
	P.helm_at = P.NO_HELM
	mira.pos = _beside(far)
	ui.request_flight(far)
	_check("4: In the cockpit at the working console", ui.nav_open and P.helm_at == far.pos)
	_check("4: Undocking at the operated console works", P.request_undock() and P.docked == "")
	for k in 60 * 16:
		gs.step(1.0 / 60.0 / 60.0)          # wait for the lock against docking again right away
	near.inv.move_to(far.inv, "mod_autodock", 1)   # put the Autodock Module into the operated console
	toasts.clear()
	P.start_autodock()
	_check("4: Auto-Dock at the operated console starts (%s)" % toasts[-1], not P.autodock.is_empty())
	P.autodock = {}
	# "Align" and "Match" buttons in the target list: only with a powered console
	P.target = "l4"
	_cut(far)
	ui._last_nav = ""
	ui._refresh_nav()
	var btns: Array = _nav_buttons()
	_check("4: Without power “Align” and “Match” are locked (%d buttons)" % btns.size(), not btns.is_empty() and btns.all(func(b): return b.disabled))
	var ang: float = P.angle
	for b in btns:
		b.pressed.emit()
	_check("4: … and do nothing", P.angle == ang and P.match_target == "")
	_wire(far)
	ui._last_nav = ""
	ui._refresh_nav()
	btns = _nav_buttons()
	_check("4: Usable again with power", not btns.is_empty() and btns.all(func(b): return not b.disabled))
	P.travel_to("karman")
	_check("4: Fast travel at the operated console starts", not P.travel.is_empty())
	P.travel = {}
	ui.leave_flight()

	# 5) Docking, running fast travel/Auto-Dock and "Align" at the operated console
	for k in 60 * 16:
		gs.step(1.0 / 60.0 / 60.0)
	var l4: Dictionary = P.loc_state(P.loc("l4"), P.secs())
	P.pos = l4.pos + Vector2(0.05, 0)
	P.vel = l4.vel
	P.ang_vel = 0.0
	P.angle = P.dock_alignment("l4").angle
	P.helm_at = P.NO_HELM
	_check("5: Without a pilot at the console: docking refused (%s)" % P.dock_block_reason("l4"), not P.can_dock("l4") and not P.dock("l4") and P.docked == "" and "cockpit" in P.dock_block_reason("l4"))
	near.broken = true
	P.helm_at = near.pos
	_check("5: At the broken console: docking refused (%s)" % P.dock_block_reason("l4"), not P.dock("l4") and "broken" in P.dock_block_reason("l4"))
	near.broken = false
	mira.pos = _beside(far)
	ui.request_flight(far)
	_check("5: At the working console: docking works", ui.nav_open and P.dock("l4") and P.docked == "l4")
	# Fast travel aborts when the starting console fails
	for t in P.ship_devices("fueltank"):
		t.stock = 400.0
	P.travel_to("karman")
	_check("5: Fast travel running", not P.travel.is_empty() and P.docked == "")
	ui.leave_flight()
	for k in 60 * 60:
		gs.step(1.0 / 60.0 / 60.0)
	_check("5: Leaving the cockpit: the trip continues", not P.travel.is_empty())
	root.get_node("SaveSystem").save_game(true)
	root.get_node("SaveSystem").load_game(true)
	far = ship.grid.device_at(far.pos)
	near = ship.grid.device_at(near.pos)
	_check("5: Loaded: the trip continues, console stored as a position", not P.travel.is_empty() and Vector2i(int(P.travel.hx), int(P.travel.hy)) == far.pos)
	toasts.clear()
	_cut(far)
	gs.step(1.0 / 60.0 / 60.0)
	_check("5: Console fails: trip aborted (%s)" % (toasts[-1] if not toasts.is_empty() else ""), P.travel.is_empty() and P.docked == "" and toasts.any(func(t): return t.begins_with("Fast travel aborted")))
	var v_tr: float = P.vel.length()
	var p_tr: Vector2 = P.pos
	for k in 60:
		gs.step(1.0 / 60.0 / 60.0)
	_check("5: Ship keeps flying free at travel speed (%.2f km/s)" % v_tr, v_tr > 1.0 and P.pos.distance_to(p_tr) > 0.5)
	_wire(far)
	# Auto-Dock aborts when the starting console fails
	l4 = P.loc_state(P.loc("l4"), P.secs())
	P.pos = l4.pos + Vector2(0.5, 0)
	P.vel = l4.vel
	mira = root.get_node("CrewSystem").player()
	mira.pos = _beside(far)
	ui.request_flight(far)
	P.start_autodock()
	_check("5: Auto-Dock running", not P.autodock.is_empty())
	toasts.clear()
	_cut(far)
	gs.step(1.0 / 60.0 / 60.0)
	_check("5: Console fails: Auto-Dock aborted (%s)" % (toasts[-1] if not toasts.is_empty() else ""), P.autodock.is_empty() and P.docked == "" and toasts.any(func(t): return t.begins_with("Auto-Dock aborted")))
	_wire(far)
	# "Align" turns with rotation thrust instead of instantly, at ×1 and ×16
	for factor in [1.0, 16.0]:
		P.angle = 0.0
		P.ang_vel = 0.0
		var f5: float = P.fuel()
		P.start_align(PI / 2.0)
		_frames_f(1, factor)
		_check("5 (×%d): Align does not jump (%.3f rad after one frame)" % [int(factor), P.angle], P.aligning and P.angle < 0.05)
		var secs_needed := 0.0
		for k in 60 * 30:
			_frames_f(1, factor)
			secs_needed += factor / 60.0
			if not P.aligning:
				break
		_check("5 (×%d): Align ends exactly at 90° without residual rotation (%.4f rad, %.1f s)" % [int(factor), P.angle, secs_needed],
			not P.aligning and absf(P.angle - PI / 2.0) < 0.001 and P.ang_vel == 0.0 and secs_needed > 2.0)
		_check("5 (×%d): … and uses fuel" % int(factor), P.fuel() < f5)
	P.angle = 0.0
	P.start_align(PI)
	_frames_f(30, 1.0)
	_frame(0.0, true)                       # Q
	_check("5: Q bricht Ausrichten ab", not P.aligning)
	P.ang_vel = 0.0
	P.start_align(PI / 2.0)
	_cut(far)
	_frames_f(10, 1.0)
	_check("5: Console without power: Align ends", not P.aligning)
	toasts.clear()
	P.start_align(0.0)
	_check("5: … and does not start (%s)" % (toasts[-1] if not toasts.is_empty() else ""), not P.aligning and not toasts.is_empty())
	_wire(far)
	ui.leave_flight()

	# 3) Load a save with one intact console: click and N keep working
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	for k in 3:
		gs.step(1.0 / 60.0)              # distribute power
	seat_pilot()
	P.request_undock()
	P.helm_at = P.NO_HELM                  # nobody at the console again
	for k in 60 * 20:
		gs.step(1.0 / 60.0 / 60.0)
	mira = root.get_node("CrewSystem").player()
	var helm = P.ship_devices("helm")[0]
	mira.pos = _beside(helm)
	ui.toggle_nav(true)
	_check("3: In the cockpit before saving", ui.nav_open and P.helm_at == helm.pos)
	var save = root.get_node("SaveSystem")
	save.save_game(true)
	var txt := FileAccess.get_file_as_string(save.path())
	_check("3: The save contains no console binding", txt != "" and not "helm_at" in txt and not "operated" in txt)
	gs.new_game()
	save.load_game(true)
	mira = root.get_node("CrewSystem").player()
	helm = P.ship_devices("helm")[0]
	_check("3: Loaded: exactly one intact console, no binding", P.ship_devices("helm").size() == 1 and not helm.broken and P.helm_at == P.NO_HELM)
	_frame()   # the old cockpit (opened before loading) closes: there is no pilot any more
	_check("3: No thrust without entering", not ui.nav_open and not P.manual_ok())
	mira.pos = _beside(helm)
	ui.toggle_nav(true)                     # N
	_check("3: N: Einstieg klappt", ui.nav_open and P.helm_at == helm.pos and ui.pilot == mira)
	_park()
	var v3 := _vrel()
	_frames(60, 1.0)
	_check("3: W gives thrust", (_vrel() - v3 - _grav(60)).length() > 0.5)
	ui.leave_flight()
	ui.request_flight(ship.grid.device_at(helm.pos))   # click on the console
	_check("3: Klick: Einstieg klappt", ui.nav_open and P.helm_at == helm.pos)
	ui.leave_flight()

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
