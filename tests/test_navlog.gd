## Tests: nav console PROX WARN (5 km, can be muted) and ship logs (Ostranauts Flying 2.1)
##   godot --headless --path . --script res://tests/boot.gd -- test_navlog
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _initialize() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var SS = root.get_node("SaveSystem")
	SS.slot = 954
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	seat_pilot()
	var P = root.get_node("PhysicsSystem")
	root.get_node("ShipPowerSystem").step(0.01)

	# 1) Docked: no warning, log empty
	_check("Docked: no PROX WARN, log empty", P.prox_warning() == "" and P.proximity().is_empty() and P.ship_log.is_empty())

	# 2) Undocking: log entry, Tycho within 5 km → PROX WARN
	_check("Abdocken klappt", P.undock())
	_check("Log: “Undocked: Tycho…” (%s)" % str(P.ship_log), P.ship_log.size() == 1 and String(P.ship_log[0].text).begins_with("Undocked: Tycho"))
	var w: String = P.prox_warning()
	_check("PROX WARN nahe Tycho: %s" % w, w.begins_with("PROX WARN: Tycho") and w.ends_with("km"))
	var ui = root.get_node("UIManager")
	ui.nav_open = true
	ui._last_nav = ""
	ui._refresh_nav()
	var texts := []
	var mute: Button = null
	for ch in ui.nav_side.get_children():
		if ch.is_queued_for_deletion():
			continue
		for x in [ch] + ch.get_children():
			if x is Label:
				texts.append(x.text)
			if x is Button and x.text == "Mute":
				mute = x
	_check("The cockpit shows PROX WARN with “Mute” and SHIP LOGS", texts.any(func(t): return String(t).contains("PROX WARN")) and mute != null and texts.has("SHIP LOGS"))
	mute.pressed.emit()
	ui.nav_open = false
	_check("Mute-Knopf schaltet stumm", P.prox_muted)
	P.prox_muted = true
	_check("Muted: no warning, the proximity stays known", P.prox_warning() == "" and not P.proximity().is_empty())
	P.prox_muted = false
	# 3) Far away: no warning
	var home: Vector2 = P.pos
	P.pos = home + Vector2(400.0, 400.0)
	_check("Far away (%.0f km): no warning" % P.nearest().dist, P.prox_warning() == "")
	P.pos = home

	# 4) Collision: log with the speed
	var st: Dictionary = P.loc_state(P.loc("tycho"), P.secs())
	P.pos = st.pos
	P.vel = st.vel + Vector2(0.05, 0.0)
	P._check_hazards()
	var last: Dictionary = P.ship_log[P.ship_log.size() - 1]
	_check("Log: collision (%s)" % last.text, String(last.text).begins_with("Collision with Tycho") and String(last.text).contains("m/s"))

	# 5) Docking: log
	P.dock("tycho", true)
	_check("Log: “Docked: Tycho…”", String(P.ship_log[P.ship_log.size() - 1].text).begins_with("Docked: Tycho"))

	# 6) At most 50 entries, saving/loading
	for k in 60:
		P.log_event("Test %d" % k)
	_check("At most %d entries, the oldest drop out" % P.LOG_MAX, P.ship_log.size() == P.LOG_MAX and P.ship_log[P.LOG_MAX - 1].text == "Test 59")
	P.prox_muted = true
	SS.save_game()
	P.ship_log.clear()
	P.prox_muted = false
	SS.load_game(true)
	_check("Saving/loading: log and muting stay", P.ship_log.size() == P.LOG_MAX and P.prox_muted)
	gs.new_game()
	_check("New game: log empty, alarm on", P.ship_log.is_empty() and not P.prox_muted)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
