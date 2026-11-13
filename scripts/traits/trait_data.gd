## Eine Charaktereigenschaft (Trait) nach der Ostranauts-Liste (Wiki „Character Creation“ 2.2.3).
## Traits ändern sich nicht durch Training, nur durch den Lebenslauf (Auswahl, Stationen, Ereignisse).
class_name TraitData
extends Resource

@export var trait_id: String = ""
@export var trait_name: String = ""
## Wirkung laut Wiki (Text). Was davon im Spiel wirkt, steht in modifiers.
@export_multiline var description: String = ""
## Positive Traits kosten Jahre (cost > 0), negative geben Jahre zurück
@export var positive: bool = true
## Spielwirkung. Faktoren (1.0 = normal): learn_speed, work_speed, work_fine, book_speed, stress_resist,
## toughness, recovery, combat, social, hunger, thirst, sleep_gain. Additiv: piloting.
@export var modifiers: Dictionary = {}
## Schließt sich mit diesen Traits aus (das Gegenstück)
@export var conflicts: PackedStringArray = []
## Jahre in der Charaktererstellung (positiv = kostet Jahre, negativ = gibt Jahre zurück)
@export var cost: int = 0
## Gegenstück (z. B. Strong ↔ Feeble), "" = keins
@export var opposite: String = ""
## Reihenfolge wie im Wiki
@export var order: int = 0
