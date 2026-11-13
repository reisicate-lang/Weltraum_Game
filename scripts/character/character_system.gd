## Charaktererstellung mit Lebenslauf. Man beginnt mit 18 Jahren (Ostranauts-Startprofil) und
## wählt Lebensstationen (Lehre, Militär, Straße ...), Kurse, Traits und Lebensereignisse
## („Seek Adventure“, Ostranauts 2.1). Daten: res://data/careers.json, res://data/encounters.json
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

# ---------------- Kurse (Entwurf bis zur Bestätigung) ----------------
# Jede Fähigkeit mit course_years > 0 (z. B. Business Admin 2, Civil Engineering 3) ist im
# Lebenslauf als Kurs wählbar. Auswahl und Entfernen ändern nur das Vorschaualter;
# erst confirm() übernimmt Alter und Fähigkeit, genau einmal.

const COURSE_YEARS := 2   ## Business Admin (ältere Aufrufer)

## Fähigkeiten, die als Kurs wählbar sind (sortiert nach ID)
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

## Kurs in den Entwurf aufnehmen oder entfernen. Ändert nur das Vorschaualter.
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

## Alter mit allem, was im Entwurf gewählt ist (Kurse und Traits)
func preview_age(c: CrewMember) -> int:
	var age := c.age
	for id in _drafts(c):
		age += course_years(id)
	return age + trait_delta(c)

# ---------------- Traits anpassen (Entwurf, Ostranauts „Tweak Skills & Traits“) ----------------
# Positiver Trait: kostet Jahre; negativer: gibt Jahre zurück. Entfernen kehrt die Buchung um
# (einen negativen Trait loswerden kostet seine Jahre). Das Gegenstück muss erst weg.
# Die Bilanz des Entwurfs darf beim Bestätigen nicht negativ sein.

func trait_adds(c: CrewMember) -> Array:
	return c.get_meta("draft_trait_add", [])

func trait_removes(c: CrewMember) -> Array:
	return c.get_meta("draft_trait_remove", [])

## Jahre, die die Trait-Auswahl im Entwurf bucht
func trait_delta(c: CrewMember) -> int:
	var d := 0
	for id in trait_adds(c):
		d += TraitSystem.get_trait(id).cost
	for id in trait_removes(c):
		d -= TraitSystem.get_trait(id).cost
	return d

## Bilanz des ganzen Entwurfs (Kurse + Traits) in Jahren; darf beim Bestätigen nicht negativ sein
func draft_balance(c: CrewMember) -> int:
	return preview_age(c) - c.age

## Hat die Figur den Trait nach dem Entwurf?
func trait_preview(c: CrewMember, id: String) -> bool:
	return (id in c.traits and not id in trait_removes(c)) or id in trait_adds(c)

## Warum sich der Trait gerade nicht umschalten lässt ("" = geht)
func trait_block_reason(c: CrewMember, id: String) -> String:
	var t: TraitData = TraitSystem.get_trait(id)
	if t == null:
		return "Unknown trait."
	if creation_ended(c):
		return "Character creation has ended (age %d)." % max_age
	if id in trait_adds(c) or id in trait_removes(c) or id in c.traits:
		return ""   # Rückgängig machen bzw. entfernen geht immer
	var opp := t.opposite
	if opp != "" and trait_preview(c, opp):
		return "Remove %s first." % TraitSystem.get_trait(opp).trait_name
	if preview_age(c) + t.cost > max_age:
		return "Too old for that."
	return ""

## Trait im Entwurf umschalten (hinzufügen, entfernen, rückgängig). Gibt den Grund zurück, falls nicht.
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

## Lebenslauf bestätigen: gewählte Kurse und Traits (Alter und Wirkung) genau einmal übernehmen.
## Eine negative Bilanz wird nicht übernommen (false).
func confirm(c: CrewMember) -> bool:
	if draft_balance(c) < 0 or pending_encounter(c) != "":
		return false
	var age_before := c.age
	var drafts: Array = _drafts(c)
	c.set_meta("draft_courses", [])
	for id in course_ids():   # feste Reihenfolge
		if not id in drafts or SkillSystem.acquired(c, id):
			continue   # schon erworben (z. B. durch eine Lebensstation): keine zweite Buchung
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

## Startprofil der Spielerfigur nach Ostranauts (Wiki 1.1): auf einem Asteroiden aufgewachsen,
## mit 18 schon in schlechter Verfassung. Die negativen Traits lassen sich im Lebenslauf gegen Jahre
## entfernen. „Youthful“ (ohne Wirkung) gibt es hier nicht.
const START_TRAITS := ["feeble", "fragile", "micro_g_hypovolemic", "immunosuppressed", "insomniac",
	"slow_metabolism", "sharp_hearing", "unfit", "visually_impaired"]
const START_SKILLS := ["spaceship", "zerog"]

## Charakter auf den Anfang des Lebenslaufs setzen. asteroid_start: Startprofil der Spielerfigur
## (Start-Traits und Start-Skills); false für zufällige Figuren (ein zufälliger Geburts-Trait).
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
	if asteroid_start:
		for t in START_TRAITS:
			if TraitSystem.get_trait(t) != null and not t in c.traits:
				c.traits.append(t)
		for s in START_SKILLS:
			if SkillSystem.skill(s) != null:
				SkillSystem.set_progress(c, s, SkillSystem.ACQUIRED)
				SkillSystem._entry(c, s).unlocked = true
		c.history.append("Grew up on an asteroid: starts at %d in poor shape, with Spaceship Engineering and Zero-g Ops." % start_age)
	else:
		# Zufällige Figur: eine angeborene Eigenschaft
		var ids := TraitSystem.traits.keys()
		TraitSystem.add(c, ids.pick_random())
		c.history.append("Geboren in einer Mondsiedlung.")

func done_careers(c: CrewMember) -> Array:
	return c.get_meta("careers", [])

## Welche Lebensstationen stehen gerade offen?
func available(c: CrewMember) -> Array:
	var out: Array = []
	var done := done_careers(c)
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

## Eine Lebensstation durchlaufen. Gibt den Text fürs Protokoll zurück.
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
	# Direkt vergebene Fähigkeiten ("grants"): erworben, ohne eigene Altersbuchung (die Station
	# hat ihre Jahre schon gebucht). Schon erworben: nichts doppelt. Ein gewählter Kurs
	# desselben Skills fällt aus dem Entwurf (sonst kämen seine Jahre dazu).
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
		line += " Machte sich %s zum Feind." % enemy
	c.history.append(line)
	_age_check(c, age_before)
	_sanitize_drafts(c)
	return line

# ---------------- Altern (Ostranauts 1.2) ----------------
# Beim Erreichen von 29 (Middle Age) und 42 (Old Age) kommt je ein zufälliger negativer Trait dazu
# (aus allen negativen; schon vorhandene und solche mit vorhandenem Gegenstück werden übersprungen).
# Mit 47 (max_age) endet die Erstellung: Entwürfe verfallen, nur noch „Los geht's“.
const AGING := [[29, "Middle age"], [42, "Old age"]]

## Nach jeder Alterung aufrufen: Schwellen zwischen altem und neuem Alter prüfen (je einmal)
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
	if creation_ended(c):
		c.set_meta("draft_courses", [])
		c.set_meta("draft_trait_add", [])
		c.set_meta("draft_trait_remove", [])

## Mit max_age (47) endet die Erstellung
func creation_ended(c: CrewMember) -> bool:
	return c.age >= max_age

# ---------------- Lebensereignisse („Seek Adventure“, Ostranauts 2.1) ----------------
# Ein Ereignis kostet 1 Jahr. Man wählt eine von mehreren Antworten; manche brauchen einen Skill
# oder Trait. RISK-Antworten: Beim Beginn eines Ereignisses kommt mit 50 % ein verdeckter
# Fehlschlag-Token dazu. Die RISK-Antwort scheitert, solange ein Token da ist, und entfernt dabei
# genau einen. Andere Antworten entfernen keinen, Tokens sammeln sich an (wie im Spiel v1.0.0.17).
# Belohnungen ohne Entsprechung im Spiel entfallen und stehen als „Not in game“ im Lebenslauf.

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

## Warum gerade kein Ereignis möglich ist ("" = geht)
func adventure_block_reason(c: CrewMember) -> String:
	if pending_encounter(c) != "":
		return "Choose an answer for the current encounter first."
	if creation_ended(c):
		return "Character creation has ended (age %d)." % max_age
	if preview_age(c) + int(enc_cfg.get("years", 1)) > max_age:
		return "Too old for that."
	return ""

## Ereignis beginnen (zufällig oder mit id). token_roll < 0: zufällig; sonst fester Wurf (Tests).
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

## Warum eine Antwort nicht wählbar ist ("" = geht)
func choice_block_reason(c: CrewMember, ch: Dictionary) -> String:
	var req: Dictionary = ch.get("req", {})
	if req.has("skill") and not SkillSystem.acquired(c, String(req.skill)):
		return "Needs %s." % SkillSystem.skill(String(req.skill)).skill_name
	if req.has("trait") and not String(req.trait) in c.traits:
		return "Needs %s." % TraitSystem.get_trait(String(req.trait)).trait_name
	return ""

## Antwort wählen: 1 Jahr, Belohnungen, ggf. RISK und Brig. Gibt den Lebenslauf-Eintrag zurück.
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
		c.age = max_age   # die Brig kann nicht über das Ende der Erstellung hinaus führen
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

## Skill durch ein Ereignis: erworben (100 %); schon erworben = nichts doppelt
func _grant_skill(c: CrewMember, id: String, parts: PackedStringArray) -> void:
	if SkillSystem.skill(id) == null or SkillSystem.acquired(c, id):
		return
	SkillSystem.set_progress(c, id, SkillSystem.ACQUIRED)
	SkillSystem._entry(c, id).unlocked = true
	parts.append(SkillSystem.skill(id).skill_name)

## Trait durch ein Ereignis (Regel: positiver Trait löst negatives Gegenstück ab)
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

## Entwurf nach einer Station oder einem Ereignis bereinigen (schon erworbene Kurse, Traits)
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

## Zufälliger Lebenslauf bis zu einem Zielalter (für NPCs und "Zufall")
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

## Startkredite aus dem Lebenslauf (kann negativ sein: Schulden)
func start_credits(c: CrewMember) -> int:
	return int(c.get_meta("credits", 0))

## Neuer NPC mit zufälliger Vorgeschichte
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
