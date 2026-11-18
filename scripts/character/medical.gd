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

static func fresh() -> Dictionary:
	return {"wounds": [], "blood": 0.0, "infection": 0.0, "crippled": [], "pain_until": 0.0, "pain_f": 0.0, "abx_until": 0.0}

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
	if GameState.time < float(c.med.pain_until):
		p /= 1.0 + float(c.med.pain_f)
	return p

static func antibiotics(c: CrewMember) -> bool:
	return GameState.time < float(c.med.abx_until)

## One step (dt in game minutes). Returns damage per hour for the health calculation.
static func step(c: CrewMember, dt: float, sleeping: bool) -> float:
	var m: Dictionary = c.med
	var h := dt / 60.0
	var heal: float = TraitSystem.factor(c, "recovery") * (1.5 if sleeping or c.unconscious else 1.0) * (Config.DIRTY_RECOVERY if c.is_dirty() else 1.0)
	var bleed := bleeding(c)
	m.blood = clampf(float(m.blood) + (bleed - (BLOOD_REGEN * heal if bleed <= 0.0 else 0.0)) * h, 0.0, 100.0)
	var infect_risk: float = (2.0 if c.is_dirty() else 1.0) * (1.2 if c.traits.has("immunosuppressed") else 1.0)
	var body_gain := 0.0
	for k in range(m.wounds.size() - 1, -1, -1):
		var w: Dictionary = m.wounds[k]
		if open(w):
			w.infect = clampf(float(w.infect) + INFECT_GAIN * h * (1.0 - float(w.dis)) * infect_risk * (0.5 if w.bandaged else 1.0)
				- (0.05 if antibiotics(c) else 0.01) * h * heal, 0.0, 1.0)
			body_gain += float(w.infect)
		var rate: float = float(HEAL[w.kind]) * heal * (1.0 - 0.8 * float(w.infect))
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
	var clear: float = BODY_CLEAR * heal * (1.2 if antibiotics(c) else 1.0)
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
	var f := 1.0
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
	var infected := float(m.infection) >= 35.0
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
