## Character menu, life story screen and encounter window.
## Uses the UIManager building blocks (_panel, _label, _button, _row).
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
	# The list scrolls, the buttons below always stay visible
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

## Fit the window heights to the screen (small screens, laptops)
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

# ---------------- Character menu ----------------

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
	var t: Label = ui._label("%s · %d years" % [c.display_name, c.age], ui.COL_AMBER, 17)
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
	box.add_child(ui._label("Stress: " + _stress_text(c) + (" · wages %d Cr/day" % c.salary if c.salary > 0 else "") +
		(" · last trained: " + SkillSystem.skill(c.last_trained).skill_name if c.last_trained != "" else ""), ui.COL_MUTED, 12))
	var tabs := HBoxContainer.new()
	for tb in [["skills", "Skills"], ["traits", "Traits"], ["hobbies", "Hobbies"], ["life", "Life story"], ["work", "Tasks"]]:
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
	# Exact values only if someone aboard knows Psychology
	if SkillSystem.best_effect("stress_insight") > 0.2 or c.is_player:
		return "%d %%" % int(c.stress)
	return "looks relaxed" if c.stress < 40.0 else ("looks tense" if c.stress < 75.0 else "looks worn out")

func _skills(c: CrewMember) -> void:
	if detail != "":
		_skill_detail(c, detail)
		return
	for cat in [["technik", "TECHNICAL"], ["kampf", "COMBAT"], ["praxis", "PRACTICE"], ["sozial", "SOCIAL AND MIND"]]:
		box.add_child(ui._label(cat[1], ui.COL_MUTED, 11))
		for id in SkillSystem.ids_by_category(cat[0]):
			var s: SkillData = SkillSystem.skill(id)
			var p := SkillSystem.progress(c, id)
			var row := HBoxContainer.new()
			var name_btn: Button = ui._button(s.skill_name, func():
				detail = id
				_last = ""
				refresh())
			name_btn.tooltip_text = SkillSystem.skill_tooltip(c, id)
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
			var info := "%d %%" % int(p) + ("  ✔ mastered" if p >= 100.0 else "  %d %% to go" % int(ceil(100.0 - p)))
			if not SkillSystem.requirements_met(c, id) and p >= 39.9:
				info += "  (prerequisite missing)"
			row.add_child(ui._label(info, ui.COL_AMBER if p >= 100.0 else ui.COL_MUTED, 12))
			box.add_child(row)

func _skill_detail(c: CrewMember, id: String) -> void:
	var s: SkillData = SkillSystem.skill(id)
	var p := SkillSystem.progress(c, id)
	box.add_child(ui._button("← Back", func():
		detail = ""
		_last = ""
		refresh()))
	box.add_child(ui._label(s.skill_name.to_upper(), ui.COL_AMBER, 16))
	box.add_child(_wrap(s.description))
	box.add_child(ui._label("Progress: %.1f %% · %.1f %% to go · experience %d" % [p, 100.0 - p, int(c.skills.get(id, {}).get("xp", 0.0))], Color(0.87, 0.9, 0.94), 13))
	box.add_child(ui._label("Ways to learn", ui.COL_MUTED, 11))
	box.add_child(_wrap("• " + "\n• ".join(s.learning_sources)))
	if not s.required_skills.is_empty():
		box.add_child(ui._label("Prerequisites (otherwise stops at 40 %)", ui.COL_MUTED, 11))
		for r in s.required_skills:
			var ok := SkillSystem.progress(c, r) >= float(s.required_skills[r])
			box.add_child(ui._label("%s %s: needs %d %% (has %d %%)" % ["✔" if ok else "✘", SkillSystem.skill(r).skill_name, int(s.required_skills[r]), int(SkillSystem.progress(c, r))],
				Color(0.44, 0.81, 0.56) if ok else Color(0.9, 0.33, 0.29), 12))
	box.add_child(ui._label("Current bonuses", ui.COL_MUTED, 11))
	box.add_child(_wrap("\n".join(SkillSystem.effect_lines(c, id))))
	box.add_child(ui._label("Mastery (100 %)" + (" – unlocked" if p >= 100.0 else " – still locked"), ui.COL_MUTED, 11))
	box.add_child(_wrap(s.mastery_text))
	var mali := []
	if c.stress > 70.0:
		mali.append("High stress: learns 30 % slower")
	var lf := TraitSystem.factor(c, "learn_speed")
	if lf != 1.0:
		mali.append("Traits: learning speed ×%.2f" % lf)
	if not mali.is_empty():
		box.add_child(ui._label("Learning bonuses and penalties", ui.COL_MUTED, 11))
		box.add_child(_wrap("\n".join(mali)))
	box.add_child(ui._label("Learning history", ui.COL_MUTED, 11))
	var hist: Array = c.skills.get(id, {}).get("hist", [])
	if hist.is_empty():
		box.add_child(ui._label("Not trained yet.", ui.COL_MUTED, 12))
	for h in hist:
		box.add_child(ui._label("Day %d: %s +%.2f %%" % [int(h.day), h.action, float(h.delta)], ui.COL_MUTED, 12))

func _wrap(text: String) -> Label:
	var l: Label = ui._label(text, Color(0.87, 0.9, 0.94), 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	return l

func _traits(c: CrewMember) -> void:
	box.add_child(_wrap("Traits do not change through training. They come from the life story."))
	for id in c.traits:
		var t: TraitData = TraitSystem.get_trait(id)
		box.add_child(ui._label(("＋ " if t.positive else "－ ") + t.trait_name, Color(0.44, 0.81, 0.56) if t.positive else Color(0.9, 0.33, 0.29), 14))
		var mods: PackedStringArray = []
		for k in t.modifiers:
			mods.append("%s ×%.2f" % [k, float(t.modifiers[k])])
		box.add_child(_wrap(t.description + "\n" + ", ".join(mods)))

func _hobbies(c: CrewMember) -> void:
	if c.hobbies.is_empty():
		box.add_child(ui._label("No hobbies.", ui.COL_MUTED, 12))
	for id in c.hobbies:
		var h: HobbyData = HobbySystem.get_hobby(id)
		box.add_child(ui._label(h.hobby_name, ui.COL_AMBER, 14))
		box.add_child(_wrap(h.description))

func _life(c: CrewMember) -> void:
	for line in c.history:
		box.add_child(_wrap(line))
	for other in CrewSystem.crew:
		if other != c:
			box.add_child(ui._label("Relationship with %s: %+d" % [other.display_name, int(CrewSocial.relation(c, other))], ui.COL_MUTED, 12))
	box.add_child(ui._label("Crew morale: %d %%" % int(CrewSocial.morale()), ui.COL_AMBER, 12))
	box.add_child(ui._button("Export character (for other saves)", func():
		GameState.toast("Saved: " + CrewSocial.export_character(c))))
	if not c.contacts.is_empty():
		box.add_child(ui._label("Contacts: " + ", ".join(c.contacts), Color(0.44, 0.81, 0.56), 12))
	if not c.enemies.is_empty():
		box.add_child(ui._label("Enemies: " + ", ".join(c.enemies), Color(0.9, 0.33, 0.29), 12))

func _work(c: CrewMember) -> void:
	box.add_child(_wrap("Which work does %s take on? This is how you steer what the crew learns." % c.display_name))
	var names := {"build": "Building", "repair": "Repairing", "remove": "Demolishing", "haul": "Hauling", "refill": "Refilling",
		"craft": "Workbench", "hack": "Hacking", "eva": "EVA work (space suit)"}
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
		box.add_child(ui._button("%s has a talk with %s (Psychology)" % [counselor.display_name, c.display_name], func():
			GameState.toast(DialogueSystem.counsel(counselor, c))
			_last = ""
			refresh()))

# ---------------- Life story at the start of the game ----------------

func open_creation() -> void:
	creation.visible = true
	# The controls help only comes after the life story (otherwise it lies hidden underneath)
	ui.close_help()
	TimeSystem.set_speed(0)
	refresh_creation()

func refresh_creation() -> void:
	var c := CrewSystem.player()
	_clear(creation_box)
	_clear(creation_bottom)
	_fit()
	creation_box.add_child(ui._label("LIFE STORY: %s" % c.display_name, ui.COL_AMBER, 18))
	creation_box.add_child(_wrap("You decide Mira's past. Every step costs years of life and shapes skills, traits, contacts and money. You start at 18 on an asteroid, with weak starting traits (removable for years in the grid below) and the skills Spaceship Engineering and Zero-g Ops."))
	var picked: PackedStringArray = []
	for id in CharacterSystem.course_ids():
		if CharacterSystem.course_drafted(c, id):
			var py := CharacterSystem.course_years(id)
			picked.append("%s course +%d %s" % [SkillSystem.skill(id).skill_name, py, "year" if py == 1 else "years"])
	creation_box.add_child(ui._label("Age: %d%s · start money from the life story: %+d Cr" % [CharacterSystem.preview_age(c), " (incl. " + ", ".join(picked) + ")" if not picked.is_empty() else "", CharacterSystem.start_credits(c)], Color(0.87, 0.9, 0.94), 14))
	var tr: PackedStringArray = []
	for t in c.traits:
		tr.append(TraitSystem.get_trait(t).trait_name)
	creation_box.add_child(ui._label("Traits: " + ", ".join(tr), ui.COL_MUTED, 12))
	if CharacterSystem.creation_ended(c) and c.age >= CharacterSystem.max_age:
		creation_box.add_child(ui._label("Age %d: character creation ends here. Press “Let's go”." % CharacterSystem.max_age, ui.COL_AMBER, 13))
	var top: Array = c.skills.keys()
	top.sort_custom(func(a, b): return SkillSystem.progress(c, a) > SkillSystem.progress(c, b))
	var sk: PackedStringArray = []
	for id in top.slice(0, 8):
		sk.append("%s %d %%" % [SkillSystem.skill(id).skill_name, int(SkillSystem.progress(c, id))])
	creation_box.add_child(_wrap("Best skills: " + ", ".join(sk)))
	for line in c.history:
		creation_box.add_child(ui._label(line, ui.COL_MUTED, 11))
	# Life encounter (Seek Adventure, 1 year): open encounter with answers, otherwise a button
	var pend := CharacterSystem.pending_encounter(c)
	if pend != "":
		var ev: Dictionary = CharacterSystem.encounter(pend)
		creation_box.add_child(ui._label("ENCOUNTER: " + String(ev.name).to_upper(), ui.COL_AMBER, 13))
		creation_box.add_child(_wrap(String(ev.intro)))
		for chv in ev.choices:
			var ch: Dictionary = chv
			var why := CharacterSystem.choice_block_reason(c, ch)
			var txt := ("RISK: " if ch.get("risk", false) else "") + String(ch.label)
			if int(ch.get("cash", 0)) != 0:
				txt += " (%+d Cr)" % int(ch.cash)
			var cid := String(ch.id)
			var cb: Button = ui._button(txt, func():
				CharacterSystem.resolve_encounter(c, cid)
				refresh_creation())
			cb.set_meta("choice", cid)
			cb.disabled = why != ""
			cb.tooltip_text = why if why != "" else "1 year."
			creation_box.add_child(cb)
	else:
		var why_adv := CharacterSystem.adventure_block_reason(c)
		var adv: Button = ui._button("Seek Adventure (1 year)", func():
			CharacterSystem.start_encounter(c)
			refresh_creation())
		adv.set_meta("adventure", true)
		adv.disabled = why_adv != ""
		adv.tooltip_text = why_adv if why_adv != "" else "A random life encounter. Some answers need skills or traits; RISK answers can fail."
		creation_box.add_child(adv)
		var sav: Button = ui._button("Save Some Money (1 year)", func():
			CharacterSystem.save_money(c)
			refresh_creation())
		sav.set_meta("save_money", true)
		sav.disabled = why_adv != ""
		sav.tooltip_text = why_adv if why_adv != "" else "Work and save for a year: about %d–%d Cr start money. Reliable, but little." % [CharacterSystem.SAVE_MONEY_MIN, CharacterSystem.SAVE_MONEY_MAX]
		creation_box.add_child(sav)
	# Seek Ship (Ostranauts 2.4): buy or decline the offer, buying ends creation
	var bought := CharacterSystem.ship_bought(c)
	var offer := CharacterSystem.ship_offer(c)
	if bought != "":
		var bt: Dictionary = CharacterSystem.starter_ship(bought)
		creation_box.add_child(ui._label("SHIP: %s (loan %d Cr). Character creation is done – press “Let's go”." % [bt.name, int(bt.price)], ui.COL_AMBER, 13))
	elif offer != "":
		var ot: Dictionary = CharacterSystem.starter_ship(offer)
		creation_box.add_child(ui._label("SHIP OFFER: " + String(ot.name).to_upper(), ui.COL_AMBER, 13))
		creation_box.add_child(_wrap("%s Loan: %d Cr (paid off in instalments)." % [ot.get("desc", ""), int(ot.price)]))
		var buy: Button = ui._button("Buy (take on the loan, ends character creation)", func():
			CharacterSystem.buy_ship(c)
			refresh_creation())
		buy.set_meta("ship_buy", true)
		buy.disabled = CharacterSystem.draft_balance(c) < 0
		buy.tooltip_text = "Your course and trait choices are confirmed first." if not buy.disabled else "The year balance of your drafts is negative."
		var dec: Button = ui._button("Decline", func():
			CharacterSystem.decline_ship(c)
			refresh_creation())
		dec.set_meta("ship_decline", true)
		creation_box.add_child(ui._row("", [buy, dec]))
	elif pend == "" and not CharacterSystem.creation_ended(c):
		var why_ship := CharacterSystem.adventure_block_reason(c)
		var seek_b: Button = ui._button("Seek Ship (1 year)", func():
			CharacterSystem.seek_ship(c)
			refresh_creation())
		seek_b.set_meta("seek_ship", true)
		seek_b.disabled = why_ship != ""
		seek_b.tooltip_text = why_ship if why_ship != "" else "Spend a year looking for a starter ship: Rustbucket, Shuttle Lumen or Freighter Bairn. Buying it ends character creation. Without one you start with the Rustbucket."
		creation_box.add_child(seek_b)
	creation_box.add_child(ui._label("NEXT LIFE STEP", ui.COL_MUTED, 11))
	for k in CharacterSystem.available(c):
		var gains: PackedStringArray = []
		for s in k.skills:
			gains.append(SkillSystem.skill(s).skill_name)
		for s in k.get("grants", []):
			gains.append(SkillSystem.skill(s).skill_name + " (acquired)")
		var kb: Button = ui._button("Choose", func():
			CharacterSystem.apply_career(c, k.id)
			refresh_creation())
		kb.disabled = pend != ""
		creation_box.add_child(ui._row("%s (%d years): %s" % [k.name, int(k.years), ", ".join(gains)], [kb]))
	# Courses: only count when confirming ("Let's go"), until then only in the preview age
	const COURSE_TEXT := {"business": "exact Item Value when trading", "civil": "+4 work value on appliances, controls, furniture, climate & ventilation, miscellaneous",
		"combat_eng": "+4 work value on appliances, controls, furniture, climate & ventilation, sensors, weapons",
		"construction": "faster building, sometimes saves material",
		"electrical": "+4 work value on appliances, controls, power systems, sensors",
		"eva": "no EVA work penalty, +4 work value on suit equipment",
		"excavation": "+4 work value on mining",
		"robotics": "+4 work value on controls and sensors",
		"software": "+4 work value on software work (debugging)",
		"spaceship": "+4 work value on ship structure work",
		"mechanical": "+4 work value on appliances, controls, furniture, climate & ventilation, miscellaneous",
		"pilot": "Piloting +0.5 at the helm (docking limits, RCS thrust, turn rate)",
		"zerog": "skill check flag, no numeric modifier"}
	for id in CharacterSystem.course_ids():
		if SkillSystem.skill(id).is_hobby:
			continue   # Hobbies: their own row below
		var course := CharacterSystem.course_drafted(c, id)
		var years := CharacterSystem.course_years(id)
		if not course and (CharacterSystem.preview_age(c) + years > CharacterSystem.max_age or SkillSystem.acquired(c, id)):
			continue
		var crow: HBoxContainer = ui._row("%s course (%d %s): %s%s" % [SkillSystem.skill(id).skill_name, years, "year" if years == 1 else "years", COURSE_TEXT.get(id, SkillSystem.skill(id).description), " · selected" if course else ""],
			[ui._button("Remove" if course else "Add", func():
				CharacterSystem.set_course(c, not course, id)
				refresh_creation())])
		crow.set_meta("course", id)
		crow.tooltip_text = SkillSystem.skill_tooltip(c, id)
		creation_box.add_child(crow)
	# Hobbies (Ostranauts 2.2.2): compact row, same course logic (years in the preview age)
	creation_box.add_child(ui._label("HOBBIES (skills, cost years)", ui.COL_MUTED, 11))
	var hflow := HFlowContainer.new()
	for hv in CharacterSystem.course_ids():
		var hid: String = hv
		var hs: SkillData = SkillSystem.skill(hid)
		if not hs.is_hobby:
			continue
		var drafted: bool = CharacterSystem.course_drafted(c, hid)
		var have: bool = SkillSystem.acquired(c, hid)
		var hb: Button = ui._button(("✔ " if have else ("+ " if drafted else "")) + hs.skill_name + (" (+%d)" % hs.course_years if not have else ""), func():
			CharacterSystem.set_course(c, not CharacterSystem.course_drafted(c, hid), hid)
			refresh_creation())
		hb.set_meta("hobby_course", hid)
		hb.add_theme_font_size_override("font_size", 11)
		hb.disabled = have or (not drafted and CharacterSystem.preview_age(c) + hs.course_years > CharacterSystem.max_age)
		hb.tooltip_text = SkillSystem.skill_tooltip(c, hid)
		hflow.add_child(hb)
	creation_box.add_child(hflow)
	# Tweaking traits (Ostranauts "Tweak Skills & Traits"): positive ones cost years, negative ones give years back
	var bal := CharacterSystem.draft_balance(c)
	creation_box.add_child(ui._label("TRAITS · draft balance %+d %s%s" % [bal, "year" if absi(bal) == 1 else "years", " – must not be negative" if bal < 0 else ""],
		Color(0.9, 0.33, 0.29) if bal < 0 else ui.COL_MUTED, 11))
	var tflow := HFlowContainer.new()
	tflow.set_meta("traits", true)
	for tv in TraitSystem.ordered_ids():
		var tid: String = tv
		var td: TraitData = TraitSystem.get_trait(tid)
		var have: bool = tid in c.traits
		var adding: bool = tid in CharacterSystem.trait_adds(c)
		var removing: bool = tid in CharacterSystem.trait_removes(c)
		var label := ("✔ " if have and not removing else ("+ " if adding else ("✘ " if removing else ""))) + td.trait_name + " (%+d)" % td.cost
		var why := CharacterSystem.trait_block_reason(c, tid)
		var tb: Button = ui._button(label, func():
			CharacterSystem.toggle_trait(c, tid)
			refresh_creation())
		tb.set_meta("trait", tid)
		tb.add_theme_font_size_override("font_size", 11)
		tb.disabled = why != ""
		tb.tooltip_text = TraitSystem.tooltip(tid) + ("\n" + why if why != "" else "")
		tflow.add_child(tb)
	creation_box.add_child(tflow)
	if c.hobbies.size() < 2:
		var row := HFlowContainer.new()
		row.add_child(ui._label("Choose hobby: ", ui.COL_MUTED, 12))
		for id in HobbySystem.hobbies:
			if not id in c.hobbies:
				row.add_child(ui._button(HobbySystem.get_hobby(id).hobby_name, func():
					CharacterSystem.choose_hobby(c, id)
					refresh_creation()))
		creation_box.add_child(row)
	var imports := CrewSocial.exported_list()
	if not imports.is_empty():
		var irow := HFlowContainer.new()
		irow.add_child(ui._label("Use saved character: ", ui.COL_MUTED, 12))
		for file in imports:
			irow.add_child(ui._button(file.trim_suffix(".json").replace("_", " "), func():
				CrewSocial.import_character(file)
				refresh_creation()))
		creation_box.add_child(irow)
	var bottom := creation_bottom
	bottom.add_child(ui._button("Start over", func():
		CharacterSystem.begin(c)
		refresh_creation()))
	bottom.add_child(ui._button("Random life story", func():
		CharacterSystem.randomize_life(c, randi_range(22, 35))
		refresh_creation()))
	var go: Button = ui._button("Let's go", func():
		CharacterSystem.confirm(c)
		EconomySystem.credits = Config.START_CREDITS + CharacterSystem.start_credits(c)
		FleetSystem.start_with(CharacterSystem.ship_bought(c))
		creation.visible = false
		ui.show_help()
		TimeSystem.set_speed(1))
	go.disabled = CharacterSystem.preview_age(c) < 18 or CharacterSystem.draft_balance(c) < 0 or CharacterSystem.pending_encounter(c) != "" or CharacterSystem.ship_offer(c) != ""
	bottom.add_child(go)

# ---------------- Encounter with plunderers ----------------

func show_encounter(result: String = "") -> void:
	encounter_panel.visible = true
	_clear(encounter_box)
	encounter_box.add_child(ui._label("PLUNDERERS!", Color(0.9, 0.33, 0.29), 18))
	if result != "":
		encounter_box.add_child(_wrap(result))
		encounter_box.add_child(ui._button("Continue", func():
			encounter_panel.visible = false
			TimeSystem.set_speed(1)))
		return
	var power := 0.0
	var names: PackedStringArray = []
	for c in NPCSystem.fighters():
		power += SkillSystem.combat_power(c)
		names.append(c.display_name)
	encounter_box.add_child(_wrap("An armed squad docks and demands %d Cr. Your fighters: %s (combat strength %d against about %d)." % [
		int(NPCSystem.encounter.demand), ", ".join(names), int(power), int(NPCSystem.encounter.strength)]))
	encounter_box.add_child(ui._button("Fight", func(): show_encounter(NPCSystem.fight())))
	encounter_box.add_child(ui._button("Negotiate (Persuasion, Street Etiquette)", func(): show_encounter(NPCSystem.negotiate())))
	encounter_box.add_child(ui._button("Pay (%d Cr)" % int(NPCSystem.encounter.demand), func(): show_encounter(NPCSystem.pay())))
