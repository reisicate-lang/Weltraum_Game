## Beziehungen, Moral, Konflikte und Gespräche in der Crew.
## Wer viel Zeit nah beieinander verbringt, lernt sich kennen:
## gesellige Leute und gemeinsame Hobbys verbessern Beziehungen,
## Stress verschlechtert sie. Gestresste Crew mit schlechter Beziehung
## gerät in Streit. Psychologie und Überzeugen schlichten.
## Kurze Sätze der Crew erzählen ihre Geschichte (keine Textbildschirme).
class_name CrewSocial
extends RefCounted

static func relation(a: CrewMember, b: CrewMember) -> float:
	return float(a.relations.get(str(b.id), 0.0))

static func change(a: CrewMember, b: CrewMember, amount: float) -> void:
	a.relations[str(b.id)] = clampf(relation(a, b) + amount, -100.0, 100.0)
	b.relations[str(a.id)] = clampf(relation(b, a) + amount, -100.0, 100.0)

## Moral der Crew: 0–100 (Stress und Beziehungen)
static func morale() -> float:
	var crew: Array = CrewSystem.crew
	if crew.is_empty():
		return 100.0
	var s := 0.0
	for c in crew:
		s += 100.0 - c.stress
		for o in crew:
			if o != c:
				s += relation(c, o) * 0.1
	return clampf(s / crew.size(), 0.0, 100.0)

## Stündlich: Beziehungen entwickeln sich, Streit, Gespräche
static func hourly() -> void:
	var crew: Array = CrewSystem.crew
	for i in crew.size():
		for j in range(i + 1, crew.size()):
			var a: CrewMember = crew[i]
			var b: CrewMember = crew[j]
			if a.pos.distance_to(b.pos) > 8.0 * Config.GRID_SCALE or a.away_until > GameState.time or b.away_until > GameState.time:
				continue
			var d := 0.5 * (TraitSystem.factor(a, "social") + TraitSystem.factor(b, "social") - 1.0)
			for h in a.hobbies:
				if h in b.hobbies:
					d += 1.0
			if a.stress > 60.0 or b.stress > 60.0:
				d -= 1.5
			change(a, b, d)
			# Streit
			if a.stress > 60.0 and b.stress > 60.0 and relation(a, b) < 0.0 and randf() < 0.3:
				_argument(a, b)
	if not crew.is_empty() and randf() < 0.15:
		_chatter(crew.pick_random())

static func _argument(a: CrewMember, b: CrewMember) -> void:
	change(a, b, -10.0)
	a.stress = minf(100.0, a.stress + 8.0)
	b.stress = minf(100.0, b.stress + 8.0)
	GameState.toast("%s: „Lass mich in Ruhe!“ – %s: „Dann mach deine Arbeit!“" % [a.display_name.split(" ")[0], b.display_name.split(" ")[0]], "bad")
	# Wer kann schlichten?
	var best: CrewMember = null
	for c in CrewSystem.crew:
		if c != a and c != b and (best == null or SkillSystem.effect(c, "calm") > SkillSystem.effect(best, "calm")):
			best = c
	if best != null and randf() < 0.3 + SkillSystem.effect(best, "calm"):
		change(a, b, 8.0)
		SkillSystem.train(best, "calm", 10.0)
		GameState.toast("%s schlichtet den Streit." % best.display_name)

## Kurze Sätze aus dem Leben der Crew
static func _chatter(c: CrewMember) -> void:
	var lines: Array = []
	for h in c.history:
		if "Werft" in h:
			lines.append("Auf der Werft haben wir solche Hüllen in einer Schicht geflickt.")
		if "Militär" in h:
			lines.append("Im Krieg war das Trümmerfeld noch eine Flotte. Ich war dabei.")
		if "Straße" in h:
			lines.append("Auf L4 lernt man schnell, wem man trauen kann. Niemandem.")
		if "Universität" in h:
			lines.append("Eine Hohmann-Bahn zum Kármán-Ring würde uns Treibstoff sparen.")
		if "Bergbau" in h:
			lines.append("Eis abbauen war ehrlicher als Schrott sammeln.")
	for e in c.enemies:
		lines.append("Wenn %s je hier auftaucht, bin ich weg." % e)
	if c.stress > 70.0:
		lines.append("Ich brauche eine Pause. Wirklich.")
	if lines.is_empty():
		lines.append("Noch ein Tag in dieser Blechdose.")
	GameState.toast("%s: „%s“" % [c.display_name.split(" ")[0], lines.pick_random()])

## Charakter in eine Datei exportieren (für andere Spielstände)
static func export_character(c: CrewMember) -> String:
	DirAccess.make_dir_recursive_absolute("user://characters")
	var path := "user://characters/%s.json" % c.display_name.replace(" ", "_")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(c.to_data()))
	f.close()
	return path

static func exported_list() -> PackedStringArray:
	var dir := DirAccess.open("user://characters")
	return dir.get_files() if dir != null else PackedStringArray()

## Exportierten Charakter als Spielerfigur übernehmen
static func import_character(file: String) -> bool:
	var f := FileAccess.open("user://characters/" + file, FileAccess.READ)
	if f == null:
		return false
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var p := CrewSystem.player()
	var c := CrewMember.from_data(d)
	c.id = p.id
	c.pos = p.pos
	c.is_player = true
	c.relations = {}
	CrewSystem.crew[CrewSystem.crew.find(p)] = c
	GameState.selected = c
	return true
