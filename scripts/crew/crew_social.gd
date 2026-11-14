## Relationships, morale, conflicts and conversations in the crew.
## Whoever spends a lot of time close together gets to know each other:
## sociable people and shared hobbies improve relationships,
## stress worsens them. A stressed crew with bad relationships
## starts arguing. Psychology and Persuasion settle it.
## Short lines from the crew tell their story (no text screens).
class_name CrewSocial
extends RefCounted

static func relation(a: CrewMember, b: CrewMember) -> float:
	return float(a.relations.get(str(b.id), 0.0))

static func change(a: CrewMember, b: CrewMember, amount: float) -> void:
	a.relations[str(b.id)] = clampf(relation(a, b) + amount, -100.0, 100.0)
	b.relations[str(a.id)] = clampf(relation(b, a) + amount, -100.0, 100.0)

## Crew morale: 0–100 (stress and relationships)
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

## Hourly: relationships develop, arguments, conversations
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
			# Arguments
			if a.stress > 60.0 and b.stress > 60.0 and relation(a, b) < 0.0 and randf() < 0.3:
				_argument(a, b)
	if not crew.is_empty() and randf() < 0.15:
		_chatter(crew.pick_random())

static func _argument(a: CrewMember, b: CrewMember) -> void:
	change(a, b, -10.0)
	a.stress = minf(100.0, a.stress + 8.0)
	b.stress = minf(100.0, b.stress + 8.0)
	GameState.toast("%s: “Leave me alone!” – %s: “Then do your job!”" % [a.display_name.split(" ")[0], b.display_name.split(" ")[0]], "bad")
	# Who can settle it?
	var best: CrewMember = null
	for c in CrewSystem.crew:
		if c != a and c != b and (best == null or SkillSystem.effect(c, "calm") > SkillSystem.effect(best, "calm")):
			best = c
	if best != null and randf() < 0.3 + SkillSystem.effect(best, "calm"):
		change(a, b, 8.0)
		SkillSystem.train(best, "calm", 10.0)
		GameState.toast("%s settles the argument." % best.display_name)

## Short lines from the crew's lives
static func _chatter(c: CrewMember) -> void:
	var lines: Array = []
	for h in c.history:
		if "Shipyard" in h:
			lines.append("At the shipyard we patched hulls like this in a single shift.")
		if "Military" in h:
			lines.append("In the war that debris field was still a fleet. I was there.")
		if "Street" in h:
			lines.append("On L4 you learn fast who you can trust. Nobody.")
		if "University" in h:
			lines.append("A Hohmann transfer to the Kármán Ring would save us fuel.")
		if "Mining" in h:
			lines.append("Mining ice was more honest than collecting scrap.")
	for e in c.enemies:
		lines.append("If %s ever shows up here, I'm gone." % e)
	if c.stress > 70.0:
		lines.append("I need a break. Really.")
	if lines.is_empty():
		lines.append("Another day in this tin can.")
	GameState.toast("%s: “%s”" % [c.display_name.split(" ")[0], lines.pick_random()])

## Export a character to a file (for other saves)
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

## Use an exported character as the player character
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
