## Zentrale Einstellungen. Zahlen hier ändern, um das Spiel anzupassen.
## Zeiten sind in Spielminuten, Luftwerte in kPa.
class_name Config
extends RefCounted

const TILE_SIZE := 32
const WORLD_W := 64
const WORLD_H := 44

## Bei 1x ist eine Sekunde im Spiel eine echte Sekunde.
const MINUTES_PER_SECOND := 1.0 / 60.0
const SPEEDS: Array[float] = [0.0, 1.0, 10.0, 60.0, 300.0]
const START_MINUTES := 8 * 60

## Laufgeschwindigkeit: 2,5 Kacheln pro Sekunde (in Kacheln pro Spielminute)
const WALK_SPEED := 150.0
const SPRINT := 1.6

## Bauzeiten und Kosten der Kacheln
const TILE_BUILD_TIME := {1: 2.0, 2: 3.0, 3: 4.0}
const TILE_COST := {1: {"plate": 1}, 2: {"plate": 2}, 3: {"plate": 2, "circuit": 1}}
const TILE_NAMES := {0: "Weltraum", 1: "Boden", 2: "Wand", 3: "Tür"}
const REMOVE_TIME := 1.5
const CABLE_TIME := 1.0
const CABLE_COST := {"copper": 1}

## Atmosphäre
const AIR_O2 := 21.0
const AIR_N2 := 79.0
const AIR_CO2 := 0.04
const O2_OK := 18.0
const O2_LOW := 16.0
const CO2_BAD := 3.0
const BREATH_O2 := 0.12      ## kPa O2 pro Minute und Person
const DIFFUSION := 0.2       ## Luftaustausch zwischen Feldern (pro 1/3 Minute)
const DOOR_SLITS := 0.05     ## geschlossene Innentüren
const VENT_LOSS := 0.35      ## Verlust ins All (pro 1/3 Minute)
const O2GEN_RATE := 0.8
const SCRUB_RATE := 0.8
const TANK_RATE := 4.0
const TANK_TARGET := 95.0

## Bedürfnisse: decay = Verlust pro Stunde, at = ab hier wird gehandelt
const NEEDS := {
	"food": {"name": "Hunger", "decay": 4.0, "at": 45.0, "gain": 45.0, "use_time": 20.0, "verb": "Isst", "use": 1.0},
	"water": {"name": "Durst", "decay": 6.0, "at": 50.0, "gain": 50.0, "use_time": 5.0, "verb": "Trinkt", "use": 0.5},
	"sleep": {"name": "Energie", "decay": 4.0, "at": 30.0, "gain": 13.0, "use_time": 0.0, "verb": "Schläft", "use": 0.0},
	"hygiene": {"name": "Hygiene", "decay": 3.0, "at": 35.0, "gain": 70.0, "use_time": 15.0, "verb": "Wäscht sich", "use": 2.0},
}

## Was ein Charakter tragen kann
const CARRY_WEIGHT := 40.0
const CARRY_VOLUME := 40.0

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1
