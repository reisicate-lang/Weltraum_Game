## Hauptszene: Kamera, Maus und Tastatur.
## Linke Maustaste: Werkzeug benutzen (ziehen = Fläche).
## Rechte Maustaste: Bauplan oder Aufgabe abbrechen, sonst zurück zur Auswahl.
## Mittlere Maustaste oder Ziehen mit "Auswahl": Ansicht verschieben.
extends Node2D

@onready var view = $ShipView  # ship_view.gd
@onready var cam: Camera2D = $Camera2D

var _drag_start := Vector2i(-1, -1)
var _panning := false
var _pan_moved := false
var _pan_origin := Vector2.ZERO

func _ready() -> void:
	cam.position = Vector2(Config.WORLD_W, Config.WORLD_H) * Config.TILE_SIZE * 0.5
	cam.zoom = Vector2(1.4, 1.4)
	EventBus.game_loaded.connect(func(): _drag_start = Vector2i(-1, -1))

func _tile_at_mouse() -> Vector2i:
	var p := get_global_mouse_position() / Config.TILE_SIZE
	return Vector2i(floori(p.x), floori(p.y))

func _process(delta: float) -> void:
	view.hover = _tile_at_mouse()
	var empty: Array[Vector2i] = []
	view.preview = _drag_tiles() if _drag_start.x >= 0 else empty
	# Ansicht mit Pfeiltasten
	var pan := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT): pan.x -= 1
	if Input.is_physical_key_pressed(KEY_RIGHT): pan.x += 1
	if Input.is_physical_key_pressed(KEY_UP): pan.y -= 1
	if Input.is_physical_key_pressed(KEY_DOWN): pan.y += 1
	cam.position += pan * 600.0 * delta / cam.zoom.x
	# Deine Figur mit WASD (echte Geschwindigkeit, nicht in der Pause)
	var p := CrewSystem.player()
	if p != null and TimeSystem.speed_index > 0:
		var dir := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_A): dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D): dir.x += 1
		if Input.is_physical_key_pressed(KEY_W): dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S): dir.y += 1
		if dir != Vector2.ZERO and not Input.is_key_pressed(KEY_CTRL):
			var sprint := Config.SPRINT if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
			p.manual_move(dir, Config.WALK_SPEED / 60.0 * delta * sprint)
			cam.position = cam.position.lerp(p.pos * Config.TILE_SIZE, minf(1.0, delta * 4.0))

func _drag_tiles() -> Array[Vector2i]:
	var a := _drag_start
	var b := _tile_at_mouse()
	var out: Array[Vector2i] = []
	if GameState.tool in ["door", "repair", "move"]:
		out.append(b)
		return out
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			# Wand: nur der Rand des Rechtecks
			if GameState.tool == "wall" and x != mini(a.x, b.x) and x != maxi(a.x, b.x) and y != mini(a.y, b.y) and y != maxi(a.y, b.y):
				continue
			out.append(Vector2i(x, y))
	return out

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(1.12)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.0 / 1.12)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and GameState.tool == "select"):
			if mb.pressed:
				_panning = true
				_pan_moved = false
				_pan_origin = mb.position
			else:
				_panning = false
				if not _pan_moved and mb.button_index == MOUSE_BUTTON_LEFT:
					_click(_tile_at_mouse())
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_start = _tile_at_mouse()
			elif _drag_start.x >= 0 and GameState.tool == "move":
				var dst := _tile_at_mouse()
				if dst != _drag_start:
					ShipConstructionSystem.place_move(_drag_start, dst)
				else:
					GameState.toast("Halte die Maustaste gedrückt und ziehe vom Gerät zum Zielfeld.")
				_drag_start = Vector2i(-1, -1)
			elif _drag_start.x >= 0:
				var count := 0
				var tiles := _drag_tiles()
				for t in tiles:
					if ShipConstructionSystem.place(GameState.tool, t):
						count += 1
				if count == 0 and tiles.size() == 1:
					GameState.toast("Das geht hier nicht.")
				_drag_start = Vector2i(-1, -1)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_right_click(_tile_at_mouse())
	elif event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_pan_origin) > 6.0:
			_pan_moved = true
		if _pan_moved:
			cam.position -= mm.relative / cam.zoom.x
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		_key(event as InputEventKey)

func _zoom(f: float) -> void:
	var z := clampf(cam.zoom.x * f, 0.35, 3.0)
	cam.zoom = Vector2(z, z)

func _click(t: Vector2i) -> void:
	var world_pos := get_global_mouse_position() / Config.TILE_SIZE
	var c := CrewSystem.at(world_pos)
	if c != null:
		GameState.selected = c
		EventBus.character_selected.emit(c)
		return
	var g := ShipSystem.grid
	if g.in_bounds(t):
		var dev := g.device_at(t)
		if (dev != null and dev.inv != null) or g.piles.has(g.idx(t)):
			UIManager.open_container(t)
			return
	var sel: CrewMember = GameState.selected if GameState.selected != null else CrewSystem.player()
	if sel == null:
		return
	if not g.walkable(t):
		GameState.toast("Dorthin kann niemand laufen.")
	elif not sel.order_move(t):
		GameState.toast(sel.display_name + " findet keinen Weg dorthin.")

func _right_click(t: Vector2i) -> void:
	var g := ShipSystem.grid
	var c := CrewSystem.at(get_global_mouse_position() / Config.TILE_SIZE)
	if c != null:
		c.cancel_all()
		GameState.toast(c.display_name + ": Aufgabe abgebrochen.")
		return
	if g.in_bounds(t) and ShipConstructionSystem.jobs.has(g.idx(t)):
		ShipConstructionSystem.cancel(ShipConstructionSystem.jobs[g.idx(t)])
		GameState.toast("Bauplan abgebrochen.")
		return
	UIManager.set_tool("select")

func _key(k: InputEventKey) -> void:
	if k.ctrl_pressed and k.keycode == KEY_S:
		SaveSystem.save_game()
		return
	match k.keycode:
		KEY_SPACE: TimeSystem.toggle_pause()
		KEY_1: TimeSystem.set_speed(1)
		KEY_2: TimeSystem.set_speed(2)
		KEY_3: TimeSystem.set_speed(3)
		KEY_4: TimeSystem.set_speed(4)
		KEY_ESCAPE: UIManager.set_tool("select"); UIManager.close_container()
		KEY_B: UIManager.set_tool("floor")
		KEY_M: UIManager.set_tool("wall")
		KEY_T: UIManager.set_tool("door")
		KEY_K: UIManager.set_tool("cable")
		KEY_X: UIManager.set_tool("remove")
		KEY_V: UIManager.set_tool("move")
		KEY_R: UIManager.set_tool("repair")
		KEY_C: UIManager.set_tool("cancel")
		KEY_L: GameState.view = "normal" if GameState.view == "air" else "air"
		KEY_P: GameState.view = "normal" if GameState.view == "power" else "power"
		KEY_E: UIManager.interact()
		KEY_H: UIManager.toggle_help()
