## Raumfahrt: Das Schiff ist ein Punkt im verkleinerten Erde-Mond-System
## mit Position, Geschwindigkeit und Ausrichtung. Erde und Mond ziehen
## es an. Triebwerke beschleunigen in Blickrichtung (Trägheit!).
## Einheiten: km, km/s, Sekunden. Daten: res://data/space.json
extends Node

var space: Dictionary = {}
var locations: Array = []

## Schiffszustand
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var angle := 0.0
var docked := "tycho"
var travel: Dictionary = {}     ## {to, t0, t1, from}
var autodock: Dictionary = {}   ## {to, t0, t1}
var match_target := ""          ## Geschwindigkeit an dieses Ziel angleichen
var thrust := 0.0               ## vor (+1) / zurück (-1), relativ zur Ausrichtung
var strafe := 0.0               ## rechts (+1) / links (-1), relativ zur Ausrichtung
var rot_input := 0.0            ## Drehschub: im Uhrzeigersinn (+1) / gegen (-1)
var rot_stop := false           ## Drehung abbremsen (Gegenschub der Lagedüsen)
var ang_vel := 0.0              ## Drehgeschwindigkeit in rad/s (bleibt ohne Gegenschub erhalten)
var target := ""                ## ausgewähltes Ziel (Ort) für Anzeige und Andocken
var crashed := false
var _warned := false
## Sperre gegen sofortiges Wieder-Andocken am selben Ort (technische Entscheidung):
## nach dem Abdocken REDOCK_LOCK_SECS Spielsekunden kein Andocken an diesem Ort
const REDOCK_LOCK_SECS := 15.0
const UNDOCK_PUSH := 0.003          ## Abstoß beim Abdocken in km/s (3 m/s, weit unter collide_speed)
var undock_lock_id := ""
## Flugbahn intern in doppelter Genauigkeit: Vector2 hat nur 32 Bit, bei
## 60 000 km sind das ~4 m Raster. Viele kleine Schritte (1×) würden sich
## sonst zu großen Fehlern aufsummieren. pos/vel bleiben die lesbaren Werte.
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
	locations = space.locations

func reset() -> void:
	undock_lock_id = ""
	undock_lock_until = 0.0
	docked = "tycho"
	travel = {}
	autodock = {}
	match_target = ""
	stop_inputs()
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

func secs() -> float:
	return GameState.time * 60.0

func _body(name: String) -> Dictionary:
	return space[name]

## Position und Geschwindigkeit eines Ortes (Stationen kreisen um Erde oder Mond)
func loc_state(l: Dictionary, t: float) -> Dictionary:
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

# ---------------- Schiff ----------------

func ship_devices(type: String) -> Array:
	var g := ShipSystem.grid
	var out: Array = []
	for i in g.devices:
		if g.devices[i].type == type and not g.foreign(i):
			out.append(g.devices[i])
	return out

## Masse in Tonnen: Rumpf, Geräte, Ladung
func mass() -> float:
	var g := ShipSystem.grid
	var m := 0.0
	for i in g.tiles.size():
		if g.tiles[i] != 0 and not g.foreign(i):
			m += 0.2
	for i in g.devices:
		if g.foreign(i):
			continue
		m += 0.5
		if g.devices[i].inv != null:
			m += g.devices[i].inv.weight() / 1000.0
	return m

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

func working_thrusters() -> int:
	var n := 0
	for t in ship_devices("thruster"):
		if t.powered and not t.broken:
			n += 1
	return n

func max_thrust() -> float:
	return working_thrusters() * ItemSystem.device("thruster").thrust

## Lagedüsen (RCS): jedes Schiff hat sie, solange das Steuerpult Strom hat
## (Ostranauts: alle Schiffe haben RCS, manche zusätzlich ein Haupttriebwerk).
func rcs_thrust() -> float:
	return float(space.rcs_thrust) if helm_ok() else 0.0

## Beschleunigungen in km/s² (Haupttriebwerk, Lagedüsen)
func main_accel() -> float:
	return max_thrust() / maxf(1.0, mass()) / 1000.0

func rcs_accel() -> float:
	return rcs_thrust() / maxf(1.0, mass()) / 1000.0

## Alle Flugeingaben auf null (Schub endet beim Verlassen der Steuerung)
func stop_inputs() -> void:
	thrust = 0.0
	strafe = 0.0
	rot_input = 0.0
	rot_stop = false

func helm_ok() -> bool:
	for h in ship_devices("helm"):
		if h.powered and not h.broken:
			return true
	return false

func autodock_ok() -> bool:
	for h in ship_devices("autodock"):
		if h.powered and not h.broken:
			return true
	return false

## Pilot-Fähigkeit spart Treibstoff (siehe SkillSystem)
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
	if not travel.is_empty():
		var f := minf(1.0, (t - travel.t0) / (travel.t1 - travel.t0))
		var to: Vector2 = loc_state(loc(travel.to), t).pos
		pos = travel.from.lerp(to, f)
		angle = (to - travel.from).angle()
		if f >= 1.0:
			var dest: String = travel.to
			travel = {}
			dock(dest, true)
			GameState.toast("Angekommen: " + loc(dest).name)
		return
	if not autodock.is_empty():
		var st := loc_state(loc(autodock.to), t)
		var f := minf(1.0, (t - autodock.t0) / (autodock.t1 - autodock.t0))
		pos = pos.lerp(st.pos, f)
		vel = vel.lerp(st.vel, f)
		if f >= 1.0:
			var dest: String = autodock.to
			autodock = {}
			dock(dest, true)
		return
	# Wurde pos/vel von außen gesetzt (Abdocken, Laden, Zusammenstoß)? Dann übernehmen.
	if pos != _p32:
		_px = pos.x
		_py = pos.y
	if vel != _v32:
		_vx = vel.x
		_vy = vel.y
	var acc := gravity(pos)
	var amax := main_accel()
	_rotate(s, dt)
	# Angleichen: Geschwindigkeit relativ zum Ziel abbauen
	if match_target != "":
		var r := rel_to(match_target)
		var dv: Vector2 = r.vel - Vector2(_vx, _vy)
		if dv.length() < 0.0005 or amax <= 0.0 or not helm_ok():
			match_target = ""
		else:
			var a := minf(amax, dv.length() / s)
			var need := working_thrusters() * float(space.burn) * (a / amax) * dt * fuel_factor()
			if fuel() >= need:
				use_fuel(need)
				_vx += dv.normalized().x * a * s
				_vy += dv.normalized().y * a * s
				angle = dv.angle()
			else:
				match_target = ""
	elif (thrust != 0.0 or strafe != 0.0) and helm_ok():
		acc += _thrust_accel(dt, amax)
	# Halb-implizites Euler-Verfahren: stabil für Umlaufbahnen
	_vx += acc.x * s
	_vy += acc.y * s
	_px += _vx * s
	_py += _vy * s
	pos = Vector2(_px, _py)
	vel = Vector2(_vx, _vy)
	_p32 = pos
	_v32 = vel
	_check_hazards()

## Schub relativ zur Ausrichtung. Vorwärts: Haupttriebwerk + Lagedüsen,
## rückwärts und seitwärts: nur Lagedüsen. Verbraucht Treibstoff.
func _thrust_accel(dt: float, amax: float) -> Vector2:
	var arcs := rcs_accel()
	var main_part := maxf(0.0, thrust) if amax > 0.0 else 0.0
	var rcs_part := absf(thrust) + absf(strafe)
	var need := (working_thrusters() * float(space.burn) * main_part + float(space.rcs_burn) * rcs_part) * dt * fuel_factor()
	if fuel() < need or (amax <= 0.0 and arcs <= 0.0):
		if not _no_fuel_warned:
			_no_fuel_warned = true
			GameState.toast("Kein Treibstoff!" if fuel() < need else "Keine Triebwerke mit Strom!", "bad")
		return Vector2.ZERO
	use_fuel(need)
	_no_fuel_warned = false
	SkillSystem.train_all_at("helm", "pilot", dt * 0.5)
	var fwd := Vector2.from_angle(angle)
	var right := Vector2.from_angle(angle + PI / 2.0)
	var a_fwd := thrust * arcs + main_part * amax
	return fwd * a_fwd + right * strafe * arcs

## Drehung mit Schwung: Drehschub beschleunigt die Drehung, ohne Gegenschub dreht
## das Schiff weiter. R bremst die Drehung. Eine Drehung ändert die Flugrichtung nicht.
func _rotate(s: float, dt: float) -> void:
	var acc := float(space.rot_accel) if helm_ok() else 0.0
	var want := ang_vel
	if rot_input != 0.0:
		want = clampf(ang_vel + rot_input * acc * s, -float(space.rot_max), float(space.rot_max))
	elif rot_stop:
		want = move_toward(ang_vel, 0.0, acc * s)
	if want != ang_vel:
		var need := float(space.rcs_burn) * 0.5 * dt * fuel_factor()
		if fuel() >= need:
			use_fuel(need)
			ang_vel = want
	angle = wrapf(angle + ang_vel * s, -PI, PI)

# ---------------- Anflug: Ausrichtung und Annäherung ----------------

## Wie gut zeigt eine freie Andockschleuse auf das Ziel? {ok, deg, angle}
## angle = Ausrichtung des Schiffs, bei der die beste Schleuse genau zum Ziel zeigt.
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
				"angle": wrapf(to_target.angle() - d.angle(), -PI, PI), "port": true, "dir": d.rotated(angle)}
	return best

## Anflugdaten zum Ziel: Entfernung, Relativgeschwindigkeit, Annäherung, Bremswege
func approach(id: String) -> Dictionary:
	var r := rel_to(id)
	var to_target: Vector2 = r.pos - pos
	var vrel: Vector2 = vel - r.vel
	var dist := to_target.length()
	var closing := vrel.dot(to_target / dist) if dist > 0.000001 else 0.0
	var arcs := rcs_accel()
	var amain := main_accel() + arcs
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
		GameState.toast("Warnung: Die Schwerkraft der Erde zieht das Schiff an! Gegenschub geben.", "bad")
	if alt_e > float(space.warn_alt) * 1.5:
		_warned = false
	if alt_e < float(space.crash_alt) or alt_m < float(space.moon_crash_alt):
		crashed = true
		TimeSystem.set_speed(0)
		var text := "Die Erde hat dein Schiff nicht mehr losgelassen. Beim Eintritt in die Atmosphäre ist es verglüht." if alt_e < float(space.crash_alt) else "Dein Schiff ist auf der Mondoberfläche zerschellt."
		EconomySystem.game_over.emit("Abgestürzt", text)
		return
	for l in locations:
		if l.kind != "station":
			continue
		var st := loc_state(l, secs())
		if pos.distance_to(st.pos) < 0.05 and vel.distance_to(st.vel) > float(space.collide_speed):
			var hits := mini(6, int(ceil(vel.distance_to(st.vel) / float(space.collide_speed))))
			for k in hits:
				DamageSystem.strike()
			vel = st.vel
			GameState.toast("Zusammenstoß mit " + l.name + "! Die Hülle ist beschädigt.", "bad")

# ---------------- Andocken, Reisen ----------------

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

## Ist das Andocken an diesem Ort gerade wegen frischen Abdockens gesperrt?
func redock_locked(id: String) -> bool:
	return id == undock_lock_id and secs() < undock_lock_until

func redock_wait(id: String) -> float:
	return maxf(0.0, undock_lock_until - secs()) if id == undock_lock_id else 0.0

## Grund, warum man hier nicht andocken kann ("" = es geht)
func dock_block_reason(id: String) -> String:
	if redock_locked(id):
		return "Gerade erst abgedockt. Andocken an %s ist in %d s wieder möglich." % [loc(id).name, int(ceil(redock_wait(id)))]
	var r := rel_to(id)
	var m := 2.5 if SkillSystem.any_mastered("pilot") else 1.0
	if r.dist >= float(space.dock_dist) * m:
		return "Zu weit weg zum Andocken (%d m, nötig unter %d m)." % [int(r.dist * 1000.0), int(float(space.dock_dist) * m * 1000.0)]
	if r.speed >= float(space.dock_speed) * m:
		return "Zu schnell zum Andocken (%.1f m/s, nötig unter %.0f m/s)." % [r.speed * 1000.0, float(space.dock_speed) * m * 1000.0]
	var al := dock_alignment(id)
	if not al.port:
		return "Keine freie Andockschleuse."
	if not al.ok:
		return "Andockschleuse zeigt nicht zum Ziel (%d° daneben, erlaubt %d°). Mit Q/E drehen." % [int(al.deg), int(space.dock_align_deg)]
	return ""

func can_dock(id: String) -> bool:
	if redock_locked(id):
		return false
	var r := rel_to(id)
	# Meister der Raumschiffsteuerung docken auch aus mehr Abstand und schneller an
	var m := 1.0
	if SkillSystem.any_mastered("pilot"):
		m = 2.5
	if not (r.dist < float(space.dock_dist) * m and r.speed < float(space.dock_speed) * m):
		return false
	# Schleuse muss zum Ziel zeigen (Ostranauts: Andockringe ausrichten)
	return dock_alignment(id).ok

func dock(id: String, force: bool = false) -> bool:
	if not force and not can_dock(id):
		return false
	if docked == id:
		return true
	# Andocken nur mit Andockschleuse (Tür an Tür, keine Gänge)
	if ShipSystem.ports().is_empty():
		GameState.toast("Keine Andockschleuse vorhanden. Bau eine in eine Außenwand (Geräte-Menü: Andockschleuse).", "bad")
		return false
	if String(loc(id).get("kind", "")) == "station" and Config.ENABLE_STATION and not StationSystem.build(id):
		return false
	docked = id
	stop_inputs()
	ang_vel = 0.0
	match_target = ""
	FleetSystem.arrive(loc(id))
	NPCSystem.on_docked(id)
	SkillSystem.train_all_at("helm", "dock", 0.3 if force else 8.0)
	GameState.toast("Angedockt: " + loc(id).name)
	return true

## Grund, der das Abdocken verhindert ("" = Abdocken möglich)
func undock_block_reason() -> String:
	if docked == "":
		return "Das Schiff ist nicht angedockt."
	if crashed:
		return "Das Schiff ist zerstört."
	var helms := ship_devices("helm")
	if helms.is_empty():
		return "Kein Steuerpult an Bord."
	if helms.all(func(h): return h.broken):
		return "Das Steuerpult ist kaputt. Erst reparieren."
	if not helm_ok():
		return "Das Steuerpult braucht Strom."
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
		return "Noch auf dem Wrack: %s. Erst alle zurück an Bord holen." % ", ".join(on_wreck)
	if not on_station.is_empty():
		return "Noch auf der Station: %s. Erst alle zurück an Bord holen." % ", ".join(on_station)
	if not in_hatch.is_empty():
		return "%s steht in der Luke zur Station." % ", ".join(in_hatch)
	return ""

## Abdocken über die Bedienung (Knopf, Taste U): meldet immer Erfolg oder Grund
func request_undock() -> bool:
	if docked == "":
		GameState.toast(undock_block_reason())
		return false
	return undock()

## Abdocken. Nicht angedockt gilt als erledigt (für Reisen).
func undock() -> bool:
	if docked == "":
		return true
	var why := undock_block_reason()
	if why != "":
		GameState.toast(why, "bad")
		return false
	var from := docked
	# Ohne Sprung: genau Lage und Bewegung des Ortes übernehmen, Ausrichtung bleibt
	var st := loc_state(loc(from), secs())
	pos = st.pos
	vel = st.vel
	thrust = 0.0
	match_target = ""
	StationSystem.clear()
	FleetSystem.leave(loc(from))
	docked = ""
	# Sanfter Abstoß nach hinten
	vel += Vector2.from_angle(angle + PI) * UNDOCK_PUSH
	undock_lock_id = from
	undock_lock_until = secs() + REDOCK_LOCK_SECS
	GameState.toast("Abgedockt von %s. Das Schiff treibt frei – Steuerung in der Navigation (WASD)." % loc(from).name)
	return true

func start_autodock() -> void:
	if not autodock_ok():
		GameState.toast("Kein funktionierendes Auto-Dock-Modul an Bord.", "bad")
		return
	var n := nearest()
	if redock_locked(n.id):
		GameState.toast(dock_block_reason(n.id))
		return
	if n.dist > float(space.autodock_dist) or n.speed > float(space.autodock_speed):
		GameState.toast("Zu weit weg oder zu schnell für das Auto-Dock.")
		return
	var need: float = (5.0 + n.speed * 60.0) * fuel_factor()
	if fuel() < need:
		GameState.toast("Nicht genug Treibstoff zum Andocken.", "bad")
		return
	use_fuel(need)
	var t_dock: float = (300.0 + n.dist * 5.0) * (0.7 if SkillSystem.any_mastered("robotics") else 1.0)
	autodock = {"to": n.id, "t0": secs(), "t1": secs() + t_dock}
	GameState.toast("Auto-Dock läuft: " + loc(n.id).name)

func travel_info(id: String) -> Dictionary:
	var r := rel_to(id)
	var tf := SkillSystem.travel_factor()
	return {"dist": r.dist, "fuel": r.dist * float(space.travel_fuel_per_km) * fuel_factor() * tf, "secs": (r.dist / float(space.travel_speed) + 600.0) * tf}

func travel_to(id: String) -> void:
	if not helm_ok():
		GameState.toast("Das Steuerpult braucht Strom.", "bad")
		return
	if docked == id:
		return
	var info := travel_info(id)
	if max_thrust() <= 0.0:
		GameState.toast("Keine Triebwerke mit Strom.", "bad")
		return
	if fuel() < info.fuel:
		GameState.toast("Zu wenig Treibstoff (%d nötig)." % int(ceil(info.fuel)), "bad")
		return
	if not undock():
		return
	use_fuel(info.fuel)
	travel = {"to": id, "t0": secs(), "t1": secs() + info.secs, "from": pos}
	SkillSystem.train_all_at("helm", "navigate", 10.0)
	SkillSystem.train_all_at("helm", "pilot", 5.0)
	GameState.toast("Schnellreise nach %s: %.1f Stunden." % [loc(id).name, info.secs / 3600.0])

func status() -> String:
	if docked != "":
		return "Angedockt: " + loc(docked).name
	if not travel.is_empty():
		return "Unterwegs nach " + loc(travel.to).name
	if not autodock.is_empty():
		return "Dockt an: " + loc(autodock.to).name
	return "Im freien Flug"

## Station, an der gerade angedockt ist (sonst leer)
func station() -> Dictionary:
	if docked == "":
		return {}
	var l := loc(docked)
	return l if l.kind == "station" else {}

func to_data() -> Dictionary:
	return {"x": pos.x, "y": pos.y, "vx": vel.x, "vy": vel.y, "angle": angle, "docked": docked,
		"travel": {"to": travel.to, "t0": travel.t0, "t1": travel.t1, "fx": travel.from.x, "fy": travel.from.y} if not travel.is_empty() else {},
		"autodock": autodock, "lock_id": undock_lock_id, "lock_until": undock_lock_until, "ang_vel": ang_vel, "target": target}

func from_data(d: Dictionary) -> void:
	pos = Vector2(d.x, d.y); vel = Vector2(d.vx, d.vy); angle = float(d.angle); docked = String(d.docked)
	travel = {}
	if not d.travel.is_empty():
		travel = {"to": d.travel.to, "t0": float(d.travel.t0), "t1": float(d.travel.t1), "from": Vector2(d.travel.fx, d.travel.fy)}
	autodock = d.autodock
	undock_lock_id = String(d.get("lock_id", ""))
	undock_lock_until = float(d.get("lock_until", 0.0))
	ang_vel = float(d.get("ang_vel", 0.0))
	target = String(d.get("target", ""))
	stop_inputs()
	crashed = false
	match_target = ""
