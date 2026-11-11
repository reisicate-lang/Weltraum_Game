## Charaktermenü, Lebenslauf-Bildschirm und Begegnungs-Fenster.
## Nutzt die Bausteine des UIManager (_panel, _label, _button, _row).
extends Node

var ui  ## UIManager
var panel: PanelContainer
var box: VBoxContainer
var tab := "skills"
var detail := ""
var _last := ""
var creation: PanelContainer
var creation_box: VBoxContainer
var creation_scroll: ScrollContainer
var creation_bottom: HBoxContainer
var char_scroll: ScrollContainer
var encounter_panel: PanelContainer
var encounter_box: VBoxContainer

func setup(manager) -> void:
	ui = manager
	panel = _big_panel()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	creation = _big_panel()
	# Liste scrollt, die Knöpfe darunter bleiben immer sichtbar
	var outer := VBoxContainer.new()
	creation.add_child(outer)
	creation_scroll = ScrollContainer.new()
	creation_scroll.custom_minimum_size = Vector2(760, 640)
	creation_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(creation_scroll)
	creation_box = VBoxContainer.new()
	creation_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creation_scroll.add_child(creation_box)
	creation_bottom = HBoxContainer.new()
	outer.add_child(creation_bottom)
	char_scroll = scroll
	encounter_panel = _big_panel()
	encounter_box = VBoxContainer.new()
	encounter_box.custom_minimum_size = Vector2(460, 0)
	encounter_panel.add_child(encounter_box)
	NPCSystem.encounter_started.connect(func(_e): show_encounter())

func _big_panel() -> PanelContainer:
	var p: PanelContainer = ui._panel()
	(p.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color(0.05, 0.07, 0.106, 0.98)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.visible = false
	ui.layer.add_child(p)
	return p

## Fensterhöhen an den Bildschirm anpassen (kleine Bildschirme, Laptops)
func _fit() -> void:
	var h: float = ui.get_viewport().get_visible_rect().size.y
	if creation_scroll != null:
		creation_scroll.custom_minimum_size.y = clampf(h - 160.0, 200.0, 640.0)
		creation.reset_size()
		creation.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	if char_scroll != null:
		char_scroll.custom_minimum_size.y = clampf(h - 120.0, 200.0, 600.0)
		panel.reset_size()
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

func _clear(b: Container) -> void:
	for ch in b.get_children():
		ch.queue_free()

func _sel() -> CrewMember:
	return GameState.selected if GameState.selected != null else CrewSystem.player()

# ---------------- Charaktermenü ----------------

func toggle() -> void:
	panel.visible = not panel.visible
	_fit()
	_last = ""
	refresh()

func refresh() -> void:
	if not panel.visible:
		return
	var c := _sel()
	if c == null:
		return
	var key := JSON.stringify([tab, detail, c.id, c.skills, c.traits, c.hobbies, int(c.stress), c.work_prefs, CrewSystem.crew.size()])
	if key == _last:
		return
	_last = key
	_clear(box)
	var head := HBoxContainer.new()
	var t: Label = ui._label("%s · %d Jahre" % [c.display_name, c.age], ui.COL_AMBER, 17)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	for other in CrewSystem.crew:
		if other != c:
			head.add_child(ui._button(other.display_name.split(" ")[0], func():
				GameState.selected = other
				_last = ""
				refresh()))
	head.add_child(ui._button("✕", toggle))
	box.add_child(head)
	box.add_child(ui._label("Stress: " + _stress_text(c) + (" · Lohn %d Cr/Tag" % c.salary if c.salary > 0 else "") +
		(" · zuletzt trainiert: " + SkillSystem.skill(c.last_trained).skill_name if c.last_trained != "" else ""), ui.COL_MUTED, 12))
	var tabs := HBoxContainer.new()
	for tb in [["skills", "Fähigkeiten"], ["traits", "Eigenschaften"], ["hobbies", "Hobbys"], ["life", "Lebenslauf"], ["work", "Aufgaben"]]:
		var b: Button = ui._button(tb[1], func():
			tab = tb[0]
			detail = ""
			_last = ""
			refresh())
		b.toggle_mode = true
		b.button_pressed = tab == tb[0]
		tabs.add_child(b)
	box.add_child(tabs)
	match tab:
		"skills": _skills(c)
		"traits": _traits(c)
		"hobbies": _hobbies(c)
		"life": _life(c)
		"work": _work(c)

func _stress_text(c: CrewMember) -> String:
	# Genaue Werte nur, wenn jemand an Bord sich mit Psychologie auskennt
	if SkillSystem.best_effect("stress_insight") > 0.2 or c.is_player:
		return "%d %%" % int(c.stress)
	return "wirkt entspannt" if c.stress < 40.0 else ("wirkt angespannt" if c.stress < 75.0 else "wirkt am Ende")

func _skills(c: CrewMember) -> void:
	if detail != "":
		_skill_detail(c, detail)
		return
	for cat in [["technik", "TECHNIK"], ["kampf", "KAMPF"], ["praxis", "PRAXIS"], ["sozial", "SOZIALES UND GEIST"]]:
		box.add_child(ui._label(cat[1], ui.COL_MUTED, 11))
		for id in SkillSystem.ids_by_category(cat[0]):
			var s: SkillData = SkillSystem.skill(id)
			var p := SkillSystem.progress(c, id)
			var row := HBoxContainer.new()
			var name_btn: Button = ui._button(s.skill_name, func():
				detail = id
				_last = ""
				refresh())
			name_btn.custom_minimum_size = Vector2(200, 0)
			name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			name_btn.add_theme_font_size_override("font_size", 12)
			row.add_child(name_btn)
			var bar := ProgressBar.new()
			bar.max_value = 100.0
			bar.value = p
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(180, 10)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var fill := StyleBoxFlat.new()
			fill.bg_color = Color(0.95, 0.64, 0.23) if p >= 100.0 else Color(0.35, 0.78, 0.9)
			bar.add_theme_stylebox_override("fill", fill)
			var bg := StyleBoxFlat.new()
			bg.bg_color = Color(0.1, 0.13, 0.19)
			bar.add_theme_stylebox_override("background", bg)
			row.add_child(bar)
			var info := "%d %%" % int(p) + ("  ✔ gemeistert" if p >= 100.0 else "  fehlt %d %%" % int(ceil(100.0 - p)))
			if not SkillSystem.requirements_met(c, id) and p >= 39.9:
				info += "  (Voraussetzung fehlt)"
			row.add_child(ui._label(info, ui.COL_AMBER if p >= 100.0 else ui.COL_MUTED, 12))
			box.add_child(row)

func _skill_detail(c: CrewMember, id: String) -> void:
	var s: SkillData = SkillSystem.skill(id)
	var p := SkillSystem.progress(c, id)
	box.add_child(ui._button("← Zurück", func():
		detail = ""
		_last = ""
		refresh()))
	box.add_child(ui._label(s.skill_name.to_upper(), ui.COL_AMBER, 16))
	box.add_child(_wrap(s.description))
	box.add_child(ui._label("Fortschritt: %.1f %% · fehlt %.1f %% · Erfahrung %d" % [p, 100.0 - p, int(c.skills.get(id, {}).get("xp", 0.0))], Color(0.87, 0.9, 0.94), 13))
	box.add_child(ui._label("Lernquellen", ui.COL_MUTED, 11))
	box.add_child(_wrap("• " + "\n• ".join(s.learning_sources)))
	if not s.required_skills.is_empty():
		box.add_child(ui._label("Voraussetzungen (sonst Stopp bei 40 %)", ui.COL_MUTED, 11))
		for r in s.required_skills:
			var ok := SkillSystem.progress(c, r) >= float(s.required_skills[r])
			box.add_child(ui._label("%s %s: %d %% nötig (hat %d %%)" % ["✔" if ok else "✘", SkillSystem.skill(r).skill_name, int(s.required_skills[r]), int(SkillSystem.progress(c, r))],
				Color(0.44, 0.81, 0.56) if ok else Color(0.9, 0.33, 0.29), 12))
	box.add_child(ui._label("Aktuelle Boni", ui.COL_MUTED, 11))
	box.add_child(_wrap("\n".join(SkillSystem.effect_lines(c, id))))
	box.add_child(ui._label("Meisterschaft (100 %)" + (" – freigeschaltet" if p >= 100.0 else " – noch gesperrt"), ui.COL_MUTED, 11))
	box.add_child(_wrap(s.mastery_text))
	var mali := []
	if c.stress > 70.0:
		mali.append("Hoher Stress: lernt 30 % langsamer")
	var lf := TraitSystem.factor(c, "learn_speed")
	if lf != 1.0:
		mali.append("Eigenschaften: Lerntempo ×%.2f" % lf)
	if not mali.is_empty():
		box.add_child(ui._label("Boni und Mali beim Lernen", ui.COL_MUTED, 11))
		box.add_child(_wrap("\n".join(mali)))
	box.add_child(ui._label("Lernhistorie", ui.COL_MUTED, 11))
	var hist: Array = c.skills.get(id, {}).get("hist", [])
	if hist.is_empty():
		box.add_child(ui._label("Noch nicht trainiert.", ui.COL_MUTED, 12))
	for h in hist:
		box.add_child(ui._label("Tag %d: %s +%.2f %%" % [int(h.day), h.action, float(h.delta)], ui.COL_MUTED, 12))

func _wrap(text: String) -> Label:
	var l: Label = ui._label(text, Color(0.87, 0.9, 0.94), 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	return l

func _traits(c: CrewMember) -> void:
	box.add_child(_wrap("Eigenschaften ändern sich nicht durch Training. Sie entstehen im Lebenslauf."))
	for id in c.traits:
		var t: TraitData = TraitSystem.get_trait(id)
		box.add_child(ui._label(("＋ " if t.positive else "－ ") + t.trait_name, Color(0.44, 0.81, 0.56) if t.positive else Color(0.9, 0.33, 0.29), 14))
		var mods: PackedStringArray = []
		for k in t.modifiers:
			mods.append("%s ×%.2f" % [k, float(t.modifiers[k])])
		box.add_child(_wrap(t.description + "\n" + ", ".join(mods)))

func _hobbies(c: CrewMember) -> void:
	if c.hobbies.is_empty():
		box.add_child(ui._label("Keine Hobbys.", ui.COL_MUTED, 12))
	for id in c.hobbies:
		var h: HobbyData = HobbySystem.get_hobby(id)
		box.add_child(ui._label(h.hobby_name, ui.COL_AMBER, 14))
		box.add_child(_wrap(h.description))

func _life(c: CrewMember) -> void:
	for line in c.history:
		box.add_child(_wrap(line))
	for other in CrewSystem.crew:
		if other != c:
			box.add_child(ui._label("Beziehung zu %s: %+d" % [other.display_name, int(CrewSocial.relation(c, other))], ui.COL_MUTED, 12))
	box.add_child(ui._label("Moral der Crew: %d %%" % int(CrewSocial.morale()), ui.COL_AMBER, 12))
	box.add_child(ui._button("Charakter exportieren (für andere Spielstände)", func():
		GameState.toast("Gespeichert: " + CrewSocial.export_character(c))))
	if not c.contacts.is_empty():
		box.add_child(ui._label("Kontakte: " + ", ".join(c.contacts), Color(0.44, 0.81, 0.56), 12))
	if not c.enemies.is_empty():
		box.add_child(ui._label("Feinde: " + ", ".join(c.enemies), Color(0.9, 0.33, 0.29), 12))

func _work(c: CrewMember) -> void:
	box.add_child(_wrap("Welche Arbeiten übernimmt %s? So steuerst du, was die Crew lernt." % c.display_name))
	var names := {"build": "Bauen", "repair": "Reparieren", "remove": "Abreißen", "haul": "Einsammeln und Tragen", "refill": "Nachfüllen",
		"craft": "Werkbank", "hack": "Hacken", "eva": "Außeneinsätze (Raumanzug)"}
	for k in names:
		var cb := CheckBox.new()
		cb.text = names[k]
		cb.button_pressed = c.work_prefs.get(k, true)
		cb.toggled.connect(func(on): c.work_prefs[k] = on)
		box.add_child(cb)
	var counselor: CrewMember = null
	for other in CrewSystem.crew:
		if other != c and (counselor == null or SkillSystem.progress(other, "psychology") > SkillSystem.progress(counselor, "psychology")):
			counselor = other
	if counselor != null:
		box.add_child(ui._button("%s führt ein Gespräch mit %s (Psychologie)" % [counselor.display_name, c.display_name], func():
			GameState.toast(DialogueSystem.counsel(counselor, c))
			_last = ""
			refresh()))

# ---------------- Lebenslauf zu Spielbeginn ----------------

func open_creation() -> void:
	creation.visible = true
	# Die Steuerungshilfe kommt erst nach dem Lebenslauf (sonst liegt sie verdeckt darunter)
	ui.close_help()
	TimeSystem.set_speed(0)
	refresh_creation()

func refresh_creation() -> void:
	var c := CrewSystem.player()
	_clear(creation_box)
	_clear(creation_bottom)
	_fit()
	creation_box.add_child(ui._label("LEBENSLAUF: %s" % c.display_name, ui.COL_AMBER, 18))
	creation_box.add_child(_wrap("Du bestimmst Miras Vergangenheit. Jede Station kostet Lebensjahre und prägt Fähigkeiten, Eigenschaften, Kontakte und Geld. Mit mindestens 18 Jahren kann es losgehen."))
	var course := CharacterSystem.course_drafted(c)
	creation_box.add_child(ui._label("Alter: %d%s · Startgeld aus dem Lebenslauf: %+d Cr" % [CharacterSystem.preview_age(c), " (incl. Business Admin course +%d years)" % CharacterSystem.COURSE_YEARS if course else "", CharacterSystem.start_credits(c)], Color(0.87, 0.9, 0.94), 14))
	var tr: PackedStringArray = []
	for t in c.traits:
		tr.append(TraitSystem.get_trait(t).trait_name)
	creation_box.add_child(ui._label("Eigenschaften: " + ", ".join(tr), ui.COL_MUTED, 12))
	var top: Array = c.skills.keys()
	top.sort_custom(func(a, b): return SkillSystem.progress(c, a) > SkillSystem.progress(c, b))
	var sk: PackedStringArray = []
	for id in top.slice(0, 8):
		sk.append("%s %d %%" % [SkillSystem.skill(id).skill_name, int(SkillSystem.progress(c, id))])
	creation_box.add_child(_wrap("Beste Fähigkeiten: " + ", ".join(sk)))
	for line in c.history:
		creation_box.add_child(ui._label(line, ui.COL_MUTED, 11))
	creation_box.add_child(ui._label("NÄCHSTE LEBENSSTATION", ui.COL_MUTED, 11))
	for k in CharacterSystem.available(c):
		var gains: PackedStringArray = []
		for s in k.skills:
			gains.append(SkillSystem.skill(s).skill_name)
		creation_box.add_child(ui._row("%s (%d Jahre): %s" % [k.name, int(k.years), ", ".join(gains)],
			[ui._button("Wählen", func():
				CharacterSystem.apply_career(c, k.id)
				refresh_creation())]))
	# Kurs: zählt erst beim Bestätigen (Los geht's), bis dahin nur im Vorschaualter
	if course or CharacterSystem.preview_age(c) + CharacterSystem.COURSE_YEARS <= CharacterSystem.max_age and not SkillSystem.acquired(c, SkillSystem.BUSINESS):
		creation_box.add_child(ui._row("Business Admin course (%d years): exact Item Value when trading%s" % [CharacterSystem.COURSE_YEARS, " · selected" if course else ""],
			[ui._button("Remove" if course else "Add", func():
				CharacterSystem.set_course(c, not course)
				refresh_creation())]))
	if c.hobbies.size() < 2:
		var row := HFlowContainer.new()
		row.add_child(ui._label("Hobby wählen: ", ui.COL_MUTED, 12))
		for id in HobbySystem.hobbies:
			if not id in c.hobbies:
				row.add_child(ui._button(HobbySystem.get_hobby(id).hobby_name, func():
					CharacterSystem.choose_hobby(c, id)
					refresh_creation()))
		creation_box.add_child(row)
	var imports := CrewSocial.exported_list()
	if not imports.is_empty():
		var irow := HFlowContainer.new()
		irow.add_child(ui._label("Gespeicherten Charakter übernehmen: ", ui.COL_MUTED, 12))
		for file in imports:
			irow.add_child(ui._button(file.trim_suffix(".json").replace("_", " "), func():
				CrewSocial.import_character(file)
				refresh_creation()))
		creation_box.add_child(irow)
	var bottom := creation_bottom
	bottom.add_child(ui._button("Von vorn", func():
		CharacterSystem.begin(c)
		refresh_creation()))
	bottom.add_child(ui._button("Zufälliger Lebenslauf", func():
		CharacterSystem.randomize_life(c, randi_range(22, 35))
		refresh_creation()))
	var go: Button = ui._button("Los geht's", func():
		CharacterSystem.confirm(c)
		EconomySystem.credits = Config.START_CREDITS + CharacterSystem.start_credits(c)
		creation.visible = false
		ui.show_help()
		TimeSystem.set_speed(1))
	go.disabled = CharacterSystem.preview_age(c) < 18
	bottom.add_child(go)

# ---------------- Begegnung mit Plünderern ----------------

func show_encounter(result: String = "") -> void:
	encounter_panel.visible = true
	_clear(encounter_box)
	encounter_box.add_child(ui._label("PLÜNDERER!", Color(0.9, 0.33, 0.29), 18))
	if result != "":
		encounter_box.add_child(_wrap(result))
		encounter_box.add_child(ui._button("Weiter", func():
			encounter_panel.visible = false
			TimeSystem.set_speed(1)))
		return
	var power := 0.0
	var names: PackedStringArray = []
	for c in NPCSystem.fighters():
		power += SkillSystem.combat_power(c)
		names.append(c.display_name)
	encounter_box.add_child(_wrap("Ein bewaffneter Trupp dockt an und verlangt %d Cr. Deine Kämpfer: %s (Kampfkraft %d gegen etwa %d)." % [
		int(NPCSystem.encounter.demand), ", ".join(names), int(power), int(NPCSystem.encounter.strength)]))
	encounter_box.add_child(ui._button("Kämpfen", func(): show_encounter(NPCSystem.fight())))
	encounter_box.add_child(ui._button("Verhandeln (Überzeugen, Straßenetikette)", func(): show_encounter(NPCSystem.negotiate())))
	encounter_box.add_child(ui._button("Bezahlen (%d Cr)" % int(NPCSystem.encounter.demand), func(): show_encounter(NPCSystem.pay())))
