## Tests: Traits nach Ostranauts (73 Traits, Jahreskosten, Gegenstücke, Auswahl im Lebenslauf, alte Stände)
##   godot --headless --path . --script res://tests/boot.gd -- test_traits
extends "res://tests/test_base.gd"

const OLD_SAVE := "res://tests/fixtures/old_save_blueports.json"

var ok_count := 0
var fail_count := 0
var gs
var ui
var TS
var SK
var CHS
var save

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _trait_button(id: String) -> Button:
	for row in ui.char_ui.creation_box.get_children():
		if row.is_queued_for_deletion() or not row.has_meta("traits"):
			continue
		for b in row.get_children():
			if b is Button and b.get_meta("trait", "") == id:
				return b
	return null

func _press(id: String) -> bool:
	var b := _trait_button(id)
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	await process_frame
	return true

func _fresh() -> CrewMember:
	var c := CrewMember.new(500 + randi() % 1000, "Test", Color.WHITE, Vector2i.ZERO)
	CHS.begin(c)
	c.traits.clear()
	CHS.apply_career(c, "school")
	return c

func _initialize() -> void:
	await process_frame
	await process_frame
	gs = root.get_node("GameState")
	ui = root.get_node("UIManager")
	TS = root.get_node("TraitSystem")
	SK = root.get_node("SkillSystem")
	CHS = root.get_node("CharacterSystem")
	save = root.get_node("SaveSystem")
	save.slot = 936
	root.get_node("Settings").meteors = false
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.close_help()

	# 1) Daten: 73 Traits mit Kosten und Gegenstücken wie im Wiki-Index
	_check("73 Traits geladen (%d)" % TS.traits.size(), TS.traits.size() == 73)
	var by_cost := {}
	var sym := true
	for id in TS.traits:
		var t: TraitData = TS.traits[id]
		by_cost[t.cost] = int(by_cost.get(t.cost, 0)) + 1
		if t.opposite != "" and (TS.get_trait(t.opposite) == null or TS.get_trait(t.opposite).opposite != id):
			sym = false
	_check("Jahreskosten wie im Index (%s)" % str(by_cost), by_cost == {3: 8, 2: 5, 1: 19, -1: 26, -2: 7, -3: 8})
	_check("Gegenstücke gegenseitig", sym)
	var sample := {"strong": [2, "feeble"], "feeble": [-2, "strong"], "genius": [3, "obtuse"], "insomniac": [-2, ""], "heavy_sleeper": [-1, "light_sleeper"], "chaste": [-2, "lustful"], "visually_impaired": [-1, ""]}
	var ok_sample := true
	for id in sample:
		var t: TraitData = TS.get_trait(id)
		if t == null or t.cost != sample[id][0] or t.opposite != sample[id][1]:
			ok_sample = false
			print("        falsch: %s" % id)
	_check("Stichproben (Kosten, Gegenstück) wie im Wiki", ok_sample)
	_check("Reihenfolge wie im Wiki (Ambitious zuerst, Visually Impaired zuletzt)", TS.ordered_ids()[0] == "ambitious" and TS.ordered_ids()[-1] == "visually_impaired")
	var tip: String = TS.tooltip("strong")
	_check("Tooltip: Kosten, Gegenstück, Wirkung im Spiel, Wiki-Text (%s)" % tip.replace("\n", " | "), "+2 years" in tip and "Opposite: Feeble" in tip and "In game: Combat power +25 %" in tip and "Wiki: G-tol" in tip)
	_check("Tooltip eines reinen Flags sagt das", "no gameplay effect yet" in TS.tooltip("beautiful"))

	# 2) Alte eigene Traits werden umgestellt
	var legacy := {"calm": "brave", "distracted": "obtuse", "frugal": "slow_metabolism", "hardy": "tough", "introvert": "shy", "lazy": "complacent",
		"nervous": "craven", "nimble": "coordinated", "smart": "genius", "social": "gregarious", "weak": "feeble",
		"ambitious": "ambitious", "clumsy": "clumsy", "fragile": "fragile", "glutton": "glutton", "strong": "strong"}
	var mig_ok := true
	for old in legacy:
		if TS.migrate([old]) != [legacy[old]]:
			mig_ok = false
			print("        %s → %s" % [old, str(TS.migrate([old]))])
	_check("Alle 16 alten Traits abgebildet", mig_ok)
	_check("Dopplungen nach dem Umstellen entfernt", TS.migrate(["smart", "genius", "unknown_x"]) == ["genius"])
	var dd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(dd))
	f.close()
	gs.new_game()
	_check("Alter Spielstand geladen", save.load_game(true))
	var mira: CrewMember = root.get_node("CrewSystem").player()
	_check("Alter Trait nimble ist jetzt Coordinated (%s)" % str(mira.traits), mira.traits == ["coordinated"] and is_equal_approx(TS.sum(mira, "piloting"), 0.1) and is_equal_approx(TS.factor(mira, "work_fine"), 1.2))
	var unknown := []
	var careers: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/careers.json"))
	for coll in [careers.careers, careers.get("events", [])]:
		for e in coll:
			for k in ["traits_add", "traits_remove"]:
				for t in e.get(k, []):
					if TS.get_trait(t) == null or TS.resolve(t) != t:
						unknown.append(t)
	_check("Lebensstationen und Ereignisse nutzen die neuen IDs (%s)" % str(unknown), unknown.is_empty())

	# 3) Regeln im Lebenslauf (Stationen, Ereignisse): positiver Trait löst negatives Gegenstück ab
	var c := _fresh()
	TS.add(c, "fragile")
	_check("Tough bekommen, während Fragile da ist: Fragile weg, Tough nicht dazu", TS.add(c, "tough") and not "fragile" in c.traits and not "tough" in c.traits)
	TS.add(c, "brave")
	_check("Craven (negativ) gegen vorhandenes Brave: nicht vergeben", not TS.add(c, "craven") and "brave" in c.traits and not "craven" in c.traits)

	# 4) Auswahl im Entwurf (über die Knöpfe im Lebenslauf)
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	mira = root.get_node("CrewSystem").player()
	CHS.begin(mira)
	mira.traits.assign(["fragile"])   # Start mit einem negativen Trait
	CHS.apply_career(mira, "school")
	var cui = ui.char_ui
	cui.open_creation()
	await process_frame
	var base: int = mira.age
	_check("4: Alle 73 Trait-Knöpfe im Lebenslauf", TS.ordered_ids().all(func(id): return _trait_button(id) != null))
	_check("4: Brave (+2) wählen: Vorschau +2", await _press("brave") and CHS.preview_age(mira) == base + 2 and mira.age == base)
	_check("4: Brave wieder abwählen: Vorschau −2", await _press("brave") and CHS.preview_age(mira) == base)
	_check("4: Tough gesperrt, solange Fragile da ist (%s)" % _trait_button("tough").tooltip_text.get_slice("\n", _trait_button("tough").tooltip_text.get_slice_count("\n") - 1), _trait_button("tough").disabled and "Remove Fragile first." in _trait_button("tough").tooltip_text)
	_check("4: Fragile (−1) entfernen kostet 1 Jahr", await _press("fragile") and CHS.preview_age(mira) == base + 1)
	_check("4: Danach Tough (+1) wählbar: Vorschau +2", await _press("tough") and CHS.preview_age(mira) == base + 2)
	_check("4: Slovenly (−1) gibt 1 Jahr zurück: Vorschau +1", await _press("slovenly") and CHS.preview_age(mira) == base + 1)
	_check("4: Gegenstück im Entwurf gesperrt (Tidy, weil Slovenly gewählt)", _trait_button("tidy").disabled)
	var hist0: int = mira.history.size()
	_check("4: Bestätigen", CHS.confirm(mira))
	_check("4: Alter +1 genau einmal, Traits übernommen (%s)" % str(mira.traits), mira.age == base + 1 and "tough" in mira.traits and "slovenly" in mira.traits and not "fragile" in mira.traits and mira.history.size() == hist0 + 1)
	_check("4: Zweites Bestätigen ändert nichts", CHS.confirm(mira) and mira.age == base + 1 and mira.history.size() == hist0 + 1)
	# Negative Bilanz: nur einen negativen Trait wählen
	cui.refresh_creation()
	await process_frame
	var age1: int = mira.age
	await _press("ugly")
	_check("4: Nur Ugly (−1): Bilanz −1, Los geht's gesperrt", CHS.draft_balance(mira) == -1 and _find_go().disabled)
	_check("4: Negative Bilanz wird nicht übernommen", not CHS.confirm(mira) and mira.age == age1 and not "ugly" in mira.traits)
	await _press("genius")
	_check("4: Mit Genius (+3) Bilanz +2, Los geht's frei", CHS.draft_balance(mira) == 2 and not _find_go().disabled)
	CHS.toggle_trait(mira, "genius")
	CHS.toggle_trait(mira, "ugly")
	cui.creation.visible = false

	# 5) Wirkungen im Spiel
	var a := CrewMember.new(701, "A", Color.WHITE, Vector2i.ZERO)
	var b := CrewMember.new(702, "B", Color.WHITE, Vector2i.ZERO)
	TS.add(b, "slow_metabolism")
	_check("5: Slow Metabolism: Essen und Wasser −25 %", is_equal_approx(TS.factor(b, "hunger"), 0.75) and is_equal_approx(TS.factor(b, "thirst"), 0.75))
	var mh := CrewMember.new(703, "C", Color.WHITE, Vector2i.ZERO)
	TS.add(mh, "micro_g_hypovolemic")
	_check("5: Micro-g Hypovolemic: Essen und Wasser +15 %", is_equal_approx(TS.factor(mh, "hunger"), 1.15) and is_equal_approx(TS.factor(mh, "thirst"), 1.15))
	var vi := CrewMember.new(704, "D", Color.WHITE, Vector2i.ZERO)
	TS.add(vi, "visually_impaired")
	TS.add(vi, "coordinated")
	_check("5: Piloting aus Traits: Coordinated +0,1, Visually Impaired −0,2 (%.2f)" % SK.piloting(vi), is_equal_approx(SK.piloting(vi), -0.1))
	var ins := CrewMember.new(705, "E", Color.WHITE, Vector2i.ZERO)
	TS.add(ins, "insomniac")
	_check("5: Insomniac schläft schlechter (Erholung ×0,75)", is_equal_approx(TS.factor(ins, "sleep_gain"), 0.75))
	# Durst im Spielablauf: gleiche Zeit, B (Slow Metabolism) verliert weniger Wasser
	gs.new_game()
	var g = root.get_node("ShipSystem").grid
	for p in [a, b]:
		p.pos = Vector2(root.get_node("ShipSystem").spawn_point()) + Vector2(0.5, 0.5)
		p.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	for k in 60:
		a._update_body(1.0)
		b._update_body(1.0)
	_check("5: Eine Stunde: Wasser A %.2f, B %.2f (B −25 %% Verbrauch)" % [a.needs.water, b.needs.water], is_equal_approx(100.0 - b.needs.water, (100.0 - a.needs.water) * 0.75))

	# 6) Speichern und Laden der neuen Traits
	gs.new_game()
	mira = root.get_node("CrewSystem").player()
	mira.traits.assign(["genius", "heavy_sleeper", "smoker"])
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	_check("6: Neue Traits nach dem Laden gleich (%s)" % str(root.get_node("CrewSystem").player().traits), root.get_node("CrewSystem").player().traits == ["genius", "heavy_sleeper", "smoker"])

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()

func _find_go() -> Button:
	for b in ui.char_ui.creation_bottom.get_children():
		if b is Button and not b.is_queued_for_deletion() and b.text == "Los geht's":
			return b
	return null
