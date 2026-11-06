## Baut die Benutzeroberfläche auf und hält sie aktuell.
## Die Anzeigen werden 5-mal pro Sekunde aufgefrischt (nicht jedes Bild).
extends Node

const TOOLS := [
	["select", "Auswahl", "Esc", "Klick auf den Boden: Figur läuft hin. Ziehen: Ansicht verschieben. WASD: deine Figur steuern."],
	["floor", "Boden", "B", "Klicken oder Fläche ziehen. Boden geht nur im Weltraum."],
	["wall", "Wand", "M", "Ziehen zeichnet eine Linie oder den Rand eines Rechtecks."],
	["door", "Tür", "T", "Klick auf eine Wand oder einen Boden."],
	["cable", "Kabel", "K", "Kabel verbinden Geräte mit Strom."],
	["move", "Versetzen", "V", "Vom Gerät zum Zielfeld ziehen. Ein Charakter trägt es dorthin."],
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

func _ready() -> void:
	layer = CanvasLayer.new()
	add_child(layer)
	_build_top()
	_build_left()
	_build_bottom()
	_build_toasts()
	_build_container()
	_build_help()
	EventBus.toast.connect(_on_toast)
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
	var names := ["❚❚", "1×", "10×", "60×", "300×"]
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
	row.add_child(_button("Speichern", func(): SaveSystem.save_game()))
	row.add_child(_button("Laden", func(): SaveSystem.load_game()))
	row.add_child(_button("Neues Spiel", func(): GameState.new_game()))
	row.add_child(_button("?", toggle_help))

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
	for key in [["health", "Gesundheit"], ["air", "Atmung"], ["food", "Hunger"], ["water", "Durst"], ["sleep", "Energie"], ["hygiene", "Hygiene"], ["suit_o2", "Anzug O₂"], ["suit_bat", "Anzug-Akku"]]:
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
		var b := _button("%s [%s]" % [t[1], t[2]], set_tool.bind(t[0]))
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
L / P: Luft- und Strom-Ansicht · Mausrad: zoomen · Pfeiltasten: Ansicht
Leertaste: Pause · 1–4: Geschwindigkeit · Strg+S: speichern""", Color(0.87, 0.9, 0.94), 14)
	text.custom_minimum_size = Vector2(560, 0)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	box.add_child(_button("Los geht's", func(): help_panel.visible = false))

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
	var net := ShipPowerSystem.main_net()
	if net.is_empty():
		power_label.text = "⚡ Kein Stromnetz"
	else:
		power_label.text = "⚡ %.1f kW erzeugt · %.1f kW verbraucht · Batterie %.1f/%.0f kWh%s" % [
			net.production, net.demand, net.charge, net.capacity, "" if net.ok else " · STROMAUSFALL"]
	money_label.text = "%d Baupläne offen" % ShipConstructionSystem.jobs.size()
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
	if inv == null or inv.items.is_empty():
		container_box.add_child(_label("Leer.", COL_MUTED, 12))
	else:
		for it in inv.items:
			container_box.add_child(_item_row(it, "Nehmen", _transfer.bind(true, it.type, it.qty)))
	if c != null and dev != null and not c.inv.items.is_empty():
		container_box.add_child(_label("Aus dem Gepäck von " + c.display_name, COL_MUTED, 11))
		for it in c.inv.items:
			container_box.add_child(_item_row(it, "Hineinlegen", _transfer.bind(false, it.type, it.qty)))

func _item_row(it: Dictionary, action: String, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var d := ItemSystem.item(it.type)
	var l := _label("%s ×%d · %d %% · %.1f kg" % [d.display_name, it.qty, int(it.cond), d.weight * it.qty], Color(0.87, 0.9, 0.94), 12)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.tooltip_text = d.description
	row.add_child(l)
	row.add_child(_button(action, cb))
	return row
