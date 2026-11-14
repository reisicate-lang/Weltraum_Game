## Central settings. Change the numbers here to tune the game.
## Times are in game minutes, air values in kPa.
class_name Config
extends RefCounted

## ---- Temporarily disabled game parts (the code stays in place) ----
## Set to true to switch them back on.
## Station: walkable station with rooms and characters when docking at stations.
static var ENABLE_STATION := true
## Wreck: wreck/asteroid at the docking port, salvage permit, scrapping.
static var ENABLE_WRECK := true

## Grid: a build tile is 16 px (formerly 32 px). GRID_SCALE = how many of today's tiles
## per direction fit into one tile of older saves (old saves are refined when loaded).
## Characters and camera keep their size, so characters look larger relative to the tiles.
const GRID_SCALE := 2
const TILE_SIZE := 16
const WORLD_W := 128
const WORLD_H := 88
## Visible size of a character in pixels (unchanged by the finer grid)
const CHAR_PX := 32.0

## At 1x one second in the game is one real second.
const MINUTES_PER_SECOND := 1.0 / 60.0
const SPEEDS: Array[float] = [0.0, 1.0, 2.0, 4.0, 8.0, 16.0]   ## pause, ×1 (real time), ×2, ×4, ×8, ×16
## Real seconds after releasing the last WASD key before a walk order (click) starts
const MANUAL_WALK_DELAY := 0.5
const START_MINUTES := 8 * 60

## Walking speed: 5 tiles per second (in tiles per game minute) – the same visible
## distance as 2.5 of the formerly twice as large tiles
const WALK_SPEED := 150.0 * GRID_SCALE
const SPRINT := 1.6

## Build times and costs of the tiles
const TILE_BUILD_TIME := {1: 2.0, 2: 3.0, 3: 4.0, 4: 4.0}
const TILE_COST := {1: {"plate": 1}, 2: {"plate": 2}, 3: {"plate": 2, "circuit": 1}, 4: {"glass": 2, "plate": 1}}
## Mass of building parts in tonnes per tile (devices: DeviceData.mass, default 0.5 t).
## 0.05 t per fine tile = 0.2 t per former tile: same area, same mass.
const TILE_MASS := {1: 0.05, 2: 0.05, 3: 0.05, 4: 0.05}
const TILE_NAMES := {0: "Space", 1: "Floor", 2: "Wall", 3: "Door", 4: "Window"}
const REMOVE_TIME := 1.5
## Debugging the navigation console (game minutes of work)
const DEBUG_TIME := 2.0
const CABLE_TIME := 1.0
const CABLE_COST := {"copper": 1}

## Atmosphere
const AIR_O2 := 21.0
const AIR_N2 := 79.0
const AIR_CO2 := 0.04
const O2_OK := 18.0
const O2_LOW := 16.0
const CO2_BAD := 3.0
const BREATH_O2 := 0.12      ## kPa O2 per minute and person
const DIFFUSION := 0.2       ## air exchange between tiles (per 1/3 minute)
const DOOR_SLITS := 0.05     ## closed inner doors
const VENT_LOSS := 0.35      ## loss to space (per 1/3 minute)
const O2GEN_RATE := 0.8
const SCRUB_RATE := 0.8
const TANK_RATE := 4.0
const TANK_TARGET := 95.0

## Needs: decay = loss per hour, at = act from this value on
const NEEDS := {
	# Hunger and thirst at real intervals (at ×1 a game day is a real day):
	# awake, about one meal every 6 h (30 points, 0.5 portions) and one glass every 2 h (10 points, 0.12 l).
	# Both drop half as fast while asleep. Without food or drink the value is empty after 20 h.
	"food": {"name": "Hunger", "decay": 5.0, "at": 70.0, "gain": 30.0, "use_time": 20.0, "verb": "Eating", "use": 0.5},
	"water": {"name": "Thirst", "decay": 5.0, "at": 90.0, "gain": 10.0, "use_time": 2.0, "verb": "Drinking", "use": 0.12},
	"sleep": {"name": "Energy", "decay": 4.0, "at": 30.0, "gain": 13.0, "use_time": 0.0, "verb": "Sleeping", "use": 0.0},
	"hygiene": {"name": "Hygiene", "decay": 3.0, "at": 35.0, "gain": 70.0, "use_time": 15.0, "verb": "Washing", "use": 2.0},
}

## What a character can carry
const CARRY_WEIGHT := 40.0
const CARRY_VOLUME := 40.0

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 3

## Space suits (percent, use per minute)
const SUIT_O2_USE := 100.0 / 120.0
const SUIT_BATTERY_USE := 100.0 / 150.0
const SUIT_REFILL := 10.0
const SUIT_CHARGE := 10.0
const SUIT_KWH_PER_100 := 0.5
const SUIT_RETURN_AT := 30.0

## Airlock
const AIRLOCK_MAX_SIZE := 12 * GRID_SCALE * GRID_SCALE
const AIRLOCK_PUMP_RATE := 600.0
const AIRLOCK_TOLERANCE := 6.0
const AIRLOCK_STORE_MAX := 3000.0

## Damage
const WEAR_PER_DAY := 4.0
const METEORS_PER_DAY := 0.7
const FIRST_METEOR_DAY := 1.0
const AUTO_REPAIR_AT := 50.0
const REPAIR_TIME := 3.0

## Economy (credits = Cr)
const START_CREDITS := 400
const START_DEBT := 24000
const PAYMENT := 1500
const PAYMENT_DAYS := 7
const LATE_FEE := 0.1
const MAX_STRIKES := 3
const DOCK_FEE := 45
const BUY_MARKUP := 1.3
const SELL_FACTOR := 0.85
## Ayotimiwa Salvage Permit (Ostranauts Trading 2.3, prices 1:1): id, name, cost, hours
const PERMIT_TIERS := [
	{"id": "yellow", "name": "Yellow", "cost": 5000, "hours": 24},
	{"id": "red", "name": "Red", "cost": 13500, "hours": 72},
	{"id": "blue", "name": "Blue", "cost": 30000, "hours": 168},
	{"id": "silver", "name": "Silver", "cost": 120000, "hours": 720},
	{"id": "black", "name": "Black", "cost": 1000000, "hours": 7200},
]
## N.A.S.S. fine for docking at a derelict near a station without a valid permit
## (the wiki names no amount: one Yellow permit)
const NASS_FINE := 5000
const HULL_FACTOR := 0.25
const PRICE_DRIFT := 0.06
const REFILL_AT := 0.3

## Wreck on the salvage line

## Temperatur (°C)
const ROOM_TEMP := 21.0
const SPACE_TEMP := -60.0
const HEAT_LOSS := 0.02        ## Heat loss to space per minute (fraction)
const HEATER_RATE := 1.5       ## degrees per minute
const BODY_TEMP := 37.0
## Fire
const FIRE_O2_MIN := 12.0
const FIRE_SPREAD := 0.004     ## Chance per minute to spread to a neighbouring tile
