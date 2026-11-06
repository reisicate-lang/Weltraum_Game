## Ein Hobby: kein normaler Skill. Hobbys schalten Gesprächsoptionen frei,
## beeinflussen Ereignisse, verbessern Beziehungen und senken Stress.
class_name HobbyData
extends Resource

@export var hobby_id: String = ""
@export var hobby_name: String = ""
@export_multiline var description: String = ""
## Fähigkeit, die beim Ausüben nebenbei mit trainiert wird
@export var related_skill: String = ""
## Wirkungen: {"stress_relief": 10, "relation_bonus": 5, "unlock": "..."}
@export var effects: Dictionary = {}
