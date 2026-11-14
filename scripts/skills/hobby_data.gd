## A hobby: not a normal skill. Hobbies unlock conversation options,
## influence events, improve relationships and lower stress.
class_name HobbyData
extends Resource

@export var hobby_id: String = ""
@export var hobby_name: String = ""
@export_multiline var description: String = ""
## Skill that is trained on the side while doing it
@export var related_skill: String = ""
## Effects: {"stress_relief": 10, "relation_bonus": 5, "unlock": "..."}
@export var effects: Dictionary = {}
