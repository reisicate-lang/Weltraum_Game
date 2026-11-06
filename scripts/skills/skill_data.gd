## Eine Fähigkeit (Datenvorlage). Der Fortschritt pro Charakter liegt im
## Charakter selbst (CharacterSkills). Neue Fähigkeit = neue .tres-Datei
## in res://resources/skills/ – ohne Code-Änderung.
class_name SkillData
extends Resource

@export var skill_id: String = ""
@export var skill_name: String = ""
@export_multiline var description: String = ""
## "technik", "kampf", "praxis", "sozial"
@export var category: String = ""
## Startwerte der Vorlage (pro Charakter wird eigener Fortschritt gespeichert)
@export var progress: float = 0.0
@export var experience: float = 0.0
## Wodurch man lernt (Text für die Anzeige), z. B. ["Reparaturen an Motoren", "Lehrbuch"]
@export var learning_sources: PackedStringArray = []
## Aktionen aus res://data/skill_actions.json, die diese Fähigkeit trainieren
@export var training_actions: PackedStringArray = []
## Voraussetzungen: {skill_id: Mindestfortschritt}. Ohne sie bleibt die Fähigkeit bei 40 % stehen.
@export var required_skills: Dictionary = {}
## Wirkung bei 100 %: {effekt_id: wert}. Die Wirkung wächst mit dem Fortschritt.
@export var gameplay_effects: Dictionary = {}
## Beschreibung der vollständigen Wirkung (freigeschaltet bei 100 %)
@export_multiline var mastery_text: String = ""
