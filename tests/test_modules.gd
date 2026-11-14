## Tests: module bay in the navigation console, Autodock Module
##   godot --headless --path . --script res://tests/boot.gd -- test_modules
extends "res://tests/test_base.gd"

const OLD_SAVE := "res://tests/fixtures/old_save_coarse.json"

var ok_count := 0
var fail_count := 0
var gs
var ui
var ship
var P
var save
var st
var helm_a
var helm_b
var mira
var toasts: Array[String] = []

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _secs(s: float) -> void:
	for k in int(s):
		gs.step(1.0 / 60.0)

func _beside(p: Vector2i) -> Vector2:
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		if ship.grid.walkable(p + d):
			return Vector2(p + d) + Vector2(0.5, 0.5)
	return Vector2(p) + Vector2(0.5, 0.5)

func _power() -> void:
	root.get_node("EventBus").ship_changed.emit()
	root.get_node("ShipPowerSystem").step(0.0)

## All Autodock Modules in the game (consoles, packs, floor, crates)
func _modules_total() -> int:
	var n := 0
	for c in root.get_node("CrewSystem").crew:
		n += c.inv.count("mod_autodock")
	for i in ship.grid.piles:
		n += ship.grid.piles[i].count("mod_autodock")
	for d in ship.grid.devices.values():
		if d.inv != null:
			n += d.inv.count("mod_autodock")
	return n

## Open the module bay of console h with E (the character stands next to it)
func _open_helm(h) -> bool:
	mira.pos = _beside(h.pos)
	mira.path.clear()
	ui.interact()
	return ui.open_pos == h.pos

## Ship free, calm and close in front of Tycho (Auto-Dock range)
func _near_tycho() -> void:
	var t0: Dictionary = P.loc_state(P.loc("tycho"), P.secs())
	P.pos = t0.pos + Vector2(0.5, 0.2)
	P.vel = t0.vel
	P.ang_vel = 0.0
	P.stop_inputs()

func _autodock_button():
	ui._last_nav = ""
	ui._refresh_nav()
	for row in ui.nav_side.get_children():
		if row.is_queued_for_deletion():
			continue
		if row is Button and row.text.begins_with("Auto-Dock"):
			return row
	return null

func _fresh() -> void:
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.char_ui.creation.visible = false
	mira = root.get_node("CrewSystem").player()
	mira.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	mira.auto_mode = false
	_secs(3)
	helm_a = P.ship_devices("helm")[0]

func _initialize() -> void:
	await process_frame
	await process_frame
	save = root.get_node("SaveSystem")
	save.slot = 924
	gs = root.get_node("GameState")
	ui = root.get_node("UIManager")
	ship = root.get_node("ShipSystem")
	P = root.get_node("PhysicsSystem")
	st = root.get_node("StationSystem")
	root.get_node("Settings").meteors = false
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(String(t)))
	Config.ENABLE_STATION = true
	_fresh()
	var g = ship.grid

	# ---------------- 0) Modulfach ----------------
	_check("The navigation console has a module bay with the Autodock Module in it", helm_a.inv != null and helm_a.inv.only_modules and helm_a.inv.count("mod_autodock") == 1)
	_check("No stand-alone auto-dock device any more, not buildable", P.ship_devices("autodock").is_empty() and not root.get_node("ItemSystem").device("autodock").buildable)
	var m0: float = P.mass()
	_check("E at the console opens the module bay", _open_helm(helm_a))
	var cond0: float = helm_a.inv.items[0].cond
	ui._transfer(true, "mod_autodock", 1)
	_check("Taking the module out: complete in the pack, same condition", helm_a.inv.count("mod_autodock") == 0 and mira.inv.count("mod_autodock") == 1 and mira.inv.items.filter(func(it): return it.type == "mod_autodock")[0].cond == cond0)
	_check("… weight 3 kg, ship mass unchanged (counts once)", root.get_node("ItemSystem").item("mod_autodock").weight == 3.0 and absf(P.mass() - m0) < 0.000001)
	mira.inv.add("plate", 1, 90.0)
	toasts.clear()
	ui._transfer(false, "plate", 1)
	_check("The module bay takes no other items (%s)" % (toasts[-1] if not toasts.is_empty() else ""), helm_a.inv.count("plate") == 0 and mira.inv.count("plate") == 1)
	mira.inv.take("plate", 1)

	# ---------------- 1) Without a module: dock manually, Autodock locked; with a module: Autodock ----------------
	mira.pos = _beside(helm_a.pos)
	ui.request_flight(helm_a)
	_check("1: In the cockpit at console A", ui.nav_open and P.helm_at == helm_a.pos)
	P.request_undock()
	_secs(20)
	_near_tycho()
	P.pos = P.loc_state(P.loc("tycho"), P.secs()).pos + Vector2(0.05, 0)
	P.angle = P.dock_alignment("tycho").angle
	_check("1: Docked manually without a module (%s)" % P.dock_block_reason("tycho"), P.dock("tycho") and P.docked == "tycho")
	P.request_undock()
	_secs(20)
	_near_tycho()
	var why: String = P.autodock_block_reason()
	_check("1: Auto-Dock locked, with a reason (%s)" % why, why.begins_with("No Autodock Module in this navigation console"))
	var btn = _autodock_button()
	_check("1: Cockpit button Auto-Dock locked", btn != null and btn.disabled)
	toasts.clear()
	P.start_autodock()
	_check("1: Start refused, the message names the reason", P.autodock.is_empty() and not toasts.is_empty() and "Autodock Module" in toasts[-1])
	ui._drop_own("mod_autodock", 1)
	_check("1: A module on the floor unlocks nothing", mira.inv.count("mod_autodock") == 0 and P.autodock_block_reason() != "")
	ui.interact()
	var pile_pos: Vector2i = ui.open_pos
	ui._transfer(true, "mod_autodock", 1)
	_check("1: Module picked up again; in the pack it unlocks nothing", mira.inv.count("mod_autodock") == 1 and P.autodock_block_reason() != "" and pile_pos != helm_a.pos)
	_open_helm(helm_a)
	ui._transfer(false, "mod_autodock", 1)
	_check("1: Module put into the operated console → Auto-Dock unlocked", helm_a.inv.count("mod_autodock") == 1 and P.autodock_block_reason() == "")
	btn = _autodock_button()
	_check("1: Cockpit button now active", btn != null and not btn.disabled)
	btn.pressed.emit()
	_check("1: Auto-Dock started from the cockpit", not P.autodock.is_empty())
	for k in 60 * 15:
		gs.step(1.0 / 60.0)
		if P.docked != "":
			break
	var hp: Vector2i = g.pos(st.hatch) if st.hatch >= 0 else Vector2i(-1, -1)
	var pdir := Vector2i(-1, 0)   # airlock on the left: the outer door faces left
	_check("1: Docked at the outer door of the airlock, station door to door", P.docked == "tycho" and root.get_node("AirlockSystem").is_lock_door(st.hatch)
		and g.linked.has(st.hatch) and g.get_tile(hp + pdir) == ShipGrid.Tile.DOOR and g.zone[g.idx(hp + pdir)] == 3)

	# ---------------- 2) Two consoles: only A has the module ----------------
	P.request_undock()
	_secs(20)
	_near_tycho()
	var far_pos := Vector2i(-1, -1)
	var best := 0.0
	for i in g.tiles.size():
		var p: Vector2i = g.pos(i)
		if g.zone[i] == 0 and g.tiles[i] == ShipGrid.Tile.FLOOR and g.cables[i] == 1 and not g.occupied(p) and not g.piles.has(i):
			var d := Vector2(p).distance_to(Vector2(helm_a.pos))
			if d > best:
				best = d
				far_pos = p
	helm_b = g.place_device("helm", far_pos)
	_power()
	_check("2: Console B built, powered, empty module bay", helm_b.powered and helm_b.inv != null and helm_b.inv.items.is_empty())
	P.helm_at = helm_a.pos
	_check("2: Available at A", P.autodock_block_reason() == "")
	P.helm_at = helm_b.pos
	_check("2: Locked at B (%s)" % P.autodock_block_reason(), P.autodock_block_reason().begins_with("No Autodock Module"))
	P.helm_at = helm_a.pos
	_open_helm(helm_a)
	ui._transfer(true, "mod_autodock", 1)
	_check("2: A locked after taking it out", P.autodock_block_reason().begins_with("No Autodock Module"))
	ui._transfer(false, "mod_autodock", 1)
	helm_a.inv.add("mod_autodock", 1, 60.0)
	_check("2: Two modules in A: one function, unlocked", helm_a.inv.count("mod_autodock") == 2 and P.autodock_block_reason() == "")
	helm_a.inv.take("mod_autodock", 1)
	g.cables[g.idx(helm_a.pos)] = 0
	_power()
	_check("2: A locked without power (%s), B has power" % P.autodock_block_reason(), "power" in P.autodock_block_reason() and helm_b.powered)
	g.cables[g.idx(helm_a.pos)] = 1
	_power()
	helm_a.inv.items[0].cond = 0.0
	_check("2: Kaputtes Modul schaltet nichts frei (%s)" % P.autodock_block_reason(), "broken" in P.autodock_block_reason())
	helm_a.inv.items[0].cond = 73.0

	# ---------------- 3) Power failure during the manoeuvre ----------------
	P.helm_at = helm_a.pos
	_near_tycho()
	P.start_autodock()
	_check("3: Auto-Dock running", not P.autodock.is_empty())
	_secs(30)
	toasts.clear()
	g.cables[g.idx(helm_a.pos)] = 0
	_power()
	gs.step(1.0 / 60.0)
	var p_cut: Vector2 = P.pos
	_check("3: Aborted (%s), not docked, no coupling" % (toasts[-1] if not toasts.is_empty() else ""), P.autodock.is_empty() and P.docked == "" and not st.active() and g.linked.is_empty()
		and toasts.any(func(t): return t.begins_with("Auto-Dock aborted")))
	_secs(30)
	_check("3: Valid flight state, the ship keeps drifting free", P.pos.is_finite() and P.vel.is_finite() and P.docked == "" and P.autodock.is_empty() and P.pos != p_cut)
	g.cables[g.idx(helm_a.pos)] = 1
	_power()
	# take the module out during the manoeuvre
	_near_tycho()
	P.start_autodock()
	_secs(10)
	helm_a.inv.move_to(mira.inv, "mod_autodock", 1)
	gs.step(1.0 / 60.0)
	_check("3: Module taken out during the manoeuvre → abort", P.autodock.is_empty() and P.docked == "" and not st.active())
	mira.inv.move_to(helm_a.inv, "mod_autodock", 1)
	ui.leave_flight()

	# ---------------- 4) Saving and loading ----------------
	var a_pos: Vector2i = helm_a.pos
	var b_pos: Vector2i = helm_b.pos
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	g = ship.grid
	var a2 = g.device_at(a_pos)
	var b2 = g.device_at(b_pos)
	_check("4: After loading exactly one module in the right console, condition 73 %", a2 != null and a2.inv.count("mod_autodock") == 1 and int(a2.inv.items[0].cond) == 73
		and b2 != null and b2.inv.count("mod_autodock") == 0 and _modules_total() == 1)
	P.helm_at = a_pos
	_check("4: … and it unlocks Auto-Dock there (console A), not at B", P.module_block_reason(a2, "autodock") == "" and P.module_block_reason(b2, "autodock") != "")
	# Old save with a stand-alone auto-dock device
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(OLD_SAVE))
	f.close()
	gs.new_game()
	save.load_game(true)
	g = ship.grid
	var helms: Array = P.ship_devices("helm")
	_check("4: Old save: the auto-dock device becomes a module in the console (%s)" % str(g.migrated), P.ship_devices("autodock").is_empty() and helms.size() == 1
		and helms[0].inv.count("mod_autodock") == 1 and int(helms[0].inv.items[0].cond) == 100 and _modules_total() == 1 and g.migrated.modules == 1)
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	_check("4: Loaded again: still exactly one module, no second conversion", _modules_total() == 1 and ship.grid.migrated.modules == 0)
	# Old save (fine grid) with two auto-dock devices and an uninstalled auto-dock in the pack
	_fresh()
	g = ship.grid
	helm_a.inv.items.clear()
	save.save_game(true)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save.path()))
	var bed: Dictionary = {}
	for dd in data.ship.devices:
		if dd.type == "bed":
			bed = dd
	for k in 2:
		var ad: Dictionary = bed.duplicate(true)
		ad.type = "autodock"
		ad.cond = 80.0 - k * 30.0
		ad.x = int(bed.x) + 2 + k * 2
		data.ship.devices.append(ad)
	data.crew[0].items.append({"type": "pk_autodock", "qty": 1, "cond": 55.0, "data": {}})
	f = FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	gs.new_game()
	save.load_game(true)
	g = ship.grid
	helm_a = P.ship_devices("helm")[0]
	var floor_mods := 0
	for i in g.piles:
		floor_mods += g.piles[i].count("mod_autodock")
	mira = root.get_node("CrewSystem").player()
	_check("4: Two old devices: one into the console, one as an item, no duplicate module in the console", helm_a.inv.count("mod_autodock") == 1 and floor_mods == 1 and g.migrated.modules == 2)
	_check("4: The uninstalled auto-dock in the pack becomes a module (55 %)", mira.inv.count("pk_autodock") == 0 and mira.inv.count("mod_autodock") == 1
		and int(mira.inv.items.filter(func(it): return it.type == "mod_autodock")[0].cond) == 55)
	Config.ENABLE_STATION = false

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
