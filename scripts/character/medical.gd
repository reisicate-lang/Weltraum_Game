## Wounds and first aid after the Ostranauts wiki page "First Aid" (core):
## wounds per body part (cut, bruise, fracture, burn), blood loss, limb and whole-body infection,
## pain, crippled limbs, and self-treatment with cloth, water, splint and pills.
## From the wiki: blood loss 15/30/40 % (minor, severe, hypovolemic shock), infection 35/65/95
## (infection, sepsis, septic shock), water disinfects 50 %, antibiotics infection healing +20 %,
## painkillers pain threshold +20 % / +70 %, crippled arm work −50 %, crippled leg movement −50 %,
## Dirty and Immunosuppressed raise the infection risk, an unsplinted fracture heals wrongly.
## Rates and durations are our own choice (the wiki gives none).
## State per character: CrewMember.med = {wounds, blood, infection, crippled, pain_until, pain_f, abx_until}
class_name Medical
extends RefCounted

const PARTS := ["head", "torso", "left arm", "right arm", "left leg", "right leg"]
const LIMBS := ["left arm", "right arm", "left leg", "right leg"]
const HEAL := {"cut": 0.03, "bruise": 0.06, "fracture": 0.008, "burn": 0.015}   ## severity per hour
const PAIN := {"cut": 20.0, "bruise": 10.0, "fracture": 50.0, "burn": 20.0}     ## pain at severity 1
const BLEED_PER_H := 8.0          ## blood % per hour at severity 1, unbandaged
const BLOOD_REGEN := 1.0          ## blood % per hour without bleeding
const INFECT_GAIN := 0.03         ## limb infection per hour on an open wound
const BODY_INFECT := 6.0          ## whole-body infection per hour and limb infection
const BODY_CLEAR := 2.0           ## whole-body infection fought off per hour
const SHOCK_DAMAGE := 600.0       ## health per hour in hypovolemic or septic shock (like suffocating)
const PILL_HOURS := 6.0
const ABX_HOURS := 12.0
const ITEMS := {"cloth": "cloth", "water": "watercan", "splint": "splint", "antibiotic": "pill_antibiotic",
	"painkiller": "pill_painkiller", "painkiller_rx": "pill_painkiller_rx"}

## Medical assistance (wiki 2.2): powered medical bed while sleeping; Nanorobotic First Aid at
## a station's Self Care service (price and durations our own choice).
const MEDBED := {"wound": 1.2, "blood": 0.45, "infection": 1.05, "pain": 0.1}
const NANO_PRICE := 500
const NANO_HOURS := 12.0
const NANO_TAIL_HOURS := 24.0
## Diseases (wiki 3.4): Gastroenteritis (50 % from "Filthy" hygiene, Iron Stomach immune) and
## Pneumonia (can follow torso wounds); antibiotics cure both. Chances per hour our own choice.
const FILTHY_AT := 5.0
const GASTRO_PER_H := 0.04
const PNEUMONIA_PER_H := 0.1
const DISEASE_HOURS := 48.0
const DISEASE_NAMES := {"gastro": "Gastroenteritis", "pneumonia": "Pneumonia", "pneumonitis": "Chemical Pneumonitis",
	"cholera": "Cholera", "hepatitis": "Hepatitis"}
## Staged diseases (wiki 3.4): stage k lasts until hour STAGES[id][k-1] after catching, then over.
## Cholera: 1 indicator, 2 diarrhea/nausea/vomiting, infection +1, infection rate +5, hydration +2.5,
## 3 severe: infection rate +15, hydration +5. Hepatitis: 1 indicator, 2 pain +10, infection rate +14,
## fatigue +0.25, 3 severe: nausea, vomiting, diarrhea, headache, pain +15, infection rate +15,
## 4 pain +10, infection rate +12. Antibiotics cure Cholera and Hepatitis stage 1 (wiki).
## Stage durations, how they are caught and "infection rate" as +0.1 infection per hour per point
## are our own choice (the wiki says Cholera is food/water-borne and does not say how Hepatitis spreads).
const STAGES := {"cholera": [12.0, 36.0, 72.0], "hepatitis": [24.0, 48.0, 96.0, 144.0]}
const STAGE_FX := {
	"cholera": [{}, {"infect": 5.0, "thirst": 2.5, "sick": true}, {"infect": 15.0, "thirst": 5.0, "sick": true}],
	"hepatitis": [{}, {"infect": 14.0, "pain": 10.0, "fatigue": 0.25}, {"infect": 15.0, "pain": 15.0, "sick": true}, {"infect": 12.0, "pain": 10.0}]}
const CHOLERA_PER_H := 0.01       ## Filthy: dirty hands on food and water
const HEPATITIS_PER_H := 0.02     ## per infected open wound (blood-borne)

## Current stage of a staged disease (0 = over)
static func stage_of(id: String, dz: Dictionary) -> int:
	var hrs := (GameState.time - float(dz.since)) / 60.0
	var b: Array = STAGES[id]
	for k in b.size():
		if hrs < float(b[k]):
			return k + 1
	return 0

## Do antibiotics help against this disease now? (not Pneumonitis, Hepatitis only in stage 1)
static func abx_cures(id: String, dz: Dictionary) -> bool:
	if id == "pneumonitis":
		return false
	if id == "hepatitis":
		return int(dz.get("stage", 1)) <= 1
	return true
## Chemical Pneumonitis (wiki: inhaled NH3/H2SO4, much more dangerous than pneumonia; severe
## coughing, dyspnea, coughing blood, pain +10). Not cured by antibiotics: it heals after a while
## away from the gas, twice as fast in a medical bed. Dose, duration and effects our choice.
const PNEUMONITIS_DOSE := 10.0       ## kPa × minutes of breathing contaminants
const PNEUMONITIS_HOURS := 72.0
const PNEUMONITIS_BLOOD := 0.5       ## blood lost per hour (coughing blood)

## Body temperature (Ostranauts Health and Safety 2.2/2.3). Stage upper bounds and effects from the
## wiki: Froze to Death < 20.05 (dead), Hypothermia (slower healing), Freezing (slower healing),
## Cold, Comfortable, Overheating, Heat Exhaustion > 38.85 (hydration +0.5), Heat Stroke > 41.15
## (dizzy, hydration +1), Organ Failure > 42.55 (dead). Air below 22.85 °C cools the body, above
## 25.85 °C heats it. Rates, the healing factors and the dying speed are our choice.
const BODY_STAGES := [[20.05, "Froze to Death"], [27.85, "Hypothermia"], [32.25, "Freezing"], [35.65, "Cold"],
	[37.75, "Comfortable"], [38.85, "Overheating"], [41.15, "Heat Exhaustion"], [42.55, "Heat Stroke"], [1000.0, "Organ Failure"]]
const AIR_MILD := Vector2(22.85, 25.85)
const BODY_COLD := 35.65
const BODY_HOT := 38.85
const BODY_COLD_K := 0.1      ## °C of body temperature lost per °C of air below 22.85 (equilibrium)
const BODY_HEAT_K := 0.05     ## °C gained per °C of air above 25.85
const BODY_RATE := 1.0        ## approach to the equilibrium per hour
const BODY_HEAL := {"Hypothermia": 0.5, "Freezing": 0.75}

static func body_stage(t: float) -> String:
	for st in BODY_STAGES:
		if t < float(st[0]):
			return st[1]
	return "Organ Failure"

## New body temperature after h hours in air of temperature air_t
static func body_step(t: float, air_t: float, insulation: float, h: float) -> float:
	var target := 37.0 - maxf(0.0, AIR_MILD.x - air_t) * BODY_COLD_K * insulation + maxf(0.0, air_t - AIR_MILD.y) * BODY_HEAT_K
	return clampf(t + (target - t) * minf(1.0, BODY_RATE * h), 15.0, 46.0)

## Effects of the body temperature stage; returns damage per hour
static func body_effects(c: CrewMember, h: float, sleeping: bool) -> float:
	match body_stage(c.body_temp):
		"Froze to Death", "Organ Failure":
			return SHOCK_DAMAGE
		"Heat Exhaustion":
			c.needs.water -= Config.NEEDS.water.decay * 0.5 * h
		"Heat Stroke":
			c.needs.water -= Config.NEEDS.water.decay * 1.0 * h
	return 0.0

static func body_heal(c: CrewMember) -> float:
	return float(BODY_HEAL.get(body_stage(c.body_temp), 1.0))

## Malnutrition (Ostranauts Health and Safety 4.8): "StatFood" rises by 1 per hour, faster when cold,
## bleeding or infected, slower when unconscious; meals lower it. Stages from the wiki: Well-Fed < 7,
## Stomach Growling < 72, Malnourished < 650 (slower healing), Starving < 1350 (much slower healing),
## Starved (death). The hunger bar itself does no damage (wiki: none of the bars kill).
## Modifier sizes, meal effect and healing factors are our choice.
const NUTRITION_STAGES := [[7.0, "Well-Fed"], [72.0, "Stomach Growling"], [650.0, "Malnourished"], [1350.0, "Starving"], [1.0e9, "Starved"]]
const NUTRITION_HEAL := {"Malnourished": 0.75, "Starving": 0.5}
## A full meal lowers StatFood by this many hours (twice what it covers, so a backlog recovers slowly)
const MEAL_NUTRITION := 12.0

static func nutrition_stage(c: CrewMember) -> String:
	var v := float(c.med.get("nutrition", 0.0))
	for st in NUTRITION_STAGES:
		if v < float(st[0]):
			return st[1]
	return "Starved"

static func nutrition_step(c: CrewMember, h: float) -> void:
	var f := 1.0
	if c.body_temp < BODY_COLD:
		f += 0.25          # cold
	if float(c.med.blood) >= 15.0:
		f += 0.15          # blood loss (wiki: food rate +0.15 / +0.25)
	if float(c.med.infection) >= 35.0:
		f += 0.25          # infection (wiki: food rate +0.25)
	if c.unconscious:
		f *= 0.5           # wiki: unconscious food rate −0.5
	c.med.nutrition = float(c.med.get("nutrition", 0.0)) + f * h

## A meal of this many hunger points
static func eat(c: CrewMember, points: float) -> void:
	var per_h: float = Config.NEEDS.food.decay
	c.med.nutrition = maxf(0.0, float(c.med.get("nutrition", 0.0)) - points / per_h * MEAL_NUTRITION / 6.0)

## Gas hazards (Ostranauts Health and Safety 2.1 and 4.9). Thresholds and names from the wiki;
## the wiki gives effects only for the deadly stages, the damage per hour below is our choice.
## CO₂ poisoning: Malaise 0.5, Mild Hypercapnia 1, Moderate 2, Advanced 3.066, Severe 5.066 (dizzy),
## Critical 8 (muscle tremors), Lethal > 9 (asphyxiating, death soon).
## Contaminants (NH3 rows): Stinging Throat and Eyes 0.003, Burning Throat and Eyes 0.05,
## Lethal Inhalation > 1 (death imminent). O₂ below 3 kPa (Void Atmo): Gasping, Ebullism (pain +10).
const CO2_STAGES := [[9.0, "Lethal Hypercapnia", 600.0], [8.0, "Critical Hypercapnia", 60.0], [5.066, "Severe Hypercapnia", 10.0],
	[3.066, "Advanced Hypercapnia", 3.0], [2.0, "Moderate Hypercapnia", 0.0], [1.0, "Mild Hypercapnia", 0.0], [0.5, "Malaise", 0.0]]
const TOX_STAGES := [[1.0, "Lethal Inhalation", 300.0], [0.05, "Burning Throat and Eyes", 2.0], [0.003, "Stinging Throat and Eyes", 0.0]]
const VOID_O2 := 3.0
const EBULLISM_MINUTES := 30.0
## Stages that raise an alarm toast
const GAS_ALERT := ["Lethal Hypercapnia", "Critical Hypercapnia", "Severe Hypercapnia", "Advanced Hypercapnia", "Lethal Inhalation", "Burning Throat and Eyes", "Ebullism"]

## Current gas conditions and damage per hour; c.med.gas lists the condition names (worst first)
static func gas_hazards(c: CrewMember, co2: float, tox: float, o2: float, in_suit: bool) -> float:
	var names: Array = []
	var dmg := 0.0
	if not in_suit:
		if o2 < VOID_O2:
			c.med.ebullism_until = GameState.time + EBULLISM_MINUTES
		for st in CO2_STAGES:
			if co2 > float(st[0]):
				names.append(st[1])
				dmg += float(st[2])
				break
		for st in TOX_STAGES:
			if tox > float(st[0]):
				names.append(st[1])
				dmg += float(st[2])
				break
	if ebullism(c):
		names.push_front("Ebullism")
	names.sort_custom(func(a, b): return _gas_rank(a) < _gas_rank(b))
	c.med.gas = names
	return dmg

static func _gas_rank(n: String) -> int:
	var k := GAS_ALERT.find(n)
	return k if k >= 0 else 99

static func ebullism(c: CrewMember) -> bool:
	return GameState.time < float(c.med.get("ebullism_until", -1.0))

## Severe Hypercapnia and worse: dizzy
static func gas_dizzy(c: CrewMember) -> bool:
	for n in c.med.get("gas", []):
		if String(n) in ["Severe Hypercapnia", "Critical Hypercapnia", "Lethal Hypercapnia"]:
			return true
	return false

## Breathing contaminants for dt minutes at kPa
static func expose(c: CrewMember, kpa: float, dt: float) -> void:
	c.med.tox_dose = float(c.med.get("tox_dose", 0.0)) + kpa * dt
	if float(c.med.tox_dose) >= PNEUMONITIS_DOSE:
		catch(c, "pneumonitis")
		c.med.disease.pneumonitis.since = GameState.time   # still breathing it: no healing

## Concussion (wiki 3.1): temporary Insomniac, Obtuse, Oblivious; 80 % headache, 60 % dizzy.
## In this game: sleep recovery ×0.75 (Insomniac), Piloting −0.1 (Oblivious), headache pain +10,
## dizzy movement −25 % (our choice). Duration and trigger (head blow ≥ 0.5) our choice.
const CONCUSSION_SEV := 0.5
const CONCUSSION_HOURS := 24.0

static func concussed(c: CrewMember) -> bool:
	var cc = c.med.get("concussion")
	return cc is Dictionary and GameState.time < float(cc.get("until", 0.0))

static func fresh() -> Dictionary:
	return {"wounds": [], "blood": 0.0, "infection": 0.0, "crippled": [], "pain_until": 0.0, "pain_f": 0.0, "abx_until": 0.0,
		"nano_until": 0.0, "nano_tail": 0.0, "disease": {}, "tox_dose": 0.0}

## Asleep in a powered medical bed?
static func on_medbed(c: CrewMember) -> bool:
	if c.activity == null or c.activity.get("need", "") != "sleep":
		return false
	var d = c.activity.get("dev")
	return d is Device and d.type == "medbed" and d.powered and not d.broken

static func nano(c: CrewMember) -> int:
	if GameState.time < float(c.med.get("nano_until", 0.0)):
		return 2
	return 1 if GameState.time < float(c.med.get("nano_tail", 0.0)) else 0

## Nanorobotic First Aid (Self Care service at a station)
static func nano_first_aid(c: CrewMember) -> bool:
	if PhysicsSystem.station().is_empty():
		GameState.toast("Nanorobotic First Aid only at a station.", "bad")
		return false
	if EconomySystem.credits < NANO_PRICE:
		GameState.toast("Nanorobotic First Aid costs %d Cr." % NANO_PRICE, "bad")
		return false
	EconomySystem.credits -= NANO_PRICE
	EconomySystem.book("Nanorobotic First Aid: " + c.display_name, -NANO_PRICE)
	c.med.nano_until = GameState.time + NANO_HOURS * 60.0
	c.med.nano_tail = c.med.nano_until + NANO_TAIL_HOURS * 60.0
	GameState.toast("%s gets nanorobotic first aid: wounds heal 40 %% faster for %d hours." % [c.display_name, int(NANO_HOURS)])
	return true

static func catch(c: CrewMember, id: String) -> void:
	if c.med.disease.has(id):
		return
	c.med.disease[id] = {"stage": 2 if id in ["pneumonia", "pneumonitis"] else 1, "since": GameState.time}
	if STAGES.has(id):
		GameState.toast("%s feels slightly off (%s, stage 1)." % [c.display_name, DISEASE_NAMES[id]], "bad")
		return
	GameState.toast("%s has caught %s." % [c.display_name, DISEASE_NAMES[id]], "bad")

static func open(w: Dictionary) -> bool:
	return w.kind == "cut" or w.kind == "burn"

static func severity_name(s: float) -> String:
	return "minor" if s < 0.25 else ("moderate" if s < 0.5 else "severe")

# ---------------- Getting hurt ----------------

## A new wound; part "" = random. Hitting a limb with an unsplinted fracture cripples it (wiki).
static func injure(c: CrewMember, kind: String, sev: float, part: String = "") -> Dictionary:
	if part == "":
		part = PARTS.pick_random()
	if part in LIMBS and not part in c.med.crippled and kind != "burn":
		for w in c.med.wounds:
			if w.part == part and w.kind == "fracture" and not w.splint:
				cripple(c, part)
				break
	var w := {"part": part, "kind": kind, "sev": clampf(sev, 0.05, 1.0), "bandaged": false, "dis": 0.0, "infect": 0.0, "splint": false}
	c.med.wounds.append(w)
	# A hard blow to the head: concussion (wiki 3.1)
	if part == "head" and kind != "burn" and w.sev >= CONCUSSION_SEV and not concussed(c):
		c.med.concussion = {"until": GameState.time + CONCUSSION_HOURS * 60.0, "headache": randf() < 0.8, "dizzy": randf() < 0.6}
		GameState.toast("%s has a concussion." % c.display_name, "bad")
	GameState.toast("%s: %s %s on the %s%s." % [c.display_name, severity_name(w.sev), kind, part, ", bleeding" if kind == "cut" else ""], "bad")
	return w

static func cripple(c: CrewMember, part: String) -> void:
	if part in LIMBS and not part in c.med.crippled:
		c.med.crippled.append(part)
		GameState.toast("%s: the %s is crippled for good." % [c.display_name, part], "bad")

## Random wound mix of a fight or an accident
static func hurt(c: CrewMember, count: int, fracture_chance: float = 0.15) -> void:
	for k in count:
		var r := randf()
		var kind := "fracture" if r < fracture_chance else ("cut" if r < 0.6 else "bruise")
		injure(c, kind, randf_range(0.2, 0.7))

# ---------------- Over time ----------------

static func bleeding(c: CrewMember) -> float:
	var b := 0.0
	for w in c.med.wounds:
		if open(w) and not w.bandaged:
			b += float(w.sev) * BLEED_PER_H
	return b

static func pain(c: CrewMember) -> float:
	var p := 0.0
	for w in c.med.wounds:
		p += float(PAIN[w.kind]) * float(w.sev) + (10.0 if w.kind == "fracture" else 0.0)
	if concussed(c) and bool(c.med.concussion.get("headache", false)):
		p += 10.0   # wiki: headache +10
	var pn = c.med.disease.get("pneumonia")
	if pn is Dictionary and int(pn.stage) >= 3:
		p += 10.0   # wiki: severe pneumonia pain +10
	if c.med.disease.has("pneumonitis"):
		p += 10.0   # wiki: severe pneumonitis pain +10
	if ebullism(c):
		p += 10.0   # wiki: ebullism (space without suit) pain +10
	for id in STAGES:
		var dz = c.med.disease.get(id)
		if dz is Dictionary and int(dz.stage) >= 1:
			p += float((STAGE_FX[id][int(dz.stage) - 1] as Dictionary).get("pain", 0.0))
	var f := 0.0
	if GameState.time < float(c.med.pain_until):
		f += float(c.med.pain_f)
	if on_medbed(c):
		f += float(MEDBED.pain)
	return p / (1.0 + f)

static func antibiotics(c: CrewMember) -> bool:
	return GameState.time < float(c.med.abx_until)

## One step (dt in game minutes). Returns damage per hour for the health calculation.
static func step(c: CrewMember, dt: float, sleeping: bool) -> float:
	var m: Dictionary = c.med
	var h := dt / 60.0
	var heal: float = TraitSystem.factor(c, "recovery") * (1.5 if sleeping or c.unconscious else 1.0) * (Config.DIRTY_RECOVERY if c.is_dirty() else 1.0) * body_heal(c) * float(NUTRITION_HEAL.get(nutrition_stage(c), 1.0))
	var bed := on_medbed(c)
	var nn := nano(c)
	var wound_f: float = (float(MEDBED.wound) if bed else 1.0) * (1.4 if nn == 2 else (1.15 if nn == 1 else 1.0))
	var regen: float = BLOOD_REGEN * heal * (1.4 if nn == 2 else 1.0) + (float(MEDBED.blood) if bed else 0.0) + (0.45 if nn == 1 else 0.0)
	var bleed := bleeding(c)
	m.blood = clampf(float(m.blood) + (bleed - (regen if bleed <= 0.0 else 0.0)) * h, 0.0, 100.0)
	var infect_risk: float = (2.0 if c.is_dirty() else 1.0) * (1.2 if c.traits.has("immunosuppressed") else 1.0)
	var body_gain := 0.0
	for k in range(m.wounds.size() - 1, -1, -1):
		var w: Dictionary = m.wounds[k]
		if open(w):
			w.infect = clampf(float(w.infect) + INFECT_GAIN * h * (1.0 - float(w.dis)) * infect_risk * (0.5 if w.bandaged else 1.0)
				- (0.05 if antibiotics(c) else 0.01) * h * heal, 0.0, 1.0)
			body_gain += float(w.infect)
		var rate: float = float(HEAL[w.kind]) * heal * wound_f * (1.0 - 0.8 * float(w.infect))
		if w.kind == "cut" and w.bandaged:
			rate *= 2.0
		if w.kind == "fracture" and w.splint:
			rate *= 2.0
		w.sev = float(w.sev) - rate * h
		if float(w.sev) <= 0.0:
			m.wounds.remove_at(k)
			if w.kind == "fracture" and not w.splint and w.part in LIMBS:
				GameState.toast("%s: the fracture of the %s healed without a splint." % [c.display_name, w.part], "bad")
				cripple(c, w.part)
	var clear: float = BODY_CLEAR * heal * (1.2 if antibiotics(c) else 1.0) * (float(MEDBED.infection) if bed else 1.0)
	# Diseases: catching, effects, cure by antibiotics or after a while
	if not m.has("disease"):
		m.disease = {}
	if c.needs.hygiene < FILTHY_AT and not c.traits.has("iron_stomach") and randf() < GASTRO_PER_H * 0.5 * (2.0 if c.traits.has("weak_stomach") else 1.0) * h:
		catch(c, "gastro")
	if c.needs.hygiene < FILTHY_AT and randf() < CHOLERA_PER_H * h:
		catch(c, "cholera")
	for w in m.wounds:
		if w.part == "torso" and open(w) and float(w.infect) >= 0.25 and randf() < PNEUMONIA_PER_H * h:
			catch(c, "pneumonia")
		if open(w) and float(w.infect) >= 0.25 and randf() < HEPATITIS_PER_H * h:
			catch(c, "hepatitis")
	# Contaminant dose wears off away from the gas (our choice: 0.1 kPa·min per minute)
	m.tox_dose = maxf(0.0, float(m.get("tox_dose", 0.0)) - 0.1 * dt)
	for id in m.disease.keys():
		var dz: Dictionary = m.disease[id]
		if id == "pneumonitis":
			if bed:
				dz.since = float(dz.since) - dt   # medical bed: heals twice as fast
			if GameState.time - float(dz.since) > PNEUMONITIS_HOURS * 60.0:
				m.disease.erase(id)
				GameState.toast("%s is over the %s." % [c.display_name, DISEASE_NAMES[id]])
				continue
			m.blood = clampf(float(m.blood) + PNEUMONITIS_BLOOD * h, 0.0, 100.0)   # coughing blood
			if not sleeping:
				c.needs.sleep -= Config.NEEDS.sleep.decay * 0.5 * h                # dyspnea: tires
			continue
		if STAGES.has(id):
			var st := stage_of(id, dz)
			if st == 0 or (antibiotics(c) and abx_cures(id, dz)):
				m.disease.erase(id)
				GameState.toast("%s is over the %s." % [c.display_name, DISEASE_NAMES[id]])
				continue
			if st > int(dz.stage):
				GameState.toast("%s: %s, stage %d." % [c.display_name, DISEASE_NAMES[id], st], "bad")
			dz.stage = st
			var fx: Dictionary = STAGE_FX[id][st - 1]
			if fx.is_empty():
				continue                                   # indicator stage, no effect
			body_gain += (1.0 + float(fx.get("infect", 0.0)) * 0.1) / BODY_INFECT
			c.needs.water -= Config.NEEDS.water.decay * float(fx.get("thirst", 0.0)) * h
			if bool(fx.get("sick", false)):
				c.needs.hygiene -= 5.0 * h                 # diarrhea
				c.needs.food -= Config.NEEDS.food.decay * 0.5 * h   # vomiting
			if not sleeping:
				c.needs.sleep -= Config.NEEDS.sleep.decay * float(fx.get("fatigue", 0.0)) * h
			continue
		if antibiotics(c) or GameState.time - float(dz.since) > DISEASE_HOURS * 60.0:
			m.disease.erase(id)
			GameState.toast("%s is over the %s." % [c.display_name, DISEASE_NAMES[id]])
			continue
		body_gain += 1.0 / BODY_INFECT   # wiki: infection stat +1 (per hour)
		if id == "gastro":
			c.needs.hygiene -= 5.0 * h        # diarrhea
			c.needs.water -= Config.NEEDS.water.decay * 0.5 * h
		if id == "pneumonia" and GameState.time - float(dz.since) > 24.0 * 60.0:
			dz.stage = 3                       # severe: pain +10
	m.infection = clampf(float(m.infection) + (body_gain * BODY_INFECT - clear) * h, 0.0, 100.0)
	# Effects after the wiki thresholds
	var extra := 0.0          # extra food/hydration rate
	var fatigue := 0.0        # extra fatigue gain
	if float(m.blood) >= 30.0:
		extra += 0.25
		fatigue += 1.0
	elif float(m.blood) >= 15.0:
		extra += 0.15
		fatigue += 0.5
	if float(m.infection) >= 65.0:
		extra += 0.25
		fatigue += 1.0
		c.needs.hygiene -= Config.NEEDS.hygiene.decay * 1.0 * h
	elif float(m.infection) >= 35.0:
		extra += 0.25
		fatigue += 0.5
		c.needs.hygiene -= Config.NEEDS.hygiene.decay * 0.5 * h
	c.needs.food -= Config.NEEDS.food.decay * extra * h
	c.needs.water -= Config.NEEDS.water.decay * extra * h
	if not sleeping:
		c.needs.sleep -= Config.NEEDS.sleep.decay * fatigue * h
	c.stress = minf(100.0, c.stress + pain(c) / 70.0 * 5.0 * h)
	var damage := 0.0
	if float(m.blood) > 40.0:
		damage += SHOCK_DAMAGE    # hypovolemic shock
	if float(m.infection) > 95.0:
		damage += SHOCK_DAMAGE    # septic shock
	return damage

## Work speed factor: crippled arms −50 % each (wiki), strong pain slows down
static func work_factor(c: CrewMember) -> float:
	var f := 1.0
	for p in c.med.crippled:
		if "arm" in String(p):
			f *= 0.5
	return f * (1.0 - clampf((pain(c) - 20.0) / 100.0, 0.0, 0.5))

## Movement factor: crippled legs −50 % each (wiki)
static func move_factor(c: CrewMember) -> float:
	var f := 0.75 if (concussed(c) and bool(c.med.concussion.get("dizzy", false))) or gas_dizzy(c) or body_stage(c.body_temp) == "Heat Stroke" else 1.0
	for p in c.med.crippled:
		if "leg" in String(p):
			f *= 0.5
	return f

# ---------------- First aid ----------------

## Take an item from the pack, otherwise from the own ship's storage (containers, terminal, piles)
static func take(c: CrewMember, item: String) -> bool:
	if c.inv.count(item) > 0:
		c.inv.take(item, 1)
		return true
	var g := c.grid()
	for i in g.devices:
		var d: Device = g.devices[i]
		if d.inv != null and not g.foreign(i) and d.lock_level == 0 and d.inv.count(item) > 0:
			d.inv.take(item, 1)
			return true
	for i in g.piles:
		if g.zone[i] == 0 and g.piles[i].count(item) > 0:
			g.piles[i].take(item, 1)
			g.clean_piles()
			return true
	return false

static func has(c: CrewMember, item: String) -> bool:
	if c.inv.count(item) > 0:
		return true
	var g := c.grid()
	for i in g.devices:
		var d: Device = g.devices[i]
		if d.inv != null and not g.foreign(i) and d.lock_level == 0 and d.inv.count(item) > 0:
			return true
	for i in g.piles:
		if g.zone[i] == 0 and g.piles[i].count(item) > 0:
			return true
	return false

## The character treats themselves with what is aboard. Returns the treatments given.
static func treat(c: CrewMember) -> PackedStringArray:
	var done: PackedStringArray = []
	if c.unconscious:
		return done
	var m: Dictionary = c.med
	for w in m.wounds:
		if open(w) and not w.bandaged and (take(c, "cloth") or take(c, "fabric")):
			w.bandaged = true
			done.append("bandaged the %s" % w.part)
		if open(w) and float(w.dis) < 0.5 and take(c, ITEMS.water):
			w.dis = 0.5   # wiki: water disinfects 50 %
			done.append("cleaned the %s" % w.part)
		if w.kind == "fracture" and not w.splint and take(c, ITEMS.splint):
			w.splint = true
			done.append("splinted the %s" % w.part)
	var infected: bool = float(m.infection) >= 35.0 or (m.get("disease", {}) as Dictionary).keys().any(func(k): return abx_cures(k, m.disease[k]))
	for w in m.wounds:
		infected = infected or float(w.infect) >= 0.25
	if infected and not antibiotics(c) and take(c, ITEMS.antibiotic):
		m.abx_until = GameState.time + ABX_HOURS * 60.0
		done.append("took an antibiotic")
	var p := pain(c)
	if p >= 30.0 and GameState.time >= float(m.pain_until):
		if p >= 50.0 and take(c, ITEMS.painkiller_rx):
			m.pain_until = GameState.time + PILL_HOURS * 60.0
			m.pain_f = 0.7
			done.append("took a prescription painkiller")
		elif take(c, ITEMS.painkiller):
			m.pain_until = GameState.time + PILL_HOURS * 60.0
			m.pain_f = 0.2
			done.append("took a painkiller")
	return done

## Status text for the character window
static func status(c: CrewMember) -> PackedStringArray:
	var m: Dictionary = c.med
	var out: PackedStringArray = []
	var head: PackedStringArray = []
	if float(m.blood) >= 1.0:
		head.append("blood loss %d %%%s" % [int(m.blood), " (severe)" if float(m.blood) >= 30.0 else (" (minor)" if float(m.blood) >= 15.0 else "")])
	if float(m.infection) >= 1.0:
		head.append("infection %d%s" % [int(m.infection), " – SEPSIS" if float(m.infection) >= 65.0 else (" – infected" if float(m.infection) >= 35.0 else "")])
	var p := pain(c)
	if p >= 1.0:
		head.append("pain %d%s" % [int(p), " (dulled)" if GameState.time < float(m.pain_until) else ""])
	if antibiotics(c):
		head.append("on antibiotics")
	if nano(c) > 0:
		head.append("nanorobotic first aid")
	if concussed(c):
		var cs: PackedStringArray = ["concussion"]
		if bool(m.concussion.get("headache", false)):
			cs.append("headache")
		if bool(m.concussion.get("dizzy", false)):
			cs.append("dizzy")
		head.append(" + ".join(cs))
	var ns := nutrition_stage(c)
	if ns in ["Malnourished", "Starving", "Starved"]:
		head.append(ns)
	var bs := body_stage(c.body_temp)
	if bs != "Comfortable":
		head.append("%s (%.1f °C)" % [bs, c.body_temp])
	for n in m.get("gas", []):
		head.append(String(n))
	for id in m.get("disease", {}):
		if STAGES.has(id):
			head.append("%s (stage %d)" % [DISEASE_NAMES[id], int(m.disease[id].stage)])
		else:
			head.append(String(DISEASE_NAMES[id]) + (" (severe)" if int(m.disease[id].stage) >= 3 else ""))
	if not head.is_empty():
		out.append(", ".join(head))
	for w in m.wounds:
		var tags: PackedStringArray = []
		if open(w):
			tags.append("bandaged" if w.bandaged else "BLEEDING")
			if float(w.dis) > 0.0:
				tags.append("cleaned")
			if float(w.infect) >= 0.05:
				tags.append("infection %s" % severity_name(float(w.infect) * 2.0))
		if w.kind == "fracture":
			tags.append("splinted" if w.splint else "no splint")
		out.append("%s: %s %s (%s)" % [String(w.part).capitalize(), severity_name(float(w.sev)), w.kind, ", ".join(tags)] if not tags.is_empty() else "%s: %s %s" % [String(w.part).capitalize(), severity_name(float(w.sev)), w.kind])
	for p2 in m.crippled:
		out.append("%s: crippled (%s −50 %%)" % [String(p2).capitalize(), "work" if "arm" in String(p2) else "movement"])
	return out
