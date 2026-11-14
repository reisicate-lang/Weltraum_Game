## Describes a kind of item (data, no logic).
## New items: just create a new .tres file in res://resources/items/.
class_name ItemData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
## Weight per piece in kg
@export var weight: float = 1.0
## Volume per piece in liters
@export var volume: float = 1.0
## Neupreis in Credits
@export var value: int = 1
@export_multiline var description: String = ""
## Textbook: which skill and up to which progress (level 1: 40 %, 2: 75 %, 3: 100 %)
@export var teaches: String = ""
@export var book_level: int = 0
## Weapon: "armed" (melee) or "ranged" (ranged)
@export var weapon: String = ""
## Contraband (worth a lot on the black market, can be seized during inspections)
@export var contraband: bool = false
## Console module: which function it unlocks in the module bay of a navigation console (e.g. "autodock")
@export var helm_module: String = ""
## Which device it refills and by how much, e.g. {"generator": 40}
@export var refill: Dictionary = {}
