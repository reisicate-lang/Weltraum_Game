## Tests: traits after Ostranauts (73 traits, year costs, counterparts, choice in the life story, old saves)
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

	# 1) Data: 73 traits with costs and counterparts as in the wiki index
	_check("73 Traits geladen (%d)" % TS.traits.size(), TS.traits.size() == 73)
	var by_cost := {}
	var sym := true
	for id in TS.traits:
		var t: TraitData = TS.traits[id]
		by_cost[t.cost] = int(by_cost.get(t.cost, 0)) + 1
		if t.opposite != "" and (TS.get_trait(t.opposite) == null or TS.get_trait(t.opposite).opposite != id):
			sym = false
	_check("Year costs as in the index (%s)" % str(by_cost), by_cost == {3: 8, 2: 5, 1: 19, -1: 26, -2: 7, -3: 8})
	_check("Counterparts mutual", sym)
	var sample := {"strong": [2, "feeble"], "feeble": [-2, "strong"], "genius": [3, "obtuse"], "insomniac": [-2, ""], "heavy_sleeper": [-1, "light_sleeper"], "chaste": [-2, "lustful"], "visually_impaired": [-1, ""]}
	var ok_sample := true
	for id in sample:
		var t: TraitData = TS.get_trait(id)
		if t == null or t.cost != sample[id][0] or t.opposite != sample[id][1]:
			ok_sample = false
			print("        falsch: %s" % id)
	_check("Samples (cost, counterpart) as in the wiki", ok_sample)
	_check("Order as in the wiki (Ambitious first, Visually Impaired last)", TS.ordered_ids()[0] == "ambitious" and TS.ordered_ids()[-1] == "visually_impaired")
	var tip: String = TS.tooltip("strong")
	_check("Tooltip: cost, counterpart, effect in the game, wiki text (%s)" % tip.replace("\n", " | "), "+2 years" in tip and "Opposite: Feeble" in tip and "In game: Combat power +25 %" in tip and "Wiki: G-tol" in tip)
	_check("The tooltip of a pure flag says so", "no gameplay effect yet" in TS.tooltip("beautiful"))

	# 2) Old own traits are converted
	var legacy := {"calm": "brave", "distracted": "obtuse", "frugal": "slow_metabolism", "hardy": "tough", "introvert": "shy", "lazy": "complacent",
		"nervous": "craven", "nimble": "coordinated", "smart": "genius", "social": "gregarious", "weak": "feeble",
		"ambitious": "ambitious", "clumsy": "clumsy", "fragile": "fragile", "glutton": "glutton", "strong": "strong"}
	var mig_ok := true
	for old in legacy:
		if TS.migrate([old]) != [legacy[old]]:
			mig_ok = false
			print("        %s → %s" % [old, str(TS.migrate([old]))])
	_check("Alle 16 alten Traits abgebildet", mig_ok)
	_check("Duplicates removed after the conversion", TS.migrate(["smart", "genius", "unknown_x"]) == ["genius"])
	var dd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(dd))
	f.close()
	gs.new_game()
	_check("Old save loaded", save.load_game(true))
	var mira: CrewMember = root.get_node("CrewSystem").player()
	_check("Old trait nimble is now Coordinated (%s)" % str(mira.traits), mira.traits == ["coordinated"] and is_equal_approx(TS.sum(mira, "piloting"), 0.1) and is_equal_approx(TS.factor(mira, "work_fine"), 1.2))
	var unknown := []
	var careers: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/careers.json"))
	for coll in [careers.careers, careers.get("events", [])]:
		for e in coll:
			for k in ["traits_add", "traits_remove"]:
				for t in e.get(k, []):
					if TS.get_trait(t) == null or TS.resolve(t) != t:
						unknown.append(t)
	_check("Life steps and encounters use the new IDs (%s)" % str(unknown), unknown.is_empty())

	# 3) Rules in the life story (life steps, encounters): a positive trait replaces its negative counterpart
	var c := _fresh()
	TS.add(c, "fragile")
	_check("Got Tough while Fragile is there: Fragile gone, Tough not added", TS.add(c, "tough") and not "fragile" in c.traits and not "tough" in c.traits)
	TS.add(c, "brave")
	_check("Craven (negative) against an existing Brave: not given", not TS.add(c, "craven") and "brave" in c.traits and not "craven" in c.traits)

	# 4) Choice in the draft (through the buttons in the life story)
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	mira = root.get_node("CrewSystem").player()
	CHS.begin(mira)
	mira.traits.assign(["fragile"])   # start with a negative trait
	CHS.apply_career(mira, "school")
	var cui = ui.char_ui
	cui.open_creation()
	await process_frame
	var base: int = mira.age
	_check("4: All 73 trait buttons in the life story", TS.ordered_ids().all(func(id): return _trait_button(id) != null))
	_check("4: Choose Brave (+2): preview +2", await _press("brave") and CHS.preview_age(mira) == base + 2 and mira.age == base)
	_check("4: Deselect Brave: preview −2", await _press("brave") and CHS.preview_age(mira) == base)
	_check("4: Tough locked while Fragile is there (%s)" % _trait_button("tough").tooltip_text.get_slice("\n", _trait_button("tough").tooltip_text.get_slice_count("\n") - 1), _trait_button("tough").disabled and "Remove Fragile first." in _trait_button("tough").tooltip_text)
	_check("4: Fragile (−1) entfernen kostet 1 Jahr", await _press("fragile") and CHS.preview_age(mira) == base + 1)
	_check("4: Then Tough (+1) can be chosen: preview +2", await _press("tough") and CHS.preview_age(mira) == base + 2)
	_check("4: Slovenly (−1) gives 1 year back: preview +1", await _press("slovenly") and CHS.preview_age(mira) == base + 1)
	_check("4: Counterpart locked in the draft (Tidy, because Slovenly is chosen)", _trait_button("tidy").disabled)
	var hist0: int = mira.history.size()
	_check("4: Confirm", CHS.confirm(mira))
	_check("4: Age +1 exactly once, traits applied (%s)" % str(mira.traits), mira.age == base + 1 and "tough" in mira.traits and "slovenly" in mira.traits and not "fragile" in mira.traits and mira.history.size() == hist0 + 1)
	_check("4: Confirming a second time changes nothing", CHS.confirm(mira) and mira.age == base + 1 and mira.history.size() == hist0 + 1)
	# Negative balance: choose only a negative trait
	cui.refresh_creation()
	await process_frame
	var age1: int = mira.age
	await _press("ugly")
	_check("4: Only Ugly (−1): balance −1, Let's go locked", CHS.draft_balance(mira) == -1 and _find_go().disabled)
	_check("4: A negative balance is not applied", not CHS.confirm(mira) and mira.age == age1 and not "ugly" in mira.traits)
	await _press("genius")
	_check("4: With Genius (+3) balance +2, Let's go free", CHS.draft_balance(mira) == 2 and not _find_go().disabled)
	CHS.toggle_trait(mira, "genius")
	CHS.toggle_trait(mira, "ugly")
	cui.creation.visible = false

	# 5) Effects in the game
	var a := CrewMember.new(701, "A", Color.WHITE, Vector2i.ZERO)
	var b := CrewMember.new(702, "B", Color.WHITE, Vector2i.ZERO)
	TS.add(b, "slow_metabolism")
	_check("5: Slow Metabolism: food and water −25 %", is_equal_approx(TS.factor(b, "hunger"), 0.75) and is_equal_approx(TS.factor(b, "thirst"), 0.75))
	var mh := CrewMember.new(703, "C", Color.WHITE, Vector2i.ZERO)
	TS.add(mh, "micro_g_hypovolemic")
	_check("5: Micro-g Hypovolemic: food and water +15 %", is_equal_approx(TS.factor(mh, "hunger"), 1.15) and is_equal_approx(TS.factor(mh, "thirst"), 1.15))
	var vi := CrewMember.new(704, "D", Color.WHITE, Vector2i.ZERO)
	TS.add(vi, "visually_impaired")
	TS.add(vi, "coordinated")
	_check("5: Piloting from traits: Coordinated +0.1, Visually Impaired −0.2 (%.2f)" % SK.piloting(vi), is_equal_approx(SK.piloting(vi), -0.1))
	var ins := CrewMember.new(705, "E", Color.WHITE, Vector2i.ZERO)
	TS.add(ins, "insomniac")
	_check("5: Insomniac sleeps worse (recovery ×0.75)", is_equal_approx(TS.factor(ins, "sleep_gain"), 0.75))
	# Thirst during play: same time, B (Slow Metabolism) loses less water
	gs.new_game()
	var g = root.get_node("ShipSystem").grid
	for p in [a, b]:
		p.pos = Vector2(root.get_node("ShipSystem").spawn_point()) + Vector2(0.5, 0.5)
		p.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	for k in 60:
		a._update_body(1.0)
		b._update_body(1.0)
	_check("5: One hour: water A %.2f, B %.2f (B −25 %% consumption)" % [a.needs.water, b.needs.water], is_equal_approx(100.0 - b.needs.water, (100.0 - a.needs.water) * 0.75))

	# 6) Saving and loading the new traits
	gs.new_game()
	mira = root.get_node("CrewSystem").player()
	mira.traits.assign(["genius", "heavy_sleeper", "smoker"])
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	_check("6: New traits unchanged after loading (%s)" % str(root.get_node("CrewSystem").player().traits), root.get_node("CrewSystem").player().traits == ["genius", "heavy_sleeper", "smoker"])

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()

func _find_go() -> Button:
	for b in ui.char_ui.creation_bottom.get_children():
		if b is Button and not b.is_queued_for_deletion() and b.text == "Let's go":
			return b
	return null
