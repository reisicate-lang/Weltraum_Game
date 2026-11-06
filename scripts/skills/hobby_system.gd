## Hobbys: senken Stress, schalten Gespräche frei, verbessern Beziehungen
## und trainieren nebenbei eine Fähigkeit. Hobbys sind keine Skills.
extends Node

const DIR := "res://resources/hobbies/"
var hobbies: Dictionary = {}

func _ready() -> void:
	_load_from(DIR)
	_load_from("user://mods/hobbies/")  # Mods

func _load_from(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")
		if f.ends_with(".tres"):
			var h: HobbyData = load(path + f)
			hobbies[h.hobby_id] = h

func get_hobby(id: String) -> HobbyData:
	return hobbies.get(id)

## Hat der Charakter ein Hobby, das dieses Gespräch freischaltet?
func unlocks(c: CrewMember, talk: String) -> bool:
	for id in c.hobbies:
		if get_hobby(id).effects.get("unlock", "") == talk:
			return true
	return false

## Lernen einer Fähigkeit, die zu einem Hobby passt, geht 25 % schneller
func learn_bonus(c: CrewMember, action: String) -> float:
	var skills_of: Array = SkillSystem.actions.get(action, {}).get("skills", [])
	for id in c.hobbies:
		if get_hobby(id).related_skill in skills_of:
			return 1.25
	return 1.0

func book_bonus(c: CrewMember) -> float:
	var f := 1.0
	for id in c.hobbies:
		f += float(get_hobby(id).effects.get("book_bonus", 0.0))
	return f

func stress_relief(c: CrewMember) -> float:
	var s := 0.0
	for id in c.hobbies:
		s += float(get_hobby(id).effects.get("stress_relief", 0.0))
	return s

## Freizeit mit dem Hobby: Stress sinkt, passende Fähigkeit wird trainiert
func practice(c: CrewMember, minutes: float) -> void:
	for id in c.hobbies:
		var h := get_hobby(id)
		if h.related_skill != "":
			SkillSystem.train(c, "study_" + h.related_skill, minutes * 0.3)
	c.stress = maxf(0.0, c.stress - stress_relief(c) * minutes / 60.0)
	# Musik und Gesang heben die Stimmung der Crew in der Nähe
	if "music" in c.hobbies:
		SkillSystem.train(c, "perform_song", minutes * 0.3)
		var mood := 3.0 + SkillSystem.effect(c, "crew_mood") * 15.0
		for other in CrewSystem.crew:
			if other != c and other.pos.distance_to(c.pos) < 5.0:
				other.stress = maxf(0.0, other.stress - mood * minutes / 60.0)
