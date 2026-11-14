## Tests: Manueller Flug ist an das Steuerpult gebunden, an dem der Pilot steht
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

## Ein Bild bei ×1 mit gehaltenen Tasten, so wie scenes/main/main.gd sie verarbeitet:
## Nur im Cockpit (und solange der Pilot am Pult bleibt) setzen W/S/A/D/Q/E Eingaben.
func _frame(w: float = 0.0, q: bool = false) -> void:
	if ui.nav_open and ui.keep_pilot():
		P.thrust = w
		P.rot_input = -1.0 if q else 0.0
	gs.step(1.0 / 60.0 / 60.0)
	ui._check_helm_walk()

## Bilder wie TimeSystem bei ×factor (ohne Tasten)
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

## Geschwindigkeitsänderung durch die Schwerkraft allein über n Bilder (zum Abziehen)
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

## Knöpfe „Ausrichten“ und „Angleichen“ der aktuell angezeigten Zielliste
## (alte Zeilen sind nach dem Neuaufbau nur zum Löschen vorgemerkt)
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
		gs.step(1.0 / 60.0)              # Strom verteilen
	seat_pilot()
	P.request_undock()
	P.helm_at = P.NO_HELM                  # wieder niemand am Pult
	for k in 60 * 20:
		gs.step(1.0 / 60.0 / 60.0)
	var g = ship.grid
	_check("Frei im All (%s)" % P.undock_block_reason(), P.docked == "")

	# Zweites Pult weit weg vom ersten, auf einem Kabelfeld (also mit Strom)
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
	_check("Zwei Pulte, beide versorgt und intakt (Abstand %.0f Felder)" % best, near.powered and far.powered and best >= 4.0)

	# 1) Erreichbares Pult kaputt bzw. ohne Strom, das entfernte funktioniert
	for mode in ["kaputt", "ohne Strom"]:
		_park()
		mira.pos = _beside(near)
		mira.path.clear()
		mira.order = null
		if mode == "kaputt":
			near.broken = true
		else:
			_cut(near)
		_check("1 (%s): Pult am Piloten erreichbar, anderes Pult versorgt" % mode, mira.can_reach(near.pos) and not mira.can_reach(far.pos) and far.powered and not far.broken and P.helm_ok())
		var v0 := _vrel()
		var f0: float = P.fuel()
		toasts.clear()
		ui.toggle_nav(true)                 # N
		_check("1 (%s): N wird abgewiesen (%s)" % [mode, toasts[-1] if not toasts.is_empty() else ""], not ui.nav_open and P.helm_at == P.NO_HELM and not toasts.is_empty() and ("broken" in toasts[-1] or "power" in toasts[-1]))
		ui.request_flight(near)             # Klick aufs Pult
		_check("1 (%s): Klick wird abgewiesen" % mode, not ui.nav_open and not ui._helm_walk)
		_frames(120, 1.0, true)             # W und Q halten
		_check("1 (%s): W/Q erzeugen keinen Schub und keine Drehung" % mode, (_vrel() - v0 - _grav(120)).length() < 0.01 and P.ang_vel == 0.0 and P.fuel() == f0)
		# Auch wenn das Cockpit an diesem Pult offen wäre: die Physik gibt keinen Schub,
		# obwohl das andere Pult Strom hat (früher reichte irgendein versorgtes Pult).
		P.helm_at = near.pos
		P.thrust = 1.0
		P.rot_input = -1.0
		v0 = _vrel()
		for k in 120:
			gs.step(1.0 / 60.0 / 60.0)
		_check("1 (%s): Physik am gebundenen Pult: kein Schub, keine Drehung" % mode, (_vrel() - v0 - _grav(120)).length() < 0.01 and P.ang_vel == 0.0 and P.thrust == 0.0 and P.fuel() == f0)
		P.helm_at = P.NO_HELM
		near.broken = false
		_wire(near)

	# 2) Zum funktionierenden Pult wechseln, fliegen, dann fällt dessen Strom unter W aus
	_park()
	mira.pos = _beside(near)
	near.broken = true                      # das nahe Pult bleibt kaputt
	ui.request_flight(far)                  # Klick aufs entfernte Pult: Mira läuft hin
	_check("2: Mira geht zum funktionierenden Pult", ui._helm_walk and not ui.nav_open)
	for k in 60 * 60:
		_frame()
		if ui.nav_open:
			break
	_check("2: Im Cockpit am entfernten Pult", ui.nav_open and P.helm_at == far.pos and mira.can_reach(far.pos))
	near.broken = false                     # jetzt sind beide Pulte in Ordnung
	_park()
	var v1 := _vrel()
	var f1: float = P.fuel()
	_frames(120, 1.0)                       # W 2 s
	var dv := _vrel() - v1 - _grav(120)
	var a_exp: float = (P.max_thrust() + P.rcs_thrust()) / P.mass()   # m/s²
	_check("2: W gibt Schub (%.2f m/s, erwartet %.2f)" % [dv.length(), a_exp * 2.0], absf(dv.length() - a_exp * 2.0) < 0.1 and P.fuel() < f1)
	_frames(30, 0.0, true)                  # Q 0,5 s
	var w_q: float = P.ang_vel
	_check("2: Q dreht (%.3f rad/s)" % w_q, w_q < -0.1)
	P.ang_vel = 0.0
	# W halten, dann fällt der Strom am bedienten Pult aus; das andere Pult hat weiter Strom
	_frames(30, 1.0)
	P.rot_input = 0.0
	toasts.clear()
	_cut(far)
	_check("2: Bedientes Pult ohne Strom, anderes versorgt", not far.powered and near.powered and not near.broken and P.helm_ok())
	_frame(1.0)
	var v_cut := _vrel()
	var f_cut: float = P.fuel()
	var vel_cut: Vector2 = P.vel
	_frames(120, 1.0, true)                 # W und Q weiter gehalten
	_check("2: Schub endet (Δv %.4f m/s, Treibstoff %.3f)" % [(_vrel() - v_cut - _grav(120)).length(), f_cut - P.fuel()],
		(_vrel() - v_cut - _grav(120)).length() < 0.01 and P.fuel() == f_cut and P.thrust == 0.0)
	_check("2: Vorhandene Bewegung bleibt (%.2f m/s)" % (vel_cut.length() * 1000.0), vel_cut.length() > 0.0 and absf((P.vel - vel_cut).length() * 1000.0 - _grav(120).length()) < 0.01 and _vrel().length() > 1.0)
	_check("2: Keine Drehung ohne versorgtes Pult", P.ang_vel == 0.0)
	_check("2: Meldung „Schub beendet“ (%s)" % ", ".join(toasts), toasts.any(func(t): return t.begins_with("Thrust stopped")))
	_check("2: Cockpit zeigt den Grund", P.helm_block_reason(P.operated_helm()) == "This navigation console has no power.")
	# Drehung, die schon läuft, dreht weiter
	_wire(far)
	_frames(30, 0.0, true)
	var w0: float = P.ang_vel
	_cut(far)
	var a0: float = P.angle
	_frames(60, 0.0, true)
	_check("2: Laufende Drehung geht ohne Strom weiter (%.3f rad/s)" % P.ang_vel, P.ang_vel == w0 and absf(P.angle - a0) > 0.01)
	P.ang_vel = 0.0
	# Angleichen endet beim Ausfall, obwohl das andere Pult Strom hat
	_wire(far)
	_park()
	P.vel += Vector2(0.01, 0)
	ui.toggle_match()
	_frames(30)
	_check("2: Angleichen läuft am bedienten Pult", P.match_target == "l4")
	toasts.clear()
	_cut(far)
	var vm := _vrel()
	_frames(60)
	_check("2: Angleichen endet beim Ausfall (%s)" % ", ".join(toasts), P.match_target == "" and toasts.any(func(t): return t.begins_with("Matching stopped")) and (_vrel() - vm - _grav(60)).length() < 0.01)
	ui.toggle_match()
	_check("2: Angleichen lässt sich ohne Strom nicht einschalten", P.match_target == "")
	_wire(far)
	ui.leave_flight()
	_check("2: Cockpit verlassen gibt das Pult frei", P.helm_at == P.NO_HELM)

	# 4) Abdocken, Schnellreise und Auto-Dock nur am bedienten, intakten Pult mit Strom
	P.dock("l4", true)
	for k in 60 * 20:
		gs.step(1.0 / 60.0 / 60.0)          # Sperre gegen Wieder-Andocken spielt hier keine Rolle
	mira.pos = _beside(near)
	mira.path.clear()
	mira.order = null
	_check("4: Angedockt an L4, beide Pulte in Ordnung, niemand am Pult", P.docked == "l4" and P.helm_at == P.NO_HELM and P.helm_ok())
	toasts.clear()
	_check("4: Ohne Pilot am Pult: Abdocken verweigert (%s)" % P.undock_block_reason(), not P.request_undock() and P.docked == "l4" and "cockpit" in toasts[-1])
	P.travel_to("karman")
	_check("4: … Schnellreise verweigert", P.travel.is_empty() and P.docked == "l4" and "cockpit" in toasts[-1])
	P.start_autodock()
	_check("4: … Auto-Dock verweigert", P.autodock.is_empty() and "cockpit" in toasts[-1])
	for mode in ["kaputt", "ohne Strom"]:
		if mode == "kaputt":
			near.broken = true
		else:
			_cut(near)
		P.helm_at = near.pos                # Pilot steht am nahen Pult
		toasts.clear()
		_check("4 (%s): Abdocken verweigert, obwohl das andere Pult geht (%s)" % [mode, P.undock_block_reason()], P.helm_ok() and not P.request_undock() and P.docked == "l4" and ("broken" in toasts[-1] or "power" in toasts[-1]))
		P.travel_to("karman")
		_check("4 (%s): Schnellreise verweigert" % mode, P.travel.is_empty() and P.docked == "l4")
		P.start_autodock()
		_check("4 (%s): Auto-Dock verweigert (%s)" % [mode, toasts[-1]], P.autodock.is_empty() and ("broken" in toasts[-1] or "power" in toasts[-1]))
		near.broken = false
		_wire(near)
	P.helm_at = P.NO_HELM
	mira.pos = _beside(far)
	ui.request_flight(far)
	_check("4: Im Cockpit am funktionierenden Pult", ui.nav_open and P.helm_at == far.pos)
	_check("4: Abdocken am bedienten Pult klappt", P.request_undock() and P.docked == "")
	for k in 60 * 16:
		gs.step(1.0 / 60.0 / 60.0)          # Sperre gegen sofortiges Wieder-Andocken abwarten
	near.inv.move_to(far.inv, "mod_autodock", 1)   # Autodock-Modul ins bediente Pult legen
	toasts.clear()
	P.start_autodock()
	_check("4: Auto-Dock am bedienten Pult startet (%s)" % toasts[-1], not P.autodock.is_empty())
	P.autodock = {}
	# Knöpfe „Ausrichten“ und „Angleichen“ in der Zielliste: nur mit versorgtem Pult
	P.target = "l4"
	_cut(far)
	ui._last_nav = ""
	ui._refresh_nav()
	var btns: Array = _nav_buttons()
	_check("4: Ohne Strom sind „Ausrichten“ und „Angleichen“ gesperrt (%d Knöpfe)" % btns.size(), not btns.is_empty() and btns.all(func(b): return b.disabled))
	var ang: float = P.angle
	for b in btns:
		b.pressed.emit()
	_check("4: … und bewirken nichts", P.angle == ang and P.match_target == "")
	_wire(far)
	ui._last_nav = ""
	ui._refresh_nav()
	btns = _nav_buttons()
	_check("4: Mit Strom wieder bedienbar", not btns.is_empty() and btns.all(func(b): return not b.disabled))
	P.travel_to("karman")
	_check("4: Schnellreise am bedienten Pult startet", not P.travel.is_empty())
	P.travel = {}
	ui.leave_flight()

	# 5) Andocken, laufende Schnellreise/Auto-Dock und „Ausrichten“ am bedienten Pult
	for k in 60 * 16:
		gs.step(1.0 / 60.0 / 60.0)
	var l4: Dictionary = P.loc_state(P.loc("l4"), P.secs())
	P.pos = l4.pos + Vector2(0.05, 0)
	P.vel = l4.vel
	P.ang_vel = 0.0
	P.angle = P.dock_alignment("l4").angle
	P.helm_at = P.NO_HELM
	_check("5: Ohne Pilot am Pult: Andocken verweigert (%s)" % P.dock_block_reason("l4"), not P.can_dock("l4") and not P.dock("l4") and P.docked == "" and "cockpit" in P.dock_block_reason("l4"))
	near.broken = true
	P.helm_at = near.pos
	_check("5: Am kaputten Pult: Andocken verweigert (%s)" % P.dock_block_reason("l4"), not P.dock("l4") and "broken" in P.dock_block_reason("l4"))
	near.broken = false
	mira.pos = _beside(far)
	ui.request_flight(far)
	_check("5: Am funktionierenden Pult: Andocken klappt", ui.nav_open and P.dock("l4") and P.docked == "l4")
	# Schnellreise bricht ab, wenn das startende Pult ausfällt
	for t in P.ship_devices("fueltank"):
		t.stock = 400.0
	P.travel_to("karman")
	_check("5: Schnellreise läuft", not P.travel.is_empty() and P.docked == "")
	ui.leave_flight()
	for k in 60 * 60:
		gs.step(1.0 / 60.0 / 60.0)
	_check("5: Cockpit verlassen: Reise läuft weiter", not P.travel.is_empty())
	root.get_node("SaveSystem").save_game(true)
	root.get_node("SaveSystem").load_game(true)
	far = ship.grid.device_at(far.pos)
	near = ship.grid.device_at(near.pos)
	_check("5: Geladen: Reise läuft weiter, Pult als Position gemerkt", not P.travel.is_empty() and Vector2i(int(P.travel.hx), int(P.travel.hy)) == far.pos)
	toasts.clear()
	_cut(far)
	gs.step(1.0 / 60.0 / 60.0)
	_check("5: Pult fällt aus: Reise abgebrochen (%s)" % (toasts[-1] if not toasts.is_empty() else ""), P.travel.is_empty() and P.docked == "" and toasts.any(func(t): return t.begins_with("Fast travel aborted")))
	var v_tr: float = P.vel.length()
	var p_tr: Vector2 = P.pos
	for k in 60:
		gs.step(1.0 / 60.0 / 60.0)
	_check("5: Schiff fliegt frei mit Reisegeschwindigkeit weiter (%.2f km/s)" % v_tr, v_tr > 1.0 and P.pos.distance_to(p_tr) > 0.5)
	_wire(far)
	# Auto-Dock bricht ab, wenn das startende Pult ausfällt
	l4 = P.loc_state(P.loc("l4"), P.secs())
	P.pos = l4.pos + Vector2(0.5, 0)
	P.vel = l4.vel
	mira = root.get_node("CrewSystem").player()
	mira.pos = _beside(far)
	ui.request_flight(far)
	P.start_autodock()
	_check("5: Auto-Dock läuft", not P.autodock.is_empty())
	toasts.clear()
	_cut(far)
	gs.step(1.0 / 60.0 / 60.0)
	_check("5: Pult fällt aus: Auto-Dock abgebrochen (%s)" % (toasts[-1] if not toasts.is_empty() else ""), P.autodock.is_empty() and P.docked == "" and toasts.any(func(t): return t.begins_with("Auto-Dock aborted")))
	_wire(far)
	# „Ausrichten“ dreht mit Drehschub statt sofort, bei ×1 und ×16
	for factor in [1.0, 16.0]:
		P.angle = 0.0
		P.ang_vel = 0.0
		var f5: float = P.fuel()
		P.start_align(PI / 2.0)
		_frames_f(1, factor)
		_check("5 (×%d): Ausrichten springt nicht (%.3f rad nach einem Bild)" % [int(factor), P.angle], P.aligning and P.angle < 0.05)
		var secs_needed := 0.0
		for k in 60 * 30:
			_frames_f(1, factor)
			secs_needed += factor / 60.0
			if not P.aligning:
				break
		_check("5 (×%d): Ausrichten endet genau auf 90° ohne Restdrehung (%.4f rad, %.1f s)" % [int(factor), P.angle, secs_needed],
			not P.aligning and absf(P.angle - PI / 2.0) < 0.001 and P.ang_vel == 0.0 and secs_needed > 2.0)
		_check("5 (×%d): … und verbraucht Treibstoff" % int(factor), P.fuel() < f5)
	P.angle = 0.0
	P.start_align(PI)
	_frames_f(30, 1.0)
	_frame(0.0, true)                       # Q
	_check("5: Q bricht Ausrichten ab", not P.aligning)
	P.ang_vel = 0.0
	P.start_align(PI / 2.0)
	_cut(far)
	_frames_f(10, 1.0)
	_check("5: Pult ohne Strom: Ausrichten endet", not P.aligning)
	toasts.clear()
	P.start_align(0.0)
	_check("5: … und startet nicht (%s)" % (toasts[-1] if not toasts.is_empty() else ""), not P.aligning and not toasts.is_empty())
	_wire(far)
	ui.leave_flight()

	# 3) Spielstand mit einem intakten Pult laden: Klick und N gehen weiter
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	for k in 3:
		gs.step(1.0 / 60.0)              # Strom verteilen
	seat_pilot()
	P.request_undock()
	P.helm_at = P.NO_HELM                  # wieder niemand am Pult
	for k in 60 * 20:
		gs.step(1.0 / 60.0 / 60.0)
	mira = root.get_node("CrewSystem").player()
	var helm = P.ship_devices("helm")[0]
	mira.pos = _beside(helm)
	ui.toggle_nav(true)
	_check("3: Vor dem Speichern im Cockpit", ui.nav_open and P.helm_at == helm.pos)
	var save = root.get_node("SaveSystem")
	save.save_game(true)
	var txt := FileAccess.get_file_as_string(save.path())
	_check("3: Spielstand enthält keine Pult-Bindung", txt != "" and not "helm_at" in txt and not "operated" in txt)
	gs.new_game()
	save.load_game(true)
	mira = root.get_node("CrewSystem").player()
	helm = P.ship_devices("helm")[0]
	_check("3: Geladen: genau ein intaktes Pult, keine Bindung", P.ship_devices("helm").size() == 1 and not helm.broken and P.helm_at == P.NO_HELM)
	_frame()   # altes Cockpit (vor dem Laden geöffnet) schließt sich: Pilot gibt es nicht mehr
	_check("3: Ohne Einstieg kein Schub", not ui.nav_open and not P.manual_ok())
	mira.pos = _beside(helm)
	ui.toggle_nav(true)                     # N
	_check("3: N: Einstieg klappt", ui.nav_open and P.helm_at == helm.pos and ui.pilot == mira)
	_park()
	var v3 := _vrel()
	_frames(60, 1.0)
	_check("3: W gibt Schub", (_vrel() - v3 - _grav(60)).length() > 0.5)
	ui.leave_flight()
	ui.request_flight(ship.grid.device_at(helm.pos))   # Klick aufs Pult
	_check("3: Klick: Einstieg klappt", ui.nav_open and P.helm_at == helm.pos)
	ui.leave_flight()

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
