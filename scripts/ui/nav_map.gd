## Navigation map: Earth, Moon, stations, your ship and the
## predicted trajectory. The mouse wheel zooms, dragging pans.
extends Control

var zoom := 0.005         ## pixels per km
var follow := true
## In the cockpit: zoom automatically so ship and target are visible (the mouse wheel turns it off)
var auto_zoom := false
var center := Vector2(30000, 0)
var _drag := false
## Solar system overview instead of the local map (regions, distances, running cruise)
var system_view := false
## Region clicked on the overview ("" = none)
var sys_pick := ""
signal picked(id: String)
var _was_cruise := false

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()
	# Course set: show the overview; arrived: back to the local map
	var cr := not PhysicsSystem.cruise.is_empty()
	if cr != _was_cruise:
		system_view = cr
		_was_cruise = cr

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom = minf(4000.0, zoom * 1.25)
			auto_zoom = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom = maxf(0.002, zoom * 0.8)
			auto_zoom = false
		elif mb.button_index == MOUSE_BUTTON_LEFT and system_view:
			if mb.pressed:
				var best := ""
				var bd := 18.0
				for r in PhysicsSystem.regions():
					var d := sys_screen(PhysicsSystem.system_pos(r.id)).distance_to(mb.position)
					if d < bd:
						bd = d
						best = r.id
				sys_pick = best
				picked.emit(best)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
	elif event is InputEventMouseMotion and _drag:
		follow = false
		center -= (event as InputEventMouseMotion).relative / zoom

func to_screen(p: Vector2) -> Vector2:
	return (p - center) * zoom + size * 0.5

## Overview scale: distances compressed with the square root so Earth and Saturn both fit
func sys_screen(au: Vector2) -> Vector2:
	var far := 1.0
	for r in PhysicsSystem.regions():
		far = maxf(far, float(r.get("au", 1.0)))
	var rad := 0.44 * minf(size.x, size.y)
	return size * 0.5 + (au.normalized() * sqrt(au.length() / far) * rad if au.length() > 0.0001 else Vector2.ZERO)

func _draw_system() -> void:
	var P := PhysicsSystem
	var font := ThemeDB.fallback_font
	var mid := size * 0.5
	draw_circle(mid, 9.0, Color(1.0, 0.82, 0.38))
	draw_string(font, mid + Vector2(-30, -14), "Sun", HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color(1.0, 0.82, 0.38))
	for r in P.regions():
		var orbit := sys_screen(Vector2(float(r.get("au", 1.0)), 0.0)).x - mid.x
		draw_arc(mid, orbit, 0, TAU, 128, Color(0.4, 0.45, 0.55, 0.35), 1.0)
	# Running cruise: course line from the start to where the target will be on arrival
	if not P.cruise.is_empty():
		var a := sys_screen(P.system_pos(P.region, float(P.cruise.t0)))
		var b := sys_screen(P.system_pos(String(P.cruise.to), float(P.cruise.t1)))
		draw_dashed_line(a, b, Color(0.95, 0.64, 0.23, 0.8), 1.5, 6.0)
		draw_arc(b, 7.0, 0, TAU, 24, Color(0.95, 0.64, 0.23, 0.8), 1.0)
	for r in P.regions():
		var c := sys_screen(P.system_pos(r.id))
		var col: Array = r.get("color", [0.6, 0.6, 0.6])
		draw_circle(c, 6.0, Color(float(col[0]), float(col[1]), float(col[2])))
		if r.id == P.region and P.cruise.is_empty():
			draw_arc(c, 11.0, 0, TAU, 32, Color(0.44, 0.81, 0.56), 2.0)
		if r.id == sys_pick:
			draw_arc(c, 14.0, 0, TAU, 32, Color(0.35, 0.78, 0.9), 2.0)
		var sub := "you are here" if r.id == P.region and P.cruise.is_empty() else "%.1f AU" % float(r.get("au", 1.0))
		draw_string(font, c + Vector2(17, -4), String(r.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.87, 0.9, 0.94))
		draw_string(font, c + Vector2(17, 10), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.6, 0.68))
	var s := sys_screen(P.system_ship_pos())
	draw_colored_polygon(PackedVector2Array([s + Vector2(0, -7), s + Vector2(5, 5), s + Vector2(-5, 5)]), Color(0.95, 0.64, 0.23))
	var lines: PackedStringArray = ["SOLAR SYSTEM · distances compressed (square root) · click a world"]
	if not P.cruise.is_empty():
		lines.append("Long-range cruise to %s: %.1f days left" % [P.region_data(String(P.cruise.to)).name, P.cruise_left_days()])
	elif sys_pick != "" and sys_pick != P.region:
		var info: Dictionary = P.cruise_info(sys_pick)
		lines.append("%s: %.1f days · fuel %d%s" % [P.region_data(sys_pick).name, float(info.days), int(ceil(float(info.fuel))), "" if info.reason == "" else " · " + String(info.reason)])
		lines.append(String(P.region_data(sys_pick).get("desc", "")))
	for k in lines.size():
		draw_string(font, Vector2(10, size.y - 12 - 16 * (lines.size() - 1 - k)), lines[k], HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 12, Color(0.78, 0.82, 0.88) if k > 0 else Color(0.55, 0.6, 0.68))

func _draw() -> void:
	var P := PhysicsSystem
	if system_view:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.016, 0.024, 0.043))
		_draw_system()
		return
	if follow:
		center = P.pos
	if auto_zoom and P.target != "" and P.docked == "":
		var d: float = P.rel_to(P.target).dist
		zoom = clampf(0.35 * minf(size.x, size.y) / maxf(d, 0.05), 0.002, 4000.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.016, 0.024, 0.043))
	var font := ThemeDB.fallback_font
	for n in P.region_bodies():
		var b: Dictionary = P.space[n]
		var c := to_screen(Vector2(b.x, b.y))
		var r := maxf(4.0, float(b.r) * zoom)
		var bc: Array = b.get("color", [0.54, 0.56, 0.6])
		draw_circle(c, r, Color(float(bc[0]), float(bc[1]), float(bc[2])))
		draw_string(font, c + Vector2(-30, -r - 6), b.name, HORIZONTAL_ALIGNMENT_CENTER, 60, 13, Color(0.78, 0.82, 0.88))
		# Danger zone of bodies that pull you in
		if b.has("warn_alt"):
			draw_arc(c, (float(b.r) + float(b.warn_alt)) * zoom, 0, TAU, 96, Color(0.9, 0.33, 0.29, 0.7), 1.0)
	var e: Dictionary = P.main_body()
	for l in P.locations:
		if l.has("body"):
			var b: Dictionary = P.space[l.body]
			draw_arc(to_screen(Vector2(b.x, b.y)), float(l.radius) * zoom, 0, TAU, 96, Color(0.35, 0.78, 0.9, 0.15), 1.0)
		var sp := to_screen(P.loc_state(l, P.secs()).pos)
		# Wake zone: no torch drive (Ostranauts Flying 3.2)
		if l.kind == "station":
			draw_arc(sp, float(P.space.get("wake_km", 500.0)) * zoom, 0, TAU, 64, Color(0.95, 0.64, 0.23, 0.18), 1.0)
		var col := Color(0.63, 0.53, 0.42) if l.kind in ["debris", "asteroid", "outpost", "wreck"] else (Color(0.69, 0.42, 0.82) if l.get("black", false) else Color(0.35, 0.78, 0.9))
		var sz := maxf(6.0, 0.08 * zoom)
		draw_rect(Rect2(sp - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), col)
		draw_string(font, sp + Vector2(sz * 0.5 + 6, 4), l.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.87, 0.9, 0.94))
	# Predicted trajectory (gravity only)
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
	# Selected target: ring and line
	if P.target != "" and not P.loc(P.target).is_empty():
		var tp := to_screen(P.loc_state(P.loc(P.target), P.secs()).pos)
		draw_arc(tp, 12.0, 0, TAU, 32, Color(0.35, 0.78, 0.9), 2.0)
		draw_line(to_screen(P.pos), tp, Color(0.35, 0.78, 0.9, 0.35), 1.0)
		if zoom > 50.0:
			# Andockbereich (250 m)
			draw_arc(tp, float(P.space.dock_dist) * zoom, 0, TAU, 48, Color(0.44, 0.81, 0.56, 0.5), 1.0)
	# Ship
	var s := to_screen(P.pos)
	var dir := Vector2.from_angle(P.angle)
	var side := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([s + dir * 10, s - dir * 7 + side * 6, s - dir * 4, s - dir * 7 - side * 6]), Color(0.95, 0.64, 0.23))
	if P.thrust > 0.0:
		draw_line(s - dir * 5, s - dir * (14 + randf() * 5), Color(1, 0.82, 0.48), 3.0)
