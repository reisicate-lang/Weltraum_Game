## Character creation with a life story. You start at 18 (Ostranauts starting profile) and
## choose life steps (apprenticeship, military, street ...), courses, traits and life encounters
## ("Seek Adventure", Ostranauts 2.1). Data: res://data/careers.json, res://data/encounters.json
extends Node

var careers: Array = []
var encounters: Array = []
var enc_cfg: Dictionary = {}
var start_age := 14
var max_age := 60

const FIRST_NAMES := ["Mira", "Jonas", "Ayla", "Tomás", "Ines", "Kofi", "Lena", "Dario", "Yuki", "Bram", "Nadia", "Oskar", "Sana", "Emil", "Rhea", "Pavel"]
const LAST_NAMES := ["Okafor", "Brandt", "Novak", "Ferreira", "Sato", "Lindqvist", "Haddad", "Kowalski", "Mbeki", "Varga", "Ruiz", "Holm"]
const COLORS := ["#59c7e6", "#6fcf8e", "#c07ad8", "#e5844b", "#d8c14b", "#e56b8f", "#7f9de6"]

func _ready() -> void:
	var f := FileAccess.open("res://data/careers.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	careers = d.careers
	start_age = int(d.start_age)
	max_age = int(d.max_age)
	var ef := FileAccess.open("res://data/encounters.json", FileAccess.READ)
	enc_cfg = JSON.parse_string(ef.get_as_text())
	encounters = enc_cfg.encounters

# ---------------- Courses (draft until confirmed) ----------------
# Every skill with course_years > 0 (e.g. Business Admin 2, Civil Engineering 3) can be chosen
# as a course in the life story. Adding and removing only changes the preview age;
# only confirm() applies age and skill, exactly once.

const COURSE_YEARS := 2   ## Business Admin (older callers)

## Skills that can be chosen as a course (sorted by ID)
func course_ids() -> Array:
	var out: Array = []
	for id in SkillSystem.skills:
		if SkillSystem.skill(id).course_years > 0:
			out.append(id)
	out.sort()
	return out

func course_years(id: String) -> int:
	var s: SkillData = SkillSystem.skill(id)
	return s.course_years if s != null else 0

func _drafts(c: CrewMember) -> Array:
	return c.get_meta("draft_courses", [])

func course_drafted(c: CrewMember, id: String = SkillSystem.BUSINESS) -> bool:
	return id in _drafts(c)

## Add a course to the draft or remove it. Only changes the preview age.
func set_course(c: CrewMember, on: bool, id: String = SkillSystem.BUSINESS) -> bool:
	if creation_ended(c):
		return false
	var drafts: Array = _drafts(c).duplicate()
	if on:
		if course_years(id) <= 0 or id in drafts or preview_age(c) + course_years(id) > max_age or SkillSystem.acquired(c, id):
			return false
		drafts.append(id)
	else:
		if not id in drafts:
			return false
		drafts.erase(id)
	c.set_meta("draft_courses", drafts)
	return true

## Age with everything chosen in the draft (courses and traits)
func preview_age(c: CrewMember) -> int:
	var age := c.age
	for id in _drafts(c):
		age += course_years(id)
	return age + trait_delta(c)

# ---------------- Tweaking traits (draft, Ostranauts "Tweak Skills & Traits") ----------------
# Positive trait: costs years; negative: gives years back. Removing reverses the booking
# (getting rid of a negative trait costs its years). The counterpart must go first.
# The balance of the draft must not be negative when confirming.

func trait_adds(c: CrewMember) -> Array:
	return c.get_meta("draft_trait_add", [])

func trait_removes(c: CrewMember) -> Array:
	return c.get_meta("draft_trait_remove", [])

## Years booked by the trait choices in the draft
func trait_delta(c: CrewMember) -> int:
	var d := 0
	for id in trait_adds(c):
		d += TraitSystem.get_trait(id).cost
	for id in trait_removes(c):
		d -= TraitSystem.get_trait(id).cost
	return d

## Balance of the whole draft (courses + traits) in years; must not be negative when confirming
func draft_balance(c: CrewMember) -> int:
	return preview_age(c) - c.age

## Does the character have the trait after the draft?
func trait_preview(c: CrewMember, id: String) -> bool:
	return (id in c.traits and not id in trait_removes(c)) or id in trait_adds(c)

## Why the trait cannot be toggled right now ("" = possible)
func trait_block_reason(c: CrewMember, id: String) -> String:
	var t: TraitData = TraitSystem.get_trait(id)
	if t == null:
		return "Unknown trait."
	if creation_ended(c):
		return ended_text(c)
	if id in trait_adds(c) or id in trait_removes(c) or id in c.traits:
		return ""   # Undoing or removing always works
	var opp := t.opposite
	if opp != "" and trait_preview(c, opp):
		return "Remove %s first." % TraitSystem.get_trait(opp).trait_name
	if preview_age(c) + t.cost > max_age:
		return "Too old for that."
	return ""

## Toggle a trait in the draft (add, remove, undo). Returns the reason if not possible.
func toggle_trait(c: CrewMember, id: String) -> String:
	var why := trait_block_reason(c, id)
	if why != "":
		return why
	var adds: Array = trait_adds(c).duplicate()
	var rems: Array = trait_removes(c).duplicate()
	if id in adds:
		adds.erase(id)
	elif id in rems:
		rems.erase(id)
	elif id in c.traits:
		rems.append(id)
	else:
		adds.append(id)
	c.set_meta("draft_trait_add", adds)
	c.set_meta("draft_trait_remove", rems)
	return ""

## Confirm the life story: apply the chosen courses and traits (age and effect) exactly once.
## A negative balance is not applied (false).
func confirm(c: CrewMember) -> bool:
	if draft_balance(c) < 0 or pending_encounter(c) != "":
		return false
	var age_before := c.age
	var drafts: Array = _drafts(c)
	c.set_meta("draft_courses", [])
	for id in course_ids():   # fixed order
		if not id in drafts or SkillSystem.acquired(c, id):
			continue   # already acquired (e.g. through a life step): no second booking
		var years := course_years(id)
		c.age += years
		SkillSystem.set_progress(c, id, SkillSystem.ACQUIRED)
		SkillSystem._entry(c, id).unlocked = true
		c.history.append("%d–%d: %s course." % [c.age - years, c.age, SkillSystem.skill(id).skill_name])
	# Traits
	var adds: Array = trait_adds(c)
	var rems: Array = trait_removes(c)
	if not adds.is_empty() or not rems.is_empty():
		var delta := trait_delta(c)
		var parts: PackedStringArray = []
		for id in rems:
			c.traits.erase(id)
			parts.append("−" + TraitSystem.get_trait(id).trait_name)
		for id in adds:
			if not id in c.traits:
				c.traits.append(id)
			parts.append("+" + TraitSystem.get_trait(id).trait_name)
		c.age += delta
		c.history.append("Traits: %s (%+d %s)." % [", ".join(parts), delta, "year" if absi(delta) == 1 else "years"])
	c.set_meta("draft_trait_add", [])
	c.set_meta("draft_trait_remove", [])
	_age_check(c, age_before)
	return true

func career(id: String) -> Dictionary:
	for c in careers:
		if c.id == id:
			return c
	return {}

## Starting profile of the player character after Ostranauts (wiki 1.1): grew up on an asteroid,
## already in poor shape at 18. The negative traits can be removed in the life story for years.
## "Youthful" (no effect) does not exist here.
const START_TRAITS := ["feeble", "fragile", "micro_g_hypovolemic", "immunosuppressed", "insomniac",
	"slow_metabolism", "sharp_hearing", "unfit", "visually_impaired"]
const START_SKILLS := ["spaceship", "zerog"]

## Reset a character to the start of the life story. asteroid_start: starting profile of the player character
## (starting traits and skills); false for random characters (one random birth trait).
func begin(c: CrewMember, asteroid_start: bool = true) -> void:
	c.age = start_age
	c.skills.clear()
	c.traits.clear()
	c.hobbies.clear()
	c.history.clear()
	c.contacts.clear()
	c.enemies.clear()
	c.inv.items.clear()
	c.set_meta("careers", [])
	c.set_meta("credits", 0)
	c.set_meta("draft_courses", [])
	c.set_meta("draft_trait_add", [])
	c.set_meta("draft_trait_remove", [])
	c.set_meta("pending_encounter", "")
	c.set_meta("risk_tokens", {})
	c.set_meta("aged_29", false)
	c.set_meta("aged_42", false)
	c.set_meta("ship_offer", "")
	c.remove_meta("ship_bought")
	if asteroid_start:
		c.set_meta("ship_bought", "")   # Player character: Seek Ship possible, forced at 47
		for t in START_TRAITS:
			if TraitSystem.get_trait(t) != null and not t in c.traits:
				c.traits.append(t)
		for s in START_SKILLS:
			if SkillSystem.skill(s) != null:
				SkillSystem.set_progress(c, s, SkillSystem.ACQUIRED)
				SkillSystem._entry(c, s).unlocked = true
		c.history.append("Grew up on an asteroid: starts at %d in poor shape, with Spaceship Engineering and Zero-g Ops." % start_age)
	else:
		# Random character: one innate trait
		var ids := TraitSystem.traits.keys()
		TraitSystem.add(c, ids.pick_random())
		c.history.append("Born in a lunar settlement.")

func done_careers(c: CrewMember) -> Array:
	return c.get_meta("careers", [])

## Which life steps are open right now?
func available(c: CrewMember) -> Array:
	var out: Array = []
	var done := done_careers(c)
	if creation_ended(c) or ship_offer(c) != "":
		return out
	for k in careers:
		if c.age < int(k.min_age) or preview_age(c) + int(k.years) > max_age:
			continue
		if k.has("max_age") and c.age > int(k.max_age):
			continue
		if done.count(k.id) >= 2:
			continue
		var ok := true
		for r in k.requires:
			if not r in done:
				ok = false
		if ok:
			out.append(k)
	return out

## Go through a life step. Returns the text for the log.
func apply_career(c: CrewMember, id: String) -> String:
	var k := career(id)
	if k.is_empty() or not k in available(c) or pending_encounter(c) != "":
		return ""
	var age_before := c.age
	c.age += int(k.years)
	var done := done_careers(c)
	done.append(id)
	c.set_meta("careers", done)
	var factor := TraitSystem.factor(c, "learn_speed")
	for s in k.skills:
		var cur := SkillSystem.progress(c, s)
		var gain := float(k.skills[s]) * factor * (0.7 if done.count(id) > 1 else 1.0)
		SkillSystem.set_progress(c, s, minf(SkillSystem.cap(c, s) if cur < 40.0 else 100.0, cur + gain))
	# Directly granted skills ("grants"): acquired without their own age booking (the step
	# has already booked its years). Already acquired: nothing twice. A chosen course
	# of the same skill drops out of the draft (otherwise its years would be added).
	var granted: PackedStringArray = []
	for gid in k.get("grants", []):
		if SkillSystem.skill(gid) == null:
			continue
		if course_drafted(c, gid):
			set_course(c, false, gid)
		if SkillSystem.acquired(c, gid):
			continue
		SkillSystem.set_progress(c, gid, SkillSystem.ACQUIRED)
		SkillSystem._entry(c, gid).unlocked = true
		granted.append(SkillSystem.skill(gid).skill_name)
	for t in k.get("traits_add", []):
		TraitSystem.add(c, t)
	c.set_meta("credits", int(c.get_meta("credits", 0)) + int(k.get("credits", 0)))
	for it in k.get("items", []):
		c.inv.add(it, 1, 80.0)
	if k.has("contact"):
		c.contacts.append(k.contact)
	var line := "%d–%d: %s. %s" % [c.age - int(k.years), c.age, k.name, k.text]
	if not granted.is_empty():
		line += " Acquired " + ", ".join(granted) + "."
	if randf() < float(k.get("enemy_chance", 0.0)):
		var enemy := "%s %s" % [FIRST_NAMES.pick_random(), LAST_NAMES.pick_random()]
		c.enemies.append(enemy)
		line += " Made an enemy of %s." % enemy
	c.history.append(line)
	_age_check(c, age_before)
	_sanitize_drafts(c)
	return line

# ---------------- Aging (Ostranauts 1.2) ----------------
# On reaching 29 (Middle Age) and 42 (Old Age) one random negative trait is added each
# (from all negative ones; ones you already have and ones whose counterpart you have are skipped).
# At 47 (max_age) creation ends: drafts expire, only "Let's go" remains.
const AGING := [[29, "Middle age"], [42, "Old age"]]

## Call after every aging: check the thresholds between the old and new age (once each)
func _age_check(c: CrewMember, old_age: int) -> void:
	if c.age > max_age:
		c.age = max_age
	for a in AGING:
		var at: int = a[0]
		var key := "aged_%d" % at
		if old_age < at and c.age >= at and not c.get_meta(key, false):
			c.set_meta(key, true)
			var pool: Array = TraitSystem.ordered_ids().filter(func(t): return TraitSystem.get_trait(t).cost < 0 and TraitSystem.can_add(c, t))
			if not pool.is_empty():
				var t: String = pool.pick_random()
				c.traits.append(t)
				c.history.append("%d: %s – gained %s." % [at, a[1], TraitSystem.get_trait(t).trait_name])
	# At 47 without a ship: Seek Ship is forced, the first offer is accepted (wiki 1.2)
	if c.age >= max_age and String(c.get_meta("ship_bought", "")) == "" and c.has_meta("ship_bought"):
		var offer := String(c.get_meta("ship_offer", ""))
		if offer == "":
			offer = String(starter_ships().pick_random().id)
		c.set_meta("ship_offer", "")
		_buy_ship(c, offer, true)
	if creation_ended(c):
		c.set_meta("draft_courses", [])
		c.set_meta("draft_trait_add", [])
		c.set_meta("draft_trait_remove", [])

func ended_text(c: CrewMember) -> String:
	if ship_bought(c) != "":
		return "Character creation has ended: you bought a ship."
	return "Character creation has ended (age %d)." % max_age

## Creation ends at max_age (47) or with a bought ship (Seek Ship)
func creation_ended(c: CrewMember) -> bool:
	return c.age >= max_age or String(c.get_meta("ship_bought", "")) != ""

# ---------------- Seek Ship (Ostranauts 2.4) ----------------
# 1 year: a random starter ship is offered. Decline (then search again, another year)
# or buy: you take on the ship's loan and creation ends. Whoever never buys a ship
# starts with the Rustbucket as before.

## Starter ships: the Rustbucket and the shipyard ships, loan = price (Cr)
func starter_ships() -> Array:
	var out: Array = [{"id": "rostlaube", "name": "Rustbucket", "price": Config.START_DEBT,
		"desc": "Your old salvage tug: life support, generator, two thrusters, an airlock."}]
	for t in PhysicsSystem.space.shipyard:
		out.append(t)
	return out

func starter_ship(id: String) -> Dictionary:
	for t in starter_ships():
		if t.id == id:
			return t
	return {}

func ship_offer(c: CrewMember) -> String:
	return String(c.get_meta("ship_offer", ""))

func ship_bought(c: CrewMember) -> String:
	return String(c.get_meta("ship_bought", ""))

## Search for a ship for 1 year. Empty id: random. Returns the ship ID ("" = not possible).
func seek_ship(c: CrewMember, id: String = "") -> String:
	if adventure_block_reason(c) != "":
		return ""
	var t: Dictionary = starter_ship(id) if id != "" else starter_ships().pick_random()
	if t.is_empty():
		return ""
	var age0 := c.age
	c.age += 1
	c.set_meta("ship_offer", String(t.id))
	c.history.append("%d–%d: Looked for a ship – offered the %s (loan %d Cr)." % [age0, c.age, t.name, int(t.price)])
	_age_check(c, age0)
	return String(t.id) if ship_bought(c) == "" else ship_bought(c)

func decline_ship(c: CrewMember) -> void:
	c.set_meta("ship_offer", "")

## Accept the offer: the life story is confirmed and creation ends. false = not possible (negative balance).
func buy_ship(c: CrewMember) -> bool:
	var id := ship_offer(c)
	if id == "" or draft_balance(c) < 0:
		return false
	confirm(c)
	if ship_bought(c) != "":
		return true   # turned 47 while confirming: the offer was already accepted by force
	c.set_meta("ship_offer", "")
	_buy_ship(c, id, false)
	return true

func _buy_ship(c: CrewMember, id: String, forced: bool) -> void:
	var t := starter_ship(id)
	c.set_meta("ship_bought", id)
	c.history.append("%d: %s the %s and took on its loan of %d Cr." % [c.age, "Had to take" if forced else "Bought", t.name, int(t.price)])
	c.set_meta("draft_courses", [])
	c.set_meta("draft_trait_add", [])
	c.set_meta("draft_trait_remove", [])

# ---------------- Life encounters ("Seek Adventure", Ostranauts 2.1) ----------------
# An encounter costs 1 year. You pick one of several answers; some need a skill
# or trait. RISK answers: when an encounter starts, a hidden failure token is added with 50 %.
# The RISK answer fails as long as a token is there and removes exactly one
# in doing so. Other answers remove none, tokens pile up (as in the game v1.0.0.17).
# Rewards without a counterpart in the game are dropped and listed as "Not in game" in the life story.

func encounter(id: String) -> Dictionary:
	for e in encounters:
		if e.id == id:
			return e
	return {}

func encounter_choice(e: Dictionary, choice_id: String) -> Dictionary:
	for ch in e.get("choices", []):
		if ch.id == choice_id:
			return ch
	return {}

func risk_tokens(c: CrewMember) -> Dictionary:
	if not c.has_meta("risk_tokens"):
		c.set_meta("risk_tokens", {})
	return c.get_meta("risk_tokens")

func pending_encounter(c: CrewMember) -> String:
	return String(c.get_meta("pending_encounter", ""))

## Why no encounter is possible right now ("" = possible)
const SAVE_MONEY_MIN := 300
const SAVE_MONEY_MAX := 600

func adventure_block_reason(c: CrewMember) -> String:
	if pending_encounter(c) != "":
		return "Choose an answer for the current encounter first."
	if ship_offer(c) != "":
		return "Buy or decline the ship offer first."
	if creation_ended(c):
		return ended_text(c)
	if preview_age(c) + int(enc_cfg.get("years", 1)) > max_age:
		return "Too old for that."
	return ""

## Save Some Money (Ostranauts 2.3): work and save for 1 year, about 300–600 Cr start money.
## amount < 0: random; otherwise a fixed amount (tests). Returns the life story line ("" = not possible).
func save_money(c: CrewMember, amount: int = -1) -> String:
	if adventure_block_reason(c) != "":
		return ""
	var cash := randi_range(SAVE_MONEY_MIN, SAVE_MONEY_MAX) if amount < 0 else amount
	var age0 := c.age
	c.age += 1
	c.set_meta("credits", int(c.get_meta("credits", 0)) + cash)
	var line := "%d–%d: Saved some money (+%d Cr)." % [age0, c.age, cash]
	c.history.append(line)
	_age_check(c, age0)
	_sanitize_drafts(c)
	return line

## Start an encounter (random or with an id). token_roll < 0: random; otherwise a fixed roll (tests).
func start_encounter(c: CrewMember, id: String = "", token_roll: float = -1.0) -> String:
	if pending_encounter(c) != "":
		return pending_encounter(c)
	if adventure_block_reason(c) != "":
		return ""
	var e: Dictionary = encounter(id) if id != "" else encounters.pick_random()
	if e.is_empty():
		return ""
	c.set_meta("pending_encounter", e.id)
	var tok := String(e.get("risk_token", ""))
	if tok != "":
		var roll := randf() if token_roll < 0.0 else token_roll
		if roll < float(enc_cfg.get("risk_add_chance", 0.5)):
			var tokens := risk_tokens(c)
			tokens[tok] = int(tokens.get(tok, 0)) + 1
	return e.id

## Why an answer cannot be chosen ("" = possible)
func choice_block_reason(c: CrewMember, ch: Dictionary) -> String:
	var req: Dictionary = ch.get("req", {})
	if req.has("skill") and not SkillSystem.acquired(c, String(req.skill)):
		return "Needs %s." % SkillSystem.skill(String(req.skill)).skill_name
	if req.has("trait") and not String(req.trait) in c.traits:
		return "Needs %s." % TraitSystem.get_trait(String(req.trait)).trait_name
	return ""

## Choose an answer: 1 year, rewards, RISK and Brig if needed. Returns the life story entry.
func resolve_encounter(c: CrewMember, choice_id: String) -> String:
	var e := encounter(pending_encounter(c))
	var ch := encounter_choice(e, choice_id)
	if e.is_empty() or ch.is_empty() or choice_block_reason(c, ch) != "":
		return ""
	var age0 := c.age
	c.age += int(enc_cfg.get("years", 1))
	var parts: PackedStringArray = []
	var missing: PackedStringArray = []
	_apply_reward(c, ch, parts, missing)
	var label := String(ch.label)
	if ch.get("risk", false):
		var tok := String(e.risk_token)
		var tokens := risk_tokens(c)
		var failed := int(tokens.get(tok, 0)) > 0
		if failed:
			tokens[tok] = int(tokens[tok]) - 1
		label = "RISK: %s – %s" % [label, "failure" if failed else "success"]
		_apply_reward(c, ch.get("failure" if failed else "success", {}), parts, missing)
	c.set_meta("pending_encounter", "")
	if c.age > max_age:
		c.age = max_age   # the Brig cannot lead past the end of character creation
	var line := "%d–%d: %s – %s." % [age0, c.age, e.name, label]
	if not parts.is_empty():
		line += " " + ", ".join(parts) + "."
	if not missing.is_empty():
		line += " (Not in game: " + "; ".join(missing) + ")"
	c.history.append(line)
	_age_check(c, age0)
	_sanitize_drafts(c)
	return line

func _apply_reward(c: CrewMember, d: Dictionary, parts: PackedStringArray, missing: PackedStringArray) -> void:
	var cash := int(d.get("cash", 0))
	if cash != 0:
		c.set_meta("credits", int(c.get_meta("credits", 0)) + cash)
		parts.append("%+d Cr" % cash)
	for s in d.get("skills", []):
		_grant_skill(c, String(s), parts)
	for t in d.get("traits", []):
		_gain_trait(c, String(t), parts)
	for r in d.get("chance", []):
		if randf() >= float(r.p):
			continue
		if r.has("skill"):
			_grant_skill(c, String(r.skill), parts)
		elif r.has("trait"):
			_gain_trait(c, String(r.trait), parts)
		elif r.has("item"):
			c.inv.add(String(r.item), 1, 70.0)
			parts.append(ItemSystem.item(String(r.item)).display_name)
	for x in d.get("contacts", []):
		c.contacts.append(String(x))
		parts.append("contact: " + String(x))
	for x in d.get("enemies", []):
		c.enemies.append(String(x))
		parts.append("enemy: " + String(x))
	if d.has("omitted"):
		missing.append(String(d.omitted))
	if d.get("brig", false):
		var b: Dictionary = enc_cfg.brig
		var years := randi_range(int(b.years_min), int(b.years_max))
		c.age += years
		parts.append("Time in the Brig (+%d %s)" % [years, "year" if years == 1 else "years"])
		_apply_reward(c, {"skills": b.skills, "contacts": b.contacts, "enemies": b.enemies, "omitted": b.omitted}, parts, missing)

## Skill from an encounter: acquired (100 %); already acquired = nothing twice
func _grant_skill(c: CrewMember, id: String, parts: PackedStringArray) -> void:
	if SkillSystem.skill(id) == null or SkillSystem.acquired(c, id):
		return
	SkillSystem.set_progress(c, id, SkillSystem.ACQUIRED)
	SkillSystem._entry(c, id).unlocked = true
	parts.append(SkillSystem.skill(id).skill_name)

## Trait from an encounter (rule: a positive trait replaces its negative counterpart)
func _gain_trait(c: CrewMember, id: String, parts: PackedStringArray) -> void:
	var t: TraitData = TraitSystem.get_trait(id)
	if t == null:
		return
	var opp := TraitSystem.held_opposite(c, id)
	if TraitSystem.add(c, id):
		if opp != "" and not opp in c.traits:
			parts.append("lost " + TraitSystem.get_trait(opp).trait_name)
		else:
			parts.append(t.trait_name)

## Clean up the draft after a life step or an encounter (courses, traits already acquired)
func _sanitize_drafts(c: CrewMember) -> void:
	for id in _drafts(c).duplicate():
		if SkillSystem.acquired(c, id):
			set_course(c, false, id)
	var adds: Array = trait_adds(c).filter(func(t): return not t in c.traits and TraitSystem.held_opposite(c, t) == "")
	var rems: Array = trait_removes(c).filter(func(t): return t in c.traits)
	c.set_meta("draft_trait_add", adds)
	c.set_meta("draft_trait_remove", rems)

func choose_hobby(c: CrewMember, id: String) -> bool:
	if id in c.hobbies or c.hobbies.size() >= 2:
		return false
	c.hobbies.append(id)
	c.history.append("Hobby: " + HobbySystem.get_hobby(id).hobby_name)
	return true

## Random life story up to a target age (for NPCs and "random")
func randomize_life(c: CrewMember, target_age: int, asteroid_start: bool = true) -> void:
	begin(c, asteroid_start)
	var guard := 0
	while c.age < target_age and guard < 20:
		guard += 1
		var opts := available(c)
		if opts.is_empty():
			break
		apply_career(c, opts.pick_random().id)
	if randf() < 0.8:
		choose_hobby(c, HobbySystem.hobbies.keys().pick_random())

## Start credits from the life story (can be negative: debt)
func start_credits(c: CrewMember) -> int:
	return int(c.get_meta("credits", 0))

## New NPC with a random background
func generate_npc() -> CrewMember:
	var name := "%s %s" % [FIRST_NAMES.pick_random(), LAST_NAMES.pick_random()]
	var c := CrewMember.new(CrewSystem.next_id, name, Color(COLORS.pick_random()), Vector2i.ZERO)
	CrewSystem.next_id += 1
	randomize_life(c, randi_range(20, 45), false)
	var total := 0.0
	for s in c.skills:
		total += SkillSystem.progress(c, s)
	c.salary = 20 + int(total / 12.0)
	return c
