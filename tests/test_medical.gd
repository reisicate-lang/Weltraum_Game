## Tests: wounds and first aid after the Ostranauts wiki page "First Aid" (core): wounds per
## body part, bleeding and blood loss thresholds, infection and Dirty, splints and crippled
## limbs, pills, self-treatment from the ship's storage, sources, saving, character window
##   godot --headless --path . --script res://tests/boot.gd -- test_medical
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FAIL    " + name)

func _initialize() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var SS = root.get_node("SaveSystem")
	SS.slot = 966
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var IS = root.get_node("ItemSystem")
	var mira: CrewMember = root.get_node("CrewSystem").player()

	# 0) Wiki items and the start kit
	_check("Wiki prices: cloth 2, splint 149, Amoxicillin 14, Cavilo 6, Hydrocodone 17", IS.item("cloth").value == 2 and IS.item("splint").value == 149
		and IS.item("pill_antibiotic").value == 14 and IS.item("pill_painkiller").value == 6 and IS.item("pill_painkiller_rx").value == 17)
	_check("Start kit: 2 cloths, 2 painkillers", mira.inv.count("cloth") == 2 and mira.inv.count("pill_painkiller") == 2)

	# 1) Bleeding: blood loss after the wiki thresholds
	mira.inv.take("cloth", 9)
	var w: Dictionary = Medical.injure(mira, "cut", 0.8, "left arm")
	Medical.step(mira, 60.0, false)
	_check("Unbandaged cut bleeds (%.1f %% blood lost in 1 h)" % mira.med.blood, mira.med.blood > 5.0 and Medical.bleeding(mira) > 0.0)
	mira.med.blood = 35.0
	var food0: float = mira.needs.food
	Medical.step(mira, 60.0, false)
	_check("Severe blood loss (30–40 %%): hunger rises faster (%.1f)" % (food0 - mira.needs.food), food0 - mira.needs.food > 0.0)
	mira.med.blood = 45.0
	_check("Over 40 %: hypovolemic shock (heavy damage)", Medical.step(mira, 1.0, false) >= Medical.SHOCK_DAMAGE)
	mira.med.blood = 0.0

	# 2) Self-treatment with what is aboard (ship storage)
	var crate: Device = null
	for d in mira.grid().devices.values():
		if d.type == "crate" and not mira.grid().foreign(mira.grid().idx(d.pos)):
			crate = d
	crate.inv.add("cloth", 1, 100.0)
	crate.inv.add("watercan", 1, 100.0)
	var given: PackedStringArray = Medical.treat(mira)
	_check("Treatment from the crate: bandaged and cleaned (%s)" % ", ".join(given), w.bandaged and is_equal_approx(w.dis, 0.5) and crate.inv.count("cloth") == 0)
	_check("Bandaged: no more bleeding", Medical.bleeding(mira) == 0.0)

	# 3) Infection: Dirty doubles the risk, antibiotics help
	mira.med.wounds.clear()
	var clean_w: Dictionary = Medical.injure(mira, "cut", 0.9, "torso")
	mira.needs.hygiene = 90.0
	Medical.step(mira, 120.0, false)
	var inf_clean: float = clean_w.infect
	var dirty_w: Dictionary = Medical.injure(mira, "cut", 0.9, "head")
	mira.med.wounds.erase(clean_w)
	mira.needs.hygiene = 5.0
	Medical.step(mira, 120.0, false)
	_check("Dirty: a wound gets infected faster (%.3f vs %.3f)" % [dirty_w.infect, inf_clean], dirty_w.infect > inf_clean * 1.5)
	mira.needs.hygiene = 90.0
	mira.med.infection = 50.0
	mira.inv.add("pill_antibiotic", 1, 100.0)
	Medical.treat(mira)
	_check("Infected (35–65): takes an antibiotic", Medical.antibiotics(mira) and mira.inv.count("pill_antibiotic") == 0)
	mira.med.infection = 96.0
	_check("Over 95: septic shock", Medical.step(mira, 1.0, false) >= Medical.SHOCK_DAMAGE)
	mira.med = Medical.fresh()

	# 4) Fractures: splint or a crippled limb (wiki)
	var f1: Dictionary = Medical.injure(mira, "fracture", 0.1, "left leg")
	for k in 30:
		Medical.step(mira, 60.0, true)
	_check("Unsplinted leg fracture heals wrongly: leg crippled, movement −50 %%", not mira.med.wounds.has(f1) and "left leg" in mira.med.crippled and is_equal_approx(Medical.move_factor(mira), 0.5))
	mira.med = Medical.fresh()
	mira.inv.add("splint", 1, 100.0)
	var f2: Dictionary = Medical.injure(mira, "fracture", 0.1, "right arm")
	Medical.treat(mira)
	for k in 30:
		Medical.step(mira, 60.0, true)
	_check("Splinted fracture heals cleanly", f2.splint and not mira.med.wounds.has(f2) and mira.med.crippled.is_empty())
	Medical.injure(mira, "fracture", 0.5, "left arm")
	Medical.injure(mira, "bruise", 0.3, "left arm")
	_check("A new hit on an unsplinted fracture cripples the arm: work −50 %", "left arm" in mira.med.crippled and Medical.work_factor(mira) <= 0.5)

	# 5) Pain and painkillers
	mira.med = Medical.fresh()
	Medical.injure(mira, "fracture", 0.8, "torso")
	var p0: float = Medical.pain(mira)
	mira.inv.add("pill_painkiller_rx", 1, 100.0)
	Medical.treat(mira)
	_check("Strong pain (%.0f): prescription painkiller, pain dulled to %.0f" % [p0, Medical.pain(mira)], mira.inv.count("pill_painkiller_rx") == 0 and Medical.pain(mira) < p0 * 0.7)

	# 6) Sources: fire leaves a burn
	mira.med = Medical.fresh()
	var g = mira.grid()
	var ti: int = g.idx(mira.tile())
	g.fire[ti] = 1
	mira._update_body(0.1)
	g.fire[ti] = 0
	_check("Standing in fire: a burn", mira.med.wounds.any(func(x): return x.kind == "burn"))

	# 6b) Medical assistance (wiki 2.2): medical bed and nanorobotic first aid
	_check("Medical bed: 18 570 Cr (wiki), a bed for the room types", IS.device("medbed").item_value == 18570 and IS.device("medbed").need == "sleep")
	mira.med = Medical.fresh()
	var bw: Dictionary = Medical.injure(mira, "bruise", 0.9, "torso")
	Medical.step(mira, 60.0, true)
	var plain_heal: float = 0.9 - float(bw.sev)
	var bed := Device.new("medbed", Vector2i.ZERO)
	bed.powered = true
	bw.sev = 0.9
	mira.activity = {"need": "sleep", "dev": bed, "timer": 0.0}
	Medical.step(mira, 60.0, true)
	mira.activity = null
	_check("Asleep in a powered medical bed: wounds heal 20 %% faster (%.4f vs %.4f)" % [0.9 - float(bw.sev), plain_heal], is_equal_approx(0.9 - float(bw.sev), plain_heal * 1.2))
	var E = root.get_node("EconomySystem")
	E.credits = 1000
	bw.sev = 0.9
	_check("Nanorobotic First Aid at Tycho: %d Cr" % Medical.NANO_PRICE, Medical.nano_first_aid(mira) and E.credits == 1000 - Medical.NANO_PRICE and Medical.nano(mira) == 2)
	Medical.step(mira, 60.0, true)
	_check("Nanorobotics: wounds heal 40 %% faster (%.4f)" % (0.9 - float(bw.sev)), is_equal_approx(0.9 - float(bw.sev), plain_heal * 1.4))
	gs.time += (Medical.NANO_HOURS + 1.0) * 60.0
	_check("After 12 h the effect fades to the tail", Medical.nano(mira) == 1)

	# 6c) Diseases: Gastroenteritis from filth (Iron Stomach immune), Pneumonia, antibiotics cure
	mira.med = Medical.fresh()
	mira.needs.hygiene = 0.0
	var caught := false
	for k in 400:
		mira.needs.hygiene = 0.0
		Medical.step(mira, 60.0, false)
		if mira.med.disease.has("gastro"):
			caught = true
			break
	_check("Filthy: Gastroenteritis is caught sooner or later", caught)
	var t_iron: Array = mira.traits.duplicate()
	mira.med = Medical.fresh()
	mira.traits.append("iron_stomach")
	for k in 400:
		mira.needs.hygiene = 0.0
		Medical.step(mira, 60.0, false)
	_check("Iron Stomach: no Gastroenteritis", not mira.med.disease.has("gastro"))
	mira.traits.assign(t_iron)
	mira.needs.hygiene = 90.0
	Medical.catch(mira, "pneumonia")
	mira.inv.add("pill_antibiotic", 1, 100.0)
	Medical.treat(mira)
	Medical.step(mira, 1.0, false)
	_check("Pneumonia: antibiotics cure it", not mira.med.disease.has("pneumonia"))

	# 6d) Concussion (wiki): a hard blow to the head
	mira.med = Medical.fresh()
	var SKC = root.get_node("SkillSystem")
	var pil0: float = SKC.piloting_now(mira)
	Medical.injure(mira, "bruise", 0.2, "head")
	_check("A light bump on the head: no concussion", not Medical.concussed(mira))
	Medical.injure(mira, "bruise", 0.7, "head")
	_check("A hard blow: concussion for 24 h, Piloting −0.1 (Oblivious)", Medical.concussed(mira) and is_equal_approx(SKC.piloting_now(mira), pil0 - 0.1))
	mira.med.concussion.headache = true
	mira.med.concussion.dizzy = true
	var pain_c: float = Medical.pain(mira)
	mira.med.concussion.headache = false
	_check("Headache +10 pain, dizzy: movement ×0.75", is_equal_approx(pain_c - Medical.pain(mira), 10.0) and is_equal_approx(Medical.move_factor(mira), 0.75))
	gs.time += 25.0 * 60.0
	_check("After 24 h the concussion is over", not Medical.concussed(mira))

	# 7) Saving/loading and the character window
	mira.med = Medical.fresh()
	Medical.injure(mira, "burn", 0.4, "torso")
	Medical.cripple(mira, "right leg")
	SS.save_game()
	SS.load_game(true)
	var m2: CrewMember = root.get_node("CrewSystem").player()
	_check("Saving/loading keeps wounds and crippled limbs", m2.med.wounds.size() == 1 and "right leg" in m2.med.crippled)
	var cui = root.get_node("UIManager").char_ui
	gs.selected = m2
	cui.panel.visible = true
	cui._last = ""
	cui.refresh()
	var shown := false
	for x in cui.box.get_children():
		if x is Label and String(x.text).begins_with("✚"):
			shown = true
	_check("Character window lists wounds", shown)

	print("%d OK, %d failed" % [ok_count, fail_count])
	quit()
