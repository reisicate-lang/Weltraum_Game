## Fluglage-Instrument im Cockpit: Ausrichtung des Schiffs, tatsächliche
## Bewegungsrichtung (relativ zum Ziel), Richtung zum Ziel und die beste
## Andockschleuse. Oben ist immer „Norden“ der Karte, damit die Pfeile direkt
## mit der Navigationskarte übereinstimmen.
extends Control

const COL_SHIP := Color(0.95, 0.64, 0.23)     ## Ausrichtung (Nase)
const COL_MOVE := Color(0.44, 0.81, 0.56)     ## Bewegung relativ zum Ziel
const COL_TARGET := Color(0.35, 0.78, 0.9)    ## Richtung zum Ziel
const COL_PORT := Color(0.95, 0.85, 0.4)      ## beste Andockschleuse
const COL_DIM := Color(0.5, 0.55, 0.62)

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	var P := PhysicsSystem
	var font := ThemeDB.fallback_font
	var c := Vector2(size.x * 0.5, size.y * 0.5)
	var r := minf(size.x, size.y) * 0.5 - 18.0
	draw_circle(c, r, Color(0.04, 0.06, 0.09))
	draw_arc(c, r, 0, TAU, 64, COL_DIM, 1.5)
	draw_arc(c, r * 0.5, 0, TAU, 48, Color(COL_DIM, 0.35), 1.0)
	for k in 12:
		var a := k * TAU / 12.0
		var inner := r - (8.0 if k % 3 == 0 else 4.0)
		draw_line(c + Vector2.from_angle(a) * inner, c + Vector2.from_angle(a) * r, COL_DIM, 1.0)
	draw_string(font, c + Vector2(-4, -r - 4), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_DIM)
	# Schiff: Rumpf und Nase in Ausrichtung, Nasenmarke außen am Kreis
	var dir := Vector2.from_angle(P.angle)
	var side := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([c + dir * 18, c - dir * 10 + side * 8, c - dir * 5, c - dir * 10 - side * 8]), COL_SHIP)
	draw_colored_polygon(PackedVector2Array([c + dir * (r - 2), c + dir * (r - 14) + side * 6, c + dir * (r - 14) - side * 6]), COL_SHIP)
	# Aktiver Schub als Flammen
	if P.docked == "":
		if P.thrust > 0.0:
			draw_line(c - dir * 10, c - dir * (24 + randf() * 6), Color(1, 0.82, 0.48), 4.0)
		if P.thrust < 0.0:
			draw_line(c + dir * 18, c + dir * (28 + randf() * 4), Color(0.8, 0.9, 1.0), 2.0)
		if P.strafe != 0.0:
			draw_line(c - side * 10 * signf(P.strafe), c - side * (22 + randf() * 4) * signf(P.strafe), Color(0.8, 0.9, 1.0), 2.0)
	var tid: String = P.target
	if tid != "" and P.docked == "":
		var ap: Dictionary = P.approach(tid)
		var st: Dictionary = P.rel_to(tid)
		var to_t: Vector2 = st.pos - P.pos
		# Richtung zum Ziel
		if to_t.length() > 0.0:
			var td := to_t.normalized()
			draw_circle(c + td * r, 6.0, COL_TARGET)
			draw_string(font, c + td * (r + 4) + Vector2(-4, 4), "Z", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TARGET)
		# Tatsächliche Bewegung relativ zum Ziel (Länge ~ Tempo, logarithmisch)
		var v: Vector2 = ap.vrel
		if v.length() > 0.0000005:
			var vlen := clampf(log(1.0 + v.length() * 1000.0) / log(1.0 + 2000.0), 0.08, 1.0) * (r - 4)
			var vd := v.normalized()
			draw_line(c, c + vd * vlen, COL_MOVE, 3.0)
			draw_circle(c + vd * vlen, 4.0, COL_MOVE)
		# Beste Andockschleuse
		var al: Dictionary = P.dock_alignment(tid)
		if al.port:
			var port_dir: Vector2 = al.dir
			draw_line(c + port_dir * (r * 0.55), c + port_dir * (r * 0.85), COL_PORT if al.ok else Color(0.9, 0.33, 0.29), 3.0)
	# Legende
	var y := size.y - 4.0
	draw_string(font, Vector2(4, y), "▲ Nose", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_SHIP)
	draw_string(font, Vector2(62, y), "— motion rel. target", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_MOVE)
	draw_string(font, Vector2(4, 12), "● Target", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TARGET)
	draw_string(font, Vector2(54, 12), "▬ Airlock", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_PORT)
