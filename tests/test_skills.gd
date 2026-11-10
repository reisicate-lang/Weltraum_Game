## Tests für Fähigkeiten, Traits, Hobbys, Lebenslauf, NPCs und Stationen:
##   godot --headless --path . --script res://tests/test_skills.gd
extends SceneTree

var _failed := 0
var _ok := 0

func _check(name: String, ok: bool) -> void:
	if ok:
		_ok += 1
	else:
		_failed += 1
		print("FEHLER  " + name)

func _fresh(n: String = "Test") -> CrewMember:
	var c := CrewMember.new(900 + randi() % 1000, n, Color.WHITE, Vector2i(30, 22))
	return c

func _run(minutes: float) -> void:
	var gs = root.get_node("GameState")
	for i in int(minutes * 60.0):
		gs.step(1.0 / 60.0)

func _initialize() -> void:
	await process_frame
	await process_frame
	# Eigener Speicherplatz: Tests überschreiben keine echten Spielstände und laufen parallel
	root.get_node("SaveSystem").slot = 907
	# Diese Tests prüfen auch die (vorübergehend abgeschaltete) Station und das Wrack
	Config.ENABLE_STATION = true
	Config.ENABLE_WRECK = true
	var gs = root.get_node("GameState")
	var SK = root.get_node("SkillSystem")
	var TS = root.get_node("TraitSystem")
	var CH = root.get_node("CharacterSystem")
	var NPC = root.get_node("NPCSystem")
	var DLG = root.get_node("DialogueSystem")
	var econ = root.get_node("EconomySystem")
	var build = root.get_node("ShipConstructionSystem")
	var ship = root.get_node("ShipSystem")
	var crew = root.get_node("CrewSystem")
	var phys = root.get_node("PhysicsSystem")
	gs.new_game()

	# 1) Jede Fähigkeit bekommt Fortschritt durch ihre eigenen Aktionen
	_check("32 Fähigkeiten geladen", SK.skills.size() == 32)
	for id in SK.skills:
		var s: SkillData = SK.skill(id)
		_check(id + ": hat Trainingsaktionen, Name, Beschreibung, Wirkungen", s.training_actions.size() > 0 and s.skill_name != "" and s.description != "" and not s.gameplay_effects.is_empty())
		var c := _fresh()
		for r in s.required_skills:
			SK.set_progress(c, r, 100.0)
		SK.train(c, s.training_actions[0], 30.0)
		_check(id + ": lernt durch '" + s.training_actions[0] + "' (%.2f %%)" % SK.progress(c, id), SK.progress(c, id) > 0.5)
		# Nur passende Aktionen: eine fremde Aktion bringt dieser Fähigkeit nichts
		var c2 := _fresh()
		var foreign := ""
		for a in SK.actions:
			if not id in SK.actions[a].skills:
				foreign = a
				break
		SK.train(c2, foreign, 30.0)
		_check(id + ": fremde Aktion '" + foreign + "' bringt nichts", SK.progress(c2, id) == 0.0)

	# 2) Wiederholung und zu leichte Aufgaben
	var r := _fresh()
	var first: float = SK.train(r, "lay_cable", 10.0)
	for k in 10:
		SK.train(r, "lay_cable", 10.0)
	var later: float = SK.train(r, "lay_cable", 10.0)
	_check("Wiederholung bringt weniger (%.3f -> %.3f)" % [first, later], later < first * 0.6)
	var novice := _fresh()
	var expert := _fresh()
	SK.set_progress(expert, "electrical", 90.0)
	var g_novice: float = SK.train(novice, "lay_cable", 10.0)
	var g_expert: float = SK.train(expert, "lay_cable", 10.0)
	_check("Zu leichte Aufgabe bringt Experten kaum etwas (%.3f vs %.3f)" % [g_expert, g_novice], g_expert < g_novice * 0.2)
	var hard := _fresh()
	SK.set_progress(hard, "electrical", 50.0)
	SK.set_progress(expert, "electrical", 50.0)
	var g_hard: float = SK.train(hard, "repair_nav", 10.0)
	var easy := _fresh()
	SK.set_progress(easy, "electrical", 50.0)
	var g_easy: float = SK.train(easy, "lay_cable", 10.0)
	_check("Schwere Aufgabe bringt mehr als leichte (%.3f vs %.3f)" % [g_hard, g_easy], g_hard > g_easy)

	# 3) Voraussetzungen
	var rob := _fresh()
	for k in 200:
		SK.train(rob, "repair_robotic", 30.0)
		rob.recent_actions.clear()
	_check("Robotik bleibt ohne Elektrotechnik bei 40 %% (%.1f)" % SK.progress(rob, "robotics"), SK.progress(rob, "robotics") <= 40.0)
	SK.set_progress(rob, "electrical", 35.0)
	SK.train(rob, "repair_robotic", 30.0)
	_check("Mit Elektrotechnik geht es weiter", SK.progress(rob, "robotics") > 40.0)

	# 4) 100 % und Meisterschaft
	var m := _fresh()
	SK.set_progress(m, "eva", 99.9)
	SK.train(m, "suit_maintenance", 30.0)
	_check("Fortschritt nie über 100 %%", SK.progress(m, "eva") <= 100.0)
	SK.set_progress(m, "eva", 100.0)
	_check("Meisterschaft erkannt", SK.mastered(m, "eva"))
	_check("Meisterbonus erhöht die Wirkung", SK.effect(m, "suit_o2_saving") > 0.35)

	# 5) Wirkungen im Spiel
	var mira = crew.player()
	var gx0: int = (ship.grid.width - 16) / 2
	var gy0: int = (ship.grid.height - 10) / 2
	var job := {"kind": "repair", "x": gx0 + 4, "y": gy0 + 4}  # Innenwand
	var e1 := _fresh()
	var e2 := _fresh()
	SK.set_progress(e2, "civil", 100.0)
	_check("Bauingenieur repariert Wände schneller (%.2f vs %.2f)" % [SK.work_speed(e2, job), SK.work_speed(e1, job)], SK.work_speed(e2, job) > SK.work_speed(e1, job) * 1.3)
	var eljob := {"kind": "device", "dev": "battery", "x": 0, "y": 0}
	var el := _fresh()
	SK.set_progress(el, "electrical", 80.0)
	var me := _fresh()
	SK.set_progress(me, "mechanical", 80.0)
	_check("Elektriker baut Batterien schneller als Mechaniker", SK.work_speed(el, eljob) > SK.work_speed(me, eljob))
	var f_before: float = SK.pilot_fuel_factor()
	SK.set_progress(mira, "pilot", 100.0)
	_check("Pilot spart Treibstoff (%.2f -> %.2f)" % [f_before, SK.pilot_fuel_factor()], SK.pilot_fuel_factor() < f_before)
	SK.set_progress(mira, "physics", 100.0)
	_check("Physik verkürzt Schnellreisen", SK.travel_factor() < 1.0)
	gs.selected = mira
	var it := {"type": "plate", "qty": 10, "cond": 100.0}
	SK.set_progress(mira, "business", 0.0)
	var p0: int = econ.sell_price(it)
	SK.set_progress(mira, "business", 100.0)
	_check("Betriebswirtschaft bringt mehr beim Verkauf (%d -> %d)" % [p0, econ.sell_price(it)], econ.sell_price(it) > p0)
	var fighter := _fresh()
	var weak := _fresh()
	SK.set_progress(fighter, "unarmed", 100.0)
	SK.set_progress(fighter, "combat_training", 100.0)
	_check("Kampfkraft steigt mit Kampffähigkeiten", SK.combat_power(fighter) > SK.combat_power(weak) * 1.5)
	fighter.inv.add("boltgun", 1)
	SK.set_progress(fighter, "ranged", 100.0)
	_check("Fernwaffe mit Fernkampf erhöht Kampfkraft", SK.combat_power(fighter) > 40.0)
	var hk := _fresh()
	_check("Ohne Hacken keine Stufe-3-Schlösser", SK.hack_value(hk) < SK.hack_needed(3))
	SK.set_progress(hk, "software", 100.0)
	SK.set_progress(hk, "hacking", 100.0)
	_check("Mit Hacken und Software auch Stufe 3", SK.hack_value(hk) >= SK.hack_needed(3))
	var ev := _fresh()
	ev.suit = {"o2": 100.0, "battery": 100.0}
	SK.set_progress(ev, "eva", 100.0)
	var ev2 := _fresh()
	ev2.suit = {"o2": 100.0, "battery": 100.0}
	for k in 600:
		ev._update_body(1.0 / 60.0)
		ev2._update_body(1.0 / 60.0)
	_check("Raumanzugpraxis spart Sauerstoff (%.1f vs %.1f)" % [ev.suit.o2, ev2.suit.o2], ev.suit.o2 > ev2.suit.o2 + 1.0)

	# 6) Lehrbücher
	var reader := _fresh()
	var got: float = 0.0
	for k in 100:
		got += SK.study(reader, "book_physics_1", 30.0)
		reader.recent_actions.clear()
	_check("Grundlagenbuch bringt bis 40 %% (%.1f)" % SK.progress(reader, "physics"), absf(SK.progress(reader, "physics") - 40.0) < 0.01)
	var noob := _fresh()
	_check("Fortgeschrittenes Buch braucht Vorwissen", SK.study(noob, "book_physics_2", 30.0) == 0.0)
	SK.study(reader, "book_physics_2", 30.0)
	_check("Fortgeschrittenes Buch mit Vorwissen wirkt", SK.progress(reader, "physics") > 40.0)
	_check("Buch trainiert nur seine Fähigkeit", SK.progress(reader, "software") == 0.0)

	# 7) Traits beeinflussen das Lernen
	var smart := _fresh()
	TS.add(smart, "smart")
	var dumb := _fresh()
	TS.add(dumb, "distracted")
	SK.train(smart, "repair_mechanical", 20.0)
	SK.train(dumb, "repair_mechanical", 20.0)
	_check("Intelligent lernt schneller als unkonzentriert", SK.progress(smart, "mechanical") > SK.progress(dumb, "mechanical") * 1.4)
	_check("Gegensätzliche Traits schließen sich aus", not TS.add(smart, "distracted"))
	var before_traits := smart.traits.size()
	SK.train(smart, "repair_mechanical", 500.0)
	_check("Training ändert keine Traits", smart.traits.size() == before_traits)

	# 8) Lebenslauf
	var life := _fresh()
	CH.begin(life)
	var avail_ids: Array = CH.available(life).map(func(k): return k.id)
	_check("Mit 14 keine Universität (braucht Schule und Alter)", not "university" in avail_ids)
	CH.apply_career(life, "school")
	_check("Schule kostet 4 Jahre", life.age == 18)
	avail_ids = CH.available(life).map(func(k): return k.id)
	_check("Nach der Schule ist die Universität offen", "university" in avail_ids)
	CH.apply_career(life, "military")
	_check("Militär bringt Fernkampf", SK.progress(life, "ranged") > 15.0)
	_check("Militär gibt eine Bolzenpistole", life.inv.count("boltgun") == 1)
	_check("Lebenslauf wird protokolliert", life.history.size() >= 3)
	_check("Hobby wählbar", CH.choose_hobby(life, "chess") and "chess" in life.hobbies)

	# 9) NPCs: eigene Fähigkeiten, lernen durch Arbeit
	var npc: CrewMember = CH.generate_npc()
	_check("NPC hat Fähigkeiten und Lohn", not npc.skills.is_empty() and npc.salary > 0)
	econ.credits = 10000
	var cands: Array = NPC.candidates_here()
	_check("Bewerber an der Station", cands.size() == 3)
	var hire: CrewMember = cands[0]
	NPC.hire(hire)
	_check("Angeheuert", hire in crew.crew)
	var before_civil: float = SK.progress(hire, "civil") + SK.progress(hire, "spaceship")
	mira.work_prefs["repair"] = false  # Mira repariert nicht: nur der NPC
	var x0: int = (ship.grid.width - 16) / 2
	var y0: int = (ship.grid.height - 10) / 2
	ship.grid.cond[ship.grid.idx(Vector2i(x0 + 4, y0 + 4))] = 30.0
	build.place("repair", Vector2i(x0 + 4, y0 + 4))
	_run(15)
	_check("NPC lernt durch Reparaturarbeit", SK.progress(hire, "civil") + SK.progress(hire, "spaceship") > before_civil)
	_check("Aufgabenverteilung: Mira hat nicht repariert", mira.job == null or mira.job.kind != "repair")

	# 10) Stationen: Gespräche, Bar, Glücksspiel, Psychologie
	gs.selected = mira
	SK.set_progress(mira, "folk", 50.0)
	var opts: Array = DLG.options()
	var tip_ok := false
	for o in opts:
		if o.id == "tip":
			tip_ok = o.ok
	_check("Volksetikette schaltet Gus' Tipp frei", tip_ok)
	_check("Antwort kommt von einer Person", DLG.choose("tip").begins_with("Gus:"))
	var cr0: int = econ.credits
	DLG.choose("song")
	_check("Auftritt bringt Gage", econ.credits > cr0)
	_check("Auftritt trainiert Gesang", SK.progress(mira, "song") > 0.0)
	var victim := hire
	victim.stress = 80.0
	DLG.counsel(mira, victim)
	_check("Gespräch senkt Stress", victim.stress < 80.0)

	# 11) Begegnung
	NPC.start_plunderers()
	var res: String = NPC.fight()
	_check("Kampf hat ein Ergebnis und trainiert", res != "" and (SK.progress(mira, "combat_training") > 0.0 or SK.progress(hire, "combat_training") > 0.0))

	# 12) Speichern und Laden erhält alles
	SK.set_progress(mira, "hacking", 33.0)
	var traits_before: Array = mira.traits.duplicate()
	root.get_node("SaveSystem").save_game(true)
	gs.new_game()
	root.get_node("SaveSystem").load_game(true)
	var m2 = crew.player()
	_check("Fähigkeit nach dem Laden gleich", absf(SK.progress(m2, "hacking") - 33.0) < 0.01)
	_check("Traits nach dem Laden gleich", m2.traits == traits_before)
	_check("Crew nach dem Laden vollständig", crew.crew.size() == 2)
	_check("Lernhistorie gespeichert", not m2.skills.get("song", {}).get("hist", []).is_empty())

	print("\n%d OK, %d Fehler" % [_ok, _failed])
	quit(1 if _failed > 0 else 0)
