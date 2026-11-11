## Fähigkeiten: Lernen durch Tätigkeit, Lehrbücher, Voraussetzungen, Wirkungen.
##
## Prinzipien:
## - Jede Spielhandlung ist eine Aktion (res://data/skill_actions.json),
##   die nur die zugehörigen Fähigkeiten trainiert.
## - Schwierige Aufgaben bringen mehr. Ist man schon viel besser als die
##   Aufgabe schwer ist, bringt sie kaum noch etwas.
## - Wiederholt man dieselbe Aktion ständig, lernt man immer weniger
##   (erholt sich mit der Zeit).
## - Ohne Voraussetzungen bleibt eine Fähigkeit bei 40 % stehen.
## - Fortschritt 0–100 %. Bei 100 % wird die volle Wirkung freigeschaltet.
extends Node

const DIR := "res://resources/skills/"
const BASE_GAIN := 0.3          ## Prozent pro Minute passender Arbeit (vor allen Faktoren)
const CAP_WITHOUT_REQ := 40.0
const MASTERY_BONUS := 0.2      ## zusätzliche Wirkung bei 100 %

var skills: Dictionary = {}     ## id -> SkillData
var actions: Dictionary = {}    ## Aktion -> {skills, difficulty, gain}

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

# ---------------- Fortschritt eines Charakters ----------------

func _entry(c: CrewMember, id: String) -> Dictionary:
	if not c.skills.has(id):
		c.skills[id] = {"p": 0.0, "xp": 0.0, "hist": []}
	return c.skills[id]

func progress(c: CrewMember, id: String) -> float:
	return float(c.skills[id].p) if c.skills.has(id) else 0.0

func set_progress(c: CrewMember, id: String, value: float) -> void:
	_entry(c, id).p = clampf(value, 0.0, 100.0)

## Sind die Voraussetzungen erfüllt?
func requirements_met(c: CrewMember, id: String) -> bool:
	return meets(c, skill(id).required_skills)

## Prüflogik für Voraussetzungen: {skill_id: Mindestfortschritt}. Auch für Interaktionen nutzbar,
## z. B. meets(c, {"business": ACQUIRED}) = Business Admin erworben.
func meets(c: CrewMember, req: Dictionary) -> bool:
	for r in req:
		if progress(c, r) < float(req[r]):
			return false
	return true

## Ab diesem Fortschritt gilt eine Fähigkeit als erworben (gemeistert)
const ACQUIRED := 100.0
const BUSINESS := "business"

## Hat die Figur die Fähigkeit erworben?
func acquired(c: CrewMember, id: String) -> bool:
	return c != null and meets(c, {id: ACQUIRED})

func cap(c: CrewMember, id: String) -> float:
	return 100.0 if requirements_met(c, id) else CAP_WITHOUT_REQ

## Lernen durch eine Aktion. amount = Minuten Arbeit (oder Gewicht der Handlung).
## Gibt den gesamten Fortschritt zurück (Summe über alle trainierten Fähigkeiten).
func train(c: CrewMember, action: String, amount: float) -> float:
	if c == null or not actions.has(action) or amount <= 0.0:
		return 0.0
	var a: Dictionary = actions[action]
	var difficulty: float = a.difficulty
	# Wiederholung: dieselbe Aktion bringt immer weniger
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
		# Zu einfache Aufgaben bringen kaum etwas
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

## Fähigkeit beim ersten Erreichen von 100 % freischalten (genau einmal pro Figur)
func _unlock(c: CrewMember, id: String) -> void:
	var e := _entry(c, id)
	if e.get("unlocked", false):
		return
	e.unlocked = true
	if id == BUSINESS:
		GameState.toast("%s acquired Business Admin: exact Item Values are now shown." % c.display_name)
	else:
		GameState.toast("%s beherrscht jetzt %s vollständig!" % [c.display_name, skill(id).skill_name])

func _add_history(e: Dictionary, action: String, delta: float) -> void:
	var h: Array = e.hist
	var day := int(GameState.time / 1440.0) + 1
	if not h.is_empty() and h[-1].action == action and h[-1].day == day:
		h[-1].delta = float(h[-1].delta) + delta
	else:
		h.append({"day": day, "action": action, "delta": delta})
		if h.size() > 20:
			h.remove_at(0)

## Wiederholungen klingen mit der Zeit ab (dt in Minuten)
func decay_recent(c: CrewMember, dt: float) -> void:
	for k in c.recent_actions.keys():
		c.recent_actions[k] = float(c.recent_actions[k]) * pow(0.995, dt)
		if c.recent_actions[k] < 0.05:
			c.recent_actions.erase(k)

# ---------------- Wirkungen ----------------

## Summe einer Wirkung über alle Fähigkeiten des Charakters
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

## Bester Wert in der Crew
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

# ---------------- Arbeit: welche Aktion, wie schnell ----------------

## Welche Aktionen und Tempo-Wirkungen gehören zu einem Auftrag?
func job_profile(job: Dictionary) -> Dictionary:
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
				return {"actions": [_repair_action(tech)], "effects": [_work_effect(tech)], "fine": tech in ["electrical", "computer", "robotic"]}
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
		"tend", "harvest":
			return {"actions": ["cook"], "effects": ["meal_bonus"]}
		"extinguish":
			return {"actions": ["repair_structure"], "effects": ["work_structure"]}
	return {"actions": [], "effects": []}

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

## Arbeitstempo eines Charakters für einen Auftrag (1.0 = normal)
func work_speed(c: CrewMember, job: Dictionary) -> float:
	var prof := job_profile(job)
	var bonus := 0.0
	for e in prof.effects:
		bonus += effect(c, e)
	var speed := (0.7 + bonus) * TraitSystem.factor(c, "work_speed")
	if prof.get("fine", false):
		speed *= TraitSystem.factor(c, "work_fine")
	if c.suit != null:
		speed *= 0.8 + effect(c, "eva_work") * 0.5
	if c.stress > 70.0:
		speed *= 0.8
	if job.kind == "extinguish" and not PhysicsSystem.ship_devices("extinguisher").is_empty():
		speed *= 3.0
	return maxf(0.2, speed)

## Arbeit an einem Auftrag trainiert die passenden Fähigkeiten
func train_job(c: CrewMember, job: Dictionary, minutes: float) -> void:
	for a in job_profile(job).actions:
		train(c, a, minutes)
	if c.suit != null:
		train(c, "eva_work", minutes)

## Pilot und Raumschifftechnik sparen Treibstoff (bester an Bord zählt)
func pilot_fuel_factor() -> float:
	var f := 1.0 - minf(0.35, best_effect("fuel_saving"))
	if any_mastered("spaceship"):
		f *= 0.9
	return f

## Physik verkürzt Schnellreisen
func travel_factor() -> float:
	return 1.0 - minf(0.3, best_effect("travel_saving"))

## Charaktere am Steuerpult (oder die Spielerfigur) trainieren eine Aktion
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

## Hacken: Wert aus Hacken und Software. Stufe 1 geht immer, 2 ab 35, 3 ab 75.
func hack_value(c: CrewMember) -> float:
	return progress(c, "hacking") + 0.3 * progress(c, "software")

func hack_needed(level: int) -> float:
	return [0.0, 0.0, 35.0, 75.0][clampi(level, 0, 3)]

## Kampfkraft (für Begegnungen mit Plünderern)
func combat_power(c: CrewMember) -> float:
	var weapon := ""
	for it in c.inv.items:
		var w: String = ItemSystem.item(it.type).weapon
		if w == "ranged" or (w == "armed" and weapon == ""):
			weapon = w
	var attack := effect(c, "combat_unarmed")
	if weapon == "armed":
		attack = maxf(attack, 0.15 + effect(c, "combat_armed"))
	elif weapon == "ranged":
		attack = maxf(attack, 0.3 + effect(c, "combat_ranged"))
	var power := 10.0 + 25.0 * attack + 15.0 * effect(c, "defense")
	power *= TraitSystem.factor(c, "combat")
	if c.stress > 70.0:
		power *= 0.8
	return power * (c.health / 100.0)

## Wertschätzung: wie genau ein geschätzter Wert angezeigt wird (0 = grob, 1 = exakt)
func appraisal() -> float:
	return clampf(best_effect("appraise"), 0.0, 1.0)

# ---------------- Lehrbücher ----------------

## Liest ein Buch: Lernfortschritt bis zur Stufe des Buches
func study(c: CrewMember, book_id: String, minutes: float) -> float:
	var b := ItemSystem.item(book_id)
	if b == null or b.teaches == "":
		return 0.0
	var limit: float = [0.0, 40.0, 75.0, 100.0][clampi(b.book_level, 0, 3)]
	if b.book_level >= 2 and progress(c, b.teaches) < 30.0:
		return 0.0  # Fortgeschrittene Bücher brauchen Vorwissen
	if progress(c, b.teaches) >= limit:
		return 0.0
	var before := progress(c, b.teaches)
	train(c, "study_" + b.teaches, minutes * TraitSystem.factor(c, "book_speed") * HobbySystem.book_bonus(c))
	if progress(c, b.teaches) > limit:
		set_progress(c, b.teaches, limit)
	return progress(c, b.teaches) - before

## Welche Lehrbücher kann der Charakter gerade sinnvoll lesen? (eigenes Gepäck und Kisten)
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

# ---------------- Texte für die Oberfläche ----------------

const EFFECT_NAMES := {
	"work_structure": "Tempo bei Wänden und Böden", "work_furniture": "Tempo bei Möbeln", "work_build": "Bautempo",
	"work_electrical": "Tempo bei Elektrik", "cable_speed": "Tempo beim Kabelverlegen", "work_robotic": "Tempo bei Automatik",
	"work_computer": "Tempo bei Rechnern", "hack_assist": "Hilfe beim Hacken", "work_hull": "Tempo bei Hüllenreparatur",
	"work_propulsion": "Tempo bei Triebwerken", "work_mechanical": "Tempo bei Mechanik", "military_salvage": "Ausbeute aus Kriegswracks",
	"weapon_care": "Waffenpflege", "combat_armed": "Angriff mit Nahkampfwaffe", "combat_unarmed": "Angriff ohne Waffe",
	"combat_ranged": "Angriff mit Fernwaffe", "defense": "Verteidigung", "threat": "Bedrohungswirkung",
	"suit_o2_saving": "Sauerstoff im Anzug gespart", "eva_work": "Arbeitstempo im Anzug", "hack_power": "Hacken",
	"sell_bonus": "Mehr beim Verkaufen", "buy_discount": "Rabatt beim Kaufen", "appraise": "Genauigkeit beim Schätzen",
	"work_demolish": "Tempo beim Abreißen", "demolish_yield": "Ausbeute beim Abreißen", "fuel_saving": "Treibstoff gespart",
	"eva_speed": "Tempo im Vakuum", "bluff": "Bluffen", "perform_income": "Gage bei Auftritten", "meal_bonus": "Sättigung von Mahlzeiten",
	"meal_mood": "Stimmung durch Mahlzeiten", "stress_relief": "Stressabbau", "talk_folk": "Gespräche mit einfachen Leuten",
	"find_hidden": "Verstecke finden", "damage_insight": "Schadensursachen erkennen", "gamble_edge": "Vorteil beim Glücksspiel",
	"talk_military": "Gespräche mit Militär", "talk_oligarch": "Gespräche mit Reichen", "negotiate": "Verhandeln", "calm": "Beruhigen",
	"travel_saving": "Kürzere Schnellreisen", "prediction": "Flugbahnvorhersage", "stress_insight": "Stress erkennen",
	"counsel": "Seelsorge", "crew_mood": "Stimmung der Crew", "smuggle": "Schmuggeln", "talk_street": "Gespräche mit der Halbwelt",
	"black_bonus": "Mehr am Schwarzmarkt",
}

func effect_lines(c: CrewMember, id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var s: SkillData = skill(id)
	var p := progress(c, id)
	for e in s.gameplay_effects:
		var v := float(s.gameplay_effects[e]) * p / 100.0 + (float(s.gameplay_effects[e]) * MASTERY_BONUS if p >= 100.0 else 0.0)
		out.append("%s: +%d %%" % [EFFECT_NAMES.get(e, e), int(round(v * 100.0))])
	return out
