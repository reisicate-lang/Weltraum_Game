## Charaktereigenschaften (Traits) nach der Ostranauts-Liste (73 Traits mit Jahreskosten und
## Gegenstücken). Sie ändern sich nicht durch Training, nur durch den Lebenslauf.
extends Node

const DIR := "res://resources/traits/"
## Additive Wirkungen (Summe statt Produkt)
const ADDITIVE := ["piloting"]
## Wirkungen, die im Spiel verrechnet werden (für den Tooltip)
const EFFECT_NAMES := {"learn_speed": "Learning speed", "work_speed": "Work speed", "work_fine": "Fine work",
	"book_speed": "Reading speed", "stress_resist": "Stress resistance", "toughness": "Toughness",
	"recovery": "Healing", "combat": "Combat power", "social": "Social", "hunger": "Food consumption",
	"thirst": "Water consumption", "sleep_gain": "Sleep recovery", "piloting": "Piloting"}
## Frühere eigene Traits → Ostranauts-Traits (alte Spielstände, Lebenslauf-Daten)
const LEGACY := {"calm": "brave", "distracted": "obtuse", "frugal": "slow_metabolism", "hardy": "tough",
	"introvert": "shy", "lazy": "complacent", "nervous": "craven", "nimble": "coordinated", "smart": "genius",
	"social": "gregarious", "weak": "feeble"}

var traits: Dictionary = {}

func _ready() -> void:
	_load_from(DIR)
	_load_from("user://mods/traits/")  # Mods

func _load_from(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")
		if f.ends_with(".tres"):
			var t: TraitData = load(path + f)
			traits[t.trait_id] = t

func get_trait(id: String) -> TraitData:
	return traits.get(resolve(id))

## Alte ID → neue ID (unbekannte bleiben, wie sie sind)
func resolve(id: String) -> String:
	return LEGACY.get(id, id)

## Alle Traits in Wiki-Reihenfolge
func ordered_ids() -> Array:
	var ids: Array = traits.keys()
	ids.sort_custom(func(a, b): return traits[a].order < traits[b].order)
	return ids

## Trait-Liste eines alten Spielstands umstellen (alte IDs → neue, ohne Dopplungen)
func migrate(list: Array) -> Array[String]:
	var out: Array[String] = []
	for id in list:
		var n := resolve(String(id))
		if traits.has(n) and not n in out:
			out.append(n)
	return out

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

## Summe einer additiven Wirkung (z. B. piloting) über alle Traits
func sum(c: CrewMember, key: String) -> float:
	if c == null:
		return 0.0
	var v := 0.0
	for id in c.traits:
		var t := get_trait(id)
		if t != null and t.modifiers.has(key):
			v += float(t.modifiers[key])
	return v

## Gegenstück, das die Figur gerade hat ("" = keins)
func held_opposite(c: CrewMember, id: String) -> String:
	var t := get_trait(id)
	if t == null:
		return ""
	for other in c.traits:
		if other == t.opposite or other in t.conflicts:
			return other
		var o := get_trait(other)
		if o != null and id in o.conflicts:
			return other
	return ""

func can_add(c: CrewMember, id: String) -> bool:
	id = resolve(id)
	return traits.has(id) and not id in c.traits and held_opposite(c, id) == ""

## Trait durch den Lebenslauf (Station, Ereignis) bekommen. Hat die Figur das negative Gegenstück,
## verschwindet stattdessen dieses (Ostranauts-Regel); ein negativer Trait gegen ein positives
## Gegenstück wird nicht vergeben. true = etwas hat sich geändert.
func add(c: CrewMember, id: String) -> bool:
	id = resolve(id)
	if not traits.has(id) or id in c.traits:
		return false
	var opp := held_opposite(c, id)
	if opp != "":
		if get_trait(id).positive and not get_trait(opp).positive:
			c.traits.erase(opp)
			return true
		return false
	c.traits.append(id)
	return true

func remove(c: CrewMember, id: String) -> void:
	c.traits.erase(resolve(id))

## Tooltip (englisch): Kosten, Gegenstück, Wirkung im Spiel, Wiki-Wirkung
func tooltip(id: String) -> String:
	var t := get_trait(id)
	if t == null:
		return ""
	var lines: PackedStringArray = [t.trait_name, "Character creation: %s." % ("%+d %s" % [t.cost, "year" if absi(t.cost) == 1 else "years"] if t.cost != 0 else "free")]
	if t.opposite != "" and get_trait(t.opposite) != null:
		lines.append("Opposite: %s (remove it first)." % get_trait(t.opposite).trait_name)
	var eff: PackedStringArray = []
	for k in t.modifiers:
		var v := float(t.modifiers[k])
		if k in ADDITIVE:
			eff.append("%s %+.2f" % [EFFECT_NAMES.get(k, k), v])
		else:
			eff.append("%s %+d %%" % [EFFECT_NAMES.get(k, k), int(round((v - 1.0) * 100.0))])
	lines.append("In game: " + (", ".join(eff) if not eff.is_empty() else "no gameplay effect yet (flag only)") + ".")
	lines.append("Wiki: " + t.description)
	return "\n".join(lines)
