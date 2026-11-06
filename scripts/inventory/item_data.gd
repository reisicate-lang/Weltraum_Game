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
## Welches Gerät damit aufgefüllt wird und um wie viel, z. B. {"generator": 40}
@export var refill: Dictionary = {}
