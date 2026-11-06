## Eine Charaktereigenschaft. Traits ändern sich nicht durch Training,
## nur durch Lebenslauf-Ereignisse.
class_name TraitData
extends Resource

@export var trait_id: String = ""
@export var trait_name: String = ""
@export_multiline var description: String = ""
@export var positive: bool = true
## Faktoren: learn_speed, work_speed, stress_resist, toughness, social, recovery, combat (1.0 = normal)
@export var modifiers: Dictionary = {}
## Schließt sich mit diesen Traits aus
@export var conflicts: PackedStringArray = []
