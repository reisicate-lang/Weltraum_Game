## Navigationskarte: Erde, Mond, Stationen, dein Schiff und die
## vorausberechnete Flugbahn. Mausrad zoomt, Ziehen verschiebt.
extends Control

var zoom := 0.005         ## Pixel pro km
var follow := true
## Im Cockpit: automatisch so zoomen, dass Schiff und Ziel zu sehen sind (Mausrad schaltet ab)
var auto_zoom := false
var center := Vector2(30000, 0)
var _drag := false

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom = minf(4000.0, zoom * 1.25)
			auto_zoom = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom = maxf(0.002, zoom * 0.8)
			auto_zoom = false
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
	elif event is InputEventMouseMotion and _drag:
		follow = false
		center -= (event as InputEventMouseMotion).relative / zoom

func to_screen(p: Vector2) -> Vector2:
	return (p - center) * zoom + size * 0.5

func _draw() -> void:
	var P := PhysicsSystem
	if follow:
		center = P.pos
	if auto_zoom and P.target != "" and P.docked == "":
		var d: float = P.rel_to(P.target).dist
		zoom = clampf(0.35 * minf(size.x, size.y) / maxf(d, 0.05), 0.002, 4000.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.016, 0.024, 0.043))
	var font := ThemeDB.fallback_font
	for n in ["earth", "moon"]:
		var b: Dictionary = P.space[n]
		var c := to_screen(Vector2(b.x, b.y))
		var r := maxf(4.0, float(b.r) * zoom)
		draw_circle(c, r, Color(0.25, 0.44, 0.69) if n == "earth" else Color(0.54, 0.56, 0.6))
		draw_string(font, c + Vector2(-30, -r - 6), b.name, HORIZONTAL_ALIGNMENT_CENTER, 60, 13, Color(0.78, 0.82, 0.88))
	# Gefahrenzone der Erde
	var e: Dictionary = P.space.earth
	draw_arc(to_screen(Vector2(e.x, e.y)), (float(e.r) + float(P.space.warn_alt)) * zoom, 0, TAU, 96, Color(0.9, 0.33, 0.29, 0.7), 1.0)
	for l in P.locations:
		if l.has("body"):
			var b: Dictionary = P.space[l.body]
			draw_arc(to_screen(Vector2(b.x, b.y)), float(l.radius) * zoom, 0, TAU, 96, Color(0.35, 0.78, 0.9, 0.15), 1.0)
		var sp := to_screen(P.loc_state(l, P.secs()).pos)
		var col := Color(0.63, 0.53, 0.42) if l.kind in ["debris", "asteroid", "outpost", "wreck"] else (Color(0.69, 0.42, 0.82) if l.get("black", false) else Color(0.35, 0.78, 0.9))
		var sz := maxf(6.0, 0.08 * zoom)
		draw_rect(Rect2(sp - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), col)
		draw_string(font, sp + Vector2(sz * 0.5 + 6, 4), l.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.87, 0.9, 0.94))
	# Vorausberechnete Flugbahn (nur Schwerkraft)
	if P.docked == "" and P.travel.is_empty():
		var p := P.pos
		var v := P.vel
		var pts := PackedVector2Array([to_screen(p)])
		var stp := clampf(30.0 / maxf(0.01, zoom), 2.0, 120.0)
		for k in 500:
			v += P.gravity(p) * stp
			p += v * stp
			pts.append(to_screen(p))
			if p.length() < float(e.r):
				break
		draw_polyline(pts, Color(0.95, 0.64, 0.23, 0.6), 1.2)
	if not P.travel.is_empty():
		draw_line(to_screen(P.pos), to_screen(P.loc_state(P.loc(P.travel.to), P.secs()).pos), Color(0.44, 0.81, 0.56, 0.7), 1.0)
	# Ausgewähltes Ziel: Ring und Linie
	if P.target != "" and not P.loc(P.target).is_empty():
		var tp := to_screen(P.loc_state(P.loc(P.target), P.secs()).pos)
		draw_arc(tp, 12.0, 0, TAU, 32, Color(0.35, 0.78, 0.9), 2.0)
		draw_line(to_screen(P.pos), tp, Color(0.35, 0.78, 0.9, 0.35), 1.0)
		if zoom > 50.0:
			# Andockbereich (250 m)
			draw_arc(tp, float(P.space.dock_dist) * zoom, 0, TAU, 48, Color(0.44, 0.81, 0.56, 0.5), 1.0)
	# Schiff
	var s := to_screen(P.pos)
	var dir := Vector2.from_angle(P.angle)
	var side := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([s + dir * 10, s - dir * 7 + side * 6, s - dir * 4, s - dir * 7 - side * 6]), Color(0.95, 0.64, 0.23))
	if P.thrust > 0.0:
		draw_line(s - dir * 5, s - dir * (14 + randf() * 5), Color(1, 0.82, 0.48), 3.0)
