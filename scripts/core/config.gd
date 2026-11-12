## Zentrale Einstellungen. Zahlen hier ändern, um das Spiel anzupassen.
## Zeiten sind in Spielminuten, Luftwerte in kPa.
class_name Config
extends RefCounted

## ---- Vorübergehend abgeschaltete Spielteile (Code bleibt erhalten) ----
## Zum Wiedereinschalten auf true setzen.
## Station: begehbare Station mit Räumen und Figuren beim Andocken an Stationen.
static var ENABLE_STATION := true
## Wrack: Wrack/Asteroid an der unteren Andockschleuse, Bergungsrecht, Verschrotten.
static var ENABLE_WRECK := true

## Raster: Ein Baufeld ist 16 px groß (früher 32 px). GRID_SCALE = so viele heutige Felder
## je Richtung passen in ein Feld früherer Spielstände (alte Stände werden beim Laden verfeinert).
## Figuren und Kamera bleiben gleich groß; Figuren wirken daher im Verhältnis zu den Feldern größer.
const GRID_SCALE := 2
const TILE_SIZE := 16
const WORLD_W := 128
const WORLD_H := 88
## Sichtbare Größe einer Figur in Pixeln (bleibt beim feineren Raster gleich)
const CHAR_PX := 32.0

## Bei 1x ist eine Sekunde im Spiel eine echte Sekunde.
const MINUTES_PER_SECOND := 1.0 / 60.0
const SPEEDS: Array[float] = [0.0, 1.0, 2.0, 4.0, 8.0, 16.0]   ## Pause, ×1 (Echtzeit), ×2, ×4, ×8, ×16
## Echte Sekunden nach dem Loslassen der letzten WASD-Taste, bis ein Laufbefehl (Klick) startet
const MANUAL_WALK_DELAY := 0.5
const START_MINUTES := 8 * 60

## Laufgeschwindigkeit: 5 Felder pro Sekunde (in Feldern pro Spielminute) – dieselbe sichtbare
## Strecke wie früher 2,5 der doppelt so großen Felder
const WALK_SPEED := 150.0 * GRID_SCALE
const SPRINT := 1.6

## Bauzeiten und Kosten der Kacheln
const TILE_BUILD_TIME := {1: 2.0, 2: 3.0, 3: 4.0, 4: 4.0}
const TILE_COST := {1: {"plate": 1}, 2: {"plate": 2}, 3: {"plate": 2, "circuit": 1}, 4: {"glass": 2, "plate": 1}}
## Masse der Bauteile in Tonnen je Feld (Geräte: DeviceData.mass, Standard 0,5 t).
## 0,05 t je feinem Feld = 0,2 t je früherem Feld: gleiche Fläche, gleiche Masse.
const TILE_MASS := {1: 0.05, 2: 0.05, 3: 0.05, 4: 0.05}
const TILE_NAMES := {0: "Weltraum", 1: "Boden", 2: "Wand", 3: "Tür", 4: "Fenster"}
const REMOVE_TIME := 1.5
## Debuggen der Navigationskonsole (Spielminuten Arbeit)
const DEBUG_TIME := 2.0
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
	# Hunger und Durst in echten Abständen (bei ×1 ist ein Spieltag ein echter Tag):
	# wach etwa alle 6 h eine Mahlzeit (30 Punkte, 0,5 Portionen) und alle 2 h ein Glas (10 Punkte, 0,12 l).
	# Im Schlaf sinkt beides halb so schnell. Ohne Essen oder Trinken ist der Wert nach 20 h leer.
	"food": {"name": "Hunger", "decay": 5.0, "at": 70.0, "gain": 30.0, "use_time": 20.0, "verb": "Isst", "use": 0.5},
	"water": {"name": "Durst", "decay": 5.0, "at": 90.0, "gain": 10.0, "use_time": 2.0, "verb": "Trinkt", "use": 0.12},
	"sleep": {"name": "Energie", "decay": 4.0, "at": 30.0, "gain": 13.0, "use_time": 0.0, "verb": "Schläft", "use": 0.0},
	"hygiene": {"name": "Hygiene", "decay": 3.0, "at": 35.0, "gain": 70.0, "use_time": 15.0, "verb": "Wäscht sich", "use": 2.0},
}

## Was ein Charakter tragen kann
const CARRY_WEIGHT := 40.0
const CARRY_VOLUME := 40.0

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 3

## Raumanzüge (Prozent, Verbrauch pro Minute)
const SUIT_O2_USE := 100.0 / 120.0
const SUIT_BATTERY_USE := 100.0 / 150.0
const SUIT_REFILL := 10.0
const SUIT_CHARGE := 10.0
const SUIT_KWH_PER_100 := 0.5
const SUIT_RETURN_AT := 30.0

## Luftschleuse
const AIRLOCK_MAX_SIZE := 12 * GRID_SCALE * GRID_SCALE
const AIRLOCK_PUMP_RATE := 600.0
const AIRLOCK_TOLERANCE := 6.0
const AIRLOCK_STORE_MAX := 3000.0

## Schäden
const WEAR_PER_DAY := 4.0
const METEORS_PER_DAY := 0.7
const FIRST_METEOR_DAY := 1.0
const AUTO_REPAIR_AT := 50.0
const REPAIR_TIME := 3.0

## Wirtschaft (Credits = Cr)
const START_CREDITS := 400
const START_DEBT := 24000
const PAYMENT := 1500
const PAYMENT_DAYS := 7
const LATE_FEE := 0.1
const MAX_STRIKES := 3
const DOCK_FEE := 45
const BUY_MARKUP := 1.3
const SELL_FACTOR := 0.85
const CLAIM_FEE := 200
const HULL_FACTOR := 0.25
const PRICE_DRIFT := 0.06
const REFILL_AT := 0.3

## Wrack an der Bergungsleine

## Temperatur (°C)
const ROOM_TEMP := 21.0
const SPACE_TEMP := -60.0
const HEAT_LOSS := 0.02        ## Wärmeverlust an das All pro Minute (Anteil)
const HEATER_RATE := 1.5       ## Grad pro Minute
const BODY_TEMP := 37.0
## Feuer
const FIRE_O2_MIN := 12.0
const FIRE_SPREAD := 0.004     ## Chance pro Minute, auf ein Nachbarfeld überzuspringen
