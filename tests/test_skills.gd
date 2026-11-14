## Tests for skills, traits, hobbies, life story, NPCs and stations:
##   godot --headless --path . --script res://tests/boot.gd -- test_skills
extends "res://tests/test_base.gd"

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
	# Own save slot: tests do not overwrite real saves and can run in parallel
	root.get_node("SaveSystem").slot = 907
	# These tests also check the (temporarily disabled) station and the wreck
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

	# 1) Every skill gets progress through its own actions
	_check("32 skills loaded", SK.skills.size() == 32)
	for id in SK.skills:
		var s: SkillData = SK.skill(id)
		_check(id + ": has training actions, name, description, effects", s.training_actions.size() > 0 and s.skill_name != "" and s.description != "" and (not s.gameplay_effects.is_empty() or s.work_value_bonus != 0.0 or s.piloting_bonus != 0.0 or s.check_flag or s.attack_bonus != 0.0))
		var c := _fresh()
		for r in s.required_skills:
			SK.set_progress(c, r, 100.0)
		SK.train(c, s.training_actions[0], 30.0)
		_check(id + ": lernt durch '" + s.training_actions[0] + "' (%.2f %%)" % SK.progress(c, id), SK.progress(c, id) > 0.5)
		# Only matching actions: a foreign action gives this skill nothing
		var c2 := _fresh()
		var foreign := ""
		for a in SK.actions:
			if not id in SK.actions[a].skills:
				foreign = a
				break
		SK.train(c2, foreign, 30.0)
		_check(id + ": fremde Aktion '" + foreign + "' bringt nichts", SK.progress(c2, id) == 0.0)

	# 2) Repetition and tasks that are too easy
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
	_check("Too easy a task hardly gives an expert anything (%.3f vs %.3f)" % [g_expert, g_novice], g_expert < g_novice * 0.2)
	var hard := _fresh()
	SK.set_progress(hard, "electrical", 50.0)
	SK.set_progress(expert, "electrical", 50.0)
	var g_hard: float = SK.train(hard, "repair_nav", 10.0)
	var easy := _fresh()
	SK.set_progress(easy, "electrical", 50.0)
	var g_easy: float = SK.train(easy, "lay_cable", 10.0)
	_check("A hard task gives more than an easy one (%.3f vs %.3f)" % [g_hard, g_easy], g_hard > g_easy)

	# 3) Voraussetzungen
	var rob := _fresh()
	for k in 200:
		SK.train(rob, "hack", 30.0)
		rob.recent_actions.clear()
	_check("Hacking stays at 40 %% without Software (%.1f)" % SK.progress(rob, "hacking"), SK.progress(rob, "hacking") <= 40.0)
	SK.set_progress(rob, "software", 30.0)
	SK.train(rob, "hack", 30.0)
	_check("With Software it goes on", SK.progress(rob, "hacking") > 40.0)

	# 4) 100 % and mastery
	var m := _fresh()
	SK.set_progress(m, "eva", 99.9)
	SK.train(m, "suit_maintenance", 30.0)
	_check("Progress never above 100 %%", SK.progress(m, "eva") <= 100.0)
	SK.set_progress(m, "eva", 100.0)
	_check("Meisterschaft erkannt", SK.mastered(m, "eva"))
	SK.set_progress(m, "combat_training", 100.0)
	_check("Mastery bonus raises the effect", SK.effect(m, "defense") > 0.5)

	# 5) Effects in the game
	var mira = crew.player()
	var gx0: int = (ship.grid.width / Config.GRID_SCALE - 16) / 2
	var gy0: int = (ship.grid.height / Config.GRID_SCALE - 10) / 2
	var job := {"kind": "repair", "x": C(gx0 + 4, gy0 + 4).x, "y": C(gx0 + 4, gy0 + 4).y}  # Innenwand
	var e1 := _fresh()
	var e2 := _fresh()
	SK.set_progress(e2, "civil", 100.0)
	# Civil Engineering only acts on devices of certain categories (+4 work value), not on walls
	var bedjob := {"kind": "device", "dev": "bed", "x": 0, "y": 0}
	_check("Civil Engineering: furniture +4 work value, walls unchanged (%.2f vs %.2f)" % [SK.work_value(e2, bedjob), SK.work_value(e1, bedjob)],
		is_equal_approx(SK.work_value(e2, bedjob) - SK.work_value(e1, bedjob), 4.0) and is_equal_approx(SK.work_speed(e2, job), SK.work_speed(e1, job)))
	var eljob := {"kind": "device", "dev": "battery", "x": 0, "y": 0}
	var el := _fresh()
	SK.set_progress(el, "electrical", 100.0)
	var me := _fresh()
	SK.set_progress(me, "mechanical", 100.0)
	_check("Electrical Engineering (acquired) builds batteries faster than Mechanical", SK.work_speed(el, eljob) > SK.work_speed(me, eljob))
	var pl_before: float = SK.piloting(mira)
	SK.set_progress(mira, "pilot", 100.0)
	_check("Spaceship Piloting gives Piloting +0.5 (%.2f -> %.2f)" % [pl_before, SK.piloting(mira)], is_equal_approx(SK.piloting(mira) - pl_before, 0.5))
	SK.set_progress(mira, "physics", 100.0)
	_check("Physics is a check flag (no shorter travel any more)", is_equal_approx(SK.travel_factor(), 1.0) and SK.acquired(mira, "physics"))
	gs.selected = mira
	var it := {"type": "plate", "qty": 10, "cond": 100.0}
	SK.set_progress(mira, "business", 0.0)
	var p0: int = econ.sell_price(it)
	SK.set_progress(mira, "business", 100.0)
	_check("Business Admin does not change the sale offer (%d -> %d)" % [p0, econ.sell_price(it)], econ.sell_price(it) == p0)
	var fighter := _fresh()
	var weak := _fresh()
	SK.set_progress(fighter, "unarmed", 100.0)
	SK.set_progress(fighter, "combat_training", 100.0)
	_check("Combat strength rises with combat skills", SK.combat_power(fighter) > SK.combat_power(weak) * 1.5)
	var plain_power: float = SK.combat_power(weak)
	var unarmed_power: float = SK.combat_power(fighter)
	var melee := _fresh()
	SK.set_progress(melee, "unarmed", 100.0)
	_check("Unarmed Melee: Angriff +50 %% (Kampfkraft %.1f → %.1f)" % [plain_power, SK.combat_power(melee)], is_equal_approx(SK.combat_power(melee) - plain_power, 25.0 * 0.5 * melee.health / 100.0 * root.get_node("TraitSystem").factor(melee, "combat")))
	var armed := _fresh()
	armed.inv.add("crowbar", 1)
	var armed0: float = SK.combat_power(armed)
	SK.set_progress(armed, "armed_melee", 100.0)
	_check("Armed Melee with a crowbar: attack +50 %%", SK.combat_power(armed) > armed0)
	var shooter := _fresh()
	shooter.inv.add("boltgun", 1)
	var sh0: float = SK.combat_power(shooter)
	SK.set_progress(shooter, "ranged", 100.0)
	_check("Ranged weapon: the base value counts, Ranged is a check flag (%.1f)" % sh0, sh0 > plain_power and is_equal_approx(SK.combat_power(shooter), sh0))
	var hk := _fresh()
	_check("No level 3 locks without Hacking", SK.hack_value(hk) < SK.hack_needed(3))
	SK.set_progress(hk, "software", 100.0)
	SK.set_progress(hk, "hacking", 100.0)
	_check("With Hacking and Software also level 3", SK.hack_value(hk) >= SK.hack_needed(3))
	var ev := _fresh()
	ev.suit = {"o2": 100.0, "battery": 100.0}
	SK.set_progress(ev, "eva", 100.0)
	var ev2 := _fresh()
	ev2.suit = {"o2": 100.0, "battery": 100.0}
	for k in 600:
		ev._update_body(1.0 / 60.0)
		ev2._update_body(1.0 / 60.0)
	_check("EVA Suits removes the suit penalty (%.2f vs %.2f)" % [SK.eva_factor(ev), SK.eva_factor(ev2)], is_equal_approx(SK.eva_factor(ev), 1.0) and is_equal_approx(SK.eva_factor(ev2), 0.55))

	# 6) Textbooks
	var reader := _fresh()
	var got: float = 0.0
	for k in 100:
		got += SK.study(reader, "book_physics_1", 30.0)
		reader.recent_actions.clear()
	_check("Basics book brings it to 40 %% (%.1f)" % SK.progress(reader, "physics"), absf(SK.progress(reader, "physics") - 40.0) < 0.01)
	var noob := _fresh()
	_check("Fortgeschrittenes Buch braucht Vorwissen", SK.study(noob, "book_physics_2", 30.0) == 0.0)
	SK.study(reader, "book_physics_2", 30.0)
	_check("Advanced book works with prior knowledge", SK.progress(reader, "physics") > 40.0)
	_check("A book only trains its skill", SK.progress(reader, "software") == 0.0)

	# 7) Traits influence learning
	var smart := _fresh()
	TS.add(smart, "genius")
	var dumb := _fresh()
	TS.add(dumb, "obtuse")
	SK.train(smart, "repair_mechanical", 20.0)
	SK.train(dumb, "repair_mechanical", 20.0)
	_check("Genius learns faster than Obtuse", SK.progress(smart, "mechanical") > SK.progress(dumb, "mechanical") * 1.4)
	_check("Opposite traits exclude each other", not TS.add(smart, "obtuse"))
	var before_traits := smart.traits.size()
	SK.train(smart, "repair_mechanical", 500.0)
	_check("Training does not change traits", smart.traits.size() == before_traits)

	# 8) Lebenslauf
	var life := _fresh()
	CH.begin(life)
	_check("Start at 18 (asteroid profile)", life.age == 18)
	_check("Starting traits and starting skills (%s)" % str(life.traits), life.traits.size() == 9 and "feeble" in life.traits and "visually_impaired" in life.traits and SK.acquired(life, "spaceship") and SK.acquired(life, "zerog"))
	var avail_ids: Array = CH.available(life).map(func(k): return k.id)
	_check("No school any more, university open from the start", not "school" in avail_ids and "university" in avail_ids)
	CH.apply_career(life, "military")
	_check("Military gives ranged combat", SK.progress(life, "ranged") > 15.0)
	_check("Military gives a bolt gun", life.inv.count("boltgun") == 1)
	_check("Life story is logged", life.history.size() >= 2)
	_check("Hobby can be chosen", CH.choose_hobby(life, "chess") and "chess" in life.hobbies)

	# 9) NPCs: own skills, learn through work
	var npc: CrewMember = CH.generate_npc()
	_check("NPC has skills and wages", not npc.skills.is_empty() and npc.salary > 0)
	econ.credits = 10000
	var cands: Array = NPC.candidates_here()
	_check("Applicants at the station", cands.size() == 3)
	var hire: CrewMember = cands[0]
	NPC.hire(hire)
	_check("Angeheuert", hire in crew.crew)
	var before_civil: float = SK.progress(hire, "civil") + SK.progress(hire, "spaceship")
	mira.work_prefs["repair"] = false  # Mira does not repair: only the NPC
	var x0: int = (ship.grid.width / Config.GRID_SCALE - 16) / 2
	var y0: int = (ship.grid.height / Config.GRID_SCALE - 10) / 2
	ship.grid.cond[ship.grid.idx(C(x0 + 4, y0 + 4))] = 30.0
	build.place("repair", C(x0 + 4, y0 + 4))
	_run(15)
	_check("NPC lernt durch Reparaturarbeit", SK.progress(hire, "civil") + SK.progress(hire, "spaceship") > before_civil)
	_check("Work assignment: Mira did not repair", mira.job == null or mira.job.kind != "repair")

	# 10) Stations: conversations, bar, gambling, psychology
	gs.selected = mira
	SK.set_progress(mira, "folk", 50.0)
	var opts: Array = DLG.options()
	var tip_ok := false
	for o in opts:
		if o.id == "tip":
			tip_ok = o.ok
	_check("Volksetikette schaltet Gus' Tipp frei", tip_ok)
	_check("The answer comes from a person", DLG.choose("tip").begins_with("Gus:"))
	var cr0: int = econ.credits
	DLG.choose("song")
	_check("Auftritt bringt Gage", econ.credits > cr0)
	_check("Auftritt trainiert Gesang", SK.progress(mira, "song") > 0.0)
	var victim := hire
	victim.stress = 80.0
	DLG.counsel(mira, victim)
	_check("Conversation lowers stress", victim.stress < 80.0)

	# 11) Begegnung
	NPC.start_plunderers()
	var res: String = NPC.fight()
	_check("The fight has a result and trains", res != "" and (SK.progress(mira, "combat_training") > 0.0 or SK.progress(hire, "combat_training") > 0.0))

	# 12) Saving and loading keeps everything
	SK.set_progress(mira, "hacking", 33.0)
	var traits_before: Array = mira.traits.duplicate()
	root.get_node("SaveSystem").save_game(true)
	gs.new_game()
	root.get_node("SaveSystem").load_game(true)
	var m2 = crew.player()
	_check("Skill unchanged after loading", absf(SK.progress(m2, "hacking") - 33.0) < 0.01)
	_check("Traits unchanged after loading", m2.traits == traits_before)
	_check("Crew complete after loading", crew.crew.size() == 2)
	_check("Lernhistorie gespeichert", not m2.skills.get("song", {}).get("hist", []).is_empty())

	print("\n%d OK, %d Fehler" % [_ok, _failed])
	quit(1 if _failed > 0 else 0)
