## Baut die Benutzeroberfläche auf und hält sie aktuell.
## Die Anzeigen werden 5-mal pro Sekunde aufgefrischt (nicht jedes Bild).
extends Node

const TOOLS := [
	["select", "Select", "Esc", "Click the floor: the character walks there. Drag: pan the view. WASD: steer your character."],
	["floor", "Floor", "B", "Click or drag an area. Floors can only be placed in empty space."],
	["wall", "Wall", "M", "Dragging draws a line or the outline of a rectangle."],
	["door", "Door", "T", "Click a wall or a floor."],
	["window", "Window", "Z", "Like a wall, but made of armored glass. The view lowers stress but costs heat."],
	["cable", "Cable", "K", "Cables connect devices to power."],
	["move", "Move", "V", "Drag from the device to the target tile. A character carries it there."],
	["haul", "Haul", "Q", "Mark piles. The crew takes everything to the nearest cargo crate on the ship."],
	["repair", "Repair", "R", "Click something damaged. Badly damaged things are repaired automatically."],
	["remove", "Demolish", "U", "Layer by layer: device, cable, wall/door, floor. Returns parts."],
	["cancel", "Cancel plan", "C", "Removes build plans. Right-click works too."],
	["orders", "Orders", "Y", "Pick an action and filters below, then click a tile or drag over an area. Only objects matching an active filter get the order."],
]
const COL_PANEL := Color(0.05, 0.07, 0.106, 0.92)
const COL_AMBER := Color(0.95, 0.64, 0.23)
const COL_MUTED := Color(0.51, 0.57, 0.65)

var layer: CanvasLayer
var auto_button: Button
## Cockpit: Flugmodus am Steuerpult
var flight_hud: Control
var pilot: CrewMember = null
var _helm_walk := false
var _walk_helm := Vector2i(-1, -1)   ## Pult, zu dem die Spielfigur gerade läuft
## Tatsächliche Tastenbelegung im Flugmodus (wird im Cockpit angezeigt)
const FLIGHT_KEYS := [["W / S", "Thrust forward / back (thrusters in that direction + RCS)"], ["A / D", "Thrust left / right (thrusters in that direction + RCS)"],
	["Q / E", "rotate counter-clockwise / clockwise"], ["R", "stop rotation"], ["X", "match velocity with the target"],
	["T", "next target (or click “Target” in the list)"], ["F", "dock"], ["U", "undock"], ["Tab", "open / close inventory"],
	["Mouse wheel", "zoom the map"], ["Esc / N", "leave the cockpit"]]
## Persönliches Inventar offen (Tab)
var inv_open := false
## Rechtsklick-Auswahl: Kachel und Ebene ("cable", "dev:…", "tile:…"), siehe RemovalSystem.next_layer
var sel_tile := Vector2i(-1, -1)
## Hauptszene (meldet sich in ihrem _ready an), bekommt weitergereichte Rechtsklicks
var world_view: Node = null
var sel_key := ""
## Rechtsklick-Menü für Objekte (Abbauen, Zerlegen, Zerstören, Einbauen)
var object_menu: PopupMenu
var menu_pos := Vector2i(-1, -1)
var menu_actions: Array = []
var clock_label: Label
var money_label: Label
var speed_buttons: Array[Button] = []
var tool_buttons := {}
var device_menu: MenuButton
var device_ids: Array[String] = []
var hint_label: Label
var hover_label: Label
var power_label: Label
var name_label: Label
var task_label: Label
var need_bars := {}
var inv_label: Label
var toast_box: VBoxContainer
var container_panel: PanelContainer
var container_box: VBoxContainer
var help_panel: PanelContainer
var help_scroll: ScrollContainer
var open_pos := Vector2i(-1, -1)
var _last_container := ""
var window_panel: PanelContainer
var window_box: VBoxContainer
var window_kind := ""
var trade_tab := "sell"
## Gespräch an einem Stationstresen: wer redet und an welchem Tresen
var talk_line := ""
var talk_role := ""
var _last_window := ""
var nav_root: HBoxContainer
var nav_map: Control
var nav_side: VBoxContainer
var nav_open := false
var _last_nav := ""
var char_ui
var gameover_panel: PanelContainer
var gameover_label: Label
var station_reply := ""
var goal_label: Label

func _ready() -> void:
	layer = CanvasLayer.new()
	add_child(layer)
	_build_top()
	_build_left()
	_build_bottom()
	_build_toasts()
	_build_container()
	_build_help()
	_build_window()
	_build_nav()
	_build_gameover()
	object_menu = PopupMenu.new()
	object_menu.id_pressed.connect(_on_object_menu)
	object_menu.window_input.connect(_on_object_menu_input)
	add_child(object_menu)
	char_ui = load("res://scripts/ui/character_ui.gd").new()
	add_child(char_ui)
	char_ui.setup(self)
	EventBus.toast.connect(_on_toast)
	EconomySystem.game_over.connect(show_game_over)
	EventBus.speed_changed.connect(func(_i): _refresh_speed())
	EventBus.game_loaded.connect(func(): close_container())
	var timer := Timer.new()
	timer.wait_time = 0.2
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(_refresh)
	set_tool.call_deferred("select")
	_refresh_speed.call_deferred()

# ---------------- Aufbau ----------------

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = Color(0.15, 0.2, 0.27)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _label(text: String = "", color: Color = Color(0.87, 0.9, 0.94), size: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

func _build_top() -> void:
	var p := _panel()
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	layer.add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	p.add_child(row)
	row.add_child(_label("WELTRAUM_GAME", COL_AMBER, 16))
	clock_label = _label("Day 1  08:00:00")
	row.add_child(clock_label)
	var names := ["❚❚", "×1", "×2", "×4", "×8", "×16"]
	for i in names.size():
		var b := _button(names[i], TimeSystem.set_speed.bind(i))
		b.toggle_mode = true
		speed_buttons.append(b)
		row.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	money_label = _label("", COL_MUTED, 12)
	row.add_child(money_label)
	row.add_child(_button("Character [I]", func(): char_ui.toggle()))
	row.add_child(_button("Save", func(): open_slots(true)))
	row.add_child(_button("Load", func(): open_slots(false)))
	row.add_child(_button("⚙", open_settings))
	row.add_child(_button("New game", func():
		GameState.new_game()
		char_ui.open_creation()))
	row.add_child(_button("?", toggle_help))
	for ch in row.get_children():
		if ch is Button:
			ch.add_theme_font_size_override("font_size", 13)

func _build_left() -> void:
	var p := _panel()
	p.position = Vector2(12, 56)
	p.custom_minimum_size = Vector2(270, 0)
	layer.add_child(p)
	var box := VBoxContainer.new()
	p.add_child(box)
	box.add_child(_label("CREW", COL_MUTED, 11))
	name_label = _label("", COL_AMBER, 15)
	box.add_child(name_label)
	task_label = _label("", COL_MUTED, 12)
	box.add_child(task_label)
	# Auto-Modus der ausgewählten Figur (Taste J)
	auto_button = _button("Auto: ON", toggle_auto)
	auto_button.tooltip_text = "ON: the character picks jobs, eats, sleeps and has free time on their own.\nOFF: they stop at once and only do what you order (click, WASD). Key J."
	box.add_child(auto_button)
	for key in [["health", "Health"], ["warmth", "Body heat"], ["stress", "Calm"], ["air", "Breathing"], ["food", "Hunger"], ["water", "Thirst"], ["sleep", "Energy"], ["hygiene", "Hygiene"], ["suit_o2", "Suit O₂"], ["suit_bat", "Suit battery"]]:
		var row := HBoxContainer.new()
		var l := _label(key[1], COL_MUTED, 12)
		l.custom_minimum_size = Vector2(80, 0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(150, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.44, 0.81, 0.56)
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.1, 0.13, 0.19)
		bg.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", bg)
		row.add_child(bar)
		box.add_child(row)
		need_bars[key[0]] = bar
	box.add_child(_label("GOAL", COL_MUTED, 11))
	goal_label = _label("", COL_AMBER, 12)
	goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal_label.custom_minimum_size = Vector2(250, 0)
	box.add_child(goal_label)
	box.add_child(_label("PACK", COL_MUTED, 11))
	inv_label = _label("", Color(0.87, 0.9, 0.94), 12)
	inv_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inv_label.custom_minimum_size = Vector2(250, 0)
	box.add_child(inv_label)

func _build_bottom() -> void:
	var p := _panel()
	p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(p)
	var box := VBoxContainer.new()
	p.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	for t in TOOLS:
		var b := _button(t[1], set_tool.bind(t[0]))
		b.tooltip_text = "%s (key %s)" % [t[1], t[2]]
		b.add_theme_font_size_override("font_size", 13)
		b.toggle_mode = true
		tool_buttons[t[0]] = b
		row.add_child(b)
	device_menu = MenuButton.new()
	device_menu.text = "Devices ▾"
	device_menu.flat = false
	var keys := ItemSystem.devices.keys()
	keys.sort()
	for k in keys:
		# Stationstresen und frühere Geräte (z. B. eigenständiges Auto-Dock) kann man nicht bauen
		if ItemSystem.device(k).tech == "station" or not ItemSystem.device(k).buildable:
			continue
		device_ids.append(k)
		device_menu.get_popup().add_item(ItemSystem.device(k).display_name)
	device_menu.get_popup().index_pressed.connect(func(i): set_tool("dev:" + device_ids[i]))
	row.add_child(device_menu)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_button("Air [L]", func(): GameState.view = "normal" if GameState.view == "air" else "air"))
	row.add_child(_button("Power [P]", func(): GameState.view = "normal" if GameState.view == "power" else "power"))
	row.add_child(_button("Heat [O]", func(): GameState.view = "normal" if GameState.view == "heat" else "heat"))
	row.add_child(_button("Damage [X]", func(): GameState.view = "normal" if GameState.view == "damage" else "damage"))
	_build_orders_bar(box)
	power_label = _label("", COL_MUTED, 12)
	box.add_child(power_label)
	var info := HBoxContainer.new()
	box.add_child(info)
	hint_label = _label("", COL_MUTED, 12)
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(hint_label)
	hover_label = _label("", Color(0.35, 0.78, 0.9), 12)
	info.add_child(hover_label)

func _build_toasts() -> void:
	toast_box = VBoxContainer.new()
	toast_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	toast_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	toast_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toast_box.position.y -= 110
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(toast_box)

func _build_container() -> void:
	container_panel = _panel()
	container_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	container_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	container_panel.position.y = 56
	container_panel.custom_minimum_size = Vector2(320, 0)
	container_panel.visible = false
	layer.add_child(container_panel)
	container_box = VBoxContainer.new()
	container_panel.add_child(container_box)

func _build_help() -> void:
	help_panel = _panel()
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	layer.add_child(help_panel)
	var outer := VBoxContainer.new()
	help_panel.add_child(outer)
	# Kopfzeile mit Schließen-Knopf
	var head := HBoxContainer.new()
	var title := _label("CONTROLS", COL_AMBER, 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("✕", close_help))
	outer.add_child(head)
	# Auf kleinen Bildschirmen scrollbar
	help_scroll = ScrollContainer.new()
	help_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(help_scroll)
	var box := VBoxContainer.new()
	help_scroll.add_child(box)
	var text := _label("""Your small ship drifts in space. Mira lives aboard and builds whatever you plan.
Keep her alive: air, food, water, sleep.

WASD: steer your character (Shift: run)
Select + click the floor: walk there · click a crate: contents
Tools below: Floor B, Wall M, Door T, Cable K, Demolish U, Cancel plan C, Orders Y, damage view X
Device menu: generator, oxygen, beds, crates ...
Right-click an object: menu (Uninstall, Dismantle, Destroy, Install) · on a character: cancel task
For work in vacuum Mira fetches a space suit herself. The airlock on the left
pumps out the air before the outer door opens. Ships dock at the airlock's outer door.
E: search a crate or pile next to you · Tab: own inventory · J: auto mode on/off
Uninstalled devices lie on the floor; a character carries one of them in their hands (E → Take).
L / P / O: air, power and heat view · mouse wheel: zoom · arrow keys: pan
Space: pause · 1–5: time ×1, ×2, ×4, ×8, ×16 · Ctrl+S: save

You owe the bank 24 000 Cr; an instalment is due every 7 days.
Selling and buying: click the trade terminal in the cockpit (only while docked).
N: go to the navigation console (cockpit) · flying: W/S forward/back, A/D sideways, Q/E rotate · fast travel
to the Kármán Ring and the debris field. Careful: Earth pulls you in.""", Color(0.87, 0.9, 0.94), 14)
	text.custom_minimum_size = Vector2(560, 0)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	outer.add_child(_button("Let's go", close_help))
	_fit_help.call_deferred()

func _build_window() -> void:
	window_panel = _panel()
	window_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	window_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	window_panel.position.y = 56
	window_panel.custom_minimum_size = Vector2(400, 0)
	window_panel.visible = false
	layer.add_child(window_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	window_panel.add_child(scroll)
	window_box = VBoxContainer.new()
	window_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(window_box)

func _build_nav() -> void:
	nav_root = HBoxContainer.new()
	nav_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	nav_root.offset_top = 48
	nav_root.visible = false
	layer.add_child(nav_root)
	nav_map = Control.new()
	nav_map.set_script(load("res://scripts/ui/nav_map.gd"))
	nav_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_map.clip_contents = true
	nav_root.add_child(nav_map)
	var side := _panel()
	(side.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color(0.05, 0.07, 0.106, 1.0)
	side.custom_minimum_size = Vector2(380, 0)
	nav_root.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(outer)
	# Fluglage-Instrument (fest, wird nicht bei jeder Aktualisierung neu gebaut)
	flight_hud = Control.new()
	flight_hud.set_script(load("res://scripts/ui/flight_hud.gd"))
	flight_hud.custom_minimum_size = Vector2(360, 230)
	outer.add_child(flight_hud)
	nav_side = VBoxContainer.new()
	nav_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(nav_side)

## N / Klick aufs Steuerpult: ins Cockpit (Figur geht hin) oder es verlassen
func toggle_nav(show = null) -> void:
	var want: bool = (not nav_open) if show == null else bool(show)
	if want:
		request_flight()
	else:
		leave_flight()

## Das Steuerpult, an dem geflogen wird: im Cockpit das bediente Pult,
## sonst das nächste zur Spielfigur (Ziel für N)
func helm_device() -> Device:
	if nav_open:
		return PhysicsSystem.operated_helm()
	var p := CrewSystem.player()
	var best: Device = null
	for h in PhysicsSystem.ship_devices("helm"):
		if best == null or (p != null and p.pos.distance_to(Vector2(h.pos)) < p.pos.distance_to(Vector2(best.pos))):
			best = h
	return best

## Ins Cockpit an diesem Pult (Klick) oder am nächsten (N): steht die Spielfigur
## dort, sofort; sonst läuft sie hin. Kaputte oder stromlose Pulte weisen ab.
func request_flight(helm: Device = null) -> void:
	if helm == null:
		helm = helm_device()
	var p := CrewSystem.player()
	if helm == null:
		GameState.toast("Your ship has no navigation console.")
		return
	if p == null or p.unconscious:
		GameState.toast("Nobody can operate the navigation console.")
		return
	var why := PhysicsSystem.helm_block_reason(helm)
	if why != "":
		GameState.toast(why + " Flying is not possible here.", "bad")
		return
	if p.can_reach(helm.pos):
		enter_flight(helm)
		return
	var res := ShipSystem.nearest_adjacent(p.tile(), [helm.pos], 1)
	if not res.ok or not p.order_move(res.path[-1] if not res.path.is_empty() else p.tile()):
		GameState.toast(p.display_name + " cannot get to the navigation console.")
		return
	_helm_walk = true
	_walk_helm = helm.pos
	GameState.toast(p.display_name + " walks to the navigation console.")

## Flugmodus an diesem Pult: Flugeingaben steuern das Schiff, die Figur bleibt am Pult
func enter_flight(helm: Device = null) -> void:
	_helm_walk = false
	if helm == null:
		helm = helm_device()
	var why := PhysicsSystem.helm_block_reason(helm)
	if why != "":
		GameState.toast(why + " Flying is not possible here.", "bad")
		return
	pilot = CrewSystem.player()
	PhysicsSystem.helm_at = helm.pos
	nav_open = true
	nav_root.visible = true
	close_container()
	close_window()
	var P := PhysicsSystem
	P.stop_inputs()
	if P.target == "" or P.loc(P.target).is_empty():
		P.target = P.docked if P.docked != "" else String(P.nearest().id)
	nav_map.follow = true
	nav_map.auto_zoom = true
	_last_nav = ""
	_refresh_nav()
	GameState.toast("%s takes the helm. Esc or N: leave the cockpit." % pilot.display_name)

## Flugmodus aus: Schub endet, die Figur wird wieder normal gesteuert
func leave_flight() -> void:
	_helm_walk = false
	var was := nav_open
	nav_open = false
	if nav_root != null:
		nav_root.visible = false
	PhysicsSystem.stop_inputs()
	PhysicsSystem.match_target = ""
	PhysicsSystem.helm_at = PhysicsSystem.NO_HELM
	if pilot != null:
		pilot.manual_until = 0.0
	pilot = null
	if was:
		GameState.toast("Left the cockpit – character control.")

## Läuft die Figur zum Pult? Angekommen: Flugmodus. Unterbrochen: abbrechen.
func _check_helm_walk() -> void:
	if not _helm_walk:
		return
	var p := CrewSystem.player()
	var helm: Device = ShipSystem.grid.device_at(_walk_helm)
	if p == null or helm == null or helm.type != "helm":
		_helm_walk = false
	elif p.can_reach(helm.pos):
		enter_flight(helm)
	elif p.order == null and p.path.is_empty():
		_helm_walk = false

## Jeden Frame im Flugmodus: Pilot bleibt am bedienten Pult. Fällt er aus, geht weg
## oder ist das Pult weg, endet der Flugmodus. Hat das Pult keinen Strom oder ist kaputt,
## bleibt das Cockpit offen, aber die Physik gibt keinen Schub (siehe PhysicsSystem.manual_ok).
func keep_pilot() -> bool:
	var helm := PhysicsSystem.operated_helm()
	if pilot == null or pilot.unconscious or not pilot in CrewSystem.crew or helm == null or not pilot.can_reach(helm.pos):
		leave_flight()
		return false
	pilot.manual_until = Time.get_ticks_msec() + 500.0
	pilot.task = "Flying the ship"
	return true

func _course(v: Vector2) -> String:
	return "%03d°" % int(fposmod(rad_to_deg(v.angle()) + 90.0, 360.0))

## Zahlen für die Fluganzeige (auch zum Erkennen, ob neu gezeichnet werden muss)
func _flight_rows() -> Array:
	var P := PhysicsSystem
	var out: Array = [_course(Vector2.from_angle(P.angle)), int(rad_to_deg(P.ang_vel)), P.thrust, P.strafe, P.rot_input, P.aligning, P.match_target, P.match_input != Vector2.ZERO,
		snappedf(P.mass(), 0.1), P.thrust_dir(Vector2i(1, 0)), P.thrust_dir(Vector2i(-1, 0)), P.thrust_dir(Vector2i(0, 1)), P.thrust_dir(Vector2i(0, -1))]
	if P.target != "" and P.docked == "":
		var ap: Dictionary = P.approach(P.target)
		out.append_array([_fmt_dist(ap.dist), snappedf(ap.speed * 1000.0, 0.1), snappedf(ap.closing * 1000.0, 0.1), int(P.dock_alignment(P.target).deg)])
	return out

## Cockpit-Anzeige: Fluglage, Ziel, Annäherung, Andock-Ampel, Tasten
func _build_flight_info() -> void:
	var P := PhysicsSystem
	var bad := Color(0.9, 0.33, 0.29)
	var good := Color(0.44, 0.81, 0.56)
	nav_side.add_child(_label("ATTITUDE", COL_MUTED, 11))
	nav_side.add_child(_row("Heading (nose)", [_label(_course(Vector2.from_angle(P.angle)), COL_AMBER, 12)]))
	nav_side.add_child(_row("Turn rate", [_label("%+d °/s" % int(rad_to_deg(P.ang_vel)), COL_AMBER if absf(P.ang_vel) < 0.01 else bad, 12)]))
	var thr: PackedStringArray = []
	if P.thrust > 0.0: thr.append("forward")
	if P.thrust < 0.0: thr.append("back")
	if P.strafe < 0.0: thr.append("left")
	if P.strafe > 0.0: thr.append("right")
	if P.rot_input != 0.0: thr.append("turning")
	if P.rot_stop: thr.append("stop rotation")
	if P.aligning: thr.append("aligning")
	if P.match_target != "":
		thr.append("matching" + (" (firing)" if P.match_input != Vector2.ZERO else " (target reached)"))
	nav_side.add_child(_row("Active thrust", [_label(", ".join(thr) if not thr.is_empty() else "none – ship drifting", COL_AMBER, 12)]))
	var fl: Vector2 = P.thrust_vector_local()
	var mass_t: float = P.mass()
	nav_side.add_child(_row("Total mass", [_label("%.1f t" % mass_t, COL_AMBER, 12)]))
	nav_side.add_child(_row("Effective thrust now", [_label("%d kN → %.2f m/s²" % [int(fl.length()), fl.length() / maxf(1.0, mass_t)], COL_AMBER if fl.length() > 0.0 else COL_MUTED, 12)]))
	nav_side.add_child(_row("Thrusters (kN)", [_label("forward %d · back %d · left %d · right %d · RCS each %d" % [
		int(P.thrust_dir(Vector2i(1, 0))), int(P.thrust_dir(Vector2i(-1, 0))), int(P.thrust_dir(Vector2i(0, -1))), int(P.thrust_dir(Vector2i(0, 1))), int(P.rcs_thrust())], COL_MUTED, 12)]))
	var tl := P.loc(P.target)
	var tr := HBoxContainer.new()
	tr.add_child(_label("TARGET: " + (String(tl.name) if not tl.is_empty() else "none"), COL_MUTED, 11))
	var nb := _button("next [T]", cycle_target)
	nb.add_theme_font_size_override("font_size", 11)
	tr.add_child(nb)
	nav_side.add_child(tr)
	if P.docked != "" or tl.is_empty():
		pass
	else:
		var ap: Dictionary = P.approach(P.target)
		var vrel: Vector2 = ap.vrel
		nav_side.add_child(_row("Distance", [_label(_fmt_dist(ap.dist), COL_AMBER, 12)]))
		nav_side.add_child(_row("Relative velocity", [_label("%s · heading %s" % [_fmt_speed(ap.speed), _course(vrel) if vrel.length() > 0.0000005 else "–"], COL_AMBER, 12)]))
		var closing: float = ap.closing
		var ctext := ("closing at %s" % _fmt_speed(closing)) if closing > 0.0000005 else (("receding at %s" % _fmt_speed(-closing)) if closing < -0.0000005 else "distance unchanged")
		nav_side.add_child(_row("Approach", [_label(ctext, good if closing > 0.0 else COL_MUTED, 12)]))
		if ap.eta > 0.0:
			nav_side.add_child(_row("Arrival at this speed", [_label("%d s" % int(ap.eta) if ap.eta < 3600.0 else "%.1f h" % (ap.eta / 3600.0), COL_MUTED, 12)]))
		if closing > 0.0:
			nav_side.add_child(_row("Stopping distance", [_label("S (RCS): %s · turned around with W: %s" % [_fmt_dist(ap.brake_rcs), _fmt_dist(ap.brake_main)], COL_MUTED, 12)]))
			if ap.brake_main >= ap.dist * 0.9:
				nav_side.add_child(_label("TOO FAST – brake now!", bad, 13))
			elif ap.brake_rcs >= ap.dist * 0.9:
				nav_side.add_child(_label("Brake now (turn around and W, or hold S).", COL_AMBER, 13))
		# Andock-Ampel
		var m := P.dock_factor()
		var al: Dictionary = P.dock_alignment(P.target)
		var lights := HBoxContainer.new()
		lights.add_child(_label("DOCKING ", COL_MUTED, 11))
		var ok_dist: bool = ap.dist < float(P.space.dock_dist) * m
		var ok_speed: bool = ap.speed < float(P.space.dock_speed) * m
		lights.add_child(_label("● distance < %d m  " % int(float(P.space.dock_dist) * m * 1000.0), good if ok_dist else bad, 11))
		lights.add_child(_label("● speed < %d m/s  " % int(float(P.space.dock_speed) * m * 1000.0), good if ok_speed else bad, 11))
		lights.add_child(_label("● airlock %d°" % int(al.deg) if al.port else "● no airlock", good if al.ok else bad, 11))
		nav_side.add_child(lights)
		var row := HBoxContainer.new()
		var db := _button("Dock [F]", func(): if not P.dock(P.target): GameState.toast(P.dock_block_reason(P.target)))
		db.disabled = not P.can_dock(P.target)
		row.add_child(db)
		var on: bool = P.match_target == P.target
		var mb := _button("Match [X]: ON" if on else "Match [X]", toggle_match)
		if on:
			mb.add_theme_color_override("font_color", good)
		row.add_child(mb)
		nav_side.add_child(row)
	nav_side.add_child(_label("COCKPIT KEYS", COL_MUTED, 11))
	for k in FLIGHT_KEYS:
		nav_side.add_child(_row(k[1], [_label(k[0], COL_AMBER, 12)], COL_MUTED))

## Nächstes Ziel auswählen
func cycle_target() -> void:
	var P := PhysicsSystem
	var ids: Array = P.locations.map(func(l): return l.id)
	var i := ids.find(P.target)
	P.target = ids[(i + 1) % ids.size()]
	# Läuft das Angleichen, gilt es ab jetzt dem neuen Ziel
	if P.match_target != "":
		P.match_target = P.target
	_last_nav = ""
	_refresh_nav()

## Geschwindigkeit ans Ziel angleichen (ein/aus)
func toggle_match() -> void:
	var P := PhysicsSystem
	if P.docked != "" or P.target == "":
		return
	if P.match_target != P.target and not P.manual_ok():
		GameState.toast("Cannot match: " + P.helm_block_reason(P.operated_helm()), "bad")
		return
	P.match_target = "" if P.match_target == P.target else P.target
	_last_nav = ""

func _fmt_dist(km: float) -> String:
	if km < 1.0:
		return "%d m" % int(km * 1000.0)
	return "%.1f km" % km if km < 100.0 else "%d km" % int(km)

func _fmt_speed(v: float) -> String:
	return "%d m/s" % int(v * 1000.0) if v < 1.0 else "%.2f km/s" % v

func _refresh_nav() -> void:
	if not nav_open:
		return
	var P := PhysicsSystem
	var e: Dictionary = P.space.earth
	var alt := P.pos.distance_to(Vector2(e.x, e.y)) - float(e.r)
	var rows: Array = [P.target, _flight_rows(), P.xpdr_faults(), P.prox_warning(), P.prox_muted, P.ship_log.size(), P.helm_block_reason(P.operated_helm()), P.autodock_block_reason(),
		P.operated_helm().inv.to_data() if P.operated_helm() != null and P.operated_helm().inv != null else [], int(ceil(P.redock_wait(P.undock_lock_id))), P.status(), _fmt_speed(P.vel.length()), _fmt_dist(alt), int(P.fuel()), P.max_thrust(), snappedf(P.mass(), 0.1)]
	for l in P.locations:
		var r := P.rel_to(l.id)
		rows.append([_fmt_dist(r.dist), _fmt_speed(r.speed), P.can_dock(l.id)])
	var key := JSON.stringify(rows)
	if key == _last_nav:
		return
	_last_nav = key
	for c in nav_side.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	var title := _label("COCKPIT · %s at the helm" % (pilot.display_name if pilot != null else "?"), COL_AMBER, 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("Leave [Esc]", toggle_nav.bind(false)))
	nav_side.add_child(head)
	nav_side.add_child(_label(P.status(), COL_AMBER, 14))
	var faults: Array = P.xpdr_faults()
	if not faults.is_empty():
		nav_side.add_child(_label("⚠ " + " · ".join(faults) + " – some stations refuse docking", Color(0.9, 0.33, 0.29), 13))
	var prox: String = P.prox_warning()
	if prox != "":
		nav_side.add_child(_row("⚠ " + prox, [_button("Mute", func(): P.prox_muted = true)], Color(0.95, 0.76, 0.31)))
	elif P.prox_muted:
		nav_side.add_child(_row("Proximity alarm muted", [_button("Unmute", func(): P.prox_muted = false)], COL_MUTED))
	_build_flight_info()
	nav_side.add_child(_row("Velocity", [_label(_fmt_speed(P.vel.length()), COL_AMBER, 12)]))
	nav_side.add_child(_row("Altitude above Earth", [_label(_fmt_dist(alt), Color(0.9, 0.33, 0.29) if alt < float(P.space.warn_alt) else COL_AMBER, 12)]))
	nav_side.add_child(_row("Fuel", [_label("%d" % int(P.fuel()), COL_AMBER, 12)]))
	nav_side.add_child(_row("Thrust / mass", [_label("%d kN / %.1f t" % [int(P.max_thrust()), P.mass()], COL_AMBER, 12)]))
	var helm_why := P.helm_block_reason(P.operated_helm())
	if helm_why != "":
		nav_side.add_child(_label(helm_why + " No thrust, no rotation.", Color(0.9, 0.33, 0.29), 12))
	if P.docked != "":
		nav_side.add_child(_button("Undock [U]", P.request_undock))
	elif P.travel.is_empty() and P.autodock.is_empty():
		var b := _button("Auto-Dock (nearest place)", P.start_autodock)
		var ad_why := P.autodock_block_reason()
		b.disabled = ad_why != ""
		b.tooltip_text = ad_why
		nav_side.add_child(b)
		if ad_why != "":
			nav_side.add_child(_label("Auto-Dock locked: " + ad_why, Color(0.9, 0.33, 0.29), 11))
	# Modulfach des bedienten Steuerpults
	var oh := P.operated_helm()
	if oh != null and oh.inv != null:
		var mods: PackedStringArray = []
		for it in oh.inv.items:
			mods.append("%s (%d %%)" % [ItemSystem.item(it.type).display_name, int(it.cond)])
		var mrow := _row("Modules in the console", [_label(", ".join(mods) if not mods.is_empty() else "none", COL_AMBER if not mods.is_empty() else COL_MUTED, 12)])
		mrow.add_child(_button("Module bay [E]", func(): open_container(PhysicsSystem.operated_helm().pos)))
		nav_side.add_child(mrow)
	# Ship logs (Diagnostik): letzte Andock- und Kollisionsereignisse
	if not P.ship_log.is_empty():
		nav_side.add_child(_label("SHIP LOGS", COL_MUTED, 11))
		for le in P.ship_log.slice(maxi(0, P.ship_log.size() - 4)):
			var tm := float(le.t)
			nav_side.add_child(_label("Day %d %02d:%02d · %s" % [int(tm / 1440.0) + 1, int(fmod(tm, 1440.0) / 60.0), int(fmod(tm, 60.0)), le.text], COL_MUTED, 11))
	nav_side.add_child(_label("TARGETS", COL_MUTED, 11))
	for l in P.locations:
		var r := P.rel_to(l.id)
		var here: bool = P.docked == l.id
		var btns: Array = []
		if l.id != P.target:
			btns.append(_button("Target", func():
				PhysicsSystem.target = l.id
				_last_nav = ""
				_refresh_nav()))
		if not here and P.travel.is_empty():
			if r.dist < 300.0:
				var mb := _button("Match", func():
					P.target = l.id
					P.match_target = ""
					toggle_match())
				mb.disabled = not P.manual_ok()
				btns.append(mb)
			var ab := _button("Align", func(): P.start_align((P.rel_to(l.id).pos - P.pos).angle()))
			ab.disabled = not P.manual_ok()
			btns.append(ab)
			if P.can_dock(l.id):
				btns.append(_button("Dock", func(): P.dock(l.id)))
			elif P.redock_locked(l.id) and r.dist < float(P.space.dock_dist) * 3.0:
				var lb := _button("Dock in %d s" % int(ceil(P.redock_wait(l.id))), func(): GameState.toast(P.dock_block_reason(l.id)))
				lb.disabled = true
				btns.append(lb)
			var info := P.travel_info(l.id)
			var tb := _button("Travel %.1f h · %d fuel" % [info.secs / 3600.0, int(ceil(info.fuel))], P.travel_to.bind(l.id))
			tb.tooltip_text = l.desc
			btns.append(tb)
		nav_side.add_child(_label("%s%s · %s · Δv %s" % [l.name, " (here)" if here else "", _fmt_dist(r.dist), _fmt_speed(r.speed)], Color(0.87, 0.9, 0.94), 12))
		var row := HBoxContainer.new()
		for b in btns:
			b.add_theme_font_size_override("font_size", 11)
			row.add_child(b)
		nav_side.add_child(row)
	var zoom_row := HBoxContainer.new()
	zoom_row.add_child(_button("Show ship", func():
		nav_map.follow = true
		nav_map.zoom = 40.0))
	zoom_row.add_child(_button("Whole system", func():
		nav_map.follow = false
		nav_map.center = Vector2(30000, -5000)
		nav_map.zoom = minf(nav_map.size.x, nav_map.size.y) / 150000.0))
	nav_side.add_child(zoom_row)
	var help := _label("Docking: closer than 250 m, slower than 6 m/s, and a free docking port facing the target.", COL_MUTED, 11)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nav_side.add_child(help)

func _build_gameover() -> void:
	gameover_panel = _panel()
	gameover_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	gameover_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	gameover_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	gameover_panel.visible = false
	layer.add_child(gameover_panel)
	var box := VBoxContainer.new()
	gameover_panel.add_child(box)
	gameover_label = _label("", Color(0.87, 0.9, 0.94), 15)
	gameover_label.custom_minimum_size = Vector2(420, 0)
	gameover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(gameover_label)
	box.add_child(_button("New game", func():
		gameover_panel.visible = false
		GameState.new_game()
		TimeSystem.set_speed(1)))

func show_game_over(title: String, text: String) -> void:
	gameover_label.text = title.to_upper() + "\n\n" + text
	gameover_panel.visible = true

# ---------------- Speicherplätze und Einstellungen ----------------

var _dialog: PanelContainer

func _show_dialog(title: String, build: Callable) -> void:
	if _dialog != null:
		_dialog.queue_free()
	_dialog = _panel()
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	layer.add_child(_dialog)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	_dialog.add_child(box)
	var head := HBoxContainer.new()
	var t := _label(title, COL_AMBER, 16)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(_button("✕", func(): _dialog.queue_free()))
	box.add_child(head)
	build.call(box)

func open_slots(saving: bool) -> void:
	_show_dialog("Save" if saving else "Load", func(box: VBoxContainer):
		for s in [1, 2, 3]:
			box.add_child(_row("Slot %d: %s" % [s, SaveSystem.slot_info(s)], [_button("Save here" if saving else "Load", func():
				SaveSystem.slot = s
				if saving:
					SaveSystem.save_game()
				else:
					SaveSystem.load_game()
				_dialog.queue_free())])))

func open_settings() -> void:
	_show_dialog("Settings", func(box: VBoxContainer):
		var depth := OptionButton.new()
		for k in Settings.DEPTHS:
			depth.add_item(k)
		depth.select(Settings.DEPTHS.keys().find(Settings.depth))
		depth.item_selected.connect(func(i):
			Settings.depth = Settings.DEPTHS.keys()[i]
			Settings.save())
		box.add_child(_row("Simulation depth (air and heat)", [depth]))
		var auto := SpinBox.new()
		auto.min_value = 15
		auto.max_value = 600
		auto.step = 15
		auto.value = Settings.autosave_seconds
		auto.value_changed.connect(func(v):
			Settings.autosave_seconds = v
			Settings.save())
		box.add_child(_row("Autosave every … seconds", [auto]))
		var met := CheckBox.new()
		met.text = "Micrometeorites"
		met.button_pressed = Settings.meteors
		met.toggled.connect(func(on):
			Settings.meteors = on
			Settings.save())
		box.add_child(met)
		var dp := CheckBox.new()
		dp.text = "Pause debt (no instalments, no penalty interest)"
		dp.button_pressed = Settings.debt_paused
		dp.toggled.connect(func(on):
			Settings.debt_paused = on
			Settings.save())
		box.add_child(dp)
		var mods := _label("Mods: put your own .tres files into %s (subfolders items, components, skills, traits, hobbies)." % ProjectSettings.globalize_path("user://mods"), COL_MUTED, 11)
		mods.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mods.custom_minimum_size = Vector2(400, 0)
		box.add_child(mods))

func open_window(kind: String) -> void:
	window_kind = kind
	window_panel.visible = true
	close_container()
	_last_window = ""
	_refresh_window()
	_refresh_nav()
	char_ui.refresh()

## Gespräch an der Station: Fenster mit passendem Reiter, Begrüßung oben
func open_talk(tab: String, line: String, role: String) -> void:
	trade_tab = tab
	station_reply = ""
	open_window("trade")
	talk_line = line
	talk_role = role
	_last_window = ""
	_refresh_window()

func close_window() -> void:
	talk_line = ""
	talk_role = ""
	window_kind = ""
	if window_panel != null:
		window_panel.visible = false

func _row(text: String, buttons: Array, color: Color = Color(0.87, 0.9, 0.94)) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := _label(text, color, 12)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	for b in buttons:
		row.add_child(b)
	return row

func _refresh_window() -> void:
	if window_kind == "":
		return
	var E := EconomySystem
	var t := E.terminal()
	var c: CrewMember = GameState.selected if GameState.selected != null else CrewSystem.player()
	var key := JSON.stringify([talk_line, station_reply, CrewSystem.crew.size(), window_kind, trade_tab, E.credits, E.debt, t.inv.to_data() if t != null else [], c.inv.to_data() if c != null else [], E.log_entries.size(), SalvageSystem.wreck_name, int(GameState.time / 60.0)])
	if key == _last_window:
		return
	_last_window = key
	for child in window_box.get_children():
		child.queue_free()
	var head := HBoxContainer.new()
	var st := PhysicsSystem.station()
	var title := _label({"bench": "Workbench", "chem": "Chemistry Station"}.get(window_kind, "Trade Terminal" + (" · " + String(st.name) if not st.is_empty() else "")), COL_AMBER, 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("✕", close_window))
	window_box.add_child(head)
	if talk_line != "":
		var tl := _label(talk_line, Color(0.95, 0.76, 0.31), 13)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.custom_minimum_size = Vector2(370, 0)
		window_box.add_child(tl)
	if window_kind in ["bench", "chem"]:
		window_box.add_child(_label("The crew fetches the material and puts the result next to the bench.", COL_MUTED, 12))
		for r in E.recipes:
			if r.get("station", "workbench") != ("workbench" if window_kind == "bench" else "chemstation"):
				continue
			var parts: PackedStringArray = []
			for k in r["in"]:
				parts.append("%d× %s" % [r["in"][k], ItemSystem.item(k).display_name])
			var txt := "%s\n%s → %d× %s" % [r.name, " + ".join(parts), int(r.out[1]), ItemSystem.item(r.out[0]).display_name]
			window_box.add_child(_row(txt, [_button("Craft", E.craft.bind(r.id))]))
		return
	if not E.terminal_online():
		window_box.add_child(_label("Offline: no power or not docked at a station.", Color(0.9, 0.33, 0.29), 12))
	if st.get("black", false):
		window_box.add_child(_label("Black market: data chips are worth double here.", COL_MUTED, 12))
	var tabs := HBoxContainer.new()
	for tb in [["sell", "Sell"], ["buy", "Buy"], ["bank", "Account"], ["salvage", "Salvage"], ["ships", "Ships"], ["station", "Station"], ["crew", "Crew"], ["jobs", "Jobs"]]:
		if tb[0] == "salvage" and not Config.ENABLE_WRECK:
			continue
		var b := _button(tb[1], func():
			trade_tab = tb[0]
			_last_window = ""
			_refresh_window())
		b.toggle_mode = true
		b.button_pressed = trade_tab == tb[0]
		tabs.add_child(b)
	window_box.add_child(tabs)
	window_box.add_child(_label("%d Cr" % E.credits, COL_AMBER, 20))
	match trade_tab:
		"sell":
			window_box.add_child(_label("You can sell whatever is in the terminal. Put things in from your pack.", COL_MUTED, 12))
			if t != null and not t.inv.items.is_empty():
				var total := 0
				for it in t.inv.items:
					total += E.sell_price(it)
					window_box.add_child(_trade_row("%s ×%d · %d %%" % [ItemSystem.item(it.type).display_name, it.qty, int(it.cond)], it,
						[_offer_button("Offer", E.sell_price(it), E.sell.bind(it.type, it.qty))]))
				window_box.add_child(_row("Total: %d Cr" % total, [_button("Sell all", E.sell_all)], COL_AMBER))
			else:
				window_box.add_child(_label("The terminal is empty.", COL_MUTED, 12))
			if c != null and not c.inv.items.is_empty():
				# Am Markttresen direkt aus dem Gepäck verkaufen
				var at_market := talk_role == "market"
				window_box.add_child(_label(("%s's pack – straight to the trader" if at_market else "%s's pack") % c.display_name, COL_MUTED, 11))
				for it in c.inv.items:
					var btn: Button = _offer_button("Offer", E.sell_price(it), E.sell.bind(it.type, it.qty, c.inv)) if at_market else _button("Put in", _put_terminal.bind(it.type, it.qty))
					window_box.add_child(_trade_row("%s ×%d" % [ItemSystem.item(it.type).display_name, it.qty], it, [btn]))
		"buy":
			window_box.add_child(_label("Purchases go into the terminal. Prices change every day.", COL_MUTED, 12))
			var ids: Array = ItemSystem.items.keys().filter(func(x): return not RemovalSystem.is_packed(x) or x in E.SHOP_PACKED)
			ids.sort()
			for id in ids:
				var f: float = E.prices.get(id, 1.0)
				var trend := "  ▲ expensive" if f > 1.1 else ("  ▼ cheap" if f < 0.9 else "")
				window_box.add_child(_trade_row(ItemSystem.item(id).display_name + trend, {"type": id, "qty": 1, "cond": 100.0},
					[_offer_button("Price", E.buy_price(id), E.buy.bind(id, 1)), _button("×5", E.buy.bind(id, 5))]))
		"bank":
			var days := maxf(0.0, (E.next_payment - GameState.time) / 1440.0)
			window_box.add_child(_row("Remaining debt", [_label("%d Cr" % E.debt, COL_AMBER, 13)]))
			window_box.add_child(_row("Next instalment", [_label("paused (settings ⚙)" if Settings.debt_paused else "%d Cr in %.1f days" % [mini(Config.PAYMENT, E.debt), days], COL_AMBER, 13)]))
			window_box.add_child(_row("Docking fee", [_label("%d Cr per day" % Config.DOCK_FEE, COL_MUTED, 13)]))
			window_box.add_child(_row("Missed instalments", [_label("%d of %d" % [E.strikes, Config.MAX_STRIKES], COL_MUTED, 13)]))
			window_box.add_child(_row("Repay", [_button("500 Cr", E.pay_debt.bind(500)), _button("All", E.pay_debt.bind(999999))]))
			window_box.add_child(_label("Account statement", COL_MUTED, 11))
			for e in E.log_entries:
				window_box.add_child(_row(e.text, [_label(("%+d" % e.amount) if e.amount != 0 else "", COL_MUTED, 12)], COL_MUTED))
		"jobs":
			var Q := QuestSystem
			for e in Q.events:
				window_box.add_child(_label("News: " + e.text, Color(0.95, 0.76, 0.31), 12))
			window_box.add_child(_label("REPUTATION", COL_MUTED, 11))
			for f in Q.FACTIONS:
				window_box.add_child(_row(Q.FACTIONS[f].name, [_label("%+d" % int(Q.reputation.get(f, 0.0)), COL_AMBER, 12)]))
			window_box.add_child(_label("ACCEPTED JOBS", COL_MUTED, 11))
			if Q.accepted.is_empty():
				window_box.add_child(_label("None.", COL_MUTED, 12))
			for o in Q.accepted.duplicate():
				window_box.add_child(_row(Q.describe(o), [_button("Deliver", func():
					Q.deliver(o)
					_last_window = ""
					_refresh_window())]))
			window_box.add_child(_label("OFFERS HERE", COL_MUTED, 11))
			for o in Q.offers_here().duplicate():
				window_box.add_child(_row(Q.describe(o), [_button("Accept", func():
					Q.accept(o)
					_last_window = ""
					_refresh_window())]))
			window_box.add_child(_row("Insurance (%d Cr/week, pays %d Cr per hull breach or fire)" % [Q.INSURANCE_PREMIUM, Q.INSURANCE_PAYOUT],
				[_button("Cancel" if Q.insured else "Sign up", func():
					Q.set_insured(not Q.insured)
					_last_window = ""
					_refresh_window())]))
		"station":
			if st.is_empty():
				window_box.add_child(_label("Only while docked at a station.", COL_MUTED, 12))
			else:
				window_box.add_child(_label("Speaking: %s (selected character)" % E.trader().display_name, COL_MUTED, 12))
				if station_reply != "":
					var rl := _label(station_reply, Color(0.95, 0.76, 0.31), 13)
					rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					rl.custom_minimum_size = Vector2(370, 0)
					window_box.add_child(rl)
				for o in DialogueSystem.options():
					var b := _button("Choose", func():
						station_reply = DialogueSystem.choose(o.id)
						_last_window = ""
						_refresh_window())
					b.disabled = not o.ok
					window_box.add_child(_row(o.text + ("" if o.ok else "  (" + o.why + ")"), [b], Color(0.87, 0.9, 0.94) if o.ok else COL_MUTED))
		"crew":
			if st.is_empty():
				window_box.add_child(_label("Applicants are only found at stations.", COL_MUTED, 12))
			for cand in NPCSystem.candidates_here():
				var best: Array = cand.skills.keys()
				best.sort_custom(func(a, b): return SkillSystem.progress(cand, a) > SkillSystem.progress(cand, b))
				var parts: PackedStringArray = []
				for id in best.slice(0, 3):
					parts.append("%s %d %%" % [SkillSystem.skill(id).skill_name, int(SkillSystem.progress(cand, id))])
				var trs: PackedStringArray = []
				for tid in cand.traits:
					trs.append(TraitSystem.get_trait(tid).trait_name)
				window_box.add_child(_row("%s, %d y. · %s · %s · %d Cr/day" % [cand.display_name, cand.age, ", ".join(parts), ", ".join(trs), cand.salary],
					[_button("Hire", NPCSystem.hire.bind(cand))]))
		"ships":
			var F := FleetSystem
			window_box.add_child(_row("Current ship", [_label(F.current_name, COL_AMBER, 13)]))
			var reg_txt := "Hull ID %s · Registered as %s" % [F.registry_id, F.registered_name] + ("" if F.registered_name == F.current_name else " (new name not registered yet)")
			var reg_btns: Array = []
			if st.get("shipyard", false):
				reg_btns.append(_button("Ship Rating service", func():
					var w := F.register_name()
					if w != "":
						GameState.toast(w)
					_last_window = ""))
			window_box.add_child(_row(reg_txt, reg_btns, COL_MUTED))
			var cg := ShipSystem.grid
			window_box.add_child(_label(ship_rating_text(cg, PhysicsSystem.mass() * 1000.0), COL_MUTED, 12))
			window_box.add_child(_label(rooms_text(cg), COL_MUTED, 12))
			window_box.add_child(_label("Your other ships", COL_MUTED, 11))
			if F.ships.is_empty():
				window_box.add_child(_label("No other ships.", COL_MUTED, 12))
			for s in F.ships:
				var b: Array = []
				if s.location == F.here():
					b.append(_button("Go aboard", F.switch_to.bind(int(s.id))))
					if st.get("shipyard", false):
						b.append(_button("Sell", F.sell.bind(int(s.id))))
				var sg := ShipGrid.from_data(s.data)
				window_box.add_child(_row("%s (%s) · moored at %s · Ship Rating %s · sale value %d Cr" % [s.name, String(s.get("registry", "")), PhysicsSystem.loc(s.location).name,
					ShipRating.rating(sg), int(F.ship_value(sg) * 0.6)], b))
			if SalvageSystem.wreck_name != "" and not st.is_empty():
				window_box.add_child(_button("Register wreck “%s” as a ship (%d Cr)" % [SalvageSystem.wreck_name, F.REGISTER_FEE], F.register_wreck))
			if st.get("shipyard", false):
				window_box.add_child(_label("Shipyard", COL_MUTED, 11))
				for t2 in PhysicsSystem.space.shipyard:
					window_box.add_child(_row("%s · %s" % [t2.name, t2.desc], [_button("%d Cr" % int(t2.price), F.buy.bind(t2.id, false)),
						_button("On credit", F.buy.bind(t2.id, true))]))
			else:
				window_box.add_child(_label("Buy and sell ships: shipyard at the Kármán Ring.", COL_MUTED, 12))
		"salvage":
			if SalvageSystem.wreck_name != "":
				window_box.add_child(_row("Wreck on the line", [_label(SalvageSystem.wreck_name, COL_AMBER, 13)]))
				window_box.add_child(_row("Scrap value", [_label("%d Cr" % SalvageSystem.hull_value(), COL_AMBER, 13)]))
				window_box.add_child(_label("Whatever you strip first and sell separately is worth much more.", COL_MUTED, 12))
				window_box.add_child(_button("Scrap wreck", E.scrap_hull))
				window_box.add_child(_button("Investigate wreck (Forensic Science, character must be on the wreck)", func():
					station_reply = SalvageSystem.investigate(E.trader())
					GameState.toast(station_reply)))
			window_box.add_child(_button("New salvage claim (%d Cr)" % Config.CLAIM_FEE, E.buy_claim))

func _put_terminal(type: String, qty: int) -> void:
	var c: CrewMember = GameState.selected if GameState.selected != null else CrewSystem.player()
	var t := EconomySystem.terminal()
	if c == null or t == null:
		return
	if not c.can_reach(t.pos):
		GameState.toast(c.display_name + " must stand next to the terminal.")
		return
	c.inv.move_to(t.inv, type, qty)
	_last_window = ""

# ---------------- Aktionen ----------------

# ---------------- Auto-Modus ----------------

## Auto-Modus der ausgewählten Figur umschalten
func toggle_auto() -> void:
	var c: CrewMember = GameState.selected if GameState.selected != null else CrewSystem.player()
	if c == null:
		return
	c.set_auto(not c.auto_mode)
	GameState.toast("%s: auto mode %s." % [c.display_name, "ON – finds tasks on their own" if c.auto_mode else "OFF – stays put"])
	_refresh_auto(c)

func _refresh_auto(c: CrewMember) -> void:
	if auto_button == null or c == null:
		return
	auto_button.text = "Auto: ON" if c.auto_mode else "Auto: OFF"
	auto_button.add_theme_color_override("font_color", Color(0.44, 0.81, 0.56) if c.auto_mode else Color(0.9, 0.33, 0.29))

# ---------------- Rechtsklick-Menü ----------------

## Menü für das Objekt auf Feld p öffnen. false = hier gibt es nichts.
## Rechtsklick auf p: nächste vorhandene Ebene dieser Kachel auswählen (Kabel → Gerät →
## Boden, dann wieder von oben). Andere Kachel: oben beginnen. Gibt die Ebene zurück.
func select_at(p: Vector2i) -> String:
	sel_key = RemovalSystem.next_layer(p, sel_tile, sel_key)
	sel_tile = p if sel_key != "" else Vector2i(-1, -1)
	return sel_key

func clear_selection() -> void:
	sel_tile = Vector2i(-1, -1)
	sel_key = ""

## Ist die Auswahl noch da? (abgebaute Ebene zeigt nichts mehr an)
func selection_valid() -> bool:
	return sel_key != "" and RemovalSystem.layers_at(sel_tile).has(sel_key)

## Ausgewählte Figur (sonst deine), wenn sie einen fortsetzbaren unterbrochenen Auftrag hat
func _resume_crew() -> CrewMember:
	var c: CrewMember = GameState.selected if GameState.selected != null and is_instance_valid(GameState.selected) and GameState.selected in CrewSystem.crew else CrewSystem.player()
	if c == null or c.resume_job == null or c.resume_route().why != "":
		return null
	return c

func open_object_menu(p: Vector2i) -> bool:
	var g := ShipSystem.grid
	if not g.in_bounds(p):
		return false
	var R := RemovalSystem
	var key := select_at(p)
	var i := g.idx(p)
	var job = ShipConstructionSystem.jobs.get(i)
	# Abgebaute Stücke, die hier passen würden (aus Gepäck und Lager)
	var installs := {}
	var invs: Array = CrewSystem.crew.map(func(c): return c.inv)
	for s in ShipConstructionSystem.sources():
		invs.append(s.inv)
	for inv in invs:
		for it in inv.items:
			if R.is_packed(it.type) and not installs.has(it.type) and R.can_install(it.type, p):
				installs[it.type] = it.cond
	var rc := _resume_crew()
	if key == "" and installs.is_empty() and job == null and rc == null:
		return false
	object_menu.clear()
	menu_actions.clear()
	menu_pos = p
	# Von WASD unterbrochener Auftrag der ausgewählten Figur: dort weitermachen
	if rc != null:
		object_menu.add_item("Resume Task", menu_actions.size())
		object_menu.set_item_tooltip(object_menu.item_count - 1, "%s: %s" % [rc.display_name, ShipConstructionSystem.label(rc.resume_job)])
		menu_actions.append({"kind": "resume", "crew": rc, "job": rc.resume_job})
	if key != "":
		var layers := R.layers_at(p)
		var pos_in := layers.find(key)
		var after: String = layers[(pos_in + 1) % layers.size()]
		var dev := g.device_at(p) if key.begins_with("dev:") else null
		var head := "▶ Selected: %s" % R.name_of(key)
		if key != "cable":
			head += " · condition %d %%" % int(dev.cond if dev != null else g.cond[i])
		head += " · layer %d of %d" % [pos_in + 1, layers.size()]
		object_menu.add_separator(head)
		if layers.size() > 1:
			object_menu.add_item("(next right-click here: %s)" % R.name_of(after), menu_actions.size())
			object_menu.set_item_disabled(object_menu.item_count - 1, true)
			menu_actions.append({"kind": "none"})
		for kind in R.KINDS:
			if key == "cable" and kind != "uninstall":
				continue
			var why := R.reason(kind, p, key)
			var text: String = R.NAMES[kind]
			if why == "":
				text += "  (" + _menu_detail(kind, key) + ")"
			else:
				text += "  – " + why
			object_menu.add_item(text, menu_actions.size())
			var idx := object_menu.item_count - 1
			object_menu.set_item_disabled(idx, why != "")
			object_menu.set_item_tooltip(idx, why)
			menu_actions.append({"kind": kind, "key": key})
	# Drehbare Geräte (Triebwerke): um 90° drehen lassen
	var rdev := g.device_at(p) if key.begins_with("dev:") else null
	if rdev != null and rdev.data().rotatable and not g.foreign(i):
		object_menu.add_item("Rotate (90° clockwise) – now pushes %s" % _push_name(rdev.push_dir()), menu_actions.size())
		object_menu.set_item_disabled(object_menu.item_count - 1, not ShipConstructionSystem.can_place("rotate", p))
		menu_actions.append({"kind": "rotate"})
	# Navigationskonsole (Steuerpult): Debuggen als Arbeitsauftrag (Software Engineering)
	var ndev := g.device_at(p)
	if ndev != null and ndev.type in SkillSystem.NAV_STATIONS and not ndev.unknown and not g.foreign(g.idx(ndev.pos)):
		object_menu.add_item("Debug navigation console (%.1f min)" % Config.DEBUG_TIME, menu_actions.size())
		object_menu.set_item_disabled(object_menu.item_count - 1, not ShipConstructionSystem.can_place("debug", p))
		menu_actions.append({"kind": "debug"})
	# Stromschalter: ein-/ausschalten (aus = trennt die Netze)
	if ndev != null and ndev.type == "power_switch" and not g.foreign(g.idx(ndev.pos)):
		object_menu.add_item("Turn power switch off" if ndev.switch_on else "Turn power switch on", menu_actions.size())
		menu_actions.append({"kind": "switch", "dev": ndev})
	# Navigationskonsole: Schiff umbenennen (Ostranauts Ship Building 1.4)
	if ndev != null and ndev.type == "helm" and not ndev.unknown and not g.foreign(g.idx(ndev.pos)):
		object_menu.add_item("Rename vessel…", menu_actions.size())
		object_menu.set_item_disabled(object_menu.item_count - 1, FleetSystem.rename_block_reason() != "")
		object_menu.set_item_tooltip(object_menu.item_count - 1, FleetSystem.rename_block_reason())
		menu_actions.append({"kind": "rename"})
	# Türen: Lüftungsschlitz (geschlossene Tür lässt sonst etwas Luft durch)
	if key == "tile:door" and not StationSystem.reserved(p):
		var lock := AirlockSystem.is_lock_door(i) or StationSystem.is_hatch(i)
		var closed := g.vent_closed[i] == 1
		object_menu.add_item("Airlock door: always sealed" if lock else ("Open door vent" if closed else "Close door vent (door becomes airtight)"), menu_actions.size())
		object_menu.set_item_disabled(object_menu.item_count - 1, lock)
		menu_actions.append({"kind": "vent", "closed": not closed})
	if job != null:
		object_menu.add_separator()
		object_menu.add_item("Cancel job: " + ShipConstructionSystem.label(job), menu_actions.size())
		menu_actions.append({"kind": "cancel"})
	for pk in installs:
		object_menu.add_item("Install: %s (%d %%)" % [ItemSystem.item(pk).display_name, int(installs[pk])], menu_actions.size())
		menu_actions.append({"kind": "install", "item": pk})
	object_menu.reset_size()
	object_menu.position = Vector2i(get_viewport().get_mouse_position())
	object_menu.popup()
	return true

## Offenes Menü verschluckt sonst jeden weiteren Rechtsklick (die Auswahl „hängt“).
## Rechtsklick außerhalb des Menüs: Menü zu und als neuen Rechtsklick ans Spiel geben –
## auf derselben Kachel wählt das die nächste Ebene.
func _on_object_menu_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton) or e.button_index != MOUSE_BUTTON_RIGHT or not e.pressed:
		return
	if Rect2(Vector2.ZERO, Vector2(object_menu.size)).has_point(e.position):
		return
	object_menu.hide()
	object_menu.set_input_as_handled()
	if world_view != null and is_instance_valid(world_view):
		world_view.call_deferred("_right_click", world_view.call("_tile_at_mouse"))

func _menu_detail(kind: String, key: String) -> String:
	var R := RemovalSystem
	var tool := R.tool_for(kind, key)
	var tool_txt := (", " + ItemSystem.item(tool).display_name) if tool != "" else ""
	match kind:
		"uninstall":
			return "%.1f min%s → %s" % [R.time_for(kind, key), tool_txt, R.uninstall_result(key)]
		"dismantle":
			return "%.1f min%s → %s" % [R.time_for(kind, key), tool_txt, _items_text(R.dismantle_yield(key))]
	return "Hits%s → %s" % [tool_txt, _items_text(R.debris(key))]

## Richtung eines Triebwerks in Worten (Schiffskoordinaten)
func _push_name(d: Vector2i) -> String:
	return {Vector2i(1, 0): "forward (towards the nose)", Vector2i(0, 1): "to the right", Vector2i(-1, 0): "backward", Vector2i(0, -1): "to the left"}.get(d, "?")

## Taste G: Bau-Drehung für drehbare Geräte weiterschalten
func rotate_build() -> void:
	var dev_id := ""
	if GameState.tool.begins_with("dev:"):
		dev_id = GameState.tool.substr(4)
	elif GameState.tool.begins_with("install:"):
		var key := RemovalSystem.key_of_packed(GameState.tool.substr(8))
		if key.begins_with("dev:"):
			dev_id = key.substr(4)
	if dev_id == "" or not ItemSystem.device(dev_id).rotatable:
		GameState.toast("G only rotates rotatable devices while building (e.g. a thruster).")
		return
	ShipConstructionSystem.build_rot = (ShipConstructionSystem.build_rot + 1) % 4
	set_tool(GameState.tool)

func _items_text(d: Dictionary) -> String:
	var parts: PackedStringArray = []
	for t in d:
		parts.append("%d× %s" % [int(d[t]), ItemSystem.item(t).display_name])
	return ", ".join(parts)

func _on_object_menu(id: int) -> void:
	if id < 0 or id >= menu_actions.size():
		return
	var a: Dictionary = menu_actions[id]
	var g := ShipSystem.grid
	match a.kind:
		"resume":
			# Beim Auswählen neu prüfen: Menü kann veraltet sein (Auftrag fertig, Ziel weg)
			var c = a.crew
			if c == null or not is_instance_valid(c) or not is_same(c.resume_job, a.job):
				GameState.toast("Task is no longer available.")
				return
			var why: String = c.resume_task()
			if why != "":
				GameState.toast(why)
		"rotate":
			if ShipConstructionSystem.place("rotate", menu_pos):
				GameState.toast("Job: rotate device by 90°.")
		"debug":
			if ShipConstructionSystem.place("debug", menu_pos):
				GameState.toast("Task: debug the navigation console.")
			else:
				GameState.toast("The navigation console can't be debugged right now.")
		"vent":
			AtmosphereSystem.set_vent(g.idx(menu_pos), bool(a.closed))
			GameState.toast("Door vent closed: the door is now airtight." if a.closed else "Door vent open: some air flows through the closed door.")
		"rename":
			open_rename_dialog()
		"switch":
			ShipPowerSystem.toggle_switch(a.dev)
			GameState.toast("Power switch on: the networks are connected." if a.dev.switch_on else "Power switch off: the network is split here.")
		"cancel":
			var job = ShipConstructionSystem.jobs.get(g.idx(menu_pos))
			if job != null:
				ShipConstructionSystem.cancel(job)
				GameState.toast("Job cancelled.")
		"install":
			if ShipConstructionSystem.place("install:" + String(a.item), menu_pos):
				GameState.toast("Job: install %s." % ItemSystem.item(a.item).display_name)
			else:
				GameState.toast(RemovalSystem.install_reason(String(a.item), menu_pos))
		"none":
			pass
		_:
			# Genau die ausgewählte Ebene (Kabel, Gerät oder Boden)
			var key := String(a.get("key", RemovalSystem.key_at(menu_pos)))
			var name := RemovalSystem.name_of(key)
			var why := RemovalSystem.order(String(a.kind), menu_pos, key)
			GameState.toast(why if why != "" else "Job: %s – %s." % [RemovalSystem.NAMES[a.kind], name])
	menu_actions.clear()

func set_tool(tool: String) -> void:
	GameState.tool = tool
	for k in tool_buttons:
		tool_buttons[k].button_pressed = k == tool
	device_menu.text = ItemSystem.device(tool.substr(4)).display_name + " ▾" if tool.begins_with("dev:") else "Devices ▾"
	var hint := ""
	for t in TOOLS:
		if t[0] == tool:
			hint = t[3]
	var c := {}
	if tool.begins_with("install:"):
		hint = "Click a suitable tile: install %s. Right-click: back to Select." % ItemSystem.item(tool.substr(8)).display_name
	if tool.begins_with("dev:"):
		var d := ItemSystem.device(tool.substr(4))
		hint = d.description
		if d.rotatable:
			hint = "Pushes %s (G: rotate). %s" % [_push_name(Device.PUSH_DIRS[ShipConstructionSystem.build_rot]), hint]
		c = d.cost
	elif ShipConstructionSystem.TOOL_TILE.has(tool):
		c = Config.TILE_COST[ShipConstructionSystem.TOOL_TILE[tool]]
	elif tool == "cable":
		c = Config.CABLE_COST
	if not c.is_empty():
		hint += "  " + ItemSystem.cost_text(c)
	hint_label.text = hint
	if orders_bar != null:
		orders_bar.visible = tool == "orders"
	EventBus.tool_changed.emit(tool)

func toggle_help() -> void:
	if help_panel.visible:
		close_help()
	else:
		show_help()

func show_help() -> void:
	_fit_help()
	help_panel.visible = true

func close_help() -> void:
	help_panel.visible = false

## Höhe an den Bildschirm anpassen (Knopf bleibt immer sichtbar)
func _fit_help() -> void:
	if help_scroll == null:
		return
	var avail := get_viewport().get_visible_rect().size.y - 170.0
	help_scroll.custom_minimum_size = Vector2(580, clampf(avail, 160.0, 470.0))
	help_panel.reset_size()
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

func interact() -> void:
	var p := CrewSystem.player()
	if p == null:
		return
	# Nächstgelegener Behälter oder Haufen (ein Haufen unter den Füßen zuerst);
	# dazu das Modulfach eines Steuerpults daneben
	var best := Vector2i(-1, -1)
	var cands: Array = ShipConstructionSystem.sources()
	for dv in ShipSystem.grid.devices.values():
		if dv.type == "helm" and dv.inv != null and not ShipSystem.grid.foreign(ShipSystem.grid.idx(dv.pos)):
			cands.append({"pos": dv.pos, "inv": dv.inv})
	for src in cands:
		if p.can_reach(src.pos) and (best.x < 0 or p.pos.distance_to(Vector2(src.pos) + Vector2(0.5, 0.5)) < p.pos.distance_to(Vector2(best) + Vector2(0.5, 0.5))):
			best = src.pos
	if best.x >= 0:
		open_container(best)
		return
	GameState.toast("Nothing to search here. Stand next to a crate or a pile.")

func open_container(p: Vector2i) -> void:
	open_pos = p
	container_panel.visible = true
	_last_container = ""
	_refresh_container()

## Behälter schließen (das persönliche Inventar bleibt offen, wenn es mit Tab geöffnet ist)
func close_container() -> void:
	open_pos = Vector2i(-1, -1)
	if container_panel != null:
		container_panel.visible = inv_open
		_last_container = ""

## Tab: persönliches Inventar der gesteuerten Figur öffnen bzw. schließen.
## Ein offener Behälter bleibt beim Öffnen daneben sichtbar (Austausch wie bisher);
## beim Schließen geht das ganze Fenster zu.
func toggle_inventory() -> void:
	inv_open = not inv_open
	if not inv_open:
		close_container()
		return
	container_panel.visible = true
	_last_container = ""
	_refresh_container()

## Aus dem eigenen Gepäck auf den Boden legen (unter der Figur bzw. daneben)
func _drop_own(type: String, qty: int) -> void:
	var c: CrewMember = GameState.selected if GameState.selected != null else CrewSystem.player()
	if c == null:
		return
	var g := ShipSystem.grid
	var spot := c.tile()
	if g.get_tile(spot) != ShipGrid.Tile.FLOOR or g.occupied(spot):
		spot = ShipConstructionSystem.drop_spot(spot)
	for st in c.inv.take(type, qty):
		g.drop_items(spot, st.type, st.qty, st.cond, st.get("data"))
	_last_container = ""
	_refresh_container()

func _container_inv() -> Inventory:
	var g := ShipSystem.grid
	if g == null or not g.in_bounds(open_pos):
		return null
	var dev := g.device_at(open_pos)
	if dev != null and dev.inv != null:
		return dev.inv
	return g.piles.get(g.idx(open_pos))

func _transfer(from_box: bool, type: String, qty: int) -> void:
	var c: CrewMember = GameState.selected if GameState.selected != null else CrewSystem.player()
	var inv := _container_inv()
	if c == null or inv == null:
		return
	if not c.can_reach(open_pos):
		GameState.toast(c.display_name + " is not next to it. Move closer (WASD).")
		return
	var moved := inv.move_to(c.inv, type, qty) if from_box else c.inv.move_to(inv, type, qty)
	if moved < qty:
		if not from_box and inv.only_modules and ItemSystem.item(type).helm_module == "":
			GameState.toast("The console's module bay only takes navigation console modules.")
		else:
			GameState.toast("Not everything fits." if not from_box else c.display_name + " cannot carry any more.")
	ShipSystem.grid.clean_piles()
	_last_container = ""
	_refresh_container()

# ---------------- Auffrischen ----------------

func _refresh_speed() -> void:
	for i in speed_buttons.size():
		speed_buttons[i].button_pressed = i == TimeSystem.speed_index

func _on_toast(text: String, kind: String) -> void:
	var p := _panel()
	var l := _label(text, Color(0.95, 0.63, 0.6) if kind == "bad" else Color(0.87, 0.9, 0.94), 13)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_child(p)
	while toast_box.get_child_count() > 5:
		toast_box.get_child(0).free()
	get_tree().create_timer(6.0 if kind == "bad" else 3.0).timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free())

func _refresh() -> void:
	if ShipSystem.grid == null:
		return
	clock_label.text = GameState.clock_text()
	var c: CrewMember = GameState.selected if GameState.selected != null else CrewSystem.player()
	if c != null:
		name_label.text = ("▸ " if c.is_player else "") + c.display_name
		task_label.text = c.task + (" · carrying " + c.carrying.data().display_name if c.carrying != null else "")
		_refresh_auto(c)
		need_bars.health.value = c.health
		need_bars.warmth.value = clampf((c.body_temp - 33.0) / 4.0 * 100.0, 0.0, 100.0)
		need_bars.stress.value = 100.0 - c.stress
		for k in ["air", "food", "water", "sleep", "hygiene"]:
			need_bars[k].value = c.needs[k]
		need_bars.suit_o2.get_parent().visible = c.suit != null
		need_bars.suit_bat.get_parent().visible = c.suit != null
		if c.suit != null:
			need_bars.suit_o2.value = c.suit.o2
			need_bars.suit_bat.value = c.suit.battery
		for k in need_bars:
			var v: float = need_bars[k].value
			var sb: StyleBoxFlat = need_bars[k].get_theme_stylebox("fill")
			sb.bg_color = Color(0.9, 0.33, 0.29) if v < 25.0 else (COL_AMBER if v < 50.0 else Color(0.44, 0.81, 0.56))
		var lines: PackedStringArray = []
		for it in c.inv.items:
			lines.append("%s ×%d (%d %%)%s" % [ItemSystem.item(it.type).display_name, it.qty, int(it.cond), " · in hands" if c.inv._in_hand(it) else ""])
		inv_label.text = ("%.1f / %d kg · Tab: inventory\n" % [c.inv.load_weight(), int(Config.CARRY_WEIGHT)]) + ("\n".join(lines) if not lines.is_empty() else "empty")
	var goal := GoalSystem.current()
	var goal_count: int = GoalSystem.GOALS.filter(func(x): return GoalSystem._available(x)).size()
	goal_label.text = ("%s (%d/%d)" % [goal.text, mini(GoalSystem.done.size() + 1, goal_count), goal_count]) if not goal.is_empty() else "All goals reached. Do whatever you like."
	var net := ShipPowerSystem.main_net()
	if net.is_empty():
		power_label.text = "⚡ No power network"
	else:
		power_label.text = "⚡ %.1f kW produced · %.1f kW used · battery %.1f/%.0f kWh%s%s" % [
			net.production, net.demand, net.charge, net.capacity, runtime_text(net), "" if net.ok else " · POWER FAILURE"]
	money_label.text = "%d Cr · debt %d · %s · %d build plans" % [EconomySystem.credits, EconomySystem.debt,
		"instalments paused" if Settings.debt_paused else "instalment in %.1f d" % maxf(0.0, (EconomySystem.next_payment - GameState.time) / 1440.0),
		ShipConstructionSystem.jobs.size()]
	money_label.add_theme_color_override("font_color", COL_AMBER)
	_refresh_window()
	_check_helm_walk()
	_refresh_nav()
	char_ui.refresh()
	_refresh_hover()
	_refresh_container()

func _refresh_hover() -> void:
	var g := ShipSystem.grid
	var main := get_tree().current_scene
	if main == null or not main.has_method("_tile_at_mouse"):
		return
	var t: Vector2i = main.call("_tile_at_mouse")
	if not g.in_bounds(t):
		hover_label.text = ""
		return
	var i := g.idx(t)
	var parts: PackedStringArray = []
	var dev := g.device_at(t)
	parts.append(dev.status_text() if dev != null else Config.TILE_NAMES[int(g.tiles[i])])
	if g.cables[i] == 1:
		parts.append("Cable")
	if ShipConstructionSystem.jobs.has(i):
		var job: Dictionary = ShipConstructionSystem.jobs[i]
		parts.append("Plan: " + ShipConstructionSystem.label(job) + (" (material missing)" if job.get("missing", false) else ""))
	var air := AtmosphereSystem.describe(i)
	if air != "":
		parts.append(air)
	hover_label.text = " · ".join(parts) + "  [%d, %d]" % [t.x, t.y]

func _refresh_container() -> void:
	if not container_panel.visible:
		return
	var inv := _container_inv()
	var c: CrewMember = GameState.selected if GameState.selected != null else CrewSystem.player()
	var key := JSON.stringify([open_pos, inv_open, inv.to_data() if inv != null else [], c.inv.to_data() if c != null else []])
	if key == _last_container:
		return
	_last_container = key
	for child in container_box.get_children():
		child.queue_free()
	var box_open := ShipSystem.grid.in_bounds(open_pos)
	if not box_open:
		# Nur das persönliche Inventar (Tab)
		_own_section(c, false)
		return
	var head := HBoxContainer.new()
	var dev := ShipSystem.grid.device_at(open_pos)
	var helm_box: bool = dev != null and inv != null and inv.only_modules
	var title := _label((dev.data().display_name + (" – module bay" if helm_box else "")) if dev != null else "Pile on the floor", COL_AMBER, 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("✕", close_container))
	container_box.add_child(head)
	if helm_box:
		# Was dieses Pult freischaltet (nur dieses Pult, nur funktionsfähige Module)
		var why := PhysicsSystem.module_block_reason(dev, "autodock")
		container_box.add_child(_label("Only takes navigation console modules. Auto-Dock at this console: " + ("unlocked" if why == "" else why), COL_MUTED, 11))
	if dev != null and dev.lock_level > 0:
		container_box.add_child(_label("Locked (security level %d). Needs Hacking+Software %d (best character has %d)." % [
			dev.lock_level, int(SkillSystem.hack_needed(dev.lock_level)), int(_best_hack())], Color(0.9, 0.33, 0.29), 12))
		container_box.add_child(_button("Have it hacked", func():
			if ShipConstructionSystem.place("hack", open_pos):
				GameState.toast("Hacking job given.")))
		return
	if inv == null or inv.items.is_empty():
		container_box.add_child(_label("Empty.", COL_MUTED, 12))
	else:
		for it in inv.items:
			container_box.add_child(_install_btn(_item_row(it, "Take", _transfer.bind(true, it.type, it.qty)), it.type))
	if c != null:
		_own_section(c, true)

## Persönliches Inventar: Gewicht, Hände, Gegenstände. Mit offenem Behälter „Hineinlegen“,
## sonst „Ablegen“ (auf den Boden).
func _own_section(c: CrewMember, box_open: bool) -> void:
	if c == null:
		return
	var head := HBoxContainer.new()
	var title := _label("%s's inventory · %.1f / %d kg" % [c.display_name, c.inv.load_weight(), int(Config.CARRY_WEIGHT)], COL_AMBER if not box_open else COL_MUTED, 15 if not box_open else 11)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if not box_open:
		head.add_child(_button("✕", toggle_inventory))
	container_box.add_child(head)
	var hand := c.inv.in_hands()
	container_box.add_child(_label("In hands: " + (ItemSystem.item(hand.type).display_name if not hand.is_empty() else "nothing"), COL_MUTED, 11))
	if c.inv.items.is_empty():
		container_box.add_child(_label("Empty.", COL_MUTED, 12))
		return
	for it in c.inv.items:
		var row := _item_row(it, "Put in" if box_open else "Drop", _transfer.bind(false, it.type, it.qty) if box_open else _drop_own.bind(it.type, it.qty), c.inv._in_hand(it))
		container_box.add_child(_install_btn(row, it.type))

func _best_hack() -> float:
	var best := 0.0
	for c in CrewSystem.crew:
		best = maxf(best, SkillSystem.hack_value(c))
	return best

## Abgebaute Stücke bekommen einen Knopf „Einbauen“ (Werkzeug: nächster Klick setzt den Auftrag)
func _install_btn(row: HBoxContainer, type: String) -> HBoxContainer:
	if RemovalSystem.is_packed(type):
		row.add_child(_button("Install", func():
			set_tool("install:" + type)
			close_container()))
	return row

## Handelszeile: Gegenstandswert (nur mit Business Admin) und Angebot getrennt
func _trade_row(text: String, it: Dictionary, controls: Array) -> HBoxContainer:
	var v := EconomySystem.value_text(EconomySystem.trader(), it)
	var row := _row(text + (" · " + v if v != "" else ""), controls)
	row.tooltip_text = item_tooltip(it)
	return row

## Knopf mit dem konkreten Händlerangebot (kann über oder unter dem Gegenstandswert liegen)
func _offer_button(kind: String, price: int, cb: Callable) -> Button:
	var b := _button("%d Cr" % price, cb)
	b.tooltip_text = "%s: %d Cr (the trader's offer, independent of the Item Value)" % [kind, price]
	return b

func _item_row(it: Dictionary, action: String, cb: Callable, hand: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	var d := ItemSystem.item(it.type)
	var l := _label("%s ×%d · %d %% · %.1f kg%s" % [d.display_name, it.qty, int(it.cond), Inventory.stack_weight(it), " · in hands" if hand else ""], Color(0.87, 0.9, 0.94), 12)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.tooltip_text = item_tooltip(it)
	row.add_child(l)
	row.add_child(_button(action, cb))
	return row

## Tooltip eines Gegenstands für die betrachtende Figur (ausgewählt, sonst deine):
## mit Business Admin zusätzlich der exakte Gegenstandswert
func item_tooltip(it: Dictionary) -> String:
	var text := ItemSystem.item(it.type).description
	var v := EconomySystem.value_text(EconomySystem.trader(), it)
	return text + ("\n" + v if v != "" else "")

## Laufzeit beim aktuellen Verbrauch: "" wenn das Netz nicht entlädt
func runtime_text(net: Dictionary) -> String:
	var h: float = net.get("hours", INF)
	if h == INF or net.charge <= 0.0:
		return ""
	if h < 1.0:
		return " · batteries last about %d min" % int(round(h * 60.0))
	return " · batteries last about %.1f h" % h

## Schiffsbewertung W-X-Y-ZZZZ mit Erklärung (Ostranauts Ship Rating)
func ship_rating_text(g: ShipGrid, mass_kg: float) -> String:
	var r := ShipRating.rating(g, mass_kg)
	return "Ship Rating %s (condition %d %%, %d unique rooms, thrust class %s, %s) · Ship value %d Cr" % [r,
		int(ShipRating.condition(g)), RoomTypes.unique_count(g), r.split("-")[2], ShipRating.size_class(ShipRating.area(g)), FleetSystem.ship_value(g)]

## Raumliste des Schiffs: Typ ×Wertfaktor (Ostranauts Rooms)
func rooms_text(g: ShipGrid) -> String:
	var parts: PackedStringArray = []
	for room in RoomTypes.classify(g):
		parts.append("%s ×%.2f (%d tiles)" % [room.name, room.modifier, room.size])
	return "Rooms: " + (", ".join(parts) if not parts.is_empty() else "none enclosed")

# ---------------- Orders-Menü (Ostranauts Orders 4): Aktion + Filter ----------------
var orders_bar: HBoxContainer
var order_buttons := {}
var filter_buttons := {}

func _build_orders_bar(box: Container) -> void:
	orders_bar = HBoxContainer.new()
	orders_bar.visible = false
	box.add_child(orders_bar)
	orders_bar.add_child(_label("Action:", COL_MUTED, 12))
	for a in Orders.ACTIONS:
		var b := _button(a, set_order_action.bind(a))
		b.toggle_mode = true
		b.tooltip_text = Orders.ACTION_HINTS[a]
		b.add_theme_font_size_override("font_size", 12)
		b.disabled = a == "LOAD"
		order_buttons[a] = b
		orders_bar.add_child(b)
	orders_bar.add_child(_label("  Filter:", COL_MUTED, 12))
	for f in Orders.FILTERS:
		var b := _button(f, toggle_order_filter.bind(f))
		b.toggle_mode = true
		b.tooltip_text = Orders.FILTER_HINTS[f]
		b.add_theme_font_size_override("font_size", 12)
		filter_buttons[f] = b
		orders_bar.add_child(b)
	_sync_orders_bar()

func set_order_action(a: String) -> void:
	Orders.action = a
	_sync_orders_bar()

func toggle_order_filter(f: String) -> void:
	Orders.filters[f] = not bool(Orders.filters[f])
	_sync_orders_bar()

func _sync_orders_bar() -> void:
	for a in order_buttons:
		order_buttons[a].set_pressed_no_signal(a == Orders.action)
	for f in filter_buttons:
		filter_buttons[f].set_pressed_no_signal(bool(Orders.filters[f]))

# ---------------- Schiff umbenennen ----------------
var rename_dialog: ConfirmationDialog
var rename_edit: LineEdit

func open_rename_dialog() -> void:
	if rename_dialog == null:
		rename_dialog = ConfirmationDialog.new()
		rename_dialog.title = "Rename vessel"
		rename_edit = LineEdit.new()
		rename_edit.max_length = FleetSystem.NAME_MAX
		rename_edit.custom_minimum_size = Vector2(260, 0)
		rename_dialog.add_child(rename_edit)
		rename_dialog.register_text_enter(rename_edit)
		rename_dialog.confirmed.connect(func():
			var why := FleetSystem.rename(rename_edit.text)
			if why != "":
				GameState.toast(why, "bad"))
		layer.add_child(rename_dialog)
	rename_edit.text = FleetSystem.current_name
	rename_dialog.popup_centered()
	rename_edit.grab_focus()
	rename_edit.select_all()
