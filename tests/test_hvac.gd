## Tests: pressure alarms and thermostat after Ostranauts "Ideal Atmosphere" 3 (Auto on demand,
## set points, built-in regulation without an alarm, standby power, saving)
##   godot --headless --path . --script res://tests/boot.gd -- test_hvac
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

var g: ShipGrid
var PS: Node

## Room of the first device of this type and a free floor tile in it
func _room_with(type: String) -> Dictionary:
	for room in RoomTypes.classify(g):
		for d in room.devices:
			if d.type == type:
				for i in room.cells:
					if g.device_at(g.pos(i)) == null and not g.piles.has(i) and g.cables[i] != 0:
						return {"room": room, "dev": d, "free": g.pos(i)}
	return {}

func _fill(room: Dictionary, field: String, v: float) -> void:
	for i in room.cells:
		g.get(field)[i] = v

func _tick() -> void:
	PS._dirty = true
	PS.step(0.01)
	Hvac.update(g, true)
	PS.step(0.01)   # power demand with the new alarm state

func _initialize() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var SS = root.get_node("SaveSystem")
	SS.slot = 959
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	g = root.get_node("ShipSystem").grid
	PS = root.get_node("ShipPowerSystem")
	var OX = root.get_node("OxygenSystem")
	var IS = root.get_node("ItemSystem")

	# 1) Devices with the wiki values
	_check("O₂/CO₂ Pressure Alarm and Thermostat: sensors, value 659 / 634 / 116",
		IS.device("o2_alarm").item_value == 659 and IS.device("co2_alarm").item_value == 634 and IS.device("thermostat").item_value == 116
		and IS.device("o2_alarm").category == "sensor")

	# 2) O₂ alarm controls the O₂ generator in its room
	var o := _room_with("o2gen")
	var gen: Device = o.dev
	_tick()
	_check("Without an alarm: the O₂ generator regulates itself", not Hvac.controlled(gen) and Hvac.runs(gen))
	var al: Device = g.place_device("o2_alarm", o.free)
	_tick()
	_check("Alarm in the room: generator linked, default set point 20 kPa", Hvac.controlled(gen) and is_equal_approx(Hvac.setpoint(al), 20.0))
	_fill(o.room, "o2", 20.6)
	_tick()
	var gi: int = g.idx(gen.pos)
	OX.step(1.0)
	_check("Above the set point: standby, no O₂ added (%.2f kPa)" % g.o2[gi], not Hvac.runs(gen) and is_equal_approx(g.o2[gi], 20.6))
	var standby: float = PS.main_net().demand
	_fill(o.room, "o2", 19.5)
	_tick()
	OX.step(10.0)
	_check("Below the set point: alarm on, generator runs, capped at set point + 1 (%.2f)" % g.o2[gi], Hvac.active(al) and Hvac.runs(gen) and is_equal_approx(g.o2[gi], 21.0))
	_check("Running uses more power than standby (%.2f → %.2f kW)" % [standby, PS.main_net().demand], PS.main_net().demand > standby)
	_fill(o.room, "o2", 20.5)
	_tick()
	_check("Hysteresis: at 20.5 kPa it keeps running", Hvac.runs(gen))
	_fill(o.room, "o2", 21.0)
	_tick()
	_check("At set point + 1: off again", not Hvac.runs(gen))
	Hvac.adjust(al, 4)
	_check("Set point +4 steps: 22 kPa (cap %.1f)" % Hvac.cap(gen), is_equal_approx(Hvac.setpoint(al), 22.0) and is_equal_approx(Hvac.cap(gen), 23.0))
	Hvac.adjust(al, -1000)
	_check("Set point limited to 5 kPa", is_equal_approx(Hvac.setpoint(al), 5.0))
	Hvac.adjust(al, 30)
	_check("Status shows the set point and the room value (%s)" % al.status_text(), al.status_text().contains("set point 20.0 kPa O₂") and al.status_text().contains("room"))
	al.broken = true
	_tick()
	_check("Broken alarm: generator falls back to its own regulation", not Hvac.controlled(gen) and Hvac.runs(gen))
	al.broken = false

	# 3) CO₂ alarm and scrubber
	var c := _room_with("scrubber")
	var scr: Device = c.dev
	var ca: Device = g.place_device("co2_alarm", c.free)
	var si: int = g.idx(scr.pos)
	_fill(c.room, "co2", 0.3)
	_tick()
	OX.step(1.0)
	_check("CO₂ 0.3 kPa (below 0.5): scrubber on standby", Hvac.controlled(scr) and not Hvac.runs(scr) and is_equal_approx(g.co2[si], 0.3))
	_fill(c.room, "co2", 0.8)
	_tick()
	OX.step(0.1)
	_check("CO₂ 0.8 kPa: alarm, scrubber removes CO₂ (%.2f)" % g.co2[si], Hvac.active(ca) and g.co2[si] < 0.8)
	_fill(c.room, "co2", 0.3)
	_tick()
	_check("0.3 kPa: still on until half the set point", Hvac.runs(scr))
	_fill(c.room, "co2", 0.2)
	_tick()
	_check("0.2 kPa: off", not Hvac.runs(scr))

	# 4) Thermostat and heater
	var h := _room_with("heater")
	var heat: Device = h.dev
	var th: Device = g.place_device("thermostat", h.free)
	Hvac.adjust(th, 2)
	_fill(h.room, "temp", 21.0)
	_tick()
	root.get_node("TemperatureSystem").step(1.0)
	var hi: int = g.idx(heat.pos)
	_check("Thermostat 23 °C, room 21 °C: heater heats above room temperature (%.1f °C)" % g.temp[hi], Hvac.runs(heat) and g.temp[hi] > 21.0)
	_fill(h.room, "temp", 23.6)
	_tick()
	_check("Above set point + 0.5: heater off", not Hvac.runs(heat))

	# 5) Alarm without a machine in its room: warning
	_fill(o.room, "o2", 10.0)
	gen.broken = true
	_tick()
	_check("O₂ alarm without a working generator: alarm stays on", Hvac.active(al))
	gen.broken = false

	# 6) Saving/loading keeps the set points
	SS.save_game()
	SS.load_game(true)
	g = root.get_node("ShipSystem").grid
	var found := -1.0
	for i in g.devices:
		if g.devices[i].type == "thermostat":
			found = Hvac.setpoint(g.devices[i])
	_check("Saving/loading: thermostat set point 23 °C stays (%.1f)" % found, is_equal_approx(found, 23.0))

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
