## Baut die Benutzeroberfläche auf und hält sie aktuell.
## Die Anzeigen werden 5-mal pro Sekunde aufgefrischt (nicht jedes Bild).
extends Node

const TOOLS := [
	["select", "Auswahl", "Esc", "Klick auf den Boden: Figur läuft hin. Ziehen: Ansicht verschieben. WASD: deine Figur steuern."],
	["floor", "Boden", "B", "Klicken oder Fläche ziehen. Boden geht nur im Weltraum."],
	["wall", "Wand", "M", "Ziehen zeichnet eine Linie oder den Rand eines Rechtecks."],
	["door", "Tür", "T", "Klick auf eine Wand oder einen Boden."],
	["window", "Fenster", "Z", "Wie eine Wand, aber aus Panzerglas. Der Ausblick senkt Stress, kostet aber Wärme."],
	["cable", "Kabel", "K", "Kabel verbinden Geräte mit Strom."],
	["move", "Versetzen", "V", "Vom Gerät zum Zielfeld ziehen. Ein Charakter trägt es dorthin."],
	["haul", "Einsammeln", "Q", "Haufen markieren. Die Crew bringt alles in die nächste Frachtkiste im Schiff."],
	["repair", "Reparieren", "R", "Auf Beschädigtes klicken. Stark Beschädigtes wird automatisch repariert."],
	["remove", "Abreißen", "X", "Schicht für Schicht: Gerät, Kabel, Wand/Tür, Boden. Gibt Teile zurück."],
	["cancel", "Plan löschen", "C", "Entfernt Baupläne. Rechtsklick geht auch."],
]
const COL_PANEL := Color(0.05, 0.07, 0.106, 0.92)
const COL_AMBER := Color(0.95, 0.64, 0.23)
const COL_MUTED := Color(0.51, 0.57, 0.65)

var layer: CanvasLayer
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
var open_pos := Vector2i(-1, -1)
var _last_container := ""
var window_panel: PanelContainer
var window_box: VBoxContainer
var window_kind := ""
var trade_tab := "sell"
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
	clock_label = _label("Tag 1  08:00:00")
	row.add_child(clock_label)
	var names := ["❚❚", "1×", "10×", "60×", "300×", "1000×"]
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
	row.add_child(_button("Charakter [I]", func(): char_ui.toggle()))
	row.add_child(_button("Speichern", func(): open_slots(true)))
	row.add_child(_button("Laden", func(): open_slots(false)))
	row.add_child(_button("⚙", open_settings))
	row.add_child(_button("Neues Spiel", func():
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
	for key in [["health", "Gesundheit"], ["warmth", "Körperwärme"], ["stress", "Ruhe"], ["air", "Atmung"], ["food", "Hunger"], ["water", "Durst"], ["sleep", "Energie"], ["hygiene", "Hygiene"], ["suit_o2", "Anzug O₂"], ["suit_bat", "Anzug-Akku"]]:
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
	box.add_child(_label("ZIEL", COL_MUTED, 11))
	goal_label = _label("", COL_AMBER, 12)
	goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal_label.custom_minimum_size = Vector2(250, 0)
	box.add_child(goal_label)
	box.add_child(_label("GEPÄCK", COL_MUTED, 11))
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
		b.tooltip_text = "%s (Taste %s)" % [t[1], t[2]]
		b.add_theme_font_size_override("font_size", 13)
		b.toggle_mode = true
		tool_buttons[t[0]] = b
		row.add_child(b)
	device_menu = MenuButton.new()
	device_menu.text = "Geräte ▾"
	device_menu.flat = false
	var keys := ItemSystem.devices.keys()
	keys.sort()
	for k in keys:
		device_ids.append(k)
		device_menu.get_popup().add_item(ItemSystem.device(k).display_name)
	device_menu.get_popup().index_pressed.connect(func(i): set_tool("dev:" + device_ids[i]))
	row.add_child(device_menu)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_button("Luft [L]", func(): GameState.view = "normal" if GameState.view == "air" else "air"))
	row.add_child(_button("Strom [P]", func(): GameState.view = "normal" if GameState.view == "power" else "power"))
	row.add_child(_button("Wärme [O]", func(): GameState.view = "normal" if GameState.view == "heat" else "heat"))
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
	var box := VBoxContainer.new()
	help_panel.add_child(box)
	box.add_child(_label("STEUERUNG", COL_AMBER, 18))
	var text := _label("""Dein kleines Schiff treibt im All. Mira lebt darin und baut, was du planst.
Halte sie am Leben: Luft, Essen, Wasser, Schlaf.

WASD: deine Figur steuern (Umschalt: rennen)
Auswahl + Klick auf Boden: hinlaufen lassen · Klick auf Kiste: Inhalt
Werkzeuge unten: Boden B, Wand M, Tür T, Kabel K, Abreißen X, Plan löschen C
Geräte-Menü: Generator, Sauerstoff, Betten, Kisten ...
Rechtsklick: Bauplan oder Aufgabe abbrechen · Versetzen V · Reparieren R
Für Arbeiten im Vakuum holt Mira selbst einen Raumanzug. Die Luftschleuse links
pumpt die Luft ab, bevor die Außentür aufgeht. Draußen auf dem Steg liegt Mondmüll.
E: Kiste oder Haufen neben dir durchsuchen
L / P / O: Luft-, Strom- und Wärme-Ansicht · Mausrad: zoomen · Pfeiltasten: Ansicht
Leertaste: Pause · 1–4: Geschwindigkeit · Strg+S: speichern

Du schuldest der Bank 24 000 Cr, alle 7 Tage ist eine Rate fällig.
Unten hängt ein Wrack: ausschlachten (Abreißen X), einsammeln (Q), im
Handelsterminal im Cockpit verkaufen (anklicken).
N: Navigation am Steuerpult · Fliegen mit WASD · Schnellreise zu Stationen
und ins Trümmerfeld. Vorsicht: Die Erde zieht dich an.""", Color(0.87, 0.9, 0.94), 14)
	text.custom_minimum_size = Vector2(560, 0)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	box.add_child(_button("Los geht's", func(): help_panel.visible = false))

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
	nav_side = VBoxContainer.new()
	nav_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(nav_side)

func toggle_nav(show = null) -> void:
	var want: bool = (not nav_open) if show == null else bool(show)
	if want and PhysicsSystem.ship_devices("helm").is_empty():
		GameState.toast("Dein Schiff hat kein Steuerpult.")
		return
	nav_open = want
	nav_root.visible = want
	if not want:
		PhysicsSystem.thrust = 0.0
	else:
		nav_map.follow = true
		_last_nav = ""
		_refresh_nav()

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
	var rows: Array = [P.status(), _fmt_speed(P.vel.length()), _fmt_dist(alt), int(P.fuel()), P.max_thrust(), snappedf(P.mass(), 0.1)]
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
	var title := _label("NAVIGATION", COL_AMBER, 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("✕", toggle_nav.bind(false)))
	nav_side.add_child(head)
	nav_side.add_child(_label(P.status(), COL_AMBER, 14))
	nav_side.add_child(_row("Geschwindigkeit", [_label(_fmt_speed(P.vel.length()), COL_AMBER, 12)]))
	nav_side.add_child(_row("Höhe über der Erde", [_label(_fmt_dist(alt), Color(0.9, 0.33, 0.29) if alt < float(P.space.warn_alt) else COL_AMBER, 12)]))
	nav_side.add_child(_row("Treibstoff", [_label("%d" % int(P.fuel()), COL_AMBER, 12)]))
	nav_side.add_child(_row("Schub / Masse", [_label("%d kN / %.1f t" % [int(P.max_thrust()), P.mass()], COL_AMBER, 12)]))
	if not P.helm_ok():
		nav_side.add_child(_label("Das Steuerpult hat keinen Strom.", Color(0.9, 0.33, 0.29), 12))
	if P.docked != "":
		nav_side.add_child(_button("Abdocken", P.undock))
	elif P.travel.is_empty() and P.autodock.is_empty():
		var b := _button("Auto-Dock (nächster Ort)", P.start_autodock)
		b.disabled = not P.autodock_ok()
		nav_side.add_child(b)
	nav_side.add_child(_label("ZIELE", COL_MUTED, 11))
	for l in P.locations:
		var r := P.rel_to(l.id)
		var here: bool = P.docked == l.id
		var btns: Array = []
		if not here and P.travel.is_empty():
			if r.dist < 300.0:
				btns.append(_button("Angleichen", func(): P.match_target = l.id))
			btns.append(_button("Ausrichten", func(): P.angle = (r.pos - P.pos).angle()))
			if P.can_dock(l.id):
				btns.append(_button("Andocken", func(): P.dock(l.id)))
			var info := P.travel_info(l.id)
			var tb := _button("Reisen %.1f h · %d T" % [info.secs / 3600.0, int(ceil(info.fuel))], P.travel_to.bind(l.id))
			tb.tooltip_text = l.desc
			btns.append(tb)
		nav_side.add_child(_label("%s%s · %s · Δv %s" % [l.name, " (hier)" if here else "", _fmt_dist(r.dist), _fmt_speed(r.speed)], Color(0.87, 0.9, 0.94), 12))
		var row := HBoxContainer.new()
		for b in btns:
			b.add_theme_font_size_override("font_size", 11)
			row.add_child(b)
		nav_side.add_child(row)
	var zoom_row := HBoxContainer.new()
	zoom_row.add_child(_button("Schiff zeigen", func():
		nav_map.follow = true
		nav_map.zoom = 40.0))
	zoom_row.add_child(_button("Ganzes System", func():
		nav_map.follow = false
		nav_map.center = Vector2(30000, -5000)
		nav_map.zoom = minf(nav_map.size.x, nav_map.size.y) / 150000.0))
	nav_side.add_child(zoom_row)
	var help := _label("W Schub · S Gegenschub · A/D drehen · F andocken · Mausrad zoomen. Andocken: näher als 250 m und langsamer als 6 m/s.", COL_MUTED, 11)
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
	box.add_child(_button("Neues Spiel", func():
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
	_show_dialog("Speichern" if saving else "Laden", func(box: VBoxContainer):
		for s in [1, 2, 3]:
			box.add_child(_row("Platz %d: %s" % [s, SaveSystem.slot_info(s)], [_button("Hier speichern" if saving else "Laden", func():
				SaveSystem.slot = s
				if saving:
					SaveSystem.save_game()
				else:
					SaveSystem.load_game()
				_dialog.queue_free())])))

func open_settings() -> void:
	_show_dialog("Einstellungen", func(box: VBoxContainer):
		var depth := OptionButton.new()
		for k in Settings.DEPTHS:
			depth.add_item(k)
		depth.select(Settings.DEPTHS.keys().find(Settings.depth))
		depth.item_selected.connect(func(i):
			Settings.depth = Settings.DEPTHS.keys()[i]
			Settings.save())
		box.add_child(_row("Simulationstiefe (Luft und Wärme)", [depth]))
		var auto := SpinBox.new()
		auto.min_value = 15
		auto.max_value = 600
		auto.step = 15
		auto.value = Settings.autosave_seconds
		auto.value_changed.connect(func(v):
			Settings.autosave_seconds = v
			Settings.save())
		box.add_child(_row("Autosave alle … Sekunden", [auto]))
		var met := CheckBox.new()
		met.text = "Mikrometeoriten"
		met.button_pressed = Settings.meteors
		met.toggled.connect(func(on):
			Settings.meteors = on
			Settings.save())
		box.add_child(met)
		var mods := _label("Mods: eigene .tres-Dateien nach %s legen (Unterordner items, components, skills, traits, hobbies)." % ProjectSettings.globalize_path("user://mods"), COL_MUTED, 11)
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

func close_window() -> void:
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
	var key := JSON.stringify([station_reply, CrewSystem.crew.size(), window_kind, trade_tab, E.credits, E.debt, t.inv.to_data() if t != null else [], c.inv.to_data() if c != null else [], E.log_entries.size(), SalvageSystem.wreck_name, int(GameState.time / 60.0)])
	if key == _last_window:
		return
	_last_window = key
	for child in window_box.get_children():
		child.queue_free()
	var head := HBoxContainer.new()
	var st := PhysicsSystem.station()
	var title := _label({"bench": "Werkbank", "chem": "Chemiestation"}.get(window_kind, "Handelsterminal" + (" · " + String(st.name) if not st.is_empty() else "")), COL_AMBER, 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("✕", close_window))
	window_box.add_child(head)
	if window_kind in ["bench", "chem"]:
		window_box.add_child(_label("Die Crew holt das Material selbst und legt das Ergebnis daneben.", COL_MUTED, 12))
		for r in E.recipes:
			if r.get("station", "workbench") != ("workbench" if window_kind == "bench" else "chemstation"):
				continue
			var parts: PackedStringArray = []
			for k in r["in"]:
				parts.append("%d× %s" % [r["in"][k], ItemSystem.item(k).display_name])
			var txt := "%s\n%s → %d× %s" % [r.name, " + ".join(parts), int(r.out[1]), ItemSystem.item(r.out[0]).display_name]
			window_box.add_child(_row(txt, [_button("Herstellen", E.craft.bind(r.id))]))
		return
	if not E.terminal_online():
		window_box.add_child(_label("Offline: kein Strom oder nicht an einer Station angedockt.", Color(0.9, 0.33, 0.29), 12))
	if st.get("black", false):
		window_box.add_child(_label("Schwarzmarkt: Datenchips bringen hier das Doppelte.", COL_MUTED, 12))
	var tabs := HBoxContainer.new()
	for tb in [["sell", "Verkaufen"], ["buy", "Kaufen"], ["bank", "Konto"], ["salvage", "Bergung"], ["ships", "Schiffe"], ["station", "Station"], ["crew", "Crew"], ["jobs", "Aufträge"]]:
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
			window_box.add_child(_label("Was im Terminal liegt, kannst du verkaufen. Leg Sachen aus dem Gepäck hinein.", COL_MUTED, 12))
			if t != null and not t.inv.items.is_empty():
				var total := 0
				for it in t.inv.items:
					total += E.sell_price(it)
					window_box.add_child(_row("%s ×%d · %d %%" % [ItemSystem.item(it.type).display_name, it.qty, int(it.cond)],
						[_button("%d Cr" % E.sell_price(it), E.sell.bind(it.type, it.qty))]))
				window_box.add_child(_row("Summe: %d Cr" % total, [_button("Alles verkaufen", E.sell_all)], COL_AMBER))
			else:
				window_box.add_child(_label("Das Terminal ist leer.", COL_MUTED, 12))
			if c != null and not c.inv.items.is_empty():
				window_box.add_child(_label("Gepäck von " + c.display_name, COL_MUTED, 11))
				for it in c.inv.items:
					window_box.add_child(_row("%s ×%d" % [ItemSystem.item(it.type).display_name, it.qty],
						[_button("Hineinlegen", _put_terminal.bind(it.type, it.qty))]))
		"buy":
			window_box.add_child(_label("Gekauftes landet im Terminal. Preise ändern sich jeden Tag.", COL_MUTED, 12))
			var ids := ItemSystem.items.keys()
			ids.sort()
			for id in ids:
				var f: float = E.prices.get(id, 1.0)
				var trend := "  ▲ teuer" if f > 1.1 else ("  ▼ günstig" if f < 0.9 else "")
				window_box.add_child(_row(ItemSystem.item(id).display_name + trend,
					[_button("%d Cr" % E.buy_price(id), E.buy.bind(id, 1)), _button("×5", E.buy.bind(id, 5))]))
		"bank":
			var days := maxf(0.0, (E.next_payment - GameState.time) / 1440.0)
			window_box.add_child(_row("Restschuld", [_label("%d Cr" % E.debt, COL_AMBER, 13)]))
			window_box.add_child(_row("Nächste Rate", [_label("%d Cr in %.1f Tagen" % [mini(Config.PAYMENT, E.debt), days], COL_AMBER, 13)]))
			window_box.add_child(_row("Liegegebühr", [_label("%d Cr pro Tag" % Config.DOCK_FEE, COL_MUTED, 13)]))
			window_box.add_child(_row("Verpasste Raten", [_label("%d von %d" % [E.strikes, Config.MAX_STRIKES], COL_MUTED, 13)]))
			window_box.add_child(_row("Tilgen", [_button("500 Cr", E.pay_debt.bind(500)), _button("Alles", E.pay_debt.bind(999999))]))
			window_box.add_child(_label("Kontoauszug", COL_MUTED, 11))
			for e in E.log_entries:
				window_box.add_child(_row(e.text, [_label(("%+d" % e.amount) if e.amount != 0 else "", COL_MUTED, 12)], COL_MUTED))
		"jobs":
			var Q := QuestSystem
			for e in Q.events:
				window_box.add_child(_label("Nachrichten: " + e.text, Color(0.95, 0.76, 0.31), 12))
			window_box.add_child(_label("ANSEHEN", COL_MUTED, 11))
			for f in Q.FACTIONS:
				window_box.add_child(_row(Q.FACTIONS[f].name, [_label("%+d" % int(Q.reputation.get(f, 0.0)), COL_AMBER, 12)]))
			window_box.add_child(_label("ANGENOMMENE AUFTRÄGE", COL_MUTED, 11))
			if Q.accepted.is_empty():
				window_box.add_child(_label("Keine.", COL_MUTED, 12))
			for o in Q.accepted.duplicate():
				window_box.add_child(_row(Q.describe(o), [_button("Abliefern", func():
					Q.deliver(o)
					_last_window = ""
					_refresh_window())]))
			window_box.add_child(_label("ANGEBOTE HIER", COL_MUTED, 11))
			for o in Q.offers_here().duplicate():
				window_box.add_child(_row(Q.describe(o), [_button("Annehmen", func():
					Q.accept(o)
					_last_window = ""
					_refresh_window())]))
			window_box.add_child(_row("Versicherung (%d Cr/Woche, zahlt %d Cr je Hüllenbruch oder Feuer)" % [Q.INSURANCE_PREMIUM, Q.INSURANCE_PAYOUT],
				[_button("Kündigen" if Q.insured else "Abschließen", func():
					Q.set_insured(not Q.insured)
					_last_window = ""
					_refresh_window())]))
		"station":
			if st.is_empty():
				window_box.add_child(_label("Nur angedockt an einer Station.", COL_MUTED, 12))
			else:
				window_box.add_child(_label("Wer redet: %s (ausgewählte Figur)" % E.trader().display_name, COL_MUTED, 12))
				if station_reply != "":
					var rl := _label(station_reply, Color(0.95, 0.76, 0.31), 13)
					rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					rl.custom_minimum_size = Vector2(370, 0)
					window_box.add_child(rl)
				for o in DialogueSystem.options():
					var b := _button("Wählen", func():
						station_reply = DialogueSystem.choose(o.id)
						_last_window = ""
						_refresh_window())
					b.disabled = not o.ok
					window_box.add_child(_row(o.text + ("" if o.ok else "  (" + o.why + ")"), [b], Color(0.87, 0.9, 0.94) if o.ok else COL_MUTED))
		"crew":
			if st.is_empty():
				window_box.add_child(_label("Bewerber gibt es nur an Stationen.", COL_MUTED, 12))
			for cand in NPCSystem.candidates_here():
				var best: Array = cand.skills.keys()
				best.sort_custom(func(a, b): return SkillSystem.progress(cand, a) > SkillSystem.progress(cand, b))
				var parts: PackedStringArray = []
				for id in best.slice(0, 3):
					parts.append("%s %d %%" % [SkillSystem.skill(id).skill_name, int(SkillSystem.progress(cand, id))])
				var trs: PackedStringArray = []
				for tid in cand.traits:
					trs.append(TraitSystem.get_trait(tid).trait_name)
				window_box.add_child(_row("%s, %d J. · %s · %s · %d Cr/Tag" % [cand.display_name, cand.age, ", ".join(parts), ", ".join(trs), cand.salary],
					[_button("Anheuern", NPCSystem.hire.bind(cand))]))
		"ships":
			var F := FleetSystem
			window_box.add_child(_row("Aktuelles Schiff", [_label(F.current_name, COL_AMBER, 13)]))
			window_box.add_child(_label("Deine anderen Schiffe", COL_MUTED, 11))
			if F.ships.is_empty():
				window_box.add_child(_label("Keine weiteren Schiffe.", COL_MUTED, 12))
			for s in F.ships:
				var b: Array = []
				if s.location == F.here():
					b.append(_button("An Bord gehen", F.switch_to.bind(int(s.id))))
					if st.get("shipyard", false):
						b.append(_button("Verkaufen", F.sell.bind(int(s.id))))
				window_box.add_child(_row("%s · liegt bei %s" % [s.name, PhysicsSystem.loc(s.location).name], b))
			if SalvageSystem.wreck_name != "" and not st.is_empty():
				window_box.add_child(_button("Wrack „%s“ als Schiff anmelden (%d Cr)" % [SalvageSystem.wreck_name, F.REGISTER_FEE], F.register_wreck))
			if st.get("shipyard", false):
				window_box.add_child(_label("Werft", COL_MUTED, 11))
				for t2 in PhysicsSystem.space.shipyard:
					window_box.add_child(_row("%s · %s" % [t2.name, t2.desc], [_button("%d Cr" % int(t2.price), F.buy.bind(t2.id, false)),
						_button("Auf Kredit", F.buy.bind(t2.id, true))]))
			else:
				window_box.add_child(_label("Schiffe kaufen und verkaufen: Werft am Kármán-Ring.", COL_MUTED, 12))
		"salvage":
			if SalvageSystem.wreck_name != "":
				window_box.add_child(_row("Wrack an der Leine", [_label(SalvageSystem.wreck_name, COL_AMBER, 13)]))
				window_box.add_child(_row("Restwert beim Verschrotten", [_label("%d Cr" % SalvageSystem.hull_value(), COL_AMBER, 13)]))
				window_box.add_child(_label("Was du vorher ausbaust und einzeln verkaufst, bringt viel mehr.", COL_MUTED, 12))
				window_box.add_child(_button("Wrack verschrotten", E.scrap_hull))
				window_box.add_child(_button("Wrack untersuchen (Forensik, Figur muss auf dem Wrack sein)", func():
					station_reply = SalvageSystem.investigate(E.trader())
					GameState.toast(station_reply)))
			window_box.add_child(_button("Neues Bergungsrecht (%d Cr)" % Config.CLAIM_FEE, E.buy_claim))

func _put_terminal(type: String, qty: int) -> void:
	var c: CrewMember = GameState.selected if GameState.selected != null else CrewSystem.player()
	var t := EconomySystem.terminal()
	if c == null or t == null:
		return
	if not c.can_reach(t.pos):
		GameState.toast(c.display_name + " muss neben dem Terminal stehen.")
		return
	c.inv.move_to(t.inv, type, qty)
	_last_window = ""

# ---------------- Aktionen ----------------

func set_tool(tool: String) -> void:
	GameState.tool = tool
	for k in tool_buttons:
		tool_buttons[k].button_pressed = k == tool
	device_menu.text = ItemSystem.device(tool.substr(4)).display_name + " ▾" if tool.begins_with("dev:") else "Geräte ▾"
	var hint := ""
	for t in TOOLS:
		if t[0] == tool:
			hint = t[3]
	var c := {}
	if tool.begins_with("dev:"):
		var d := ItemSystem.device(tool.substr(4))
		hint = d.description
		c = d.cost
	elif ShipConstructionSystem.TOOL_TILE.has(tool):
		c = Config.TILE_COST[ShipConstructionSystem.TOOL_TILE[tool]]
	elif tool == "cable":
		c = Config.CABLE_COST
	if not c.is_empty():
		hint += "  " + ItemSystem.cost_text(c)
	hint_label.text = hint
	EventBus.tool_changed.emit(tool)

func toggle_help() -> void:
	help_panel.visible = not help_panel.visible

func interact() -> void:
	var p := CrewSystem.player()
	if p == null:
		return
	for src in ShipConstructionSystem.sources():
		if p.can_reach(src.pos):
			open_container(src.pos)
			return
	GameState.toast("Hier ist nichts zum Durchsuchen. Stell dich neben eine Kiste oder einen Haufen.")

func open_container(p: Vector2i) -> void:
	open_pos = p
	container_panel.visible = true
	_last_container = ""
	_refresh_container()

func close_container() -> void:
	open_pos = Vector2i(-1, -1)
	if container_panel != null:
		container_panel.visible = false

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
		GameState.toast(c.display_name + " steht nicht daneben. Geh näher heran (WASD).")
		return
	var moved := inv.move_to(c.inv, type, qty) if from_box else c.inv.move_to(inv, type, qty)
	if moved < qty:
		GameState.toast("Nicht alles passt hinein." if not from_box else c.display_name + " kann nicht mehr tragen.")
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
		task_label.text = c.task + (" · trägt " + c.carrying.data().display_name if c.carrying != null else "")
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
			lines.append("%s ×%d (%d %%)" % [ItemSystem.item(it.type).display_name, it.qty, int(it.cond)])
		inv_label.text = ("%.1f / %d kg\n" % [c.inv.weight(), int(Config.CARRY_WEIGHT)]) + ("\n".join(lines) if not lines.is_empty() else "leer")
	var goal := GoalSystem.current()
	goal_label.text = ("%s (%d/%d)" % [goal.text, GoalSystem.done.size() + 1, GoalSystem.GOALS.size()]) if not goal.is_empty() else "Alle Ziele erreicht. Mach, was du willst."
	var net := ShipPowerSystem.main_net()
	if net.is_empty():
		power_label.text = "⚡ Kein Stromnetz"
	else:
		power_label.text = "⚡ %.1f kW erzeugt · %.1f kW verbraucht · Batterie %.1f/%.0f kWh%s" % [
			net.production, net.demand, net.charge, net.capacity, "" if net.ok else " · STROMAUSFALL"]
	money_label.text = "%d Cr · Schulden %d · Rate in %.1f T · %d Baupläne" % [EconomySystem.credits, EconomySystem.debt,
		maxf(0.0, (EconomySystem.next_payment - GameState.time) / 1440.0), ShipConstructionSystem.jobs.size()]
	money_label.add_theme_color_override("font_color", COL_AMBER)
	_refresh_window()
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
		parts.append("Kabel")
	if ShipConstructionSystem.jobs.has(i):
		var job: Dictionary = ShipConstructionSystem.jobs[i]
		parts.append("Plan: " + ShipConstructionSystem.label(job) + (" (Material fehlt)" if job.get("missing", false) else ""))
	var air := AtmosphereSystem.describe(i)
	if air != "":
		parts.append(air)
	hover_label.text = " · ".join(parts) + "  [%d, %d]" % [t.x, t.y]

func _refresh_container() -> void:
	if not container_panel.visible:
		return
	var inv := _container_inv()
	var c: CrewMember = GameState.selected if GameState.selected != null else CrewSystem.player()
	var key := JSON.stringify([inv.to_data() if inv != null else [], c.inv.to_data() if c != null else []])
	if key == _last_container:
		return
	_last_container = key
	for child in container_box.get_children():
		child.queue_free()
	var head := HBoxContainer.new()
	var dev := ShipSystem.grid.device_at(open_pos)
	var title := _label(dev.data().display_name if dev != null else "Haufen auf dem Boden", COL_AMBER, 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("✕", close_container))
	container_box.add_child(head)
	if dev != null and dev.lock_level > 0:
		container_box.add_child(_label("Verschlossen (Sicherheitsstufe %d). Nötig: Hacken+Software %d (beste Figur hat %d)." % [
			dev.lock_level, int(SkillSystem.hack_needed(dev.lock_level)), int(_best_hack())], Color(0.9, 0.33, 0.29), 12))
		container_box.add_child(_button("Hacken lassen", func():
			if ShipConstructionSystem.place("hack", open_pos):
				GameState.toast("Hack-Auftrag erteilt.")))
		return
	if inv == null or inv.items.is_empty():
		container_box.add_child(_label("Leer.", COL_MUTED, 12))
	else:
		for it in inv.items:
			container_box.add_child(_item_row(it, "Nehmen", _transfer.bind(true, it.type, it.qty)))
	if c != null and dev != null and not c.inv.items.is_empty():
		container_box.add_child(_label("Aus dem Gepäck von " + c.display_name, COL_MUTED, 11))
		for it in c.inv.items:
			container_box.add_child(_item_row(it, "Hineinlegen", _transfer.bind(false, it.type, it.qty)))

func _best_hack() -> float:
	var best := 0.0
	for c in CrewSystem.crew:
		best = maxf(best, SkillSystem.hack_value(c))
	return best

func _item_row(it: Dictionary, action: String, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var d := ItemSystem.item(it.type)
	var l := _label("%s ×%d · %d %% · %.1f kg" % [d.display_name, it.qty, int(it.cond), d.weight * it.qty], Color(0.87, 0.9, 0.94), 12)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.tooltip_text = d.description
	row.add_child(l)
	row.add_child(_button(action, cb))
	return row
