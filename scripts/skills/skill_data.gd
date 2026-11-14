## A skill (data template). The progress per character is stored in the
## character itself (CharacterSkills). New skill = new .tres file
## in res://resources/skills/ – without code changes.
class_name SkillData
extends Resource

@export var skill_id: String = ""
@export var skill_name: String = ""
@export_multiline var description: String = ""
## "technik", "kampf", "praxis", "sozial"
@export var category: String = ""
## Starting values of the template (each character stores its own progress)
@export var progress: float = 0.0
@export var experience: float = 0.0
## How you learn it (text for the display), e.g. ["Repairing engines", "Textbook"]
@export var learning_sources: PackedStringArray = []
## Actions from res://data/skill_actions.json that train this skill
@export var training_actions: PackedStringArray = []
## Prerequisites: {skill_id: minimum progress}. Without them the skill stops at 40 %.
@export var required_skills: Dictionary = {}
## Effect at 100 %: {effect_id: value}. The effect grows with the progress.
@export var gameplay_effects: Dictionary = {}
## Description of the full effect (unlocked at 100 %)
@export_multiline var mastery_text: String = ""
## Character creation: can be chosen as a course, costs this many years of life (0 = no course)
@export var course_years: int = 0
## Acquired (100 %): additive work value for jobs at devices of these categories
## (DeviceData.category). Work value = work speed × 10, see SkillSystem.work_value().
@export var work_value_bonus: float = 0.0
@export var work_categories: PackedStringArray = []
## Acquired: removes the EVA work penalty (work in a space suit, see SkillSystem.EVA_WORK_FACTOR)
@export var removes_eva_malus: bool = false
## Acquired: raises the character's Piloting at the navigation console (see SkillSystem.piloting)
@export var piloting_bonus: float = 0.0
## Pure check flag without a numeric effect: query it via SkillSystem.acquired / meets
@export var check_flag: bool = false
## Ostranauts hobby (wiki 2.2.2): in the hobby row of the life story instead of a course row
@export var is_hobby: bool = false
## Acquired: attack + attack_bonus with this weapon type ("armed" = melee weapon, "unarmed" = no weapon)
@export var attack_bonus: float = 0.0
@export var attack_weapon: String = ""
