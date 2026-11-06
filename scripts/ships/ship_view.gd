## Zeichnet das Schiff von oben: Felder, Kabel, Geräte, Haufen,
## Baupläne, Charaktere und Werkzeug-Vorschau. Ohne Grafikdateien,
## nur mit einfachen Formen (draw_rect, draw_circle, ...).
extends Node2D

const S := Config.TILE_SIZE
const COL_FLOOR := Color(0.165, 0.204, 0.259)
const COL_FLOOR_ALT := Color(0.153, 0.192, 0.251)
const COL_WALL := Color(0.655, 0.694, 0.753)
const COL_WALL_EDGE := Color(0.294, 0.333, 0.4)
const COL_DOOR := Color(0.788, 0.541, 0.173)
const COL_PLAN := Color(0.349, 0.78, 0.902)
const COL_REMOVE := Color(0.898, 0.329, 0.294)

## Vom Hauptskript gesetzt: Feld unter der Maus und markierte Felder
var hover := Vector2i(-1, -1)
var preview: Array[Vector2i] = []

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var g := ShipSystem.grid
	if g == null:
		return
	# Nur sichtbare Felder zeichnen
	var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()
	var x0 := maxi(0, floori(view.position.x / S))
	var y0 := maxi(0, floori(view.position.y / S))
	var x1 := mini(g.width - 1, ceili(view.end.x / S))
	var y1 := mini(g.height - 1, ceili(view.end.y / S))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_draw_tile(g, Vector2i(x, y))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := g.idx(Vector2i(x, y))
			if g.cables[i] == 1:
				_draw_cable(g, Vector2i(x, y))
	for i in g.piles:
		_draw_pile(g.pos(i))
	for i in g.devices:
		_draw_device(g.devices[i])
	if GameState.view == "air":
		_draw_air(g, x0, y0, x1, y1)
	if GameState.view == "heat":
		_draw_heat(g, x0, y0, x1, y1)
	_draw_fire(g, x0, y0, x1, y1)
	_draw_jobs()
	for c in CrewSystem.crew:
		_draw_char(c)
	_draw_effects()
	_draw_preview(g)

func _draw_effects() -> void:
	var now := Time.get_ticks_msec()
	DamageSystem.effects = DamageSystem.effects.filter(func(e): return now - e.start < 1500)
	for e in DamageSystem.effects:
		var f: float = (now - e.start) / 1500.0
		var c := (Vector2(e.pos) + Vector2(0.5, 0.5)) * S
		draw_circle(c, S * (0.2 + f * 1.6), Color(1, 0.95, 0.77, 1.0 - f))
		draw_arc(c, S * (0.4 + f * 2.5), 0, TAU, 32, Color(1, 0.7, 0.28, 1.0 - f), 2.5)

func _rect(p: Vector2i, inset: float = 0.0) -> Rect2:
	return Rect2(Vector2(p) * S + Vector2(inset, inset) * S, Vector2(S, S) * (1.0 - 2.0 * inset))

func _draw_tile(g: ShipGrid, p: Vector2i) -> void:
	var t := g.get_tile(p)
	if t == ShipGrid.Tile.SPACE:
		return
	var zone := g.zone[g.idx(p)]
	var floor_col := COL_FLOOR if (p.x + p.y) % 2 == 0 else COL_FLOOR_ALT
	if zone == 1:
		floor_col = Color(0.2, 0.188, 0.172) if (p.x + p.y) % 2 == 0 else Color(0.184, 0.172, 0.157)
	elif zone == 2:
		floor_col = Color(0.17, 0.19, 0.21)
	draw_rect(_rect(p), floor_col)
	draw_rect(_rect(p, 0.02), Color(0.11, 0.145, 0.19), false, 1.0)
	# Schleusenboden: Warnstreifen
	if t == ShipGrid.Tile.FLOOR and AirlockSystem.is_lock_tile(g.idx(p)):
		var o := Vector2(p) * S
		for k in 3:
			var a := o + Vector2(k * 0.35 * S, S)
			draw_line(a, a + Vector2(S * 0.35, -S * 0.35), Color(0.95, 0.64, 0.23, 0.25), 3.0)
	if t == ShipGrid.Tile.WALL:
		draw_rect(_rect(p), COL_WALL)
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			if not g.wall_like(p + d):
				var r := _rect(p)
				var e := S * 0.1
				if d == Vector2i(0, -1):
					r = Rect2(r.position, Vector2(S, e))
				elif d == Vector2i(0, 1):
					r = Rect2(r.position + Vector2(0, S - e), Vector2(S, e))
				elif d == Vector2i(-1, 0):
					r = Rect2(r.position, Vector2(e, S))
				else:
					r = Rect2(r.position + Vector2(S - e, 0), Vector2(e, S))
				draw_rect(r, COL_WALL_EDGE)
		_draw_cracks(p, g.cond[g.idx(p)])
	elif t == ShipGrid.Tile.WINDOW:
		draw_rect(_rect(p), Color(0.35, 0.55, 0.7))
		draw_rect(_rect(p, 0.12), Color(0.55, 0.8, 0.95, 0.8))
		draw_line(Vector2(p) * S + Vector2(0.25, 0.7) * S, Vector2(p) * S + Vector2(0.7, 0.25) * S, Color(1, 1, 1, 0.6), 1.5)
	elif t == ShipGrid.Tile.DOOR:
		var horizontal := g.wall_like(p + Vector2i(-1, 0)) or g.wall_like(p + Vector2i(1, 0))
		var gap := 0.3 if g.door_open(g.idx(p)) else 0.0
		var o := Vector2(p) * S
		if horizontal:
			draw_rect(Rect2(o + Vector2(0.04, 0.36) * S, Vector2(0.44 - gap, 0.28) * S), COL_DOOR)
			draw_rect(Rect2(o + Vector2(0.52 + gap, 0.36) * S, Vector2(0.44 - gap, 0.28) * S), COL_DOOR)
		else:
			draw_rect(Rect2(o + Vector2(0.36, 0.04) * S, Vector2(0.28, 0.44 - gap) * S), COL_DOOR)
			draw_rect(Rect2(o + Vector2(0.36, 0.52 + gap) * S, Vector2(0.28, 0.44 - gap) * S), COL_DOOR)
		if AirlockSystem.is_lock_door(g.idx(p)):
			draw_rect(_rect(p, 0.04), COL_PLAN, false, 2.0)
		_draw_cracks(p, g.cond[g.idx(p)])

func _draw_cracks(p: Vector2i, c: float) -> void:
	if c >= 85.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p)
	var o := Vector2(p) * S
	for k in (3 if c < 40.0 else 1):
		var a := o + Vector2(rng.randf_range(0.2, 0.8), rng.randf_range(0.2, 0.8)) * S
		var b := a + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)) * S
		draw_line(a, b, Color(0.08, 0.04, 0.02, 0.8), 1.5)

func _draw_cable(g: ShipGrid, p: Vector2i) -> void:
	var col := Color(0.84, 0.63, 0.24, 0.55)
	if GameState.view == "power":
		var net_id := ShipPowerSystem.net_of[g.idx(p)] if ShipPowerSystem.net_of.size() > g.idx(p) else -1
		var ok: bool = net_id >= 0 and ShipPowerSystem.nets[net_id].ok and ShipPowerSystem.nets[net_id].production > 0.0
		col = Color(1, 0.82, 0.25) if ok else COL_REMOVE
	var c := (Vector2(p) + Vector2(0.5, 0.5)) * S
	var any := false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = p + d
		if g.in_bounds(q) and g.cables[g.idx(q)] == 1:
			draw_line(c, c + Vector2(d) * S * 0.5, col, 2.0)
			any = true
	if not any:
		draw_line(c - Vector2(S * 0.2, 0), c + Vector2(S * 0.2, 0), col, 2.0)

func _draw_device(dev: Device, ghost: bool = false) -> void:
	var d := dev.data()
	var r := _rect(dev.pos, 0.1)
	if dev.unknown and not ghost:
		draw_rect(r, Color(0.23, 0.24, 0.26))
		draw_rect(r, Color(0, 0, 0, 0.5), false, 1.0)
		draw_string(ThemeDB.fallback_font, r.position + Vector2(S * 0.28, S * 0.58), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.55, 0.57, 0.6))
		return
	var col := d.color
	if ghost:
		col.a = 0.45
	draw_rect(r, col)
	draw_rect(r, Color(0, 0, 0, 0.5), false, 1.0)
	_draw_icon(dev, r, 0.45 if ghost else 1.0)
	if ghost:
		return
	# Füllstand / Ladung
	var f := -1.0
	if d.stock > 0.0:
		f = dev.stock / d.stock
	elif d.capacity > 0.0:
		f = dev.charge / d.capacity
	if f >= 0.0:
		draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3), Vector2(r.size.x * clampf(f, 0.0, 1.0), 3)), Color(0.44, 0.81, 0.56))
	_draw_cracks(dev.pos, dev.cond)
	if dev.type == "locker" and dev.suit != null:
		draw_circle(r.get_center() - Vector2(0, S * 0.1), S * 0.13, Color(0.9, 0.91, 0.93))
	if dev.type == "pump" and AirlockSystem.is_pumping(dev):
		draw_arc(r.get_center(), S * 0.25, Time.get_ticks_msec() / 100.0, Time.get_ticks_msec() / 100.0 + 4.0, 12, COL_PLAN, 2.0)
	if dev.broken:
		draw_line(r.position, r.end, COL_REMOVE, 2.0)
		draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), COL_REMOVE, 2.0)
	var problem := (dev.needs_power() and not dev.powered) or (d.stock >= 0.0 and dev.stock <= 0.0) or dev.broken or (dev.type == "solar" and not dev.producing)
	if problem and int(Time.get_ticks_msec() / 400) % 2 == 0:
		draw_circle(Vector2(dev.pos) * S + Vector2(0.82, 0.18) * S, S * 0.09, COL_REMOVE)

func _draw_pile(p: Vector2i) -> void:
	var o := Vector2(p) * S
	for k in 3:
		draw_rect(Rect2(o + Vector2(0.2 + k * 0.2, 0.35 + (k % 2) * 0.2) * S, Vector2(0.22, 0.18) * S), Color(0.6, 0.55, 0.48))

func _draw_air(g: ShipGrid, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := g.idx(Vector2i(x, y))
			if not g.holds_air(i):
				continue
			var o2 := g.o2[i]
			var col := Color(0.44, 0.81, 0.56, 0.38)
			if o2 < Config.O2_LOW:
				col = Color(0.9, 0.33, 0.29, 0.3 + 0.35 * (1.0 - o2 / Config.O2_LOW))
			elif o2 < Config.O2_OK or g.co2[i] > Config.CO2_BAD:
				col = Color(0.95, 0.78, 0.23, 0.45)
			draw_rect(_rect(Vector2i(x, y)), col)

func _draw_heat(g: ShipGrid, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := g.idx(Vector2i(x, y))
			if not g.holds_air(i):
				continue
			var t := g.temp[i]
			var col := Color(0.3, 0.5, 0.95, clampf((15.0 - t) / 40.0, 0.0, 0.6)) if t < 15.0 else Color(0.95, 0.45, 0.2, clampf((t - 25.0) / 40.0, 0.0, 0.6))
			if t >= 15.0 and t <= 25.0:
				col = Color(0.44, 0.81, 0.56, 0.25)
			draw_rect(_rect(Vector2i(x, y)), col)

func _draw_fire(g: ShipGrid, x0: int, y0: int, x1: int, y1: int) -> void:
	var tm := Time.get_ticks_msec() / 120.0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if g.fire[g.idx(Vector2i(x, y))] == 1:
				var c := (Vector2(x, y) + Vector2(0.5, 0.6)) * S
				for k in 3:
					var off := Vector2(sin(tm + k * 2.1), -absf(cos(tm * 1.3 + k))) * S * 0.2
					draw_circle(c + off, S * (0.28 - k * 0.07), [Color(0.9, 0.3, 0.1, 0.8), Color(1, 0.6, 0.15, 0.85), Color(1, 0.9, 0.5, 0.9)][k])

func _draw_jobs() -> void:
	var pulse := 0.55 + 0.25 * sin(Time.get_ticks_msec() / 300.0)
	for job in ShipConstructionSystem.jobs.values():
		var p := ShipConstructionSystem.pos_of(job)
		var col := COL_REMOVE if job.kind == "remove" or job.get("missing", false) else COL_PLAN
		col.a = pulse
		if job.kind == "haul":
			draw_rect(_rect(p, 0.08), Color(0.44, 0.81, 0.56, pulse), false, 2.0)
			continue
		if job.kind == "remove":
			var o := Vector2(p) * S
			draw_line(o + Vector2(0.2, 0.2) * S, o + Vector2(0.8, 0.8) * S, col, 2.5)
			draw_line(o + Vector2(0.8, 0.2) * S, o + Vector2(0.2, 0.8) * S, col, 2.5)
		else:
			draw_rect(_rect(p, 0.05), Color(COL_PLAN, 0.18))
			draw_rect(_rect(p, 0.08), col, false, 1.5)
			if job.kind == "device":
				_draw_device(Device.new(job.dev, p), true)
		if job.progress > 0.0:
			var o := Vector2(p) * S
			draw_rect(Rect2(o + Vector2(0.1, 0.82) * S, Vector2(0.8, 0.1) * S), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(o + Vector2(0.1, 0.82) * S, Vector2(0.8 * minf(1.0, job.progress / job.need), 0.1) * S), Color(0.95, 0.64, 0.23))

func _draw_char(c: CrewMember) -> void:
	var center := c.pos * S
	var font := ThemeDB.fallback_font
	if c.unconscious:
		draw_circle(center, S * 0.28, Color(0.48, 0.42, 0.35))
		draw_string(font, center + Vector2(-3, -S * 0.4), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_REMOVE)
		return
	draw_circle(center + Vector2(1, 2), S * 0.3, Color(0, 0, 0, 0.35))
	if c.suit != null:
		# Raumanzug: weiß mit farbigem Ring und Rucksack
		draw_circle(center - Vector2.from_angle(c.facing) * S * 0.2, S * 0.13, Color(0.54, 0.58, 0.65))
		draw_circle(center, S * 0.31, Color(0.9, 0.91, 0.93))
		draw_arc(center, S * 0.31, 0, TAU, 24, c.color, 2.5)
		draw_circle(center + Vector2.from_angle(c.facing) * S * 0.14, S * 0.14, Color(0.95, 0.76, 0.31))
	else:
		draw_circle(center, S * 0.28, c.color)
		draw_circle(center + Vector2.from_angle(c.facing) * S * 0.14, S * 0.11, Color(0.75, 0.91, 1.0))
	if c.carrying != null:
		var cr := Rect2(center + Vector2(-0.25, -0.85) * S, Vector2(0.5, 0.5) * S)
		draw_rect(cr, c.carrying.data().color)
		draw_rect(cr, Color(0, 0, 0, 0.5), false, 1.0)
	if GameState.selected == c:
		draw_arc(center, S * 0.42, 0, TAU, 32, Color(0.95, 0.64, 0.23), 1.5)
	var label := ("▸ " if c.is_player else "") + c.display_name
	draw_string(font, center + Vector2(-S * 2, -S * 0.5), label, HORIZONTAL_ALIGNMENT_CENTER, S * 4, 11,
		Color(0.95, 0.76, 0.31) if c.is_player else Color(0.91, 0.93, 0.96))
	if not c.path.is_empty() and (c.order != null):
		var prev := center
		for q in c.path:
			var nxt := (Vector2(q) + Vector2(0.5, 0.5)) * S
			draw_line(prev, nxt, Color(0.95, 0.64, 0.23, 0.6), 1.0)
			prev = nxt

func _draw_preview(g: ShipGrid) -> void:
	if not g.in_bounds(hover):
		return
	if GameState.tool == "select":
		draw_rect(_rect(hover), Color(1, 1, 1, 0.15))
		return
	var tiles: Array[Vector2i] = []
	if preview.is_empty():
		tiles.append(hover)
	else:
		tiles = preview
	for p in tiles:
		var ok := ShipConstructionSystem.can_place(GameState.tool, p)
		var col := Color(1, 1, 1, 0.06)
		if ok:
			col = Color(0.9, 0.33, 0.29, 0.35) if GameState.tool in ["remove", "cancel"] else Color(0.35, 0.78, 0.9, 0.35)
		draw_rect(_rect(p), col)

## Einfache Symbole pro Gerät (nur Formen, keine Grafikdateien)
func _draw_icon(dev: Device, r: Rect2, a: float) -> void:
	var c := r.get_center()
	var u := S * 0.8  # Größe des Geräts
	var t := Time.get_ticks_msec() / 1000.0
	var on := dev.powered or dev.producing or not dev.needs_power()
	match dev.type:
		"generator":
			draw_circle(c, u * 0.3, Color(1, 0.7, 0.28, a) if dev.producing else Color(0.35, 0.27, 0.19, a))
			if dev.producing:
				draw_circle(c, u * (0.15 + sin(t * 4.0) * 0.03), Color(1, 0.95, 0.78, a))
		"battery", "charger":
			var cap := dev.data().capacity
			var f := dev.charge / cap if cap > 0.0 else 0.0
			var br := Rect2(c - Vector2(u * 0.2, u * 0.3), Vector2(u * 0.4, u * 0.6))
			draw_rect(br, Color(0.1, 0.13, 0.12, a))
			draw_rect(Rect2(br.position + Vector2(0, br.size.y * (1.0 - f)), Vector2(br.size.x, br.size.y * f)), Color(0.44, 0.81, 0.56, a) if f > 0.25 else Color(0.9, 0.33, 0.29, a))
			if dev.type == "charger":
				draw_line(c + Vector2(u * 0.05, -u * 0.2), c + Vector2(-u * 0.08, u * 0.02), Color(1, 0.82, 0.25, a), 2.0)
				draw_line(c + Vector2(-u * 0.08, u * 0.02), c + Vector2(u * 0.05, u * 0.2), Color(1, 0.82, 0.25, a), 2.0)
		"o2gen":
			draw_circle(c, u * 0.3, Color(0.35, 0.78, 0.9, a))
			draw_circle(c, u * 0.14, Color(0.9, 0.97, 1, a))
			if dev.powered:
				for k in 3:
					var p := fmod(t * 0.7 + k / 3.0, 1.0)
					draw_circle(c + Vector2(sin(k * 2.1) * u * 0.2, -u * 0.1 - p * u * 0.35), u * 0.05, Color(0.75, 0.94, 1, a * (1.0 - p)))
		"scrubber", "heater":
			var ang := t * 6.0 if dev.powered else 0.0
			var col := Color(0.62, 0.7, 0.6, a) if dev.type == "scrubber" else Color(1, 0.5, 0.25, a)
			for k in 4:
				draw_line(c, c + Vector2.from_angle(ang + k * PI / 2.0) * u * 0.32, col, 3.0)
			draw_circle(c, u * 0.08, Color(0.16, 0.2, 0.16, a))
		"airtank":
			draw_circle(c, u * 0.38, Color(0.53, 0.59, 0.67, a))
			var f2 := dev.stock / maxf(1.0, dev.data().stock)
			draw_rect(Rect2(c + Vector2(-u * 0.3, -u * 0.05), Vector2(u * 0.6 * f2, u * 0.1)), Color(0.35, 0.78, 0.9, a))
		"bed":
			draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, r.size.y * 0.3)), Color(0.85, 0.87, 0.92, a))
			draw_rect(Rect2(r.position + Vector2(1, r.size.y * 0.38), Vector2(r.size.x - 2, r.size.y * 0.58)), Color(0.35, 0.45, 0.66, a))
		"food", "crate", "terminal", "workbench", "chemstation", "locker":
			draw_rect(r.grow(-u * 0.12), Color(0, 0, 0, 0.25 * a), false, 1.5)
			match dev.type:
				"food":
					draw_line(Vector2(c.x, r.position.y + 3), Vector2(c.x, r.end.y - 3), Color(0.24, 0.2, 0.15, a), 1.5)
				"crate":
					draw_line(r.position + Vector2(4, 4), r.end - Vector2(4, 4), Color(0.23, 0.18, 0.12, a), 1.5)
					var f3 := dev.inv.volume() / maxf(1.0, dev.data().storage) if dev.inv != null else 0.0
					draw_rect(Rect2(Vector2(r.position.x + 2, r.end.y - 3), Vector2((r.size.x - 4) * f3, 2)), Color(0.95, 0.64, 0.23, a))
				"terminal":
					draw_rect(Rect2(c - Vector2(u * 0.3, u * 0.22), Vector2(u * 0.6, u * 0.36)), Color(0.35, 0.78, 0.9, a * (0.9 if on else 0.2)))
				"workbench", "chemstation":
					draw_line(c - Vector2(u * 0.25, u * 0.15), c + Vector2(u * 0.25, u * 0.15), Color(0.75, 0.75, 0.78, a), 3.0)
					draw_circle(c + Vector2(u * 0.15, -u * 0.15), u * 0.08, Color(0.6, 0.85, 0.5, a) if dev.type == "chemstation" else Color(0.8, 0.8, 0.8, a))
				"locker":
					if dev.suit != null:
						draw_circle(c - Vector2(0, u * 0.12), u * 0.13, Color(0.9, 0.91, 0.93, a))
						draw_rect(Rect2(c + Vector2(-u * 0.16, 0), Vector2(u * 0.32, u * 0.3)), Color(0.9, 0.91, 0.93, a))
		"water", "sink", "waterfilter":
			draw_circle(c + Vector2(0, u * 0.05), u * 0.25, Color(0.79, 0.84, 0.89, a))
			var f4 := dev.stock / maxf(1.0, dev.data().stock)
			draw_circle(c + Vector2(0, u * 0.05), u * 0.18 * f4, Color(0.5, 0.83, 0.96, a))
		"solar":
			for k in range(1, 3):
				draw_line(r.position + Vector2(r.size.x * k / 3.0, 0), r.position + Vector2(r.size.x * k / 3.0, r.size.y), Color(0.31, 0.44, 0.71, a), 1.0)
				draw_line(r.position + Vector2(0, r.size.y * k / 3.0), r.position + Vector2(r.size.x, r.size.y * k / 3.0), Color(0.31, 0.44, 0.71, a), 1.0)
		"pump":
			draw_arc(c, u * 0.25, t * 10.0 if AirlockSystem.is_pumping(dev) else 0.3, (t * 10.0 if AirlockSystem.is_pumping(dev) else 0.3) + 4.5, 12, Color(0.35, 0.78, 0.9, a), 2.5)
		"helm":
			draw_arc(c, u * 0.28, PI, TAU, 12, Color(0.95, 0.64, 0.23, a), 3.0)
			draw_circle(c, u * 0.08, Color(0.35, 0.78, 0.9, a))
		"thruster":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.25, -u * 0.3), c + Vector2(u * 0.25, -u * 0.3), c + Vector2(u * 0.35, u * 0.3), c + Vector2(-u * 0.35, u * 0.3)]), Color(0.45, 0.48, 0.52, a))
			if PhysicsSystem.thrust > 0.0 and dev.powered:
				draw_circle(c + Vector2(0, u * 0.45), u * (0.15 + randf() * 0.08), Color(1, 0.75, 0.3, a))
		"fueltank":
			draw_circle(c, u * 0.36, Color(0.6, 0.22, 0.2, a))
			draw_string(ThemeDB.fallback_font, c + Vector2(-u * 0.12, u * 0.12), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.9, 0.8, a))
		"autodock":
			draw_rect(Rect2(c - Vector2(u * 0.2, u * 0.2), Vector2(u * 0.4, u * 0.4)), Color(0.35, 0.78, 0.9, a), false, 2.0)
			draw_line(c - Vector2(u * 0.3, 0), c + Vector2(u * 0.3, 0), Color(0.35, 0.78, 0.9, a), 1.5)
		"hydro", "autofarm":
			var g2 := dev.growth
			for k in 3:
				var stem := c + Vector2((k - 1) * u * 0.22, u * 0.25)
				draw_line(stem, stem - Vector2(0, u * (0.1 + 0.4 * g2)), Color(0.4, 0.8, 0.35, a), 2.0)
				draw_circle(stem - Vector2(0, u * (0.1 + 0.4 * g2)), u * (0.04 + 0.08 * g2), Color(0.5, 0.9, 0.4, a))
		"meatvat":
			draw_circle(c, u * 0.3, Color(0.75, 0.35, 0.4, a))
			draw_arc(c, u * 0.36, 0, TAU, 16, Color(0.6, 0.6, 0.65, a), 1.5)
		"trainer":
			draw_circle(c, u * 0.25, Color(0.6, 0.3, 0.3, a))
			draw_arc(c, u * 0.35, 0, TAU, 16, Color(0.9, 0.9, 0.9, a), 1.0)
		"extinguisher":
			draw_rect(Rect2(c - Vector2(u * 0.12, u * 0.3), Vector2(u * 0.24, u * 0.6)), Color(0.85, 0.15, 0.15, a))
		_:
			draw_string(ThemeDB.fallback_font, r.position + Vector2(3, S * 0.5), dev.data().display_name.substr(0, 2), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85 * a))
