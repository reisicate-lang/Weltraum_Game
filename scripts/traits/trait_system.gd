## Charaktereigenschaften (Traits). Sie ändern sich nicht durch Training,
## nur durch Ereignisse im Lebenslauf.
extends Node

const DIR := "res://resources/traits/"
var traits: Dictionary = {}

func _ready() -> void:
	var dir := DirAccess.open(DIR)
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")
		if f.ends_with(".tres"):
			var t: TraitData = load(DIR + f)
			traits[t.trait_id] = t

func get_trait(id: String) -> TraitData:
	return traits.get(id)

## Produkt eines Faktors über alle Traits eines Charakters (1.0 = normal)
func factor(c: CrewMember, key: String) -> float:
	if c == null:
		return 1.0
	var f := 1.0
	for id in c.traits:
		var t := get_trait(id)
		if t != null and t.modifiers.has(key):
			f *= float(t.modifiers[key])
	return f

func can_add(c: CrewMember, id: String) -> bool:
	if id in c.traits:
		return false
	for other in c.traits:
		if id in get_trait(other).conflicts:
			return false
	return true

func add(c: CrewMember, id: String) -> bool:
	if not can_add(c, id):
		return false
	c.traits.append(id)
	return true

func remove(c: CrewMember, id: String) -> void:
	c.traits.erase(id)
