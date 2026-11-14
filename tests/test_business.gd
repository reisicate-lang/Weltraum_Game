## Tests: Fähigkeit „Business Admin“ (ID business) – Erstellung, Wertanzeige, Handel, Lehrbuch, alte Stände
##   godot --headless --path . --script res://tests/boot.gd -- test_business
extends "res://tests/test_base.gd"

const OLD_SAVE := "res://tests/fixtures/old_save_blueports.json"

var ok_count := 0
var fail_count := 0
var toasts: Array = []
var gs
var ui
var SK
var CHS
var E
var save

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

## Knopf mit diesem Text unter einem Knoten (rekursiv)
func _find_button(n: Node, text: String) -> Button:
	for ch in n.get_children():
		if ch.is_queued_for_deletion():
			continue
		if ch is Button and ch.text == text:
			return ch
		var b := _find_button(ch, text)
		if b != null:
			return b
	return null

func _texts(n: Node) -> String:
	var out := ""
	for ch in n.get_children():
		if ch.is_queued_for_deletion():
			continue
		if ch is Label:
			out += ch.text + "\n"
		out += _texts(ch)
	return out

func _press(text: String, where: Node) -> bool:
	var b := _find_button(where, text)
	if b == null:
		return false
	b.pressed.emit()
	await process_frame
	return true

func _fresh(name: String) -> CrewMember:
	var c := CrewMember.new(900 + toasts.size() + randi() % 1000, name, Color.WHITE, Vector2i.ZERO)
	return c

func _initialize() -> void:
	await process_frame
	await process_frame
	gs = root.get_node("GameState")
	ui = root.get_node("UIManager")
	SK = root.get_node("SkillSystem")
	CHS = root.get_node("CharacterSystem")
	E = root.get_node("EconomySystem")
	save = root.get_node("SaveSystem")
	save.slot = 923
	root.get_node("Settings").meteors = false
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(t))
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.close_help()
	var mira: CrewMember = root.get_node("CrewSystem").player()
	_check("Skill vorhanden, ID business, englischer Name", SK.skill("business") != null and SK.skill("business").skill_name == "Business Admin")
	_check("Skill hat keine Preis-Boni mehr", not SK.skill("business").gameplay_effects.has("sell_bonus") and not SK.skill("business").gameplay_effects.has("buy_discount"))

	# 1) Charaktererstellung: auswählen, entfernen, erneut wählen; Bestätigung übernimmt genau einmal
	var cui = ui.char_ui
	CHS.begin(mira)
	CHS.apply_career(mira, "school")
	cui.open_creation()
	await process_frame
	var base: int = mira.age
	_check("1: Entwurf ohne Kurs: Vorschau %d" % CHS.preview_age(mira), CHS.preview_age(mira) == base and "Age: %d " % base in _texts(cui.creation_box))
	_check("1: Kurs auswählen (Knopf „Add“)", await _press("Add", cui.creation_box))
	_check("1: Vorschau +2 Jahre (%d), Alter selbst unverändert" % CHS.preview_age(mira), CHS.preview_age(mira) == base + 2 and mira.age == base and "Age: %d (incl. Business Admin course" % (base + 2) in _texts(cui.creation_box))
	_check("1: Noch kein Skill im Entwurf", SK.progress(mira, "business") < 100.0)
	_check("1: Kurs entfernen (Knopf „Remove“)", await _press("Remove", cui.creation_box))
	_check("1: Vorschau wieder −2 Jahre (%d)" % CHS.preview_age(mira), CHS.preview_age(mira) == base and "Age: %d " % base in _texts(cui.creation_box))
	_check("1: Erneut auswählen", await _press("Add", cui.creation_box) and CHS.preview_age(mira) == base + 2)
	_check("1: Doppelte Auswahl nicht möglich", not CHS.set_course(mira, true) and CHS.preview_age(mira) == base + 2)
	var hist0: int = mira.history.size()
	_check("1: Bestätigen (Los geht's)", await _press("Let's go", cui.creation_bottom))
	_check("1: Alter genau +2 (%d → %d)" % [base, mira.age], mira.age == base + 2 and CHS.preview_age(mira) == base + 2)
	_check("1: Skill genau einmal erworben (%.0f %%)" % SK.progress(mira, "business"), SK.acquired(mira, "business") and mira.history.size() == hist0 + 1)
	CHS.confirm(mira)
	_check("1: Zweites Bestätigen ändert nichts", mira.age == base + 2 and mira.history.size() == hist0 + 1)

	# 2) Derselbe Gegenstand, zwei Figuren: exakter Wert nur mit Skill, Angebot gleich
	var a := _fresh("Ada Admin")
	var b := _fresh("Ben Basic")
	SK.set_progress(a, "business", 100.0)
	SK.set_progress(b, "business", 0.0)
	var it := {"type": "plate", "qty": 4, "cond": 60.0}
	var exact: int = int(ItemSystem.item("plate").value * 4 * (0.25 + 0.75 * 0.6))
	_check("2: Gegenstandswert aus den Spieldaten, nach Zustand (%d Cr)" % E.item_value(it), E.item_value(it) == exact and E.item_value({"type": "plate", "qty": 4, "cond": 100.0}) > exact)
	gs.selected = a
	var tip_a: String = ui.item_tooltip(it)
	var sell_a: int = E.sell_price(it)
	var buy_a: int = E.buy_price("plate")
	gs.selected = b
	var tip_b: String = ui.item_tooltip(it)
	var sell_b: int = E.sell_price(it)
	var buy_b: int = E.buy_price("plate")
	_check("2: Mit Skill: Tooltip zeigt „Item Value: %d Cr“ (%s)" % [exact, tip_a.replace("\n", " | ")], ("Item Value: %d Cr" % exact) in tip_a)
	_check("2: Ohne Skill: bisherige Anzeige (nur Beschreibung)", tip_b == ItemSystem.item("plate").description and not "Item Value" in tip_b)
	_check("2: Verkaufsangebot gleich (%d / %d Cr)" % [sell_a, sell_b], sell_a == sell_b)
	_check("2: Kaufpreis gleich (%d / %d Cr)" % [buy_a, buy_b], buy_a == buy_b)
	_check("2: Angebot weicht vom Gegenstandswert ab (Angebot %d, Wert %d)" % [sell_a, exact], sell_a != exact)
	# Handelsfenster: Wert und Angebot getrennt
	var term = E.terminal()
	term.inv.items.clear()
	term.inv.add("plate", 4, 60.0)
	gs.selected = a
	ui.open_window("trade")
	ui.trade_tab = "sell"
	ui._last_window = ""
	ui._refresh_window()
	var win_a: String = _texts(ui.window_box)
	var offer_btn := _find_button(ui.window_box, "%d Cr" % E.sell_price(term.inv.items[0]))
	gs.selected = b
	ui._last_window = ""
	ui._refresh_window()
	var win_b: String = _texts(ui.window_box)
	_check("2: Handel mit Skill: Wert als eigene Angabe, Angebot im Knopf", ("Item Value: %d Cr" % E.item_value(term.inv.items[0])) in win_a and offer_btn != null and "Offer:" in offer_btn.tooltip_text)
	_check("2: Handel ohne Skill: kein Wert, Angebot unverändert", not "Item Value" in win_b and _find_button(ui.window_box, offer_btn.text) != null)
	ui.close_window()
	gs.selected = null

	# 4) Prüflogik: Business Admin als Voraussetzung abfragbar
	_check("4: meets({business: 100}) mit Skill", SK.meets(a, {"business": SK.ACQUIRED}) and SK.acquired(a, "business"))
	_check("4: meets({business: 100}) ohne Skill", not SK.meets(b, {"business": SK.ACQUIRED}) and not SK.acquired(b, "business"))

	# 3) Lehrbuch: beginnen, unterbrechen, speichern, laden, weiterlernen
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	mira.inv.items.clear()
	SK.set_progress(mira, "business", 75.0)
	var age0: int = mira.age
	mira.inv.add("book_business_3", 1, 90.0)
	_check("3: Buch „%s“ im Handel erhältlich" % ItemSystem.item("book_business_3").display_name, E.buy_price("book_business_3") > 0 and SK.readable_book(mira) == "book_business_3")
	var started := false
	for k in 60 * 60 * 3:
		gs.step(1.0 / 60.0)
		if mira.activity != null and mira.activity.get("kind", "") == "study" and SK.progress(mira, "business") > 75.0:
			started = true
			break
	var p_mid: float = SK.progress(mira, "business")
	_check("3: Figur liest das Buch (Lernlogik, %.3f %%)" % p_mid, started and p_mid > 75.0 and p_mid < 100.0)
	mira.stop_activity()
	gs.selected = mira
	_check("3: Unterbrochen: noch kein exakter Wert", not "Item Value" in ui.item_tooltip(it))
	save.save_game(true)
	gs.new_game()
	_check("3: Laden", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	gs.selected = mira
	_check("3: Fortschritt gehört der Figur und ist erhalten (%.3f %%)" % SK.progress(mira, "business"), absf(SK.progress(mira, "business") - p_mid) < 0.0001)
	_check("3: Nach dem Laden noch kein exakter Wert", not "Item Value" in ui.item_tooltip(it) and not SK.acquired(mira, "business"))
	toasts.clear()
	var guard := 0
	while SK.progress(mira, "business") < 100.0 and guard < 20000:
		guard += 1
		SK.study(mira, "book_business_3", 30.0)
		SK.decay_recent(mira, 120.0)
	var unlock_msgs := toasts.filter(func(t): return "acquired Business Admin" in t)
	_check("3: Abschluss schaltet frei (%d × 30 min gelesen)" % guard, SK.acquired(mira, "business") and unlock_msgs.size() == 1)
	_check("3: Jetzt exakter Wert sichtbar", ("Item Value: %d Cr" % exact) in ui.item_tooltip(it))
	SK.study(mira, "book_business_3", 30.0)
	SK.set_progress(mira, "business", 100.0)
	_check("3: Keine zweite Freischaltung", toasts.filter(func(t): return "acquired Business Admin" in t).size() == 1 and SK.readable_book(mira) == "")
	_check("3: Alter unverändert (%d)" % mira.age, mira.age == age0)
	gs.selected = null

	# 5) Älterer Spielstand mit bestehendem Business-Eintrag
	for variant in [[60.0, false], [100.0, true]]:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
		d.crew[0].skills["business"] = {"p": variant[0], "xp": 12.0, "hist": []}
		var f := FileAccess.open(save.path(), FileAccess.WRITE)
		f.store_string(JSON.stringify(d))
		f.close()
		gs.new_game()
		_check("5 (%d %%): Alter Spielstand geladen" % int(variant[0]), save.load_game(true))
		mira = root.get_node("CrewSystem").player()
		gs.selected = mira
		_check("5 (%d %%): Vorhandene Skills und Lernfortschritt erhalten (Bau %.0f %%, Business %.0f %%)" % [int(variant[0]), SK.progress(mira, "construction"), SK.progress(mira, "business")],
			is_equal_approx(SK.progress(mira, "construction"), 33.0) and is_equal_approx(SK.progress(mira, "business"), variant[0]))
		_check("5 (%d %%): Wirkung nach neuer Definition (Wert sichtbar: %s)" % [int(variant[0]), str(variant[1])], ("Item Value" in ui.item_tooltip(it)) == variant[1] and SK.effect(mira, "sell_bonus") == 0.0 and SK.effect(mira, "buy_discount") == 0.0)
		var p_with: int = E.sell_price(it)
		gs.selected = b
		_check("5 (%d %%): Verkaufsangebot wie ohne Skill (%d Cr)" % [int(variant[0]), p_with], p_with == E.sell_price(it))
		gs.selected = null

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
