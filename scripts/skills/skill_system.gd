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
	var e := _entry(c, id)
	e.p = clampf(value, 0.0, 100.0)
	if e.p < ACQUIRED:
		e.erase("unlocked")   # Freischaltung gilt nur, solange 100 % erreicht sind

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

## Welche Aktionen und Tempo-Wirkungen gehören zu einem Auftrag? Arbeit an einem Gerät einer
## Kategorie, auf die eine Fähigkeit wirkt (work_categories), trainiert zusätzlich deren
## Aktion "<skill_id>_work" (z. B. civil_work), falls die übrigen Aktionen sie noch nicht trainieren.
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

## Gerätekategorien in Worten (für Tooltips und Meldungen)
const CATEGORY_NAMES := {"appliance": "Appliances", "control": "Controls", "furniture": "Furniture", "hvac": "Climate & Ventilation",
	"misc": "Miscellaneous", "power": "Power Systems", "propulsion": "Propulsion", "docking": "Docking", "water": "Water",
	"farming": "Farming", "production": "Production", "station": "Station", "sensor": "Sensors", "weapon": "Weapons", "suit": "Suits",
	"mining": "Mining", "software": "Software (debugging the navigation console)", "structure": "Ship Structure"}

func category_list(cats: PackedStringArray) -> String:
	var names: PackedStringArray = []
	for k in cats:
		names.append(CATEGORY_NAMES.get(k, k))
	return ", ".join(names)

## Auftragsarten, die an einem Gerät arbeiten (bauen, einbauen, reparieren, abbauen, zerlegen, drehen, versetzen)
const DEVICE_JOB_KINDS := ["device", "install", "repair", "remove", "uninstall", "dismantle", "destroy", "rotate", "move"]

## Geräteart, an der ein Auftrag arbeitet ("" = kein Gerät, z. B. Wand, Boden, Kabel)
func job_device_id(job: Dictionary) -> String:
	if not String(job.get("kind", "")) in DEVICE_JOB_KINDS:
		return ""
	if job.kind == "device":
		return String(job.dev)
	if job.kind == "install":
		var key: String = RemovalSystem.key_of_packed(String(job.item))
		return key.substr(4) if key.begins_with("dev:") else ""
	if job.has("target") and not String(job.target).begins_with("dev:"):
		return ""   # Abbau einer anderen Ebene (Kabel, Boden) auf demselben Feld
	var g := ShipSystem.grid
	var dev := g.device_at(ShipConstructionSystem.pos_of(job)) if g != null else null
	return dev.type if dev != null else ""

## Kategorie eines Auftrags: Gerätekategorie, oder "weapon" für das Herstellen einer Waffe
## an der Werkbank ("" = nichts davon, z. B. Wand, Boden, Kabel, andere Rezepte)
func job_category(job: Dictionary) -> String:
	if is_mining(job):
		return "mining"
	if String(job.get("kind", "")) == "debug":
		return "software"   # Softwarearbeit (nicht die Gerätekategorie der Konsole)
	if is_structure(job):
		return "structure"
	if String(job.get("kind", "")) == "craft":
		var out: Array = EconomySystem.recipe(String(job.get("recipe", ""))).get("out", [])
		return "weapon" if not out.is_empty() and ItemSystem.item(String(out[0])) != null and ItemSystem.item(String(out[0])).weapon != "" else ""
	var id := job_device_id(job)
	if id == "" or ItemSystem.device(id) == null:
		return ""
	return ItemSystem.device(id).category

## Strukturarbeit: Aufträge, die die vorhandenen Struktur-Wirkungen (work_structure, work_hull)
## bekommen – Wände, Böden, Türen, Fenster bauen oder einbauen, Wände/Böden und Hülle reparieren,
## Feuer löschen. Geräteaufträge zählen nur, wenn ihr Profil so klassifiziert ist (derzeit keiner).
func is_structure(job: Dictionary) -> bool:
	var effs: Array = _base_profile(job).effects
	return "work_structure" in effs or "work_hull" in effs

## Bergbau: Abtragen von Asteroidenfels (Wand im fremden Bereich, solange ein Asteroid angedockt ist)
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

## Alle Kategorien eines Auftrags: Hauptkategorie und Zusatzkategorien des Geräts (z. B. "suit")
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
				# Navigationsstation (Steuerpult) reparieren: vorhandene Aktion repair_nav (Elektro + Robotik)
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

## Geräte, die als Navigationsstation gelten
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

## Arbeitswert-Skala: Arbeitswert = Arbeitstempo × 10. Grundwert 7 (Tempo 0,7), Tempo-Wirkungen
## der Fähigkeiten zählen ×10, feste Boni erworbener Fähigkeiten (work_value_bonus) kommen
## additiv dazu. Eigenschaften, Anzug und Stress wirken danach als Faktoren aufs Tempo.
const WORK_VALUE_SCALE := 10.0
const BASE_WORK_VALUE := 7.0

## Additiver Arbeitswert aus erworbenen Fähigkeiten für die Gerätekategorie dieses Auftrags
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

## EVA-Arbeitsmalus: Wer im Raumanzug arbeitet, schafft ohne erworbenen Skill (removes_eva_malus,
## z. B. EVA Suits) nur 55 % der normalen Rate. Maßgeblich ist die Ausrüstung der Figur, nicht das Ziel.
const EVA_WORK_FACTOR := 0.55

func eva_factor(c: CrewMember) -> float:
	if c == null or c.suit == null:
		return 1.0
	for id in skills:
		if skills[id].removes_eva_malus and acquired(c, id):
			return 1.0
	return EVA_WORK_FACTOR

## Arbeitswert eines Charakters für einen Auftrag (vor Eigenschaften, Anzug und Stress)
func work_value(c: CrewMember, job: Dictionary) -> float:
	var bonus := 0.0
	for e in job_profile(job).effects:
		bonus += effect(c, e)
	return BASE_WORK_VALUE + bonus * WORK_VALUE_SCALE + work_value_bonus(c, job)

## Arbeitstempo eines Charakters für einen Auftrag (1.0 = normal)
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

## Arbeit an einem Auftrag trainiert die passenden Fähigkeiten
func train_job(c: CrewMember, job: Dictionary, minutes: float) -> void:
	for a in job_profile(job).actions:
		train(c, a, minutes)
	if c.suit != null:
		train(c, "eva_work", minutes)

## Pilot spart Treibstoff (bester an Bord zählt)
func pilot_fuel_factor() -> float:
	return 1.0 - minf(0.35, best_effect("fuel_saving"))

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
	return progress(c, "hacking")

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

## Tooltip einer Fähigkeit (englisch): Kurskosten, Bonus, Kategorien, Lernwege, aktueller Fortschritt
func skill_tooltip(c: CrewMember, id: String) -> String:
	var s: SkillData = skill(id)
	var lines: PackedStringArray = [s.skill_name, s.description]
	if s.course_years > 0:
		lines.append("Character creation: costs %d %s." % [s.course_years, "year" if s.course_years == 1 else "years"])
	if s.removes_eva_malus:
		lines.append("Effect when acquired (100 %%): removes the EVA work penalty (without it, work in an EVA suit runs at %d %% of the normal rate)." % int(round(EVA_WORK_FACTOR * 100.0)))
	if s.work_value_bonus != 0.0:
		lines.append("Bonus when acquired (100 %%): %+d work value." % int(s.work_value_bonus))
		lines.append("Affected categories: %s." % category_list(s.work_categories))
	var p := progress(c, id) if c != null else 0.0
	# Nur Wirkungen, die im Spiel tatsächlich verrechnet werden (gameplay_effects)
	for e in s.gameplay_effects:
		var full := float(s.gameplay_effects[e]) * (1.0 + MASTERY_BONUS)
		var now := float(s.gameplay_effects[e]) * p / 100.0 + (float(s.gameplay_effects[e]) * MASTERY_BONUS if p >= ACQUIRED else 0.0)
		if e in WORK_EFFECTS:
			lines.append("Effect: %s %+.1f work value at 100 %% (now %+.1f, grows with progress)." % [EFFECT_NAMES_EN.get(e, e), full * WORK_VALUE_SCALE, now * WORK_VALUE_SCALE])
		else:
			lines.append("Effect: %s %+d %% at 100 %% (now %+d %%, grows with progress)." % [EFFECT_NAMES_EN.get(e, e), int(round(full * 100.0)), int(round(now * 100.0))])
	if s.mastery_text != "":
		lines.append(s.mastery_text if s.mastery_text.begins_with("Acquired") else "At 100 %: " + s.mastery_text)
	lines.append("Ways to learn: " + "; ".join(s.learning_sources) + ".")
	lines.append("Status: %s." % ("acquired" if p >= ACQUIRED else "not acquired (acquired at 100 %)"))
	lines.append("Learning progress: %.1f %%%s" % [p, " (acquired)" if p >= ACQUIRED else ""])
	return "\n".join(lines)

## Tempo-Wirkungen (zählen als Arbeitswert ×10, siehe work_value)
const WORK_EFFECTS := ["work_structure", "work_furniture", "work_build", "work_electrical", "cable_speed", "work_robotic",
	"work_computer", "work_hull", "work_propulsion", "work_mechanical", "work_demolish"]

## Englische Namen der Wirkungen für Tooltips
const EFFECT_NAMES_EN := {
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
