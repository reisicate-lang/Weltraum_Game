## Beschreibt eine Gegenstandssorte (Daten, keine Logik).
## Neue Gegenstände: einfach eine neue .tres-Datei in res://resources/items/ anlegen.
class_name ItemData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
## Gewicht pro Stück in kg
@export var weight: float = 1.0
## Volumen pro Stück in Litern
@export var volume: float = 1.0
## Neupreis in Credits
@export var value: int = 1
@export_multiline var description: String = ""
## Lehrbuch: welche Fähigkeit und bis zu welchem Fortschritt (Stufe 1: 40 %, 2: 75 %, 3: 100 %)
@export var teaches: String = ""
@export var book_level: int = 0
## Waffe: "armed" (Nahkampf) oder "ranged" (Fernkampf)
@export var weapon: String = ""
## Schmuggelware (am Schwarzmarkt viel wert, kann bei Kontrollen beschlagnahmt werden)
@export var contraband: bool = false
## Steuerpultmodul: welche Funktion es im Modulfach eines Steuerpults freischaltet (z. B. "autodock")
@export var helm_module: String = ""
## Welches Gerät damit aufgefüllt wird und um wie viel, z. B. {"generator": 40}
@export var refill: Dictionary = {}
