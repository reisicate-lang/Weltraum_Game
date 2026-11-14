## Skills: learning by doing, textbooks, prerequisites, effects.
##
## Prinzipien:
## - Every game action is an action (res://data/skill_actions.json)
##   that only trains the skills that belong to it.
## - Hard tasks give more. If you are already much better than the
##   task is hard, it hardly gives anything.
## - If you repeat the same action all the time, you learn less and less
##   (it recovers over time).
## - Without prerequisites a skill stops at 40 %.
## - Progress 0–100 %. At 100 % the full effect is unlocked.
extends Node

const DIR := "res://resources/skills/"
const BASE_GAIN := 0.3          ## percent per minute of matching work (before all factors)
const CAP_WITHOUT_REQ := 40.0
const MASTERY_BONUS := 0.2      ## additional effect at 100 %

var skills: Dictionary = {}     ## id -> SkillData
var actions: Dictionary = {}    ## action -> {skills, difficulty, gain}

func _ready() -> void:
	_load_from(DIR)
	_load_from("user://mods/skills/")  # Mods

func _load_from(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")
		if f.ends_with(".tres"):
			var s: SkillData = load(path + f)
			skills[s.skill_id] = s
	var af := FileAccess.open("res://data/skill_actions.json", FileAccess.READ)
	actions = JSON.parse_string(af.get_as_text())

func skill(id: String) -> SkillData:
	return skills.get(id)

func ids_by_category(cat: String) -> Array:
	var out: Array = []
	for id in skills:
		if skills[id].category == cat:
			out.append(id)
	out.sort_custom(func(a, b): return skills[a].skill_name < skills[b].skill_name)
	return out

# ---------------- Progress of a character ----------------

func _entry(c: CrewMember, id: String) -> Dictionary:
	if not c.skills.has(id):
		c.skills[id] = {"p": 0.0, "xp": 0.0, "hist": []}
	return c.skills[id]

func progress(c: CrewMember, id: String) -> float:
	return float(c.skills[id].p) if c.skills.has(id) else 0.0

func set_progress(c: CrewMember, id: String, value: float) -> void:
	var e := _entry(c, id)
	e.p = clampf(value, 0.0, 100.0)
	if e.p < ACQUIRED:
		e.erase("unlocked")   # The unlock only counts as long as 100 % is reached

## Are the prerequisites met?
func requirements_met(c: CrewMember, id: String) -> bool:
	return meets(c, skill(id).required_skills)

## Check logic for prerequisites: {skill_id: minimum progress}. Also usable for interactions,
## e.g. meets(c, {"business": ACQUIRED}) = Business Admin acquired.
func meets(c: CrewMember, req: Dictionary) -> bool:
	for r in req:
		if progress(c, r) < float(req[r]):
			return false
	return true

## From this progress on a skill counts as acquired (mastered)
const ACQUIRED := 100.0
const BUSINESS := "business"

## Has the character acquired the skill?
func acquired(c: CrewMember, id: String) -> bool:
	return c != null and meets(c, {id: ACQUIRED})

func cap(c: CrewMember, id: String) -> float:
	return 100.0 if requirements_met(c, id) else CAP_WITHOUT_REQ

## Learning through an action. amount = minutes of work (or weight of the action).
## Returns the total progress (sum over all trained skills).
func train(c: CrewMember, action: String, amount: float) -> float:
	if c == null or not actions.has(action) or amount <= 0.0:
		return 0.0
	var a: Dictionary = actions[action]
	var difficulty: float = a.difficulty
	# Repetition: the same action gives less and less
	var rep: float = c.recent_actions.get(action, 0.0)
	var rep_factor := 1.0 / (1.0 + rep / 30.0)
	c.recent_actions[action] = rep + amount
	var learn := TraitSystem.factor(c, "learn_speed") * HobbySystem.learn_bonus(c, action)
	if c.stress > 70.0:
		learn *= 0.7
	var total := 0.0
	for id in a.skills:
		if not skills.has(id):
			continue
		var e := _entry(c, id)
		var p: float = e.p
		var limit := cap(c, id)
		if p >= limit:
			continue
		# Tasks that are too easy hardly give anything
		var challenge := clampf(1.2 - maxf(0.0, p / 100.0 - difficulty) * 3.0, 0.03, 1.2)
		var gain := BASE_GAIN * amount * float(a.gain) * challenge * rep_factor * learn * (1.0 - p / 125.0)
		var new_p := minf(limit, p + gain)
		var delta := new_p - p
		if delta <= 0.0:
			continue
		e.p = new_p
		e.xp = float(e.xp) + delta * 10.0
		_add_history(e, action, delta)
		c.last_trained = id
		total += delta
		if p < 100.0 and new_p >= 100.0:
			_unlock(c, id)
	return total

## Unlock a skill the first time it reaches 100 % (exactly once per character)
func _unlock(c: CrewMember, id: String) -> void:
	var e := _entry(c, id)
	if e.get("unlocked", false):
		return
	e.unlocked = true
	if id == BUSINESS:
		GameState.toast("%s acquired Business Admin: exact Item Values are now shown." % c.display_name)
	elif skill(id).piloting_bonus != 0.0:
		GameState.toast("%s acquired %s: Piloting %+.1f at the helm." % [c.display_name, skill(id).skill_name, skill(id).piloting_bonus])
	elif skill(id).work_value_bonus > 0.0:
		GameState.toast("%s acquired %s: %s+%d work value on %s." % [c.display_name, skill(id).skill_name, "no EVA work penalty, " if skill(id).removes_eva_malus else "", int(skill(id).work_value_bonus), category_list(skill(id).work_categories)])
	else:
		GameState.toast("%s acquired %s." % [c.display_name, skill(id).skill_name])

func _add_history(e: Dictionary, action: String, delta: float) -> void:
	var h: Array = e.hist
	var day := int(GameState.time / 1440.0) + 1
	if not h.is_empty() and h[-1].action == action and h[-1].day == day:
		h[-1].delta = float(h[-1].delta) + delta
	else:
		h.append({"day": day, "action": action, "delta": delta})
		if h.size() > 20:
			h.remove_at(0)

## Repetitions fade over time (dt in minutes)
func decay_recent(c: CrewMember, dt: float) -> void:
	for k in c.recent_actions.keys():
		c.recent_actions[k] = float(c.recent_actions[k]) * pow(0.995, dt)
		if c.recent_actions[k] < 0.05:
			c.recent_actions.erase(k)

# ---------------- Wirkungen ----------------

## Sum of an effect over all skills of the character
func effect(c: CrewMember, effect_id: String) -> float:
	if c == null:
		return 0.0
	var total := 0.0
	for id in skills:
		var eff: Dictionary = skills[id].gameplay_effects
		if not eff.has(effect_id):
			continue
		var p := progress(c, id)
		total += float(eff[effect_id]) * p / 100.0
		if p >= 100.0:
			total += float(eff[effect_id]) * MASTERY_BONUS
	return total

func mastered(c: CrewMember, id: String) -> bool:
	return progress(c, id) >= 100.0

## Best value in the crew
func best_effect(effect_id: String) -> float:
	var best := 0.0
	for c in CrewSystem.crew:
		best = maxf(best, effect(c, effect_id))
	return best

func any_mastered(id: String) -> bool:
	for c in CrewSystem.crew:
		if mastered(c, id):
			return true
	return false

# ---------------- Work: which action, how fast ----------------

## Which actions and speed effects belong to a job? Work at a device of a
## category a skill acts on (work_categories) also trains its
## action "<skill_id>_work" (e.g. civil_work), if the other actions do not train it yet.
func job_profile(job: Dictionary) -> Dictionary:
	var prof := _base_profile(job)
	var cats := job_categories(job)
	if cats.is_empty():
		return prof
	for id in skills:
		var s: SkillData = skills[id]
		var act: String = id + "_work"
		if not _overlaps(cats, s.work_categories) or not actions.has(act):
			continue
		var trained := false
		for a in prof.actions:
			if actions.has(a) and id in actions[a].skills:
				trained = true
		if not trained:
			prof.actions = prof.actions + [act]
	return prof

## Device categories in words (for tooltips and messages)
const CATEGORY_NAMES := {"appliance": "Appliances", "control": "Controls", "furniture": "Furniture", "hvac": "Climate & Ventilation",
	"misc": "Miscellaneous", "power": "Power Systems", "propulsion": "Propulsion", "docking": "Docking", "water": "Water",
	"farming": "Farming", "production": "Production", "station": "Station", "sensor": "Sensors", "weapon": "Weapons", "suit": "Suits",
	"mining": "Mining", "software": "Software (debugging the navigation console)", "structure": "Ship Structure"}

func category_list(cats: PackedStringArray) -> String:
	var names: PackedStringArray = []
	for k in cats:
		names.append(CATEGORY_NAMES.get(k, k))
	return ", ".join(names)

## Job kinds that work at a device (build, install, repair, uninstall, dismantle, rotate, move)
const DEVICE_JOB_KINDS := ["device", "install", "repair", "remove", "uninstall", "dismantle", "destroy", "rotate", "move"]

## Device type a job works at ("" = no device, e.g. wall, floor, cable)
func job_device_id(job: Dictionary) -> String:
	if not String(job.get("kind", "")) in DEVICE_JOB_KINDS:
		return ""
	if job.kind == "device":
		return String(job.dev)
	if job.kind == "install":
		var key: String = RemovalSystem.key_of_packed(String(job.item))
		return key.substr(4) if key.begins_with("dev:") else ""
	if job.has("target") and not String(job.target).begins_with("dev:"):
		return ""   # Removing another layer (cable, floor) on the same tile
	var g := ShipSystem.grid
	var dev := g.device_at(ShipConstructionSystem.pos_of(job)) if g != null else null
	return dev.type if dev != null else ""

## Category of a job: device category, or "weapon" for making a weapon
## at the workbench ("" = none of these, e.g. wall, floor, cable, other recipes)
func job_category(job: Dictionary) -> String:
	if is_mining(job):
		return "mining"
	if String(job.get("kind", "")) == "debug":
		return "software"   # Software work (not the device category of the console)
	if is_structure(job):
		return "structure"
	if String(job.get("kind", "")) == "craft":
		var out: Array = EconomySystem.recipe(String(job.get("recipe", ""))).get("out", [])
		return "weapon" if not out.is_empty() and ItemSystem.item(String(out[0])) != null and ItemSystem.item(String(out[0])).weapon != "" else ""
	var id := job_device_id(job)
	if id == "" or ItemSystem.device(id) == null:
		return ""
	return ItemSystem.device(id).category

## Structure work: jobs that get the existing structure effects (work_structure, work_hull)
## – building or installing walls, floors, doors, windows, repairing walls/floors and the hull,
## putting out fires. Device jobs only count if their profile is classified that way (none at the moment).
func is_structure(job: Dictionary) -> bool:
	var effs: Array = _base_profile(job).effects
	return "work_structure" in effs or "work_hull" in effs

## Mining: removing asteroid rock (wall in the foreign zone while an asteroid is docked)
const MINING_KINDS := ["remove", "uninstall", "dismantle", "destroy"]

func is_mining(job: Dictionary) -> bool:
	if not String(job.get("kind", "")) in MINING_KINDS or String(job.get("target", "")).begins_with("dev:"):
		return false
	var g := ShipSystem.grid
	if g == null:
		return false
	var p := ShipConstructionSystem.pos_of(job)
	if not g.in_bounds(p) or g.device_at(p) != null:
		return false
	var i := g.idx(p)
	return g.tiles[i] == ShipGrid.Tile.WALL and g.zone[i] == 1 and SalvageSystem.is_asteroid()

## All categories of a job: main category and additional categories of the device (e.g. "suit")
func job_categories(job: Dictionary) -> Array:
	var cat := job_category(job)
	if cat == "":
		return []
	var out: Array = [cat]
	var id := job_device_id(job)
	if id != "" and ItemSystem.device(id) != null:
		for e in ItemSystem.device(id).extra_categories:
			if not e in out:
				out.append(e)
	return out

func _overlaps(cats: Array, wanted: PackedStringArray) -> bool:
	for k in cats:
		if k in wanted:
			return true
	return false

func _base_profile(job: Dictionary) -> Dictionary:
	var g := ShipSystem.grid
	var p := ShipConstructionSystem.pos_of(job)
	var dev := g.device_at(p) if g != null else null
	var tech := ""
	if job.kind == "device":
		tech = ItemSystem.device(job.dev).tech
	elif dev != null:
		tech = dev.data().tech
	match job.kind:
		"build":
			return {"actions": ["build_structure"], "effects": ["work_structure", "work_build"]}
		"cable":
			return {"actions": ["lay_cable"], "effects": ["cable_speed", "work_build"]}
		"device":
			return {"actions": [_install_action(tech), "build_device"], "effects": [_work_effect(tech), "work_build"], "fine": tech in ["electrical", "computer", "robotic"]}
		"repair":
			if dev != null:
				var racts := [_repair_action(tech)]
				# Repairing the navigation station (console): existing action repair_nav (electrical + robotics)
				if dev.type in NAV_STATIONS:
					racts.append("repair_nav")
				return {"actions": racts, "effects": [_work_effect(tech)], "fine": tech in ["electrical", "computer", "robotic"]}
			var hull := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if g.get_tile(p + d) == ShipGrid.Tile.SPACE:
					hull = true
			return {"actions": ["repair_hull" if hull else "repair_structure"], "effects": ["work_hull" if hull else "work_structure"]}
		"remove":
			if dev != null:
				var acts := ["deconstruct_furniture"]
				if g.zone[g.idx(p)] == 1 and PhysicsSystem.docked == "debris":
					acts.append("deconstruct_military")
				return {"actions": acts, "effects": ["work_furniture", "work_demolish"]}
			if g.cables[g.idx(p)] == 1:
				return {"actions": ["lay_cable"], "effects": ["cable_speed"]}
			return {"actions": ["deconstruct_structure"], "effects": ["work_demolish"]}
		"craft":
			return {"actions": [String(EconomySystem.recipe(job.recipe).get("action", "build_device"))], "effects": ["work_build"]}
		"uninstall", "dismantle":
			if dev != null:
				return {"actions": ["deconstruct_furniture"], "effects": [_work_effect(tech), "work_demolish"], "fine": tech in ["electrical", "computer", "robotic"]}
			return {"actions": ["deconstruct_structure"], "effects": ["work_demolish"]}
		"destroy":
			return {"actions": ["deconstruct_structure"], "effects": ["work_demolish"]}
		"install":
			var key: String = RemovalSystem.key_of_packed(String(job.item))
			if key.begins_with("dev:"):
				var t2 := ItemSystem.device(key.substr(4)).tech
				return {"actions": [_install_action(t2), "build_device"], "effects": [_work_effect(t2), "work_build"]}
			return {"actions": ["build_structure"], "effects": ["work_structure", "work_build"]}
		"hack":
			return {"actions": ["hack", "analyze_software"], "effects": ["hack_assist", "hack_power"], "fine": true}
		"debug":
			return {"actions": ["debug_software"], "effects": [], "fine": true}
		"tend", "harvest":
			return {"actions": ["cook"], "effects": ["meal_bonus"]}
		"extinguish":
			return {"actions": ["repair_structure"], "effects": ["work_structure"]}
	return {"actions": [], "effects": []}

## Devices that count as a navigation station
const NAV_STATIONS := ["helm"]

func _install_action(tech: String) -> String:
	match tech:
		"electrical": return "install_electrical"
		"mechanical": return "install_mechanical"
		"robotic": return "install_sensor"
		"computer": return "analyze_software"
		"propulsion": return "install_propulsion"
	return "deconstruct_furniture"

func _repair_action(tech: String) -> String:
	match tech:
		"electrical": return "repair_electrical"
		"mechanical": return "repair_mechanical"
		"robotic": return "repair_robotic"
		"computer": return "repair_computer"
		"propulsion": return "repair_propulsion"
	return "repair_furniture"

func _work_effect(tech: String) -> String:
	match tech:
		"electrical": return "work_electrical"
		"mechanical": return "work_mechanical"
		"robotic": return "work_robotic"
		"computer": return "work_computer"
		"propulsion": return "work_propulsion"
	return "work_furniture"

## Work value scale: work value = work speed × 10. Base value 7 (speed 0.7), speed effects
## of the skills count ×10, fixed bonuses of acquired skills (work_value_bonus) are
## added on top. Traits, suit and stress then act as factors on the speed.
const WORK_VALUE_SCALE := 10.0
const BASE_WORK_VALUE := 7.0

## Additive work value from acquired skills for the device category of this job
func work_value_bonus(c: CrewMember, job: Dictionary) -> float:
	var cats := job_categories(job)
	if cats.is_empty():
		return 0.0
	var total := 0.0
	for id in skills:
		var s: SkillData = skills[id]
		if s.work_value_bonus != 0.0 and _overlaps(cats, s.work_categories) and acquired(c, id):
			total += s.work_value_bonus
	return total

## EVA work penalty: whoever works in a space suit only manages 55 % of the normal rate without an
## acquired skill (removes_eva_malus, e.g. EVA Suits). What counts is the character's gear, not the target.
const EVA_WORK_FACTOR := 0.55

func eva_factor(c: CrewMember) -> float:
	if c == null or c.suit == null:
		return 1.0
	for id in skills:
		if skills[id].removes_eva_malus and acquired(c, id):
			return 1.0
	return EVA_WORK_FACTOR

## Work value of a character for a job (before traits, suit and stress)
func work_value(c: CrewMember, job: Dictionary) -> float:
	var bonus := 0.0
	for e in job_profile(job).effects:
		bonus += effect(c, e)
	return BASE_WORK_VALUE + bonus * WORK_VALUE_SCALE + work_value_bonus(c, job)

## Work speed of a character for a job (1.0 = normal)
func work_speed(c: CrewMember, job: Dictionary) -> float:
	var prof := job_profile(job)
	var speed := work_value(c, job) / WORK_VALUE_SCALE * TraitSystem.factor(c, "work_speed")
	if prof.get("fine", false):
		speed *= TraitSystem.factor(c, "work_fine")
	speed *= eva_factor(c)
	if c.stress > 70.0:
		speed *= 0.8
	if job.kind == "extinguish" and not PhysicsSystem.ship_devices("extinguisher").is_empty():
		speed *= 3.0
	return maxf(0.2, speed)

## Work on a job trains the matching skills
func train_job(c: CrewMember, job: Dictionary, minutes: float) -> void:
	for a in job_profile(job).actions:
		train(c, a, minutes)
	if c.suit != null:
		train(c, "eva_work", minutes)

## Piloting value of a character: sum of the piloting_bonus of acquired skills (e.g. Spaceship
## Piloting +0.5). Traits can be added here later. Never below −0.9.
func piloting(c: CrewMember) -> float:
	if c == null:
		return 0.0
	var v := TraitSystem.sum(c, "piloting")   # Traits (e.g. Coordinated +0.1, Visually Impaired −0.2)
	for id in skills:
		if skills[id].piloting_bonus != 0.0 and acquired(c, id):
			v += skills[id].piloting_bonus
	return maxf(-0.9, v)

## Fuel saving (the best aboard counts; currently no skill has this effect)
func pilot_fuel_factor() -> float:
	return 1.0 - minf(0.35, best_effect("fuel_saving"))

## Physics shortens fast travel
func travel_factor() -> float:
	return 1.0 - minf(0.3, best_effect("travel_saving"))

## Characters at the navigation console (or the player character) train an action
func train_all_at(device_type: String, action: String, amount: float) -> void:
	var trained := false
	for c in CrewSystem.crew:
		for dev in PhysicsSystem.ship_devices(device_type):
			if c.can_reach(dev.pos):
				train(c, action, amount)
				trained = true
				break
	if not trained:
		train(CrewSystem.player(), action, amount)

## Hacking: value from Hacking and Software. Level 1 always works, 2 from 35, 3 from 75.
func hack_value(c: CrewMember) -> float:
	return progress(c, "hacking")

func hack_needed(level: int) -> float:
	return [0.0, 0.0, 35.0, 75.0][clampi(level, 0, 3)]

## Combat strength (for encounters with plunderers)
func combat_power(c: CrewMember) -> float:
	var weapon := ""
	for it in c.inv.items:
		var w: String = ItemSystem.item(it.type).weapon
		if w == "ranged" or (w == "armed" and weapon == ""):
			weapon = w
	# Attack: base value of the weapon type plus partial effects plus the bonus of acquired skills
	# (Armed/Unarmed Melee: +0.5 = "Attack dmg +50 %")
	var attack := effect(c, "combat_unarmed") + attack_bonus(c, "unarmed")
	if weapon == "armed":
		attack = maxf(attack, 0.15 + effect(c, "combat_armed") + attack_bonus(c, "armed"))
	elif weapon == "ranged":
		attack = maxf(attack, 0.3 + effect(c, "combat_ranged"))
	var power := 10.0 + 25.0 * attack + 15.0 * effect(c, "defense")
	power *= TraitSystem.factor(c, "combat")
	if c.stress > 70.0:
		power *= 0.8
	return power * (c.health / 100.0)

## Attack bonus of acquired skills for a weapon type ("armed", "unarmed")
func attack_bonus(c: CrewMember, weapon: String) -> float:
	var v := 0.0
	for id in skills:
		var s: SkillData = skills[id]
		if s.attack_bonus != 0.0 and s.attack_weapon == weapon and acquired(c, id):
			v += s.attack_bonus
	return v

## Appraisal: how precisely an estimated value is shown (0 = rough, 1 = exact)
func appraisal() -> float:
	return clampf(best_effect("appraise"), 0.0, 1.0)

# ---------------- Textbooks ----------------

## Reads a book: learning progress up to the level of the book
func study(c: CrewMember, book_id: String, minutes: float) -> float:
	var b := ItemSystem.item(book_id)
	if b == null or b.teaches == "":
		return 0.0
	var limit: float = [0.0, 40.0, 75.0, 100.0][clampi(b.book_level, 0, 3)]
	if b.book_level >= 2 and progress(c, b.teaches) < 30.0:
		return 0.0  # Advanced books need prior knowledge
	if progress(c, b.teaches) >= limit:
		return 0.0
	var before := progress(c, b.teaches)
	train(c, "study_" + b.teaches, minutes * TraitSystem.factor(c, "book_speed") * HobbySystem.book_bonus(c))
	if progress(c, b.teaches) > limit:
		set_progress(c, b.teaches, limit)
	return progress(c, b.teaches) - before

## Which textbooks can the character usefully read right now? (own pack and crates)
func readable_book(c: CrewMember) -> String:
	var invs: Array = [c.inv]
	for src in ShipConstructionSystem.sources():
		if ShipSystem.grid.zone[ShipSystem.grid.idx(src.pos)] == 0:
			invs.append(src.inv)
	for inv in invs:
		for it in inv.items:
			var b := ItemSystem.item(it.type)
			if b.teaches == "":
				continue
			var limit: float = [0.0, 40.0, 75.0, 100.0][clampi(b.book_level, 0, 3)]
			var p := progress(c, b.teaches)
			if p < limit and (b.book_level < 2 or p >= 30.0):
				return it.type
	return ""

# ---------------- Texts for the UI ----------------


## Tooltip of a skill: course cost, bonus, categories, ways to learn, current progress
func skill_tooltip(c: CrewMember, id: String) -> String:
	var s: SkillData = skill(id)
	var lines: PackedStringArray = [s.skill_name, s.description]
	if s.course_years > 0:
		lines.append("Character creation: costs %d %s." % [s.course_years, "year" if s.course_years == 1 else "years"])
	if s.is_hobby:
		lines.insert(1, "Hobby (Ostranauts 2.2.2).")
	if s.check_flag:
		lines.append("Effect when acquired (100 %): no numeric modifier; counts as " + s.skill_name + " for skill checks.")
	if s.attack_bonus != 0.0:
		lines.append("Effect when acquired (100 %%): attack %+d %% %s." % [int(round(s.attack_bonus * 100.0)), "with a melee weapon" if s.attack_weapon == "armed" else "without a weapon"])
	if s.piloting_bonus != 0.0:
		lines.append("Effect when acquired (100 %%): Piloting %+.1f while flying at the helm (docking limits, RCS thrust and turn rate ×(1 + Piloting))." % s.piloting_bonus)
	if s.removes_eva_malus:
		lines.append("Effect when acquired (100 %%): removes the EVA work penalty (without it, work in an EVA suit runs at %d %% of the normal rate)." % int(round(EVA_WORK_FACTOR * 100.0)))
	if s.work_value_bonus != 0.0:
		lines.append("Bonus when acquired (100 %%): %+d work value." % int(s.work_value_bonus))
		lines.append("Affected categories: %s." % category_list(s.work_categories))
	var p := progress(c, id) if c != null else 0.0
	# Only effects that are actually applied in the game (gameplay_effects)
	for e in s.gameplay_effects:
		var full := float(s.gameplay_effects[e]) * (1.0 + MASTERY_BONUS)
		var now := float(s.gameplay_effects[e]) * p / 100.0 + (float(s.gameplay_effects[e]) * MASTERY_BONUS if p >= ACQUIRED else 0.0)
		if e in WORK_EFFECTS:
			lines.append("Effect: %s %+.1f work value at 100 %% (now %+.1f, grows with progress)." % [EFFECT_NAMES.get(e, e), full * WORK_VALUE_SCALE, now * WORK_VALUE_SCALE])
		else:
			lines.append("Effect: %s %+d %% at 100 %% (now %+d %%, grows with progress)." % [EFFECT_NAMES.get(e, e), int(round(full * 100.0)), int(round(now * 100.0))])
	if s.mastery_text != "":
		lines.append(s.mastery_text if s.mastery_text.begins_with("Acquired") else "At 100 %: " + s.mastery_text)
	lines.append("Ways to learn: " + "; ".join(s.learning_sources) + ".")
	lines.append("Status: %s." % ("acquired" if p >= ACQUIRED else "not acquired (acquired at 100 %)"))
	lines.append("Learning progress: %.1f %%%s" % [p, " (acquired)" if p >= ACQUIRED else ""])
	return "\n".join(lines)

## Speed effects (count as work value ×10, see work_value)
const WORK_EFFECTS := ["work_structure", "work_furniture", "work_build", "work_electrical", "cable_speed", "work_robotic",
	"work_computer", "work_hull", "work_propulsion", "work_mechanical", "work_demolish"]

## Names of the effects for tooltips
const EFFECT_NAMES := {
	"work_structure": "Walls and floors", "work_furniture": "Furniture work", "work_build": "Building (walls, floors, cables, new devices, crafting, installing)",
	"work_electrical": "Electrical work", "cable_speed": "Laying cables", "work_robotic": "Automation work", "work_computer": "Computer work",
	"hack_assist": "Hacking assistance", "work_hull": "Hull repair", "work_propulsion": "Propulsion work", "work_mechanical": "Mechanical work",
	"military_salvage": "Military salvage yield", "weapon_care": "Weapon care", "combat_armed": "Melee attack", "combat_unarmed": "Unarmed attack",
	"combat_ranged": "Ranged attack", "defense": "Defense", "threat": "Intimidation", "suit_o2_saving": "Suit oxygen saved",
	"eva_work": "Work speed in a suit", "hack_power": "Hacking", "sell_bonus": "Selling bonus", "buy_discount": "Buying discount",
	"appraise": "Appraisal accuracy", "work_demolish": "Demolition", "demolish_yield": "Demolition yield", "fuel_saving": "Fuel saved",
	"eva_speed": "Speed in vacuum", "bluff": "Bluffing", "perform_income": "Performance pay", "meal_bonus": "Meal satiation",
	"meal_mood": "Mood from meals", "stress_relief": "Stress relief", "talk_folk": "Talking to common folk", "find_hidden": "Finding hidden stashes",
	"damage_insight": "Reading damage causes", "gamble_edge": "Gambling edge", "talk_military": "Talking to the military",
	"talk_oligarch": "Talking to the wealthy", "negotiate": "Negotiating", "calm": "Calming", "travel_saving": "Shorter fast travel",
	"prediction": "Trajectory prediction", "stress_insight": "Reading stress", "counsel": "Counseling", "crew_mood": "Crew mood",
	"smuggle": "Smuggling", "talk_street": "Talking to the underworld", "black_bonus": "Black market bonus",
}

func effect_lines(c: CrewMember, id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var s: SkillData = skill(id)
	var p := progress(c, id)
	if s.work_value_bonus != 0.0:
		out.append("Work value %+d on %s: %s" % [int(s.work_value_bonus), category_list(s.work_categories), "active" if p >= ACQUIRED else "locked until 100 %"])
	for e in s.gameplay_effects:
		var v := float(s.gameplay_effects[e]) * p / 100.0 + (float(s.gameplay_effects[e]) * MASTERY_BONUS if p >= 100.0 else 0.0)
		out.append("%s: +%d %%" % [EFFECT_NAMES.get(e, e), int(round(v * 100.0))])
	return out
