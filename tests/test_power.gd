## Tests: power after Ostranauts "Power": battery types, condition, power switch/backup power, runtime
##   godot --headless --path . --script res://tests/boot.gd -- test_power
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var g
var P

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

## Empty test area: all devices and cables gone, only what the test builds
func _clear() -> void:
	g.devices.clear()
	g.cables.fill(0)
	P._dirty = true

func _dev(type: String, p: Vector2i, charge: float = 0.0) -> Device:
	var d: Device = g.place_device(type, p)
	d.charge = charge
	P._dirty = true
	return d

func _initialize() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var IS = root.get_node("ItemSystem")
	var ui = root.get_node("UIManager")
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	g = root.get_node("ShipSystem").grid
	P = root.get_node("ShipPowerSystem")

	# 0) Small starter ship without a generator: one Ship Battery lasts 3–5 h (wiki)
	for i in g.devices.keys():
		if g.devices[i].type in ["generator", "solar"]:
			g.devices.erase(i)
	P._dirty = true
	P.step(0.01)
	var start_demand: float = P.main_net().demand
	var hours: float = IS.device("battery").capacity / start_demand
	var backup: float = IS.device("battery_mini").capacity / start_demand
	_check("Starter ship: Mini XS backup power lasts about 1 h (%.2f h)" % backup, backup >= 0.8 and backup <= 1.5)
	_check("Starter ship: Ship Battery lasts %.1f h at %.1f kW" % [hours, start_demand], hours >= 3.0 and hours <= 5.0)

	# 1) Battery types: capacity 1:2:4, charge/discharge limit 20/40/81 kW
	var mini = IS.device("battery_mini")
	var comp = IS.device("battery_compact")
	var ship = IS.device("battery")
	_check("Typen: Mini XS 5 kWh/20 kW, Compact S 10/40, Ship Battery 20/81",
		mini.capacity == 5.0 and comp.capacity == 10.0 and ship.capacity == 20.0
		and mini.max_rate == 20.0 and comp.max_rate == 40.0 and ship.max_rate == 81.0)
	_check("Today's battery is called Ship Battery", ship.display_name == "Ship Battery")
	_check("All three in the build menu (category power)", mini.category == "power" and comp.category == "power" and IS.device("power_switch").category == "power")

	# 2) Runtime: 20 kWh at 3 kW consumption → about 6.7 h, display in the status
	_clear()
	var y := 3
	var x := 3
	cable_line(g, Vector2i(x, y), Vector2i(x + 4, y))
	var bat := _dev("battery", Vector2i(x, y), 20.0)
	_dev("o2gen", Vector2i(x + 1, y))     # 1,5 kW
	_dev("scrubber", Vector2i(x + 2, y))  # 1 kW
	_dev("locker", Vector2i(x + 3, y))    # 0,5 kW
	P.step(0.01)
	var net: Dictionary = P.main_net()
	_check("Laufzeit %.2f h ≈ 20/3" % net.hours, absf(net.hours - 20.0 / 3.0) < 0.05)
	var txt: String = ui.runtime_text(net)
	_check("Display: “%s”" % txt, txt.contains("batteries last about 6.7 h"))
	P.step(60.0)
	_check("After 1 h: charge %.2f kWh (−3)" % bat.charge, absf(bat.charge - (20.0 - 3.0 - 0.0005)) < 0.01)
	bat.charge = 0.2
	P.step(0.01)
	_check("Under 1 h in minutes: “%s”" % ui.runtime_text(P.main_net()), ui.runtime_text(P.main_net()).contains("min"))

	# 3) Condition: capacity × condition, below that the charge creeps away
	_clear()
	var good := _dev("battery", Vector2i(3, 3), 20.0)
	var bad := _dev("battery", Vector2i(3, 6), 20.0)
	good.cond = 90.0
	bad.cond = 50.0
	g.cables[g.idx(Vector2i(3, 3))] = 1
	g.cables[g.idx(Vector2i(3, 6))] = 1
	P.step(0.001)
	_check("Condition 50 %%: usable %.1f kWh, charge capped to %.2f" % [P.capacity_of(bad), bad.charge], P.capacity_of(bad) == 10.0 and bad.charge <= 10.0)
	_check("Zustand 90 %: nutzbar 18 kWh", is_equal_approx(P.capacity_of(good), 18.0))
	good.charge = 18.0
	bad.charge = 10.0
	P.step(60.0)
	var leak: float = 10.0 - bad.charge
	_check("Zustand 50 %%: verliert %.3f kWh/h (erwartet 0,667)" % leak, absf(leak - 20.0 * 0.1 * 25.0 / 75.0) < 0.01)
	_check("Condition 90 %%: keeps its charge (%.2f)" % good.charge, is_equal_approx(good.charge, 18.0))
	bad.broken = true
	P.step(0.01)
	_check("Kaputt: speichert nichts mehr", P.capacity_of(bad) == 0.0 and bad.charge == 0.0)

	# 4) Discharge limit: above the limit the power fails despite the charge
	_clear()
	cable_line(g, Vector2i(3, 3), Vector2i(4, 3))
	var m := _dev("battery_mini", Vector2i(3, 3), 5.0)
	var o2 := _dev("o2gen", Vector2i(4, 3))
	var old_rate: float = mini.max_rate
	mini.max_rate = 1.0   # temporarily below the 1.5 kW demand
	P.step(1.0)
	_check("Demand above the discharge limit → failure, the charge stays", not o2.powered and m.charge == 5.0)
	mini.max_rate = old_rate
	P.step(1.0)
	_check("Demand below the limit → supplied", o2.powered and m.charge < 5.0)
	# Charging: at most max_rate per hour
	m.charge = 0.0
	mini.max_rate = 2.0
	var gen := _dev("generator", Vector2i(5, 3))
	gen.stock = 100.0
	g.cables[g.idx(Vector2i(5, 3))] = 1
	P.step(60.0)
	_check("Charging limited to 2 kW: %.2f kWh in 1 h" % m.charge, absf(m.charge - 2.0) < 0.01)
	mini.max_rate = old_rate

	# 5) Power switch + backup power: Mini XS behind a switch that is off
	_clear()
	cable_line(g, Vector2i(3, 3), Vector2i(4, 3))   # Notstrom-Seite
	cable_line(g, Vector2i(6, 3), Vector2i(8, 3))   # Hauptnetz
	var reserve := _dev("battery_mini", Vector2i(3, 3), 5.0)
	var sw := _dev("power_switch", Vector2i(5, 3))  # without a cable underneath
	sw.switch_on = false
	var main_bat := _dev("battery", Vector2i(6, 3), 0.0)
	var load := _dev("o2gen", Vector2i(7, 3))
	P.step(1.0)
	_check("Switch off: separate networks", reserve.net != load.net and reserve.net >= 0 and load.net >= 0)
	_check("Switch off: main battery empty → failure, reserve untouched", not load.powered and reserve.charge == 5.0)
	# Right-click menu: switch on
	ui.open_object_menu(Vector2i(5, 3))
	var k := -1
	for idx in ui.object_menu.item_count:
		if ui.object_menu.get_item_text(idx) == "Turn power switch on":
			k = ui.object_menu.get_item_id(idx)
	_check("Right-click menu: “Turn power switch on”", k >= 0)
	ui._on_object_menu(k)
	ui.object_menu.hide()
	P.step(1.0)
	_check("Switch on: one network, consumer supplied", sw.switch_on and reserve.net == load.net and load.powered)
	P.step(60.0)
	_check("Backup power: Mini XS lasts about %.1f h for 1.5 kW (rest %.2f kWh)" % [5.0 / 1.5, reserve.charge], absf(reserve.charge - (5.0 - 1.5 * 61.0 / 60.0)) < 0.01)
	ui.open_object_menu(Vector2i(5, 3))
	var labels := []
	for idx in ui.object_menu.item_count:
		labels.append(ui.object_menu.get_item_text(idx))
	ui.object_menu.hide()
	_check("Afterwards the menu offers “Turn power switch off”", labels.has("Turn power switch off"))
	# A switch that is off also splits when a cable lies underneath
	sw.switch_on = false
	g.cables[g.idx(Vector2i(5, 3))] = 1
	P._dirty = true
	P.step(0.01)
	_check("Switch off also splits with a cable underneath", reserve.net != load.net)

	# 6) Saving: the switch position is kept
	var copy := Device.from_data(sw.to_data())
	_check("Saving/loading: a switch that is off stays off", copy.type == "power_switch" and copy.switch_on == false)
	var plain := Device.from_data(bat.to_data())
	_check("Old save without the field: the switch counts as on", plain.switch_on)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
