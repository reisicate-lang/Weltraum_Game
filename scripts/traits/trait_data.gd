## A character trait after the Ostranauts list (wiki "Character Creation" 2.2.3).
## Traits do not change through training, only through the life story (choices, life steps, encounters).
class_name TraitData
extends Resource

@export var trait_id: String = ""
@export var trait_name: String = ""
## Effect according to the wiki (text). What of it works in the game is in modifiers.
@export_multiline var description: String = ""
## Positive traits cost years (cost > 0), negative ones give years back
@export var positive: bool = true
## Gameplay effect. Factors (1.0 = normal): learn_speed, work_speed, work_fine, book_speed, stress_resist,
## toughness, recovery, combat, social, hunger, thirst, sleep_gain. Additive: piloting.
@export var modifiers: Dictionary = {}
## Excludes itself with these traits (the counterpart)
@export var conflicts: PackedStringArray = []
## Years in character creation (positive = costs years, negative = gives years back)
@export var cost: int = 0
## Counterpart (e.g. Strong ↔ Feeble), "" = none
@export var opposite: String = ""
## Order as in the wiki
@export var order: int = 0
