## Tests für die manuelle Schiffssteuerung im Cockpit
##   godot --headless --path . --script res://tests/boot.gd -- test_flight
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var toasts: Array[String] = []
var gs
var P
var ui
var crew
var ship

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

## Spielzeit laufen lassen wie TimeSystem: pro Bild (1/60 s echt) factor Spielsekunden,
## aufgeteilt in Schritte von höchstens einer Spielsekunde.
func _frames(n: int, factor: float) -> void:
	for f in n:
		var total := (1.0 / 60.0) * factor / 60.0
		var steps := int(ceil(total / (1.0 / 60.0)))
		for k in steps:
			gs.step(total / steps)

func _secs(s: float) -> void:
	for k in int(s):
		gs.step(1.0 / 60.0)

func _rel(id: String) -> Vector2:
	return P.vel - P.rel_to(id).vel

## Frei treibend 2 km vor Tycho, ohne Relativgeschwindigkeit
func _free_near(id: String, dist_km: float, angle: float) -> void:
	var st: Dictionary = P.loc_state(P.loc(id), P.secs())
	P.pos = st.pos + Vector2(dist_km, 0)
	P.vel = st.vel
	P.angle = angle
	P.ang_vel = 0.0
	P.stop_inputs()

func _initialize() -> void:
	await process_frame
	await process_frame
	root.get_node("SaveSystem").slot = 914
	gs = root.get_node("GameState")
	P = root.get_node("PhysicsSystem")
	ui = root.get_node("UIManager")
	crew = root.get_node("CrewSystem")
	ship = root.get_node("ShipSystem")
	root.get_node("Settings").meteors = false
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(String(t)))
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.char_ui.creation.visible = false
	var mira = crew.player()
	mira.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	_secs(2)

	# 1) Ins Cockpit: Figur läuft zum Steuerpult, dann Flugmodus
	var helm = ui.helm_device()
	_check("Steuerpult vorhanden", helm != null)
	_check("Weit weg vom Pult: noch nicht im Cockpit", not mira.can_reach(helm.pos))
	ui.toggle_nav(true)
	_check("… Figur läuft zum Pult", ui._helm_walk and not ui.nav_open)
	for k in 30:
		_secs(1)
		ui._check_helm_walk()
		if ui.nav_open:
			break
	_check("Am Pult angekommen: Flugmodus an", ui.nav_open and ui.pilot == mira and mira.can_reach(helm.pos))
	_check("Ziel automatisch gesetzt (%s)" % P.target, P.target == "tycho")
	ui._refresh_nav()
	var texts: Array = []
	for l in ui.nav_side.find_children("*", "Label", true, false):
		texts.append(l.text)
	_check("Cockpit zeigt die Tastenbelegung", texts.has("Q / E") and texts.has("W / S") and texts.has("A / D") and texts.has("Esc / N"))
	ui.keep_pilot()
	_secs(5)
	_check("Pilot bleibt am Pult", mira.can_reach(helm.pos) and mira.task == "Steuert das Schiff")

	# 2) Abdocken, wegfliegen, Schub loslassen: Schiff driftet weiter
	_check("Abdocken", P.request_undock())
	_secs(20)
	_free_near("tycho", 2.0, PI)          # Nase zeigt nach Westen (zum Ziel)
	var v0 := _rel("tycho")
	P.thrust = 1.0
	_secs(10)
	P.thrust = 0.0
	var v1 := _rel("tycho")
	_check("Vorwärtsschub beschleunigt (%.1f m/s in 10 s)" % ((v1 - v0).length() * 1000.0), (v1 - v0).length() * 1000.0 > 5.0)
	_check("… in Richtung der Nase", rad_to_deg(absf((v1 - v0).angle_to(Vector2.from_angle(P.angle)))) < 2.0)
	_secs(30)
	var v2 := _rel("tycho")
	_check("Ohne Schub: Geschwindigkeit bleibt (%.2f → %.2f m/s)" % [v1.length() * 1000.0, v2.length() * 1000.0], absf(v2.length() - v1.length()) * 1000.0 < 0.5)
	var d_before: float = P.approach("tycho").dist
	_secs(10)
	_check("… und das Schiff driftet weiter (%.0f m näher)" % ((d_before - P.approach("tycho").dist) * 1000.0), P.approach("tycho").dist < d_before - 0.05)
	_check("Anzeige: Ziel wird angeflogen (Annäherung %.1f m/s)" % (P.approach("tycho").closing * 1000.0), P.approach("tycho").closing > 0.0)

	# 3) Drehen während der Drift: Ausrichtung ändert sich, Flugrichtung nicht
	var a0: float = P.angle
	var vr0 := _rel("tycho")
	P.rot_input = 1.0
	_secs(2)
	P.rot_input = 0.0
	_check("Drehung hat Schwung (%.0f °/s)" % rad_to_deg(P.ang_vel), absf(P.ang_vel) > 0.5)
	_secs(2)
	P.rot_stop = true
	_secs(5)
	P.rot_stop = false
	_check("R stoppt die Drehung", absf(P.ang_vel) < 0.001)
	var turned: float = rad_to_deg(absf(angle_difference(a0, P.angle)))
	var vr1 := _rel("tycho")
	_check("Ausrichtung geändert (%.0f°)" % turned, turned > 30.0)
	_check("Geschwindigkeitsvektor unverändert (%.2f m/s Abweichung)" % ((vr1 - vr0).length() * 1000.0), (vr1 - vr0).length() * 1000.0 < 0.5)

	# 4) Seitwärts- und Rückwärtsschub relativ zur Ausrichtung
	var vs0 := _rel("tycho")
	P.strafe = 1.0
	_secs(5)
	P.strafe = 0.0
	var dv: Vector2 = _rel("tycho") - vs0
	_check("Seitwärtsschub wirkt quer zur Nase (%.0f°)" % rad_to_deg(absf(dv.angle_to(Vector2.from_angle(P.angle + PI / 2.0)))), rad_to_deg(absf(dv.angle_to(Vector2.from_angle(P.angle + PI / 2.0)))) < 2.0)
	P.strafe = -1.0
	_secs(5)
	P.strafe = 0.0
	# 5) Bremsen mit Gegenschub: zur Flugrichtung drehen und S (zurück) halten
	P.angle = _rel("tycho").angle()
	var s0: float = _rel("tycho").length()
	P.thrust = -1.0
	for k in 600:
		_secs(1)
		if _rel("tycho").length() < 0.0005:
			break
	P.thrust = 0.0
	_check("Gegenschub bremst (%.1f → %.1f m/s)" % [s0 * 1000.0, _rel("tycho").length() * 1000.0], _rel("tycho").length() < 0.001 and s0 > 0.005)

	# 6) Anflug mit geringer Relativgeschwindigkeit und Andocken
	_free_near("tycho", 2.0, 0.0)
	var res := _fly_and_dock("tycho")
	_check("Anflug: Ziel erreicht und angedockt (%s)" % res, P.docked == "tycho")
	_check("Andock-Tempo war gering", res.begins_with("ok"))

	# 7) Andocken nur mit ausgerichteter Schleuse
	P.request_undock()
	_secs(20)
	var st: Dictionary = P.loc_state(P.loc("tycho"), P.secs())
	P.pos = st.pos + Vector2(0.1, 0)
	P.vel = st.vel
	P.angle = P.dock_alignment("tycho").angle + PI
	_check("Schleuse zeigt weg: kein Andocken (%s)" % P.dock_block_reason("tycho"), not P.can_dock("tycho") and "zeigt nicht zum Ziel" in P.dock_block_reason("tycho"))
	P.angle = P.dock_alignment("tycho").angle
	_check("Ausgerichtet: Andocken möglich", P.can_dock("tycho"))

	# 8) Cockpit verlassen: Schub endet, Charaktersteuerung zurück
	P.thrust = 1.0
	P.strafe = 1.0
	ui.leave_flight()
	_check("Verlassen: kein Schub mehr", P.thrust == 0.0 and P.strafe == 0.0 and P.rot_input == 0.0)
	_check("… Figur wieder frei", not ui.nav_open and not mira.is_manual())
	var mp: Vector2 = mira.pos
	mira.order_move(ship.spawn_point())
	_secs(10)
	_check("… und läuft wieder (%.1f Felder)" % mira.pos.distance_to(mp), mira.pos.distance_to(mp) > 1.0)
	ui.toggle_nav(true)
	for k in 30:
		_secs(1)
		ui._check_helm_walk()
		if ui.nav_open:
			break
	_check("Wieder ins Cockpit", ui.nav_open)
	mira.unconscious = true
	_check("Pilot fällt aus: Cockpit endet", not ui.keep_pilot() and not ui.nav_open)
	mira.unconscious = false

	# 9) Zeit: gleiche Spielzeit = gleiche Wirkung bei ×1, ×2, ×4, ×8, ×16
	var gains: Array = []
	for factor in [1.0, 2.0, 4.0, 8.0, 16.0]:
		_free_near("tycho", 50.0, PI)
		var g0 := _rel("tycho")
		var t0: float = gs.time
		P.thrust = 1.0
		_frames(int(1200.0 / factor), factor)   # 20 Spielsekunden Schub
		P.thrust = 0.0
		var gt: float = (gs.time - t0) * 60.0
		gains.append((_rel("tycho") - g0).length() * 1000.0)
		_frames(int(1200.0 / factor), factor)   # 20 Spielsekunden Drift
		_check("×%d: 20 s Schub = %.2f m/s in %.1f Spielsekunden" % [int(factor), gains[-1], gt], absf(gt - 20.0) < 0.01)
	_check("Gleiche Spielzeit, gleiche Wirkung auf allen Stufen (%s)" % str(gains.map(func(x): return snappedf(x, 0.01))), gains.all(func(x): return absf(x - gains[0]) < 0.05))
	_free_near("tycho", 50.0, PI)
	var h0 := _rel("tycho")
	P.thrust = 1.0
	_frames(60, 16.0)                       # 1 echte Sekunde bei ×16
	P.thrust = 0.0
	var at16: float = (_rel("tycho") - h0).length() * 1000.0
	_check("Eine echte Sekunde Schub bei ×16 wirkt wie 16 Sekunden (%.2f m/s)" % at16, absf(at16 - gains[0] * 0.8) < 0.2)

	# 10) Speichern und Laden behält Drehung und Ziel
	P.ang_vel = 0.3
	P.target = "karman"
	root.get_node("SaveSystem").save_game(true)
	gs.new_game()
	root.get_node("SaveSystem").load_game(true)
	_check("Nach dem Laden: Drehung und Ziel erhalten", absf(P.ang_vel - 0.3) < 0.0001 and P.target == "karman" and P.thrust == 0.0)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()

## Test-Pilot: nur Spieler-Eingaben (Schub, seitwärts, drehen, stoppen, andocken)
func _fly_and_dock(id: String) -> String:
	var max_v := 0.0
	for k in 1800:
		var ap: Dictionary = P.approach(id)
		var st: Dictionary = P.rel_to(id)
		var to_t: Vector2 = st.pos - P.pos
		var dir := to_t.normalized()
		var vrel: Vector2 = ap.vrel
		# Nase zum Ziel, Drehung ruhig halten
		var err := angle_difference(P.angle, dir.angle() if ap.dist > 0.18 else P.dock_alignment(id).angle)
		P.rot_input = clampf(err * 3.0 - P.ang_vel * 3.0, -1.0, 1.0)
		P.rot_stop = absf(err) < 0.02 and absf(P.ang_vel) > 0.0
		if P.rot_stop:
			P.rot_input = 0.0
		# Wunschtempo zum Ziel: so schnell, dass Bremsen mit den Lagedüsen noch reicht
		var want := minf(0.02, sqrt(2.0 * P.rcs_accel() * maxf(0.0, ap.dist - 0.1)) * 0.6)
		var along: float = ap.closing
		var lateral: Vector2 = vrel - dir * along
		# Schub entlang und quer, umgerechnet in Schiffskoordinaten
		var need: Vector2 = dir * (want - along) - lateral
		var fwd := Vector2.from_angle(P.angle)
		var right := Vector2.from_angle(P.angle + PI / 2.0)
		P.thrust = clampf(need.dot(fwd) * 400.0, -1.0, 1.0)
		P.strafe = clampf(need.dot(right) * 400.0, -1.0, 1.0)
		_secs(1)
		max_v = maxf(max_v, ap.speed)
		if P.can_dock(id):
			P.stop_inputs()
			var sp: float = P.approach(id).speed * 1000.0
			return ("ok %.1f m/s, Spitze %.0f m/s" % [sp, max_v * 1000.0]) if P.dock(id) else "Andocken abgelehnt"
	P.stop_inputs()
	return "nicht angekommen (%.0f m)" % (P.approach(id).dist * 1000.0)
