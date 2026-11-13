## Charaktererstellung mit Lebenslauf. Man beginnt mit 14 Jahren und
## wählt Lebensstationen (Schule, Lehre, Militär, Straße ...). Jede kostet
## Lebensjahre und bringt Fähigkeiten, Eigenschaften, Kontakte, Feinde,
## Geld oder Gegenstände. Zufällige Lebensereignisse kommen dazu.
## Daten: res://data/careers.json
extends Node

var careers: Array = []
var events: Array = []
var start_age := 14
var max_age := 60

const FIRST_NAMES := ["Mira", "Jonas", "Ayla", "Tomás", "Ines", "Kofi", "Lena", "Dario", "Yuki", "Bram", "Nadia", "Oskar", "Sana", "Emil", "Rhea", "Pavel"]
const LAST_NAMES := ["Okafor", "Brandt", "Novak", "Ferreira", "Sato", "Lindqvist", "Haddad", "Kowalski", "Mbeki", "Varga", "Ruiz", "Holm"]
const COLORS := ["#59c7e6", "#6fcf8e", "#c07ad8", "#e5844b", "#d8c14b", "#e56b8f", "#7f9de6"]

func _ready() -> void:
	var f := FileAccess.open("res://data/careers.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	careers = d.careers
	events = d.events
	start_age = int(d.start_age)
	max_age = int(d.max_age)

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
	if draft_balance(c) < 0:
		return false
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
	return true

func career(id: String) -> Dictionary:
	for c in careers:
		if c.id == id:
			return c
	return {}

## Charakter auf den Anfang des Lebenslaufs setzen
func begin(c: CrewMember) -> void:
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
	# Eine angeborene Eigenschaft
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
	if k.is_empty() or not k in available(c):
		return ""
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
	# Zufälliges Lebensereignis
	if randf() < 0.4:
		c.history.append("   Ereignis: " + _event(c, events.pick_random()))
	return line

func _event(c: CrewMember, e: Dictionary) -> String:
	for t in e.get("traits_remove", []):
		TraitSystem.remove(c, t)
	for t in e.get("traits_add", []):
		TraitSystem.add(c, t)
	c.set_meta("credits", int(c.get_meta("credits", 0)) + int(e.get("credits", 0)))
	if e.get("enemy", false):
		c.enemies.append("%s %s" % [FIRST_NAMES.pick_random(), LAST_NAMES.pick_random()])
	if e.has("learn"):
		for s in c.skills.keys():
			SkillSystem.set_progress(c, s, minf(SkillSystem.cap(c, s), SkillSystem.progress(c, s) + float(e.learn) * 0.3))
	if e.get("item", "") == "book":
		var ids := SkillSystem.skills.keys()
		c.inv.add("book_%s_1" % ids.pick_random(), 1, 70.0)
	return e.text

func choose_hobby(c: CrewMember, id: String) -> bool:
	if id in c.hobbies or c.hobbies.size() >= 2:
		return false
	c.hobbies.append(id)
	c.history.append("Hobby: " + HobbySystem.get_hobby(id).hobby_name)
	return true

## Zufälliger Lebenslauf bis zu einem Zielalter (für NPCs und "Zufall")
func randomize_life(c: CrewMember, target_age: int) -> void:
	begin(c)
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
	randomize_life(c, randi_range(20, 45))
	var total := 0.0
	for s in c.skills:
		total += SkillSystem.progress(c, s)
	c.salary = 20 + int(total / 12.0)
	return c
