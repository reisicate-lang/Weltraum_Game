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
var thrust := 0.0               ## -0.5 .. 1 (vom Spieler)
var crashed := false
var _warned := false
var _no_fuel_warned := false


func _ready() -> void:
	var f := FileAccess.open("res://data/space.json", FileAccess.READ)
	space = JSON.parse_string(f.get_as_text())
	locations = space.locations

func reset() -> void:
	docked = "tycho"
	travel = {}
	autodock = {}
	match_target = ""
	thrust = 0.0
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
		if g.devices[i].type == type and g.zone[i] != 1:
			out.append(g.devices[i])
	return out

## Masse in Tonnen: Rumpf, Geräte, Ladung
func mass() -> float:
	var g := ShipSystem.grid
	var m := 0.0
	for i in g.tiles.size():
		if g.tiles[i] != 0 and g.zone[i] != 1:
			m += 0.2
	for i in g.devices:
		if g.zone[i] == 1:
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
	var skills = get_node_or_null("/root/SkillSystem")
	return skills.pilot_fuel_factor() if skills != null else 1.0

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
	var acc := gravity(pos)
	var amax := max_thrust() / maxf(1.0, mass()) / 1000.0
	# Angleichen: Geschwindigkeit relativ zum Ziel abbauen
	if match_target != "":
		var r := rel_to(match_target)
		var dv: Vector2 = r.vel - vel
		if dv.length() < 0.0005 or amax <= 0.0 or not helm_ok():
			match_target = ""
		else:
			var a := minf(amax, dv.length() / s)
			var need := working_thrusters() * float(space.burn) * (a / amax) * dt * fuel_factor()
			if fuel() >= need:
				use_fuel(need)
				vel += dv.normalized() * a * s
				angle = dv.angle()
			else:
				match_target = ""
	elif thrust != 0.0 and helm_ok():
		var need := working_thrusters() * float(space.burn) * absf(thrust) * dt * fuel_factor()
		if amax > 0.0 and fuel() >= need:
			use_fuel(need)
			acc += Vector2.from_angle(angle) * amax * thrust
			_no_fuel_warned = false
			var sk = get_node_or_null("/root/SkillSystem")
			if sk != null:
				sk.train_all_at("helm", "pilot", dt * 0.5)
		elif not _no_fuel_warned:
			_no_fuel_warned = true
			GameState.toast("Kein Treibstoff!" if amax > 0.0 else "Keine Triebwerke mit Strom!", "bad")
	# Halb-implizites Euler-Verfahren: stabil für Umlaufbahnen
	vel += acc * s
	pos += vel * s
	_check_hazards()

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

func can_dock(id: String) -> bool:
	var r := rel_to(id)
	return r.dist < float(space.dock_dist) and r.speed < float(space.dock_speed)

func dock(id: String, force: bool = false) -> bool:
	if not force and not can_dock(id):
		return false
	docked = id
	thrust = 0.0
	match_target = ""
	FleetSystem.arrive(loc(id))
	var sk = get_node_or_null("/root/SkillSystem")
	if sk != null:
		sk.train_all_at("helm", "pilot", 0.3 if force else 3.0)
	GameState.toast("Angedockt: " + loc(id).name)
	return true

func undock() -> bool:
	if docked == "":
		return true
	if not helm_ok():
		GameState.toast("Das Steuerpult braucht Strom.", "bad")
		return false
	if not SalvageSystem.clearable():
		GameState.toast("Erst alle Crewmitglieder vom Wrack holen.")
		return false
	FleetSystem.leave(loc(docked))
	GameState.toast("Abgedockt von " + loc(docked).name + ".")
	docked = ""
	vel += Vector2.from_angle(angle + PI) * 0.003
	return true

func start_autodock() -> void:
	if not autodock_ok():
		GameState.toast("Kein funktionierendes Auto-Dock-Modul an Bord.", "bad")
		return
	var n := nearest()
	if n.dist > float(space.autodock_dist) or n.speed > float(space.autodock_speed):
		GameState.toast("Zu weit weg oder zu schnell für das Auto-Dock.")
		return
	var need: float = (5.0 + n.speed * 60.0) * fuel_factor()
	if fuel() < need:
		GameState.toast("Nicht genug Treibstoff zum Andocken.", "bad")
		return
	use_fuel(need)
	autodock = {"to": n.id, "t0": secs(), "t1": secs() + 300.0 + n.dist * 5.0}
	GameState.toast("Auto-Dock läuft: " + loc(n.id).name)

func travel_info(id: String) -> Dictionary:
	var r := rel_to(id)
	return {"dist": r.dist, "fuel": r.dist * float(space.travel_fuel_per_km) * fuel_factor(), "secs": r.dist / float(space.travel_speed) + 600.0}

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
		"autodock": autodock}

func from_data(d: Dictionary) -> void:
	pos = Vector2(d.x, d.y); vel = Vector2(d.vx, d.vy); angle = float(d.angle); docked = String(d.docked)
	travel = {}
	if not d.travel.is_empty():
		travel = {"to": d.travel.to, "t0": float(d.travel.t0), "t1": float(d.travel.t1), "from": Vector2(d.travel.fx, d.travel.fy)}
	autodock = d.autodock
	crashed = false
	match_target = ""
