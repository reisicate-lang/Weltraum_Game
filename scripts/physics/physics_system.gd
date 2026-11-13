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
## Angleichen: aktuelle Schub-Eingabe der Angleichung (für Anzeige und Flammen)
var match_input := Vector2.ZERO
## Feld des Steuerpults, an dem der Pilot gerade steht (NO_HELM = niemand fliegt).
## Nur eine Position, keine Geräte-Instanz; wird nicht gespeichert.
const NO_HELM := Vector2i(-1, -1)
var helm_at := NO_HELM
var aligning := false            ## „Ausrichten“: mit Drehschub auf align_angle drehen
var align_angle := 0.0
var _helm_fail_warned := false
const MATCH_DEADBAND := 0.00005  ## 0,05 m/s: darunter feuert die Angleichung nicht
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
	locations = space.locations.duplicate()

## Zusätzliche Orte (Wracks als eigene Ziele, siehe FleetSystem.sites) zu den festen Orten
func set_extra_locations(extra: Array) -> void:
	locations = space.locations.duplicate()
	locations.append_array(extra)

func reset() -> void:
	undock_lock_id = ""
	undock_lock_until = 0.0
	docked = "tycho"
	travel = {}
	autodock = {}
	match_target = ""
	stop_inputs()
	helm_at = NO_HELM
	angle = 0.0          # neues Spiel: Nase nach vorn (nicht vom vorigen Spiel erben)
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
	# Wrack neben einem Ort: fester Abstand, bewegt sich mit diesem Ort
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

# ---------------- Schiff ----------------

func ship_devices(type: String) -> Array:
	var g := ShipSystem.grid
	var out: Array = []
	for i in g.devices:
		if g.devices[i].type == type and not g.foreign(i):
			out.append(g.devices[i])
	return out

## Masse in Tonnen: Rumpffelder (Config.TILE_MASS), Geräte (DeviceData.mass,
## z. B. Triebwerk 1,5 t), Ladung in Behältern und lose Ladung auf dem eigenen
## Schiffsboden. Jede Ladung zählt genau einmal: Umlagern zwischen eigenem Behälter
## und eigenem Boden ändert die Masse nicht. Fremde Bereiche (Wrack, Station) und
## Haufen im All neben dem Rumpf zählen nicht. Was eine Figur an Bord trägt (Gepäck,
## Hände, ein getragenes Gerät), zählt ebenfalls genau einmal mit – mit demselben
## Einzelgewicht wie im Inventar (ItemData.weight, abgebaute Geräte = Gerätemasse).
## Verlässt es das Schiff (Station, Wrack), fällt sein Beitrag weg.
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

## Liegt ein Haufen auf dem eigenen Schiffsboden? (eigenes Feld, kein Weltraum)
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

## Aktive Triebwerke: eingebaut, mit Strom, nicht kaputt
func active_thrusters() -> Array:
	return ship_devices("thruster").filter(func(t): return t.powered and not t.broken)

func working_thrusters() -> int:
	return active_thrusters().size()

## Verfügbarer Schub der Triebwerke in eine Richtung (Schiffskoordinaten:
## (1,0) nach vorn zur Nase, (0,1) nach rechts, (-1,0) nach hinten, (0,-1) nach links).
## Gleich ausgerichtete Triebwerke addieren ihren Schub.
func thrust_dir(d: Vector2i) -> float:
	var s := 0.0
	for t in active_thrusters():
		if t.push_dir() == d:
			s += t.data().thrust
	return s

## Schub nach vorn (Haupttriebwerke)
func max_thrust() -> float:
	return thrust_dir(Vector2i(1, 0))

## Welche Triebwerksrichtungen eine Eingabe anfordert (Schiffskoordinaten).
## Ohne Angabe: die aktuellen Eingaben (Tasten oder Angleichung).
func _requested(inp = null) -> Dictionary:
	var v: Vector2 = inp if inp != null else _input_now()
	return {Vector2i(1, 0): maxf(0.0, v.x), Vector2i(-1, 0): maxf(0.0, -v.x),
		Vector2i(0, 1): maxf(0.0, v.y), Vector2i(0, -1): maxf(0.0, -v.y)}

## Wirksame Translationseingabe: Tasten haben Vorrang, sonst die Angleichung
func _input_now() -> Vector2:
	if thrust != 0.0 or strafe != 0.0:
		return Vector2(thrust, strafe)
	return match_input

## Schubvektor in Schiffskoordinaten (kN) aus Triebwerken und Lagedüsen für eine Eingabe
func thrust_vector_local(inp = null) -> Vector2:
	var v: Vector2 = inp if inp != null else _input_now()
	var f := v * rcs_thrust()
	var req := _requested(v)
	for t in active_thrusters():
		var d: Vector2i = t.push_dir()
		if req[d] > 0.0:
			f += Vector2(d) * t.data().thrust * req[d]
	return f

## Feuert gerade ein Triebwerk in diese Richtung? (für die Anzeige)
func firing(d: Vector2i) -> bool:
	return docked == "" and manual_ok() and _requested()[d] > 0.0

## Lagedüsen (RCS): jedes Schiff hat sie, solange das Steuerpult Strom hat
## (Ostranauts: alle Schiffe haben RCS, manche zusätzlich ein Haupttriebwerk).
func rcs_thrust() -> float:
	return float(space.rcs_thrust) * pilot_factor() if helm_ok() else 0.0

## Beschleunigungen in km/s² (Haupttriebwerk, Lagedüsen) = Schub (kN) ÷ Masse (t) ÷ 1000
func main_accel() -> float:
	return max_thrust() / maxf(1.0, mass()) / 1000.0

## Beschleunigung, die die aktuellen Eingaben gerade erzeugen (km/s², Schiffskoordinaten)
func accel_local() -> Vector2:
	return thrust_vector_local() / maxf(1.0, mass()) / 1000.0

func rcs_accel() -> float:
	return rcs_thrust() / maxf(1.0, mass()) / 1000.0

## Alle Flugeingaben auf null (Schub endet beim Verlassen der Steuerung)
func stop_inputs() -> void:
	thrust = 0.0
	strafe = 0.0
	rot_input = 0.0
	rot_stop = false
	aligning = false

## „Ausrichten“: Schiff mit den Lagedüsen auf diese Richtung drehen (bremst rechtzeitig).
## Q, E oder R brechen ab. Nur am bedienten, versorgten Pult.
func start_align(a: float) -> void:
	var why := pilot_block_reason()
	if why != "":
		GameState.toast(why, "bad")
		return
	align_angle = wrapf(a, -PI, PI)
	aligning = true

## Hat das Schiff irgendein versorgtes, intaktes Steuerpult? (Abdocken, Schnellreise, Anzeige)
func helm_ok() -> bool:
	for h in ship_devices("helm"):
		if h.powered and not h.broken:
			return true
	return false

## Das Steuerpult, an dem der Pilot steht (oder null)
func operated_helm() -> Device:
	if helm_at == NO_HELM:
		return null
	var g := ShipSystem.grid
	var d := g.device_at(helm_at)
	if d == null or d.type != "helm" or d.unknown or g.foreign(g.idx(helm_at)):
		return null
	return d

## Wer fliegt gerade? Die Figur am bedienten Steuerpult (deine Figur zuerst), sonst null
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

## Piloting-Faktor (1 + Piloting der fliegenden Figur): Andockgrenzen, Lagedüsenschub, Drehung
func pilot_factor() -> float:
	return 1.0 + SkillSystem.piloting(pilot_crew())

## Drehbeschleunigung beim Steuern (mit Piloting-Faktor); 0 ohne bedientes, intaktes Pult
func rot_accel() -> float:
	return float(space.rot_accel) * pilot_factor() if manual_ok() else 0.0

## Andockgrenzen (Abstand, Geschwindigkeit) mit dem Piloting-Faktor
func dock_factor() -> float:
	return pilot_factor()

## Warum ein Steuerpult nicht geflogen werden kann ("" = es geht)
func helm_block_reason(h: Device) -> String:
	if h == null:
		return "Niemand steht an einem Steuerpult."
	if h.broken:
		return "Dieses Steuerpult ist kaputt."
	if not h.powered:
		return "Dieses Steuerpult hat keinen Strom."
	return ""

## Grund, warum der Pilot gerade keine Flugbefehle geben kann (Abdocken, Schnellreise,
## Auto-Dock): Es braucht das bediente Pult, intakt und mit Strom. "" = es geht.
func pilot_block_reason() -> String:
	if ship_devices("helm").is_empty():
		return "Kein Steuerpult an Bord."
	var h := operated_helm()
	if h == null:
		return "Das geht nur am Steuerpult: erst ins Cockpit (N)."
	var why := helm_block_reason(h)
	if why != "":
		return why + (" Erst reparieren." if h.broken else "")
	return ""

## Pult, das eine Schnellreise oder ein Auto-Dock gestartet hat ({hx, hy} im Auftrag):
## "" = noch in Ordnung. Ältere Spielstände ohne Pult-Angabe: irgendein versorgtes Pult.
func _cmd_helm_reason(d: Dictionary) -> String:
	if not d.has("hx"):
		return "" if helm_ok() else "Kein Steuerpult mit Strom."
	var h := ShipSystem.grid.device_at(Vector2i(int(d.hx), int(d.hy)))
	if h == null or h.type != "helm":
		return "Das Steuerpult ist weg."
	return helm_block_reason(h)

## Manueller Flug (Schub, Drehen, Angleichen) nur über das bediente Pult,
## und nur, wenn genau dieses Pult intakt ist und Strom hat.
func manual_ok() -> bool:
	return helm_block_reason(operated_helm()) == ""

## Auto-Dock ist freigeschaltet, wenn am bedienten Pult (intakt, mit Strom) ein
## funktionsfähiges Autodock-Modul im Modulfach steckt. Module anderswo (Gepäck, Boden,
## anderes Pult) zählen nicht; mehrere gleiche Module schalten dieselbe Funktion frei.
func autodock_ok() -> bool:
	return autodock_block_reason() == ""

## Grund, warum Auto-Dock hier gesperrt ist ("" = freigeschaltet)
func autodock_block_reason() -> String:
	var why := pilot_block_reason()
	if why != "":
		return why
	return module_block_reason(operated_helm(), "autodock")

## Steckt im Pult h ein funktionsfähiges Modul dieser Art? "" = ja, sonst der Grund
func module_block_reason(h: Device, kind: String) -> String:
	if h == null:
		return "Das Steuerpult ist weg."
	if not h.module(kind).is_empty():
		return ""
	var name := module_name(kind)
	if h.has_module_item(kind):
		return "Das %s in diesem Steuerpult ist kaputt." % name
	return "Kein %s in diesem Steuerpult. Modul ins Modulfach legen (E am Pult)." % name

## Anzeigename des Moduls für eine Funktion (z. B. "Autodock-Modul")
func module_name(kind: String) -> String:
	for id in ItemSystem.items:
		if ItemSystem.item(id).helm_module == kind:
			return ItemSystem.item(id).display_name
	return kind

## Kann ein laufendes Auto-Dock-Manöver weitergehen? (Pult, Strom, Modul im startenden Pult)
func _autodock_reason() -> String:
	var why := _cmd_helm_reason(autodock)
	if why != "" or not autodock.has("hx"):
		return why
	return module_block_reason(ShipSystem.grid.device_at(Vector2i(int(autodock.hx), int(autodock.hy))), "autodock")

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
	if not travel.is_empty() and _cmd_helm_reason(travel) != "":
		# Pult ausgefallen: Reise endet, das Schiff fliegt mit der Reisegeschwindigkeit weiter
		var dest_now: Vector2 = loc_state(loc(travel.to), t).pos
		vel = (dest_now - travel.from) / maxf(1.0, travel.t1 - travel.t0)
		GameState.toast("Schnellreise abgebrochen: %s Das Schiff fliegt mit %.2f km/s weiter." % [_cmd_helm_reason(travel), vel.length()], "bad")
		travel = {}
		return
	if not autodock.is_empty() and _autodock_reason() != "":
		# Kontrolliert abbrechen: freier Flug mit der erreichten Lage und Geschwindigkeit,
		# keine Kopplung
		GameState.toast("Auto-Dock abgebrochen: " + _autodock_reason(), "bad")
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
			if not dock(dest, true):
				GameState.toast("Auto-Dock: Ankoppeln nicht möglich, das Schiff treibt frei.", "bad")
		return
	# Wurde pos/vel von außen gesetzt (Abdocken, Laden, Zusammenstoß)? Dann übernehmen.
	if pos != _p32:
		_px = pos.x
		_py = pos.y
	if vel != _v32:
		_vx = vel.x
		_vy = vel.y
	var acc := gravity(pos)
	# Fällt das bediente Pult aus, enden Schub, Drehschub und Angleichung sofort.
	# Die vorhandene Bewegung (Geschwindigkeit, Drehung) läuft physikalisch weiter.
	var manual := manual_ok()
	if not manual and (thrust != 0.0 or strafe != 0.0 or rot_input != 0.0 or rot_stop or aligning or match_target != ""):
		var why := helm_block_reason(operated_helm())
		if match_target != "":
			GameState.toast("Angleichen beendet: " + why, "bad")
		elif helm_at != NO_HELM and not _helm_fail_warned:
			GameState.toast("Schub beendet: " + why, "bad")
		_helm_fail_warned = helm_at != NO_HELM
		stop_inputs()
		match_target = ""
	elif manual:
		_helm_fail_warned = false
	_rotate(s, dt)
	# Manueller Schub hat Vorrang. Ohne Tasten arbeitet eine aktive Angleichung mit
	# denselben Triebwerken und Lagedüsen auf die Zielgeschwindigkeit hin.
	match_input = Vector2.ZERO
	if (thrust != 0.0 or strafe != 0.0) and manual:
		acc += _thrust_accel(dt, Vector2(thrust, strafe))
	elif match_target != "":
		match_input = _match_input(s)
		if match_input != Vector2.ZERO:
			acc += _thrust_accel(dt, match_input)
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

## Schub relativ zur Ausrichtung: Summe der Schubvektoren aller aktiven Triebwerke,
## deren Richtung zur Eingabe passt (W vorn, S hinten, D rechts, A links), plus
## Lagedüsen. Beschleunigung = Gesamtschub ÷ Schiffsmasse. Verbraucht Treibstoff.
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
			GameState.toast("Kein Treibstoff!" if fuel() < need else "Kein Triebwerk für diese Richtung und keine Lagedüsen!", "bad")
		return Vector2.ZERO
	use_fuel(need)
	_no_fuel_warned = false
	SkillSystem.train_all_at("helm", "pilot", dt * 0.5)
	return (f / maxf(1.0, mass()) / 1000.0).rotated(angle)

## Angleichen: Eingabe (vor/zurück, rechts/links, je -1..1), die die Relativgeschwindigkeit
## zum Ziel in diesem Schritt so weit wie möglich abbaut – ohne das Schiff zu drehen.
## Nutzt pro Achse die Triebwerke dieser Richtung plus Lagedüsen. Unterhalb der
## Totzone MATCH_DEADBAND wird nicht gefeuert (eigene Festlegung).
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

## Drehung mit Schwung: Drehschub beschleunigt die Drehung, ohne Gegenschub dreht
## das Schiff weiter. R bremst die Drehung. Eine Drehung ändert die Flugrichtung nicht.
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
		# Ausrichten: beschleunigen, dann so bremsen, dass die Drehung am Ziel endet
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
				"angle": wrapf(to_target.angle() - d.angle(), -PI, PI), "port": true, "dir": d.rotated(angle), "i": int(p.i)}
	return best

## Anflugdaten zum Ziel: Entfernung, Relativgeschwindigkeit, Annäherung, Bremswege
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
	var why := pilot_block_reason()
	if why != "":
		return why
	if redock_locked(id):
		return "Gerade erst abgedockt. Andocken an %s ist in %d s wieder möglich." % [loc(id).name, int(ceil(redock_wait(id)))]
	var r := rel_to(id)
	var m := dock_factor()
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
	if pilot_block_reason() != "" or redock_locked(id):
		return false
	var r := rel_to(id)
	# Piloting (Spaceship Piloting): größere Andockgrenzen
	var m := dock_factor()
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
		GameState.toast("Kein Andockport: Angedockt wird an der Außentür einer Luftschleuse (Raum mit Pumpe, Tür ins All).", "bad")
		return false
	# Klammern am ausgerichteten Port: dort entsteht der Übergang
	var al := dock_alignment(id)
	ShipSystem.dock_pref = int(al.get("i", -1))
	if String(loc(id).get("kind", "")) == "station" and Config.ENABLE_STATION and not StationSystem.build(id):
		return false
	# Wrack als eigenes Ziel: erst jetzt an den Port hängen (vorher kein Wrackbereich am Schiff)
	if String(loc(id).get("kind", "")) == "wreck" and Config.ENABLE_WRECK and not FleetSystem.attach_site(loc(id)):
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
	# Frühere Andockschleusen (5×2) nach dem Lösen entfernen und abdichten
	ShipSystem.retire_legacy_ports()
	# Sanfter Abstoß nach hinten
	vel += Vector2.from_angle(angle + PI) * UNDOCK_PUSH
	undock_lock_id = from
	undock_lock_until = secs() + REDOCK_LOCK_SECS
	GameState.toast("Abgedockt von %s. Das Schiff treibt frei – Steuerung in der Navigation (WASD)." % loc(from).name)
	return true

func start_autodock() -> void:
	var why := autodock_block_reason()
	if why != "":
		GameState.toast(why, "bad")
		return
	if docked != "":
		GameState.toast("Das Schiff ist schon angedockt.")
		return
	if ShipSystem.free_ports().is_empty():
		GameState.toast("Keine freie Andockschleuse für das Auto-Dock.", "bad")
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
	var t_dock: float = 300.0 + n.dist * 5.0
	autodock = {"to": n.id, "t0": secs(), "t1": secs() + t_dock, "hx": helm_at.x, "hy": helm_at.y}
	GameState.toast("Auto-Dock läuft: " + loc(n.id).name)

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
	travel = {"to": id, "t0": secs(), "t1": secs() + info.secs, "from": pos, "hx": helm_at.x, "hy": helm_at.y}
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
		"travel": _travel_data(),
		"autodock": autodock, "lock_id": undock_lock_id, "lock_until": undock_lock_until, "ang_vel": ang_vel, "target": target}

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
	stop_inputs()
	helm_at = NO_HELM
	crashed = false
	match_target = ""
	match_input = Vector2.ZERO
