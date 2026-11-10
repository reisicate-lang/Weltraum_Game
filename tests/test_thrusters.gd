## Tests für einbaubare, drehbare Triebwerke: Schub, Masse, Beschleunigung
##   godot --headless --path . --script res://tests/boot.gd -- test_thrusters
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var gs
var P
var ship
var CS
var R

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _secs(s: float) -> void:
	for k in int(s):
		gs.step(1.0 / 60.0)

## Wie TimeSystem: pro Bild factor/60 Spielsekunden, in Schritten von höchstens 1 s
func _frames(n: int, factor: float) -> void:
	for f in n:
		var total := (1.0 / 60.0) * factor / 60.0
		var steps := int(ceil(total / (1.0 / 60.0)))
		for k in steps:
			gs.step(total / steps)

## Frei im All bei Habitat L4 (weit weg von Erde und Mond), ruhend, Nase nach Osten
func _park() -> void:
	var st: Dictionary = P.loc_state(P.loc("l4"), P.secs())
	P.pos = st.pos + Vector2(500.0, 0)
	P.vel = st.vel
	P.angle = 0.0
	P.ang_vel = 0.0
	P.stop_inputs()
	# Pilot steht am (einzigen) Steuerpult: nur dann gibt es manuellen Schub
	P.helm_at = P.ship_devices("helm")[0].pos

func _rel() -> Vector2:
	return P.vel - P.rel_to("l4").vel

## Geschwindigkeitsgewinn (m/s) nach `secs` Spielsekunden Schub in Richtung (vor, rechts).
## Die Schwerkraft von Erde und Mond wirkt auch hier; sie wird abgezogen, indem dieselbe
## Zeit einmal ohne Schub gerechnet wird (gleicher Startpunkt).
func _burn(fwd: float, right: float, secs: float) -> float:
	return _burn_vec(fwd, right, secs).length() * 1000.0

func _burn_vec(fwd: float, right: float, secs: float) -> Vector2:
	var t_start: float = gs.time
	_park()
	var v0 := _rel()
	_secs(secs)
	var coast := _rel() - v0
	gs.time = t_start
	_park()
	v0 = _rel()
	P.thrust = fwd
	P.strafe = right
	_secs(secs)
	P.stop_inputs()
	return _rel() - v0 - coast

func _count_type(type: String) -> int:
	var n := 0
	for c in root.get_node("CrewSystem").crew:
		n += c.inv.count(type)
	for i in ship.grid.piles:
		n += ship.grid.piles[i].count(type)
	return n

func _until_done(p: Vector2i, max_s: int = 1200) -> bool:
	var g = ship.grid
	for k in max_s:
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(g.idx(p)):
			return true
	return false

func _initialize() -> void:
	await process_frame
	await process_frame
	root.get_node("SaveSystem").slot = 915
	gs = root.get_node("GameState")
	P = root.get_node("PhysicsSystem")
	ship = root.get_node("ShipSystem")
	CS = root.get_node("ShipConstructionSystem")
	R = root.get_node("RemovalSystem")
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var g = ship.grid
	var x0: int = (g.width - 16) / 2
	var y0: int = (g.height - 10) / 2
	var mira = root.get_node("CrewSystem").player()
	mira.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	_secs(2)
	seat_pilot()   # Pilot am Steuerpult (Flugbefehle nur dort)
	P.request_undock()
	_secs(2)
	# Startschiff: zwei 1×3-Triebwerke durch die hintere Außenwand (Düse nach hinten, Schub nach vorn)
	var t1: Vector2i = Vector2i(x0 + 1, y0 + 2)
	var t2: Vector2i = Vector2i(x0 + 1, y0 + 3)
	var thr: float = root.get_node("ItemSystem").device("thruster").thrust
	var rcs: float = P.rcs_thrust()
	_check("Startschiff: zwei Triebwerke nach vorn (%d kN)" % int(P.thrust_dir(Vector2i(1, 0))), P.thrust_dir(Vector2i(1, 0)) == 2.0 * thr)
	_check("Triebwerk hat Masse 1,5 t", root.get_node("ItemSystem").device("thruster").mass == 1.5)
	_check("… und belegt 3 Felder: innen, Außenwand, Düse im All", g.device_at(t1) == g.device_at(t1 + Vector2i(-1, 0)) and g.device_at(t1) == g.device_at(t1 + Vector2i(-2, 0))
		and g.get_tile(t1 + Vector2i(-1, 0)) == ShipGrid.Tile.WALL and g.get_tile(t1 + Vector2i(-2, 0)) == ShipGrid.Tile.SPACE)

	# 1) Gleiche Masse: ein aktives gegen zwei aktive Triebwerke
	g.device_at(t2).broken = true          # bleibt eingebaut (gleiche Masse), liefert keinen Schub
	_secs(1)
	var m1: float = P.mass()
	var dv1 := _burn(1.0, 0.0, 10)
	g.device_at(t2).broken = false
	g.device_at(t2).cond = 100.0
	_secs(1)
	var m2: float = P.mass()
	var dv2 := _burn(1.0, 0.0, 10)
	var expect1 := (thr + rcs) / m1 * 10.0
	var expect2 := (2.0 * thr + rcs) / m2 * 10.0
	_check("Gleiche Masse (%.2f t = %.2f t)" % [m1, m2], absf(m1 - m2) < 0.001)
	_check("1 Triebwerk: %.2f m/s in 10 s (erwartet %.2f = %d kN ÷ %.1f t)" % [dv1, expect1, int(thr + rcs), m1], absf(dv1 - expect1) < 0.05)
	_check("2 Triebwerke: %.2f m/s in 10 s (erwartet %.2f)" % [dv2, expect2], absf(dv2 - expect2) < 0.05)
	_check("Zwei gleich ausgerichtete beschleunigen stärker (×%.2f)" % (dv2 / dv1), dv2 > dv1 * 1.5)

	# 2) Leichtes gegen schweres Schiff bei gleichem Schub
	var light_m: float = P.mass()
	var dv_light := _burn(1.0, 0.0, 10)
	var ballast: Array = []
	for k in 50:
		var q := Vector2i(2 + k % 10, 2 + k / 10)    # 50 Bodenfelder Ballast (+10 t)
		g.tiles[g.idx(q)] = ShipGrid.Tile.FLOOR
		ballast.append(g.idx(q))
	var heavy_m: float = P.mass()
	var dv_heavy := _burn(1.0, 0.0, 10)
	for i in ballast:
		g.tiles[i] = ShipGrid.Tile.SPACE
	_check("Ballast macht das Schiff schwerer (%.1f → %.1f t)" % [light_m, heavy_m], absf(heavy_m - light_m - 10.0) < 0.001)
	_check("Leichtes Schiff schneller (%.2f > %.2f m/s)" % [dv_light, dv_heavy], dv_light > dv_heavy)
	_check("… genau im Verhältnis der Massen", absf(dv_light / dv_heavy - heavy_m / light_m) < 0.01)

	# 3a) Ein Triebwerk, das nach rechts schiebt: oben in die Außenwand bauen (Düse nach oben)
	for dv in g.devices.values():
		if dv.type == "crate" and g.zone[g.idx(dv.pos)] == 0:
			dv.inv.add("motor", 2, 90.0)
			dv.inv.add("pipe", 6, 90.0)
			dv.inv.add("plate", 8, 90.0)
			break
	var tr: Vector2i = Vector2i(x0 + 12, y0 + 1)   # Cockpit, oben an der Außenwand
	g.cables[g.idx(tr)] = 1                       # Kabel ans Netz (Heizung daneben)
	CS.build_rot = 1
	_check("Rechts-Triebwerk oben planbar (%s)" % CS.place_reason("dev:thruster", tr), CS.place("dev:thruster", tr))
	_check("Crew baut es", _until_done(tr, 3600) and g.device_at(tr) != null and g.device_at(tr).rot == 1)
	_secs(1)
	_check("Danach: vorn %d kN, rechts %d kN" % [int(P.thrust_dir(Vector2i(1, 0))), int(P.thrust_dir(Vector2i(0, 1)))],
		P.thrust_dir(Vector2i(1, 0)) == 2.0 * thr and P.thrust_dir(Vector2i(0, 1)) == thr)
	var m_rot: float = P.mass()
	var dv_fwd := _burn(1.0, 0.0, 10)
	var dv_right := _burn(0.0, 1.0, 10)
	_check("W wirkt mit beiden hinteren Triebwerken (%.2f m/s)" % dv_fwd, absf(dv_fwd - (2.0 * thr + rcs) / m_rot * 10.0) < 0.05)
	_check("D (rechts) nutzt das obere Triebwerk (%.2f m/s)" % dv_right, absf(dv_right - (thr + rcs) / m_rot * 10.0) < 0.05)
	var side_dv := _burn_vec(0.0, 1.0, 5)
	_check("… und schiebt wirklich nach rechts (quer zur Nase)", rad_to_deg(absf(side_dv.angle_to(Vector2.from_angle(P.angle + PI / 2.0)))) < 1.0)

	# 3b) Speichern und Laden: Richtung, Felder und Schub bleiben
	root.get_node("SaveSystem").save_game(true)
	gs.new_game()
	root.get_node("SaveSystem").load_game(true)
	g = ship.grid
	_secs(1)
	_check("Nach dem Laden: Richtung und alle 3 Felder erhalten", g.device_at(tr) != null and g.device_at(tr).rot == 1 and g.device_at(tr + Vector2i(0, -2)) == g.device_at(tr)
		and g.migrated.packed == 0 and g.migrated.converted == 0)
	_check("… und dieselben Schubwerte", P.thrust_dir(Vector2i(1, 0)) == 2.0 * thr and P.thrust_dir(Vector2i(0, 1)) == thr and absf(P.mass() - m_rot) < 0.001)

	# 3c) Triebwerk abbauen (über das Düsenfeld): Schub weg, Teil liegt innen am Boden
	mira = root.get_node("CrewSystem").player()
	var m_before: float = P.mass()
	_check("Abbau über das Düsenfeld beauftragt", R.order("uninstall", tr + Vector2i(0, -2)) == "" and CS.jobs.has(g.idx(tr)))
	_until_done(tr)
	_secs(1)
	var pile = g.piles.get(g.idx(tr))
	_check("Ausgebaut: Schub rechts weg, alle 3 Felder frei", P.thrust_dir(Vector2i(0, 1)) == 0.0 and g.device_at(tr) == null and g.device_at(tr + Vector2i(0, -1)) == null and g.device_at(tr + Vector2i(0, -2)) == null)
	_check("… Wand bleibt", g.get_tile(tr + Vector2i(0, -1)) == ShipGrid.Tile.WALL)
	_check("… ein Triebwerk-Gegenstand liegt innen (%.0f kg)" % (pile.weight() if pile != null else -1.0), pile != null and pile.count("pk_thruster") == 1 and absf(pile.weight() - 1500.0) < 0.001)
	_check("… Masse unverändert: das Teil ist ja noch an Bord (%.3f t)" % (m_before - P.mass()), absf(m_before - P.mass()) < 0.000001)
	# 3d) Wieder einbauen: Crew trägt es in den Händen, Masse bleibt, Schub kommt zurück
	CS.build_rot = 1
	_check("Einbau planbar", CS.place("install:pk_thruster", tr))
	var installed := _until_done(tr, 3600)
	_secs(1)
	_check("Wieder eingebaut (nach rechts)", installed and g.device_at(tr) != null and g.device_at(tr).rot == 1 and P.thrust_dir(Vector2i(0, 1)) == thr)
	_check("… Masse unverändert (%.3f t)" % (P.mass() - m_before), absf(P.mass() - m_before) < 0.000001 and _count_type("pk_thruster") == 0)
	# 3e) Ein neues Triebwerk bauen (vorn rechts, Düse nach vorn = Schub zurück)
	var spot := Vector2i(x0 + 14, y0 + 2)   # Kabel liegt hier schon (Steuerpult-Leitung)
	CS.build_rot = 2
	var m_b: float = P.mass()
	_check("Vorderes Triebwerk planbar (%s)" % CS.place_reason("dev:thruster", spot), CS.place("dev:thruster", spot))
	var built := _until_done(spot, 3600)
	_secs(1)
	var used: float = (4 * 8.0 + 6.0 + 3 * 2.0) / 1000.0   # 4 Platten, 1 Motor, 3 Rohre aus dem Lager
	_check("Crew baut ein neues Triebwerk", built and g.device_at(spot) != null and g.device_at(spot).type == "thruster")
	_check("Einbau: +1,5 t Triebwerk, abzüglich verbautem Material (%.3f t mehr)" % (P.mass() - m_b), absf(P.mass() - m_b - (1.5 - used)) < 0.001)
	_check("… und zurück %d kN" % int(P.thrust_dir(Vector2i(-1, 0))), P.thrust_dir(Vector2i(-1, 0)) == thr and P.thrust_dir(Vector2i(1, 0)) == 2.0 * thr)

	# 4) Gleiche Flugsequenz bei ×1 und ×16 über dieselbe Spielzeit, danach Drift
	var res: Array = []
	for factor in [1.0, 16.0]:
		_park()
		var a0 := _rel()
		var t0: float = gs.time
		P.thrust = 1.0
		_frames(int(1200.0 / factor), factor)   # 20 Spielsekunden Schub
		P.thrust = 0.0
		var after := _rel()
		var spent: float = (gs.time - t0) * 60.0
		var g_acc: Vector2 = P.gravity(P.pos)       # Schwerkraft wirkt auch beim Driften
		_frames(int(1800.0 / factor), factor)   # 30 Spielsekunden Drift
		var drift := _rel()
		res.append([(after - a0).length() * 1000.0, spent, (drift - after - g_acc * 30.0).length() * 1000.0])
	_check("×1: %.3f m/s nach %.1f s, ×16: %.3f m/s nach %.1f s" % [res[0][0], res[0][1], res[1][0], res[1][1]],
		absf(res[0][0] - res[1][0]) < 0.01 and absf(res[0][1] - res[1][1]) < 0.01)
	_check("Drift ohne Schub: Tempo bleibt bis auf die Schwerkraft (Rest %.4f / %.4f m/s in 30 s)" % [res[0][2], res[1][2]], res[0][2] < 0.01 and res[1][2] < 0.01)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
