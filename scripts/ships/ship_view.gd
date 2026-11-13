## Zeichnet das Schiff von oben: Felder, Kabel, Geräte, Haufen,
## Baupläne, Charaktere und Werkzeug-Vorschau. Ohne Grafikdateien,
## nur mit einfachen Formen (draw_rect, draw_circle, ...).
extends Node2D

const S := Config.TILE_SIZE
## Figurengröße in Pixeln (bleibt beim feineren Raster gleich)
const CS := Config.CHAR_PX
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
	if GameState.view == "damage":
		_draw_damage(g, x0, y0, x1, y1)
	_draw_fire(g, x0, y0, x1, y1)
	_draw_jobs()
	_draw_station()
	for c in CrewSystem.crew:
		_draw_char(c)
	_draw_bubbles()
	_draw_effects()
	_draw_selection(g)
	_draw_preview(g)

func _draw_effects() -> void:
	var now := Time.get_ticks_msec()
	DamageSystem.effects = DamageSystem.effects.filter(func(e): return now - e.start < 1500)
	for e in DamageSystem.effects:
		var f: float = (now - e.start) / 1500.0
		var c := (Vector2(e.pos) + Vector2(0.5, 0.5)) * S
		if e.get("small", false):
			# Schlag beim Zerstören: kurzer, kleiner Funke
			if f < 0.3:
				var k := f / 0.3
				draw_circle(c, S * (0.12 + k * 0.3), Color(1, 0.9, 0.6, 1.0 - k))
				draw_arc(c, S * (0.2 + k * 0.45), 0, TAU, 16, Color(1, 0.6, 0.25, 1.0 - k), 1.5)
			continue
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
	elif zone == StationSystem.ZONE:
		floor_col = Color(0.2, 0.235, 0.27) if (p.x + p.y) % 2 == 0 else Color(0.19, 0.225, 0.26)
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
	if d.width > 1 and not (dev.unknown and not ghost):
		_draw_dock(dev, ghost)
		return
	if d.length > 1 and not (dev.unknown and not ghost):
		_draw_long_device(dev, ghost)
		return
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

## Mehrfeld-Gerät (Triebwerk 1×3): Gehäuse innen, Halterung auf der Wand, Düse im All
func _draw_long_device(dev: Device, ghost: bool) -> void:
	var d := dev.data()
	var a := 0.45 if ghost else 1.0
	var cells := dev.cells()
	var ex := Vector2(dev.outward())
	var side := ex.orthogonal()
	var col := d.color
	col.a = a
	# Gehäuse auf dem Innenfeld
	var r0 := _rect(cells[0], 0.1)
	draw_rect(r0, col)
	draw_rect(r0, Color(0, 0, 0, 0.5 * a), false, 1.0)
	# Halterung durch die Wand (schmaler Steg)
	var c1 := (Vector2(cells[1]) + Vector2(0.5, 0.5)) * S
	draw_line(c1 - ex * S * 0.5, c1 + ex * S * 0.5, Color(0.55, 0.58, 0.62, a), S * 0.32)
	# Düse draußen: öffnet sich zum All
	var c2 := (Vector2(cells[2]) + Vector2(0.5, 0.5)) * S
	draw_colored_polygon(PackedVector2Array([c2 - ex * S * 0.5 + side * S * 0.16, c2 - ex * S * 0.5 - side * S * 0.16,
		c2 + ex * S * 0.35 - side * S * 0.36, c2 + ex * S * 0.35 + side * S * 0.36]), Color(0.45, 0.48, 0.52, a))
	# Pfeil: Schubrichtung (vom All weg)
	var c0 := r0.get_center()
	draw_colored_polygon(PackedVector2Array([c0 - ex * S * 0.32, c0 + side * S * 0.16, c0 - side * S * 0.16]), Color(0.95, 0.76, 0.31, a))
	if ghost:
		return
	if dev.powered and not dev.broken and PhysicsSystem.firing(dev.push_dir()):
		draw_circle(c2 + ex * S * 0.6, S * (0.2 + randf() * 0.1), Color(1, 0.75, 0.3))
	_draw_cracks(cells[0], dev.cond)
	if dev.broken:
		draw_line(r0.position, r0.end, COL_REMOVE, 2.0)
		draw_line(Vector2(r0.end.x, r0.position.y), Vector2(r0.position.x, r0.end.y), COL_REMOVE, 2.0)
	if ((dev.needs_power() and not dev.powered) or dev.broken) and int(Time.get_ticks_msec() / 400) % 2 == 0:
		draw_circle(Vector2(cells[0]) * S + Vector2(0.82, 0.18) * S, S * 0.09, COL_REMOVE)

## Andockschleuse 5×2: Rahmen über die ganze Fläche, Außentür mit Lampe (grün = gekoppelt),
## Innentür mit Pfeil nach außen
func _draw_dock(dev: Device, ghost: bool) -> void:
	var a := 0.45 if ghost else 1.0
	var cells := dev.cells()
	var lo := cells[0]
	var hi := cells[0]
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var r := Rect2(Vector2(lo) * S, Vector2(hi - lo + Vector2i.ONE) * S).grow(-1.0)
	if ghost:
		draw_rect(r, Color(0.36, 0.33, 0.24, 0.45))
	draw_rect(r, Color(0.95, 0.76, 0.31, a), false, 2.0)
	var out := Vector2(dev.outward())
	var linked := ShipSystem.grid.linked.has(ShipSystem.grid.idx(dev.pos))
	var od := (Vector2(dev.pos) + Vector2(0.5, 0.5)) * S
	draw_circle(od, S * 0.22, Color(0.44, 0.81, 0.56, a) if linked else Color(0.9, 0.33, 0.29, a))
	var idr := od - out * S
	draw_line(idr - out * S * 0.25, idr + out * S * 0.25, Color(0.95, 0.76, 0.31, a), 2.0)
	if ghost:
		return
	_draw_cracks(dev.pos, dev.cond)
	if dev.broken:
		draw_line(r.position, r.end, COL_REMOVE, 2.0)

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
	_draw_room_types(g)

## Raumtypen (Ostranauts Rooms) in der Luft-Ansicht: Name und Wertfaktor oben links im Raum
var _room_cache: Array = []
var _room_cache_at := -100000
func _draw_room_types(g: ShipGrid) -> void:
	var now := Time.get_ticks_msec()
	if now - _room_cache_at > 1000:
		_room_cache = RoomTypes.classify(g)
		_room_cache_at = now
	var font := ThemeDB.fallback_font
	for room in _room_cache:
		var r: Rect2i = room.rect
		var col := Color(0.95, 0.93, 0.88, 0.9) if room.modifier > 1.0 else Color(0.75, 0.8, 0.86, 0.7)
		draw_string(font, Vector2(r.position) * S + Vector2(2, 11), "%s ×%.2f" % [room.name, room.modifier],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)

## Schadensansicht (Ostranauts: Lecks finden): beschädigte Felder und Geräte rot, je
## schlimmer desto kräftiger, mit „~“; Vakuumkanten (Leck ins All) als roter Rand
func _draw_damage(g: ShipGrid, x0: int, y0: int, x1: int, y1: int) -> void:
	var font := ThemeDB.fallback_font
	var m := damage_marks(g, x0, y0, x1, y1)
	for i in m.damaged:
		var p := g.pos(i)
		draw_rect(_rect(p), Color(0.9, 0.2, 0.18, 0.2 + 0.5 * (1.0 - float(m.damaged[i]) / 100.0)))
		draw_string(font, Vector2(p) * S + Vector2(S * 0.22, S * 0.75), "~", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.85, 0.8))
	for i in m.leaks:
		draw_rect(_rect(g.pos(i)), Color(1, 0.3, 0.25, 0.9), false, 2.0)

## Was die Schadensansicht markiert: {damaged: {Feld: schlechtester Zustand}, leaks: [Felder mit Vakuumkante]}
func damage_marks(g: ShipGrid, x0: int, y0: int, x1: int, y1: int) -> Dictionary:
	var damaged := {}
	var leaks: Array[int] = []
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := g.idx(Vector2i(x, y))
			if g.tiles[i] == ShipGrid.Tile.SPACE or g.foreign(i):
				continue
			var c := g.cond[i]
			var dev = g.devices.get(i)
			if dev != null:
				c = minf(c, 0.0 if dev.broken else dev.cond)
			if c < 100.0:
				damaged[i] = c
			if g.holds_air(i) and AtmosphereSystem.vacuum_edges(i) > 0:
				leaks.append(i)
	return {"damaged": damaged, "leaks": leaks}

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
		if job.kind == "remove" or job.kind == "destroy":
			var o := Vector2(p) * S
			if job.kind == "destroy":
				col = Color(COL_REMOVE, pulse)
			draw_line(o + Vector2(0.2, 0.2) * S, o + Vector2(0.8, 0.8) * S, col, 2.5)
			draw_line(o + Vector2(0.8, 0.2) * S, o + Vector2(0.2, 0.8) * S, col, 2.5)
		elif job.kind == "uninstall" or job.kind == "dismantle":
			# Abbauen: Pfeil nach oben, Zerlegen: Schraubenschlüssel-Symbol
			draw_rect(_rect(p, 0.08), Color(0.95, 0.76, 0.31, pulse), false, 1.5)
			draw_string(ThemeDB.fallback_font, Vector2(p) * S + Vector2(0.3, 0.65) * S, "⇧" if job.kind == "uninstall" else "⚒",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.76, 0.31, pulse))
		else:
			draw_rect(_rect(p, 0.05), Color(COL_PLAN, 0.18))
			draw_rect(_rect(p, 0.08), col, false, 1.5)
			if job.kind == "device":
				var ghost := Device.new(job.dev, p)
				ghost.rot = int(job.get("rot", 0))
				_draw_device(ghost, true)
			elif job.kind == "install" and RemovalSystem.key_of_packed(String(job.item)).begins_with("dev:"):
				_draw_device(Device.new(RemovalSystem.key_of_packed(String(job.item)).substr(4), p), true)
		if job.progress > 0.0:
			var o := Vector2(p) * S
			draw_rect(Rect2(o + Vector2(0.1, 0.82) * S, Vector2(0.8, 0.1) * S), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(o + Vector2(0.1, 0.82) * S, Vector2(0.8 * minf(1.0, job.progress / job.need), 0.1) * S), Color(0.95, 0.64, 0.23))

func _draw_char(c: CrewMember) -> void:
	var center := c.pos * S
	var font := ThemeDB.fallback_font
	if c.unconscious:
		draw_circle(center, CS * 0.28, Color(0.48, 0.42, 0.35))
		draw_string(font, center + Vector2(-3, -CS * 0.4), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_REMOVE)
		return
	draw_circle(center + Vector2(1, 2), CS * 0.3, Color(0, 0, 0, 0.35))
	if c.suit != null:
		# Raumanzug: weiß mit farbigem Ring und Rucksack
		draw_circle(center - Vector2.from_angle(c.facing) * CS * 0.2, CS * 0.13, Color(0.54, 0.58, 0.65))
		draw_circle(center, CS * 0.31, Color(0.9, 0.91, 0.93))
		draw_arc(center, CS * 0.31, 0, TAU, 24, c.color, 2.5)
		draw_circle(center + Vector2.from_angle(c.facing) * CS * 0.14, CS * 0.14, Color(0.95, 0.76, 0.31))
	else:
		draw_circle(center, CS * 0.28, c.color)
		draw_circle(center + Vector2.from_angle(c.facing) * CS * 0.14, CS * 0.11, Color(0.75, 0.91, 1.0))
	if c.carrying != null:
		var cr := Rect2(center + Vector2(-0.25, -0.85) * CS, Vector2(0.5, 0.5) * CS)
		draw_rect(cr, c.carrying.data().color)
		draw_rect(cr, Color(0, 0, 0, 0.5), false, 1.0)
	if GameState.selected == c:
		# Ausgewählt: weiße Eckmarkierungen um die Figur (wie in Ostranauts)
		var h := CS * 0.5
		var l := CS * 0.18
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner := center + Vector2(sx * h, sy * h)
				draw_line(corner, corner - Vector2(sx * l, 0), Color(1, 1, 1, 0.95), 2.0)
				draw_line(corner, corner - Vector2(0, sy * l), Color(1, 1, 1, 0.95), 2.0)
	var label := ("▸ " if c.is_player else "") + c.display_name
	draw_string(font, center + Vector2(-CS * 2, -CS * 0.5), label, HORIZONTAL_ALIGNMENT_CENTER, CS * 4, 11,
		Color(0.95, 0.76, 0.31) if c.is_player else Color(0.91, 0.93, 0.96))
	if not c.path.is_empty() and (c.order != null):
		var prev := center
		for q in c.path:
			var nxt := (Vector2(q) + Vector2(0.5, 0.5)) * S
			draw_line(prev, nxt, Color(0.95, 0.64, 0.23, 0.6), 1.0)
			prev = nxt

## Rechtsklick-Auswahl: genau die markierte Ebene hervorheben (Kabel, Gerät mit allen
## Feldern, oder Boden/Wand) und benennen
func _draw_selection(g: ShipGrid) -> void:
	if not UIManager.selection_valid():
		return
	var p: Vector2i = UIManager.sel_tile
	var key: String = UIManager.sel_key
	var col := Color(1.0, 0.86, 0.2)
	var c := (Vector2(p) + Vector2(0.5, 0.5)) * S
	if key == "cable":
		draw_circle(c, S * 0.16, col)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if g.in_bounds(q) and g.cables[g.idx(q)] == 1:
				draw_line(c, c + Vector2(d) * S * 0.5, col, 4.0)
	elif key.begins_with("dev:"):
		var dev := g.device_at(p)
		for cell in dev.cells():
			draw_rect(_rect(cell, 0.04), col, false, 3.0)
	else:
		# Boden/Wand: gestrichelter Rahmen am Feldrand
		var r := _rect(p)
		for k in 4:
			var a := r.position + Vector2(r.size.x * k / 4.0, 0)
			draw_line(a, a + Vector2(r.size.x / 8.0, 0), col, 3.0)
			draw_line(a + Vector2(0, r.size.y), a + Vector2(r.size.x / 8.0, r.size.y), col, 3.0)
			var b := r.position + Vector2(0, r.size.y * k / 4.0)
			draw_line(b, b + Vector2(0, r.size.y / 8.0), col, 3.0)
			draw_line(b + Vector2(r.size.x, 0), b + Vector2(r.size.x, r.size.y / 8.0), col, 3.0)
	draw_string(ThemeDB.fallback_font, Vector2(p) * S + Vector2(0, -4), RemovalSystem.name_of(key), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

func _draw_preview(g: ShipGrid) -> void:
	if not g.in_bounds(hover):
		return
	if GameState.tool == "select":
		draw_rect(_rect(hover), Color(1, 1, 1, 0.15))
		return
	var tiles: Array[Vector2i] = []
	# Mehrfeld-Gerät (Triebwerk 1×3): alle Felder zeigen, grün nur wenn alles passt
	var long_type := ""
	if GameState.tool.begins_with("dev:") and ItemSystem.device(GameState.tool.substr(4)).length > 1:
		long_type = GameState.tool.substr(4)
	elif GameState.tool.begins_with("install:"):
		var key := RemovalSystem.key_of_packed(GameState.tool.substr(8))
		if key.begins_with("dev:") and ItemSystem.device(key.substr(4)).length > 1:
			long_type = key.substr(4)
	if long_type != "":
		var ok_all := ShipConstructionSystem.can_place(GameState.tool, hover)
		for c in ShipConstructionSystem.cells_of(long_type, hover, ShipConstructionSystem.build_rot):
			if g.in_bounds(c):
				draw_rect(_rect(c), Color(0.35, 0.78, 0.9, 0.35) if ok_all else Color(0.9, 0.33, 0.29, 0.3))
		var gh := Device.new(long_type, hover)
		gh.rot = ShipConstructionSystem.build_rot
		if long_type == "dockport":
			# Andockschleuse richtet sich selbst an der Wand aus
			var dd: Vector2i = g.dock_check(hover).dir
			if dd == Vector2i.ZERO:
				return
			gh.rot = Device.PUSH_DIRS.find(-dd)
		_draw_device(gh, true)
		return
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
		# Drehbares Gerät: Vorschau mit der gewählten Richtung (Taste G)
		if GameState.tool.begins_with("dev:") and ItemSystem.device(GameState.tool.substr(4)).rotatable:
			var ghost := Device.new(GameState.tool.substr(4), p)
			ghost.rot = ShipConstructionSystem.build_rot
			_draw_device(ghost, true)

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
		"chair":
			draw_rect(Rect2(c - Vector2(u * 0.22, u * 0.22), Vector2(u * 0.44, u * 0.44)), Color(0.42, 0.36, 0.3, a))
			draw_rect(Rect2(c - Vector2(u * 0.22, u * 0.3), Vector2(u * 0.44, u * 0.1)), Color(0.3, 0.25, 0.2, a))
		"table":
			draw_rect(Rect2(c - Vector2(u * 0.38, u * 0.3), Vector2(u * 0.76, u * 0.6)), Color(0.48, 0.4, 0.3, a))
		"toilet":
			draw_circle(c + Vector2(0, u * 0.06), u * 0.24, Color(0.85, 0.87, 0.9, a))
			draw_rect(Rect2(c - Vector2(u * 0.22, u * 0.36), Vector2(u * 0.44, u * 0.16)), Color(0.75, 0.77, 0.8, a))
		"light":
			draw_circle(c, u * 0.18, Color(1, 0.93, 0.6, a) if dev.powered else Color(0.4, 0.38, 0.3, a))
		"power_switch":
			var col := Color(0.44, 0.81, 0.56, a) if dev.switch_on else Color(0.9, 0.33, 0.29, a)
			draw_rect(Rect2(c - Vector2(u * 0.25, u * 0.25), Vector2(u * 0.5, u * 0.5)), Color(0.1, 0.13, 0.12, a))
			var tip := c + (Vector2(0, -u * 0.2) if dev.switch_on else Vector2(u * 0.18, -u * 0.1))
			draw_line(c + Vector2(0, u * 0.15), tip, col, 3.0)
		"battery", "battery_mini", "battery_compact", "charger":
			var cap := ShipPowerSystem.capacity_of(dev)
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
			# Düse zeigt zum Abgas (entgegen der Schubrichtung), Pfeil zeigt die Schubrichtung
			var push := Vector2(dev.push_dir())
			var ex := -push
			var side := ex.orthogonal()
			draw_colored_polygon(PackedVector2Array([c - ex * u * 0.3 + side * u * 0.22, c - ex * u * 0.3 - side * u * 0.22,
				c + ex * u * 0.3 - side * u * 0.35, c + ex * u * 0.3 + side * u * 0.35]), Color(0.45, 0.48, 0.52, a))
			draw_colored_polygon(PackedVector2Array([c - ex * u * 0.42, c - ex * u * 0.22 + side * u * 0.12, c - ex * u * 0.22 - side * u * 0.12]), Color(0.95, 0.76, 0.31, a))
			if dev.powered and not dev.broken and PhysicsSystem.firing(dev.push_dir()):
				draw_circle(c + ex * u * 0.48, u * (0.15 + randf() * 0.08), Color(1, 0.75, 0.3, a))
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
		"dockport":
			# Andockschleuse: Rahmen mit Warnstreifen, Licht grün = angedockt
			var linked := ShipSystem.grid.linked.has(ShipSystem.grid.idx(dev.pos))
			draw_rect(Rect2(c - Vector2(u * 0.42, u * 0.42), Vector2(u * 0.84, u * 0.84)), Color(0.95, 0.76, 0.31, a), false, 2.0)
			for k in 3:
				var o := c + Vector2(-u * 0.3 + k * u * 0.25, u * 0.3)
				draw_line(o, o + Vector2(u * 0.15, -u * 0.15), Color(0.1, 0.1, 0.1, a), 2.0)
			draw_circle(c - Vector2(0, u * 0.08), u * 0.17, Color(0.44, 0.81, 0.56, a) if linked else Color(0.9, 0.33, 0.29, a))
		"st_market", "st_bar", "st_board", "st_hiring", "st_claims", "st_bank", "st_shipyard":
			# Tresen mit Zeichen
			draw_rect(Rect2(c - Vector2(u * 0.42, u * 0.12), Vector2(u * 0.84, u * 0.24)), Color(0.75, 0.62, 0.4, a))
			var glyph: String = {"st_market": "$", "st_bar": "♪", "st_board": "!", "st_hiring": "+", "st_claims": "§", "st_bank": "¢", "st_shipyard": "⚓"}[dev.type]
			draw_string(ThemeDB.fallback_font, c + Vector2(-u * 0.18, -u * 0.18), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.9, 0.6, a))
		_:
			draw_string(ThemeDB.fallback_font, r.position + Vector2(3, S * 0.5), dev.data().display_name.substr(0, 2), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85 * a))

# ---------------- Station: Raumnamen, Figuren, Sprechblasen ----------------

func _draw_station() -> void:
	if not StationSystem.active():
		return
	var font := ThemeDB.fallback_font
	var a := StationSystem.area
	var st := PhysicsSystem.loc(StationSystem.station_id)
	draw_string(font, Vector2(a.position.x + 2, a.position.y) * S + Vector2(0, -4), String(st.get("name", "Station")).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.76, 0.31, 0.9))
	for r in StationSystem.rooms:
		var inner: Rect2i = r.inner
		draw_string(font, Vector2(inner.position) * S + Vector2(3, 11), StationSystem.ROOMS[r.kind].name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.8, 0.86, 0.75))
	for n in StationSystem.npcs:
		var center: Vector2 = n.pos * S
		draw_circle(center + Vector2(1, 2), CS * 0.28, Color(0, 0, 0, 0.35))
		draw_circle(center, CS * 0.26, n.color)
		match n.kind:
			"staff":
				draw_arc(center, CS * 0.26, 0, TAU, 20, Color(0.95, 0.76, 0.31), 2.0)
			"contact":
				draw_arc(center, CS * 0.26, 0, TAU, 20, Color(0.62, 0.85, 1.0), 2.0)
			"candidate":
				draw_string(font, center + Vector2(-3, -CS * 0.32), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.9, 0.6))
		var near: bool = hover.distance_to(Vector2i(n.pos)) <= 1.0 * Config.GRID_SCALE
		if near or n.kind != "visitor":
			draw_string(font, center + Vector2(-CS * 3, CS * 0.75), String(n.name).split(" (")[0].split(",")[0], HORIZONTAL_ALIGNMENT_CENTER, CS * 6, 10,
				Color(0.91, 0.93, 0.96, 0.95 if near else 0.6))

func _draw_bubbles() -> void:
	if not StationSystem.active():
		return
	var font := ThemeDB.fallback_font
	for n in StationSystem.npcs:
		if String(n.line) == "" or GameState.time > float(n.line_until):
			continue
		var text := String(n.line)
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		var center: Vector2 = n.pos * S
		var box := Rect2(center + Vector2(-size.x / 2.0 - 5, -CS * 0.55 - size.y - 6), size + Vector2(10, 6))
		draw_rect(box, Color(0.08, 0.1, 0.13, 0.92))
		draw_rect(box, Color(0.95, 0.76, 0.31, 0.8), false, 1.0)
		draw_string(font, box.position + Vector2(5, size.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.93, 0.88))
