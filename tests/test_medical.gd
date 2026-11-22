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

	# 6c2) Cholera and Hepatitis in stages (wiki 3.4)
	mira.med = Medical.fresh()
	mira.needs.water = 100.0
	Medical.catch(mira, "cholera")
	Medical.step(mira, 60.0, false)
	var w1: float = 100.0 - mira.needs.water
	_check("Cholera stage 1: indicator only, no extra thirst", int(mira.med.disease.cholera.stage) == 1)
	gs.time += 13.0 * 60.0
	mira.needs.water = 100.0
	Medical.step(mira, 60.0, false)
	_check("Cholera stage 2: hydration rate +2.5 (%.1f extra thirst in 1 h, stage 1: %.1f)" % [100.0 - mira.needs.water, w1], int(mira.med.disease.cholera.stage) == 2 and is_zero_approx(w1) and (100.0 - mira.needs.water) > 1.0)
	mira.inv.add("pill_antibiotic", 1, 100.0)
	Medical.treat(mira)
	Medical.step(mira, 1.0, false)
	_check("Antibiotics cure Cholera", not mira.med.disease.has("cholera"))
	mira.med = Medical.fresh()
	var p_h0: float = Medical.pain(mira)
	Medical.catch(mira, "hepatitis")
	gs.time += 25.0 * 60.0
	Medical.step(mira, 1.0, false)
	_check("Hepatitis stage 2: pain +10", int(mira.med.disease.hepatitis.stage) == 2 and is_equal_approx(Medical.pain(mira) - p_h0, 10.0))
	mira.inv.add("pill_antibiotic", 1, 100.0)
	Medical.treat(mira)
	Medical.step(mira, 1.0, false)
	_check("Hepatitis stage 2: antibiotics no longer help (none taken)", mira.med.disease.has("hepatitis") and mira.inv.count("pill_antibiotic") == 1)
	gs.time += 24.0 * 60.0
	Medical.step(mira, 1.0, false)
	_check("Stage 3 (severe): pain +15", int(mira.med.disease.hepatitis.stage) == 3 and is_equal_approx(Medical.pain(mira) - p_h0, 15.0))
	gs.time += 100.0 * 60.0
	Medical.step(mira, 1.0, false)
	_check("After 144 h Hepatitis is over", not mira.med.disease.has("hepatitis"))
	mira.inv.take("pill_antibiotic", 1)
	mira.med = Medical.fresh()

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

	# 6e) Chemical Pneumonitis from contaminants (wiki First Aid 1, 3.4)
	mira.med = Medical.fresh()
	var g2 = mira.grid()
	var mt: int = g2.idx(mira.tile())
	g2.add_tox(mt, 2.0)
	_check("Over 1 kPa contaminants: unsafe air", not mira.safe_air(mt))
	mira._update_body(1.0)
	_check("A minute of breathing it: no Pneumonitis yet", not mira.med.disease.has("pneumonitis"))
	for k in 6:
		mira._update_body(1.0)
	_check("A few minutes: Chemical Pneumonitis", mira.med.disease.has("pneumonitis"))
	g2.tox[mt] = 0.0
	var p_pn: float = Medical.pain(mira)
	mira.inv.add("pill_antibiotic", 1, 100.0)
	Medical.treat(mira)
	_check("Pain +10; antibiotics are not wasted on it (pain %.0f)" % p_pn, p_pn >= 10.0 and mira.inv.count("pill_antibiotic") == 1)
	Medical.step(mira, 60.0, false)
	_check("Coughing blood (%.2f %% lost in 1 h)" % mira.med.blood, mira.med.blood > 0.0)
	gs.time += 40.0 * 60.0
	Medical.step(mira, 1.0, false)
	_check("After 40 h it is still there", mira.med.disease.has("pneumonitis"))
	gs.time += 33.0 * 60.0
	Medical.step(mira, 1.0, false)
	_check("After 72 h away from the gas it is over", not mira.med.disease.has("pneumonitis"))
	mira.inv.take("pill_antibiotic", 1)

	# 6f) Gas hazards (wiki Health and Safety 4.9 and 2.1)
	mira.med = Medical.fresh()
	_check("CO₂ 0.4 kPa: no condition", is_zero_approx(Medical.gas_hazards(mira, 0.4, 0.0, 21.0, false)) and mira.med.gas.is_empty())
	Medical.gas_hazards(mira, 1.5, 0.0, 21.0, false)
	_check("CO₂ 1.5 kPa: Mild Hypercapnia (%s)" % str(mira.med.gas), mira.med.gas == ["Mild Hypercapnia"])
	Medical.gas_hazards(mira, 6.0, 0.0, 21.0, false)
	_check("CO₂ 6 kPa: Severe Hypercapnia, dizzy", mira.med.gas == ["Severe Hypercapnia"] and is_equal_approx(Medical.move_factor(mira), 0.75))
	_check("CO₂ over 9 kPa: lethal (%.0f per hour)" % Medical.gas_hazards(mira, 9.5, 0.0, 21.0, false), Medical.gas_hazards(mira, 9.5, 0.0, 21.0, false) >= 600.0)
	_check("In a working suit: nothing", is_zero_approx(Medical.gas_hazards(mira, 9.5, 2.0, 0.0, true)) and mira.med.gas.is_empty())
	Medical.gas_hazards(mira, 0.0, 0.2, 21.0, false)
	_check("Contaminants 0.2 kPa: Burning Throat and Eyes", mira.med.gas == ["Burning Throat and Eyes"])
	_check("Contaminants over 1 kPa: Lethal Inhalation", Medical.gas_hazards(mira, 0.0, 1.5, 21.0, false) >= 300.0 and mira.med.gas == ["Lethal Inhalation"])
	var pe: float = Medical.pain(mira)
	Medical.gas_hazards(mira, 0.0, 0.0, 1.0, false)
	_check("O₂ under 3 kPa without a suit: Ebullism, pain +10", mira.med.gas.has("Ebullism") and is_equal_approx(Medical.pain(mira) - pe, 10.0))
	Medical.gas_hazards(mira, 0.0, 0.0, 21.0, false)
	_check("Ebullism lingers after getting to air", Medical.ebullism(mira) and mira.med.gas == ["Ebullism"])
	gs.time += 31.0
	Medical.gas_hazards(mira, 0.0, 0.0, 21.0, false)
	_check("After 30 minutes it has passed", not Medical.ebullism(mira) and mira.med.gas.is_empty())
	mira.med = Medical.fresh()

	# 6g) Body temperature stages (wiki Health and Safety 2.3)
	_check("Stages: 37 Comfortable, 33 Cold, 30 Freezing, 39 Heat Exhaustion, 20 Froze to Death, 43 Organ Failure",
		Medical.body_stage(37.0) == "Comfortable" and Medical.body_stage(33.0) == "Cold" and Medical.body_stage(30.0) == "Freezing"
		and Medical.body_stage(39.0) == "Heat Exhaustion" and Medical.body_stage(20.0) == "Froze to Death" and Medical.body_stage(43.0) == "Organ Failure")
	var bt := 37.0
	for k in 10:
		bt = Medical.body_step(bt, 21.0, 1.0, 1.0)
	_check("10 h at 21 °C room air: still Comfortable (%.2f °C)" % bt, Medical.body_stage(bt) == "Comfortable")
	bt = 37.0
	for k in 10:
		bt = Medical.body_step(bt, 60.0, 1.0, 1.0)
	_check("10 h at 60 °C: overheating (%.2f °C, %s)" % [bt, Medical.body_stage(bt)], bt > 37.75)
	mira.med = Medical.fresh()
	mira.body_temp = 39.5
	mira.needs.water = 100.0
	Medical.body_effects(mira, 1.0, false)
	_check("Heat Exhaustion: hydration rate +0.5 (%.1f)" % (100.0 - mira.needs.water), mira.needs.water < 100.0)
	mira.body_temp = 41.5
	_check("Heat Stroke: dizzy, movement ×0.75", is_equal_approx(Medical.move_factor(mira), 0.75))
	mira.body_temp = 30.0
	_check("Freezing: wounds heal slower (×%.2f)" % Medical.body_heal(mira), is_equal_approx(Medical.body_heal(mira), 0.75))
	mira.body_temp = 43.0
	_check("Organ Failure: deadly", Medical.body_effects(mira, 1.0, false) >= Medical.SHOCK_DAMAGE)
	mira.body_temp = 37.0
	mira.needs.water = 90.0

	# 6h) Malnutrition (wiki Health and Safety 4.8)
	mira.med = Medical.fresh()
	_check("Start: Well-Fed", Medical.nutrition_stage(mira) == "Well-Fed")
	Medical.nutrition_step(mira, 80.0)
	_check("80 h without food: Malnourished, healing ×0.75", Medical.nutrition_stage(mira) == "Malnourished")
	Medical.eat(mira, 30.0)
	_check("A meal lowers StatFood (%.0f)" % float(mira.med.nutrition), float(mira.med.nutrition) < 80.0)
	mira.med.nutrition = 700.0
	_check("Starving", Medical.nutrition_stage(mira) == "Starving")
	mira.med.nutrition = 1400.0
	var h0: float = mira.health
	mira.needs.food = 0.0
	mira._update_body(1.0)
	_check("Starved: deadly (%.1f health lost in 1 min)" % (h0 - mira.health), h0 - mira.health > 5.0)
	mira.med = Medical.fresh()
	mira.health = 100.0
	mira.needs = {"food": 0.0, "water": 100.0, "sleep": 100.0, "hygiene": 90.0, "air": 100.0}
	mira.body_temp = 37.0
	mira.health = 90.0
	h0 = mira.health
	mira._update_body(10.0)
	_check("An empty hunger bar alone does no damage (wiki) (%.1f → %.1f, %s)" % [h0, mira.health, str(mira.med.gas)], mira.health >= h0)
	mira.needs.food = 90.0

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
