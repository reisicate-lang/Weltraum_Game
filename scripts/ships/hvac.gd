## HVAC control after Ostranauts "Ideal Atmosphere" 3: pressure alarms and thermostats measure
## their room and switch the linked machines there on demand (Auto). Machines in a room without
## a matching alarm keep their built-in regulation, so ships without alarms work as before.
##   O₂ Pressure Alarm  → O₂ generators: on below the set point, off 1 kPa above it
##   CO₂ Pressure Alarm → CO₂ scrubbers: on above the set point, off at half of it
##   Thermostat         → heaters: on 0.5 °C below the set point, off 0.5 °C above it
## The wiki has no N₂-only source in this game: the air tank keeps its own pressure control.
class_name Hvac
extends RefCounted

const DEFAULTS := {"o2_alarm": 20.0, "co2_alarm": 0.5, "thermostat": 21.0, "tox_alarm": 0.1}
const STEPS := {"o2_alarm": 0.5, "co2_alarm": 0.1, "thermostat": 1.0, "tox_alarm": 0.05}
const LIMITS := {"o2_alarm": [5.0, 40.0], "co2_alarm": [0.1, 5.0], "thermostat": [10.0, 30.0], "tox_alarm": [0.05, 1.0]}
const UNITS := {"o2_alarm": "kPa O₂", "co2_alarm": "kPa CO₂", "thermostat": "°C", "tox_alarm": "kPa contaminants"}
const MACHINES := {"o2_alarm": ["o2gen"], "co2_alarm": ["scrubber"], "thermostat": ["heater"], "tox_alarm": ["tox_scrubber"]}
## Recompute rooms at most this often (game minutes)
const PERIOD := 0.25
## Alarm toast without a working machine in the room: at most every 30 game minutes
const WARN_EVERY := 30.0

static var _ctrl := {}        ## machine Device -> alarm Device
static var _active := {}      ## alarm Device -> bool (machines running)
static var _reading := {}     ## alarm Device -> room average
static var _warned := {}      ## alarm Device -> game time of the last toast
static var _at := -1000.0
static var _grid: ShipGrid = null

static func is_alarm(type: String) -> bool:
	return DEFAULTS.has(type)

static func setpoint(dev: Device) -> float:
	return dev.setpoint if dev.setpoint >= 0.0 else float(DEFAULTS.get(dev.type, 0.0))

static func adjust(dev: Device, steps: int) -> void:
	var lim: Array = LIMITS[dev.type]
	dev.setpoint = clampf(snappedf(setpoint(dev) + float(STEPS[dev.type]) * steps, 0.01), float(lim[0]), float(lim[1]))
	_at = -1000.0

static func reset() -> void:
	_ctrl.clear()
	_active.clear()
	_reading.clear()
	_warned.clear()
	_at = -1000.0
	_grid = null

## Is this machine linked to an alarm in its room?
static func controlled(dev: Device) -> bool:
	return _ctrl.has(dev)

## May the machine run? Without an alarm: always (built-in regulation)
static func runs(dev: Device) -> bool:
	var a = _ctrl.get(dev)
	return a == null or bool(_active.get(a, false))

## Upper limit for a linked machine (O₂ generator: kPa, heater: °C); -1 = built-in default
static func cap(dev: Device) -> float:
	var a = _ctrl.get(dev)
	if a == null:
		return -1.0
	match a.type:
		"o2_alarm":
			return setpoint(a) + 1.0
		"thermostat":
			return setpoint(a) + 0.5
	return -1.0

static func reading(alarm: Device) -> float:
	return float(_reading.get(alarm, -1.0))

static func active(alarm: Device) -> bool:
	return bool(_active.get(alarm, false))

## Status text for an alarm (shown on hover)
static func status(alarm: Device) -> String:
	var r := reading(alarm)
	var n := 0
	for m in _ctrl:
		if _ctrl[m] == alarm:
			n += 1
	var unit: String = UNITS[alarm.type]
	var txt := "set point %s %s" % [_num(setpoint(alarm)), unit]
	if r >= 0.0:
		txt += " · room %s" % _num(r)
	txt += " · %d linked" % n + (" · ALARM, machines on" if active(alarm) else "")
	return txt

static func _num(v: float) -> String:
	return "%.1f" % v if absf(v) >= 1.0 else "%.2f" % v

static func update(g: ShipGrid, force: bool = false) -> void:
	if g != _grid:
		reset()
		_grid = g
	if not force and GameState.time - _at < PERIOD:
		return
	_at = GameState.time
	_ctrl.clear()
	var seen := {}
	for room in RoomTypes.classify(g):
		var alarms := {}
		for dev in room.devices:
			if is_alarm(dev.type) and not dev.broken and dev.powered and not alarms.has(dev.type):
				alarms[dev.type] = dev
		for t in alarms:
			var a: Device = alarms[t]
			seen[a] = true
			var r := _average(g, room.cells, t)
			_reading[a] = r
			var sp := setpoint(a)
			var on := bool(_active.get(a, false))
			match t:
				"o2_alarm":
					on = r < sp if not on else r < sp + 1.0
				"co2_alarm", "tox_alarm":
					on = r > sp if not on else r > sp * 0.5
				"thermostat":
					on = r < sp - 0.5 if not on else r < sp + 0.5
			_active[a] = on
			var working := 0
			for dev in room.devices:
				if dev.type in MACHINES[t]:
					_ctrl[dev] = a
					if not dev.broken and dev.powered:
						working += 1
			if on and working == 0 and GameState.time - float(_warned.get(a, -1000.0)) >= WARN_EVERY:
				_warned[a] = GameState.time
				GameState.toast("%s in %s: %s %s – no working machine linked." % [a.data().display_name, String(room.get("name", "a room")), _num(r), UNITS[t]], "bad")
	for a in _active.keys():
		if not seen.has(a):
			_active.erase(a)
			_reading.erase(a)

static func _average(g: ShipGrid, cells: Array, t: String) -> float:
	var s := 0.0
	for i in cells:
		match t:
			"o2_alarm":
				s += g.o2[i]
			"co2_alarm":
				s += g.co2[i]
			"tox_alarm":
				s += g.tox[i]
			"thermostat":
				s += g.temp[i]
	return s / maxf(1.0, cells.size())
