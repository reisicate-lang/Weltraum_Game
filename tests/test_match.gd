## Tests for the manual velocity matching in the cockpit (key X)
##   godot --headless --path . --script res://tests/boot.gd -- test_match
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var gs
var P
var ui
var ship

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

## Like TimeSystem at ×factor: factor/60 game seconds per frame, steps ≤ 1 s
func _frames(n: int, factor: float = 1.0) -> void:
	for f in n:
		var total := (1.0 / 60.0) * factor / 60.0
		var steps := int(ceil(total / (1.0 / 60.0)))
		for k in steps:
			gs.step(total / steps)
		ui.keep_pilot()

## Relative velocity to the target in m/s
func _vrel() -> Vector2:
	return (P.vel - P.rel_to("l4").vel) * 1000.0

## Free flight 3 km in front of Habitat L4 with a clear relative velocity (15 m/s)
func _setup(v_mps: Vector2) -> void:
	var st: Dictionary = P.loc_state(P.loc("l4"), P.secs())
	P.pos = st.pos + Vector2(3.0, 0)
	P.vel = st.vel + v_mps / 1000.0
	P.angle = 0.0
	P.ang_vel = 0.0
	P.stop_inputs()
	P.match_target = ""
	P.target = "l4"

func _fill_fuel(amount: float) -> void:
	for t in P.ship_devices("fueltank"):
		t.stock = amount

func _initialize() -> void:
	await process_frame
	await process_frame
	root.get_node("SaveSystem").slot = 916
	gs = root.get_node("GameState")
	P = root.get_node("PhysicsSystem")
	ui = root.get_node("UIManager")
	ship = root.get_node("ShipSystem")
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.char_ui.creation.visible = false
	var mira = root.get_node("CrewSystem").player()
	var helm = ui.helm_device()
	mira.pos = Vector2(helm.pos) + Vector2(-0.5, 1.5)
	_frames(2)
	ui.toggle_nav(true)
	_check("In the cockpit at the console", ui.nav_open and ui.pilot == mira)
	P.request_undock()
	_frames(20 * 60)

	# 1) ×1: match with X, D pulse, then match again
	_setup(Vector2(15.0, -6.0))
	var v0 := _vrel()
	ui.toggle_match()
	_check("X: Angleichen an (%s)" % P.match_target, P.match_target == "l4")
	_frames(120)   # 2 s
	var v1 := _vrel()
	# Braking against the flight direction: backwards there is only RCS (12 kN ÷ mass)
	var a_rcs: float = P.rcs_accel() * 1000.0
	_check("Matching removes relative velocity (%.1f → %.1f m/s, RCS %.2f m/s²)" % [v0.length(), v1.length(), a_rcs], v1.length() < v0.length() - a_rcs * 2.0 * 0.8)
	_check("… without turning the ship", absf(P.angle) < 0.0001 and P.ang_vel == 0.0)
	var right := Vector2.from_angle(P.angle + PI / 2.0)
	var vr_before := _vrel()
	P.strafe = 1.0                       # D halten
	var during_match := false
	for k in 60:
		_frames(1)
		if P.match_input != Vector2.ZERO:
			during_match = true
	P.strafe = 0.0                       # loslassen
	var dv_pulse := _vrel() - vr_before
	_check("The D pulse acts to the right despite matching (+%.2f m/s across)" % dv_pulse.dot(right), dv_pulse.dot(right) > 0.15)
	_check("… manual thrust takes priority (matching pauses)", not during_match and P.match_target == "l4")
	var after_pulse := _vrel().length()
	var reached := false
	var t_need := 0
	for k in 120:
		_frames(60)
		t_need += 1
		if _vrel().length() < 0.1:
			reached = true
			break
	_check("After releasing it matches again (%.2f → %.3f m/s in %d s)" % [after_pulse, _vrel().length(), t_need], reached)
	_check("Matching stays active (holds the velocity)", P.match_target == "l4")
	_frames(600)
	_check("10 s later still holds < 0.1 m/s (%.3f)" % _vrel().length(), _vrel().length() < 0.1)
	ui.toggle_match()
	_check("X again: matching off", P.match_target == "")

	# 2) Main thrusters without power, only RCS
	var g = ship.grid
	var cut: Array = []
	for t in P.ship_devices("thruster"):
		cut.append(g.idx(t.pos))
		g.cables[g.idx(t.pos)] = 0
	root.get_node("EventBus").ship_changed.emit()
	_frames(2)
	_check("Main thrusters without power, console and RCS there (%d kN, RCS %d kN)" % [int(P.max_thrust()), int(P.rcs_thrust())], P.max_thrust() == 0.0 and P.rcs_thrust() > 0.0 and P.helm_ok())
	_setup(Vector2(15.0, -6.0))
	var f0: float = P.fuel()
	var w0 := _vrel().length()
	ui.toggle_match()
	_frames(60 * 20)   # 20 s
	_check("Only RCS: matching stays on and removes velocity (%.1f → %.1f m/s)" % [w0, _vrel().length()], P.match_target == "l4" and _vrel().length() < w0 - 3.0)
	_check("… and uses fuel (%.2f)" % (f0 - P.fuel()), f0 - P.fuel() > 0.0)
	for i in cut:
		g.cables[i] = 1
	root.get_node("EventBus").ship_changed.emit()
	_frames(2)

	# 3) Fuel used up: no correcting thrust any more; not after leaving either
	_setup(Vector2(15.0, -6.0))
	_fill_fuel(0.05)
	P.match_target = ""
	ui.toggle_match()
	_frames(60 * 5)
	_check("Treibstoff aufgebraucht", P.fuel() <= 0.0001)
	var e0 := _vrel()
	var g0: Vector2 = P.gravity(P.pos) * 1000.0 * 1000.0   # m/s² (Schwerkraft wirkt weiter)
	_frames(60 * 10)
	var e_drift := (_vrel() - e0 - g0 * 10.0 / 1000.0).length()
	_check("Without fuel: no correcting thrust (rest %.3f m/s)" % e_drift, e_drift < 0.05)
	ui.leave_flight()
	_check("Leaving the cockpit: matching off", P.match_target == "" and not ui.nav_open)
	_fill_fuel(400.0)
	var x0 := _vrel()
	var fuel_after_exit: float = P.fuel()
	_frames(60 * 10)
	_check("After leaving no correcting thrust, no consumption (%.3f m/s, %.3f)" % [(_vrel() - x0).length(), fuel_after_exit - P.fuel()],
		(_vrel() - x0).length() < 0.3 and fuel_after_exit - P.fuel() == 0.0)

	# 4) Save in free flight: flight state and target stay, matching only after pressing X again
	ui.toggle_nav(true)
	for k in 30:
		_frames(60)
		ui._check_helm_walk()
		if ui.nav_open:
			break
	_setup(Vector2(12.0, 4.0))
	ui.toggle_match()
	_frames(30)
	var pos_s: Vector2 = P.pos
	var vel_s: Vector2 = P.vel
	root.get_node("SaveSystem").save_game(true)
	gs.new_game()
	root.get_node("SaveSystem").load_game(true)
	_check("Loaded: free flight, position and speed taken over", P.docked == "" and P.pos.distance_to(pos_s) < 0.000001 and P.vel.distance_to(vel_s) < 0.000001)
	_check("… target taken over (%s)" % P.target, P.target == "l4")
	_check("… matching is off", P.match_target == "" and P.match_input == Vector2.ZERO)
	var l0 := _vrel()
	_frames(60 * 5)
	var lg: Vector2 = P.gravity(P.pos) * 1000.0 * 1000.0
	_check("… and does not start on its own (rest %.3f m/s)" % (_vrel() - l0 - lg * 5.0 / 1000.0).length(), (_vrel() - l0 - lg * 5.0 / 1000.0).length() < 0.05)
	mira = root.get_node("CrewSystem").player()
	helm = ui.helm_device()
	mira.pos = Vector2(helm.pos) + Vector2(-0.5, 1.5)
	ui.toggle_nav(true)
	ui.toggle_match()
	var l1 := _vrel().length()
	_frames(60 * 3)
	_check("Matching only after pressing X again (%.1f → %.1f m/s)" % [l1, _vrel().length()], P.match_target == "l4" and _vrel().length() < l1 - P.rcs_accel() * 1000.0 * 3.0 * 0.8)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
