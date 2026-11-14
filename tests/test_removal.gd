## Tests for the right-click menu: uninstall, dismantle, destroy, install
##   godot --headless --path . --script res://tests/boot.gd -- test_removal
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0
var toasts: Array[String] = []
var gs
var ship
var crew
var CS
var R
var ui

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FEHLER  " + name)

func _run(seconds: float) -> void:
	for i in int(seconds):
		gs.step(1.0 / 60.0)

## Run until there is no job on tile p any more (at most max_min game minutes)
func _until_done(p: Vector2i, max_min: float = 20.0) -> bool:
	var g = ship.grid
	for k in int(max_min * 60.0):
		gs.step(1.0 / 60.0)
		if not CS.jobs.has(g.idx(p)):
			return true
	return false

## Total amount of one kind: packs, piles, containers
func _count(type: String) -> int:
	var n := 0
	for c in crew.crew:
		n += c.inv.count(type)
	for i in ship.grid.piles:
		n += ship.grid.piles[i].count(type)
	for d in ship.grid.devices.values():
		if d.inv != null:
			n += d.inv.count(type)
	return n

## Uninstalled item of this kind – no matter whether on the floor, in a pack or in a container
func _find_packed(type: String) -> Dictionary:
	var invs: Array = []
	for c in crew.crew:
		invs.append(c.inv)
	for i in ship.grid.piles:
		invs.append(ship.grid.piles[i])
	for d in ship.grid.devices.values():
		if d.inv != null:
			invs.append(d.inv)
	for inv in invs:
		for it in inv.items:
			if it.type == type:
				return it
	return {}

## Like _count, but also in the kept contents of uninstalled devices
func _count_deep(type: String) -> int:
	var n := _count(type)
	var invs: Array = []
	for c in crew.crew:
		invs.append(c.inv)
	for i in ship.grid.piles:
		invs.append(ship.grid.piles[i])
	for inv in invs:
		for it in inv.items:
			var d = it.get("data")
			if d is Dictionary and d.get("items") is Array:
				for sub in d.items:
					if sub.type == type:
						n += int(sub.qty)
	return n

## Pick a menu entry for an action (like a click in the right-click menu)
## It picks the layer "device, otherwise tile" (right-click cycles cable → device → floor)
func _menu(p: Vector2i, kind: String) -> int:
	ui.clear_selection()
	var want: String = R.key_at(p)
	var opened := false
	for k in 3:
		opened = ui.open_object_menu(p)
		if not opened or ui.sel_key == want or want == "":
			break
	if not opened:
		return -1
	for k in ui.menu_actions.size():
		if ui.menu_actions[k].kind == kind:
			return k
	return -1

func _menu_text(p: Vector2i, kind: String) -> String:
	var id := _menu(p, kind)
	if id < 0:
		return ""
	var idx: int = ui.object_menu.get_item_index(id)
	return ("[off] " if ui.object_menu.is_item_disabled(idx) else "") + ui.object_menu.get_item_text(idx)

func _click(p: Vector2i, kind: String) -> void:
	var id := _menu(p, kind)
	ui._on_object_menu(id)
	ui.object_menu.hide()

func _fresh() -> void:
	gs.new_game()
	root.get_node("SalvageSystem").clear()
	root.get_node("TimeSystem").set_speed(0)
	var m = crew.player()
	m.pos = Vector2(ship.spawn_point()) + Vector2(0.5, 0.5)
	m.needs = {"food": 100.0, "water": 100.0, "sleep": 100.0, "hygiene": 100.0, "air": 100.0}
	m.stress = 0.0
	_run(2)

func _initialize() -> void:
	await process_frame
	await process_frame
	# Own save slot: tests do not overwrite real saves and can run in parallel
	root.get_node("SaveSystem").slot = 906
	# These tests also check the (temporarily disabled) station and the wreck
	Config.ENABLE_STATION = true
	Config.ENABLE_WRECK = true
	gs = root.get_node("GameState")
	ship = root.get_node("ShipSystem")
	crew = root.get_node("CrewSystem")
	CS = root.get_node("ShipConstructionSystem")
	R = root.get_node("RemovalSystem")
	ui = root.get_node("UIManager")
	var save = root.get_node("SaveSystem")
	var power = root.get_node("ShipPowerSystem")
	root.get_node("Settings").meteors = false
	root.get_node("EventBus").toast.connect(func(t, _k): toasts.append(String(t)))
	_fresh()
	var x0: int = (ship.grid.width / Config.GRID_SCALE - 16) / 2
	var y0: int = (ship.grid.height / Config.GRID_SCALE - 10) / 2
	var mira = crew.player()
	var g = ship.grid

	# Konfiguration
	_check("Uninstalled items created", R.is_packed("pk_generator") and root.get_node("ItemSystem").item("pk_generator") != null and root.get_node("ItemSystem").item("pk_tile_wall") != null)
	var gy: Dictionary = R.dismantle_yield("dev:generator")
	_check("Dismantle recipe from removal.json (generator %s)" % str(gy), int(gy.plate) == 2 and int(gy.motor) == 1 and int(gy.circuit) == 1 and gy == R.data.generator.dismantle)

	# 1) Uninstall a block and install it again (inner wall between cabin and cockpit)
	var wall := C(x0 + 10, y0 + 2)
	_check("Menu shows Uninstall (%s)" % _menu_text(wall, "uninstall"), _menu_text(wall, "uninstall").begins_with("Uninstall  ("))
	_click(wall, "uninstall")
	_check("Uninstall job created", CS.jobs.has(g.idx(wall)) and CS.jobs[g.idx(wall)].kind == "uninstall")
	_check("Abbau fertig", _until_done(wall))
	_check("Wall is gone, floor stays", g.get_tile(wall) == ShipGrid.Tile.FLOOR)
	var wall_pile := -1
	for i in g.piles:
		if g.piles[i].count("pk_tile_wall") > 0:
			wall_pile = i
	_check("Wall as one complete item on the floor (not in the pack)", _count("pk_tile_wall") == 1 and wall_pile >= 0 and mira.inv.count("pk_tile_wall") == 0 and g.walkable(g.pos(wall_pile)))
	_check("Walking path through the former wall", not ship.find_path(wall + Vector2i(-1, 0), wall + Vector2i(1, 0)).is_empty())
	_check("Menu offers Install", _menu(wall + Vector2i(0, 0), "install") >= 0)
	ui.object_menu.hide()
	_click(wall, "install")
	_check("Einbau fertig", _until_done(wall))
	_check("Wall back (100 %%), item used up", g.get_tile(wall) == ShipGrid.Tile.WALL and g.cond[g.idx(wall)] == 100.0 and _count("pk_tile_wall") == 0)

	# 2) Uninstall damaged and install with the same condition (wall and battery)
	var wall2 := C(x0 + 10, y0 + 7)
	g.cond[g.idx(wall2)] = 63.0
	_click(wall2, "uninstall")
	_until_done(wall2)
	var st: Dictionary = _find_packed("pk_tile_wall")
	_check("Damaged wall keeps its condition as an item (%d %%)" % int(st.get("cond", -1)), int(st.get("cond", -1)) == 63)
	_click(wall2, "install")
	_until_done(wall2)
	_check("Installed again with 63 %%", g.get_tile(wall2) == ShipGrid.Tile.WALL and int(g.cond[g.idx(wall2)]) == 63)
	var bat_p := C(x0 + 2, y0 + 5)
	var bat = g.device_at(bat_p)
	bat.cond = 71.0
	bat.charge = 12.5
	power.step(0.0)
	var cap_before: float = power.main_net().capacity if power.main_net().has("capacity") else -1.0
	_click(bat_p, "uninstall")
	_until_done(bat_p)
	power.step(0.0)
	_check("Battery removed: no longer in the power network", g.device_at(bat_p) == null and PhysicsSystem_ok(root))
	var pk: Dictionary = _find_packed("pk_battery")
	var packed_charge: float = float(pk.get("data", {}).get("charge", -1))
	_check("Uninstalled battery keeps charge and condition (%.2f kWh, %d %%)" % [packed_charge, int(pk.get("cond", -1))], absf(packed_charge - 12.5) < 1.0 and int(pk.cond) == 71)
	_run(30)
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	mira = crew.player()
	g = ship.grid
	var pk2: Dictionary = _find_packed("pk_battery")
	_check("After saving/loading: data kept in the item", absf(float(pk2.get("data", {}).get("charge", -1)) - packed_charge) < 0.000001)
	_click(bat_p, "install")
	_until_done(bat_p)
	var bat2 = g.device_at(bat_p)
	_check("Battery installed again with 71 %% and the same charge", bat2 != null and bat2.type == "battery" and int(bat2.cond) == 71 and absf(bat2.charge - packed_charge) < 0.5)

	# 3) Dismantle: exactly the configured materials
	_fresh()
	g = ship.grid
	mira = crew.player()
	var bed_p := C(x0 + 1, y0 + 1)
	var yield_bed: Dictionary = R.dismantle_yield("dev:bed")
	var before := {}
	for t in yield_bed:
		before[t] = _count(t)
	_click(bed_p, "dismantle")
	_check("Zerlegen fertig", _until_done(bed_p))
	var exact := g.device_at(bed_p) == null
	for t in yield_bed:
		if _count(t) - before[t] != int(yield_bed[t]):
			exact = false
	_check("Bed dismantled: exactly %s" % str(yield_bed), exact)

	# 4) Destroy: several hits, scrap per the data, visible hits
	var bench_p := C(x0 + 13, y0 + 5)
	var scrap_before := _count("scrap")
	var fx_before: int = root.get_node("DamageSystem").effects.size()
	_click(bench_p, "destroy")
	var hits_seen := 0
	var conds: Array = []
	for k in 60 * 20:
		gs.step(1.0 / 60.0)
		var j = CS.jobs.get(g.idx(bench_p))
		if j == null:
			break
		if int(j.get("hits", 0)) > hits_seen:
			hits_seen = int(j.hits)
			conds.append(int(g.device_at(bench_p).cond))
	_check("Several hits (%d), condition drops %s" % [hits_seen, str(conds.slice(0, 4))], hits_seen >= 3 and conds[0] > conds[-1])
	_check("Workbench destroyed", g.device_at(bench_p) == null)
	_check("Scrap per the data (%s)" % str(R.debris("dev:workbench")), _count("scrap") - scrap_before == int(R.debris("dev:workbench").scrap))
	_check("Treffer sichtbar (Funken)", root.get_node("DamageSystem").effects.any(func(e): return e.get("small", false)) or root.get_node("DamageSystem").effects.size() >= fx_before)

	# 5) Cancel and restart (all three)
	_fresh()
	g = ship.grid
	mira = crew.player()
	var sink_p := C(x0 + 3, y0 + 1)
	for kind in ["uninstall", "dismantle"]:
		_click(sink_p, kind)
		for k in 60 * 3:
			gs.step(1.0 / 60.0)
		var prog: float = CS.jobs[g.idx(sink_p)].progress if CS.jobs.has(g.idx(sink_p)) else -1.0
		_click(sink_p, "cancel")
		_check("%s cancelled (progress was %.2f): sink stays, no result" % [kind, prog], g.device_at(sink_p) != null and not CS.jobs.has(g.idx(sink_p)) and _count("pk_sink") == 0)
	_click(sink_p, "destroy")
	for k in 60 * 15:
		gs.step(1.0 / 60.0)
		var j = CS.jobs.get(g.idx(sink_p))
		if j != null and int(j.get("hits", 0)) >= 2:
			break
	var dmg_cond: float = g.device_at(sink_p).cond
	_click(sink_p, "cancel")
	_run(5)
	_check("Destroy cancelled: damage stays (%d %%)" % int(dmg_cond), g.device_at(sink_p) != null and g.device_at(sink_p).cond == dmg_cond and dmg_cond < 100.0)
	_click(sink_p, "destroy")
	_check("Neustart setzt beim Schaden fort (Fortschritt %.2f)" % CS.jobs[g.idx(sink_p)].progress, absf(CS.jobs[g.idx(sink_p)].progress - (1.0 - dmg_cond / 100.0)) < 0.001)
	_check("Restarted destroy finishes", _until_done(sink_p))
	_click(C(x0 + 5, y0 + 1), "uninstall")
	_check("Uninstall restarted after cancelling and finished", _until_done(C(x0 + 5, y0 + 1)) and _count("pk_food") == 1)

	# 6) Full pack: the result ends up as a pile next to it
	_fresh()
	g = ship.grid
	mira = crew.player()
	while mira.inv.add("plate", 1, 90.0) > 0:
		pass
	var o2_p := C(x0 + 9, y0 + 1)
	var y_o2: Dictionary = R.dismantle_yield("dev:o2gen")
	var b2 := {}
	for t in y_o2:
		b2[t] = _count(t)
	toasts.clear()
	_click(o2_p, "dismantle")
	_until_done(o2_p)
	var ok_full := true
	for t in y_o2:
		if _count(t) - b2[t] != int(y_o2[t]):
			ok_full = false
	_check("Full pack: amount still exact", ok_full)
	_check("… the rest lies as a pile, with a message", toasts.any(func(t): return "cannot carry everything" in t))

	# 7) Out of reach / without a tool
	_fresh()
	g = ship.grid
	mira = crew.player()
	var far := Vector2i(2, 2)
	g.set_tile(far, ShipGrid.Tile.WALL)
	_check("Unreachable: reason in the menu (%s)" % _menu_text(far, "destroy"), "Nobody can reach" in _menu_text(far, "destroy") and _menu_text(far, "destroy").begins_with("[off]"))
	ui.object_menu.hide()
	mira.inv.take("crowbar", 9)
	var wall3 := C(x0 + 10, y0 + 2)
	_check("Without a crowbar: uninstalling a wall is locked (%s)" % R.reason("uninstall", wall3), "Needs tool: Crowbar" in R.reason("uninstall", wall3))
	_check("… destroying works with bare hands", R.reason("destroy", wall3) == "")
	var st_desk: Vector2i = root.get_node("StationSystem").rooms[0].desk
	_check("Station counter: locked (%s)" % R.reason("destroy", st_desk), R.reason("destroy", st_desk) == "Belongs to the station.")
	mira.inv.add("crowbar", 1, 80.0)

	# 8) Click the same entry several times quickly
	var heater_p := C(x0 + 8, y0 + 1)
	var id := _menu(heater_p, "dismantle")
	ui._on_object_menu(id)
	ui._on_object_menu(id)
	ui._on_object_menu(id)
	_check("Second job is refused (%s)" % R.order("dismantle", heater_p), R.order("dismantle", heater_p).begins_with("Already in progress here"))
	var plate_b := _count("plate")
	_until_done(heater_p)
	_run(5)
	_check("Result exactly once (+%d plates)" % (_count("plate") - plate_b), _count("plate") - plate_b == int(R.dismantle_yield("dev:heater").get("plate", 0)))

	# 9) Object with contents and connections
	_fresh()
	g = ship.grid
	mira = crew.player()
	var crate_p := C(x0 + 13, y0 + 8)
	var rations := _count("ration")
	_click(crate_p, "uninstall")
	_until_done(crate_p)
	var pkc: Dictionary = _find_packed("pk_crate")
	_check("Crate uninstalled: one item on the floor, contents kept inside, nothing lost", g.device_at(crate_p) == null and _count_deep("ration") == rations and _count("ration") == 0
		and g.piles.has(g.idx(crate_p)) and g.piles[g.idx(crate_p)].count("pk_crate") == 1 and not pkc.get("data", {}).get("items", []).is_empty())
	var locker_p := C(x0 + 1, y0 + 8)
	_check("Locker with a suit: dismantling locked (%s)" % R.reason("dismantle", locker_p), "space suit" in R.reason("dismantle", locker_p))
	_click(locker_p, "uninstall")
	_until_done(locker_p)
	var lk: Dictionary = _find_packed("pk_locker")
	_check("Uninstalled locker keeps the suit", lk.get("data", {}).get("suit") != null)
	var gen_p := C(x0 + 1, y0 + 5)
	power.step(0.0)
	var prod_before: float = power.main_net().production
	_click(gen_p, "uninstall")
	_until_done(gen_p)
	power.step(0.0)
	_check("Generator gone: power network recomputed (%.1f → %.1f kW), cable stays" % [prod_before, power.main_net().production], power.main_net().production < prod_before and g.cables[g.idx(gen_p)] == 1)
	g.devices[g.idx(C(x0 + 13, y0 + 1))].lock_level = 0
	var crate2: Vector2i = C(x0 + 14, y0 + 8)
	g.device_at(crate2).lock_level = 2
	_check("Locked crate: locked", R.reason("destroy", crate2) == "Locked – crack it first (hacking).")
	g.device_at(crate2).lock_level = 0
	# Object disappears during the job
	var sink2 := C(x0 + 3, y0 + 1)
	_click(sink2, "dismantle")
	g.devices.erase(g.idx(sink2))
	var pipes := _count("pipe")
	_run(120)
	_check("Object removed beforehand: job ends without a result", not CS.jobs.has(g.idx(sink2)) and _count("pipe") == pipes)

	# 10) Time speeds (real time passing) and saving/loading in the middle of destroying
	var results := []
	for si in range(1, 6):
		_fresh()
		g = ship.grid
		var time = root.get_node("TimeSystem")
		var p := C(x0 + 13, y0 + 5)
		_click(p, "destroy")
		var fx0: int = root.get_node("DamageSystem").effects.filter(func(e): return e.get("small", false) and e.pos == p).size()
		time.set_speed(si)
		var t0: float = gs.time
		var first_hit := -1.0
		var hits := 0
		var frames := 0
		while CS.jobs.has(g.idx(p)) and frames < 20000:
			time._process(1.0 / 60.0)
			frames += 1
			var j = CS.jobs.get(g.idx(p))
			if j != null and int(j.get("hits", 0)) > hits:
				if first_hit < 0.0:
					first_hit = gs.time
				hits = int(j.hits)
		var dur: float = (gs.time - first_hit) * 60.0
		# count hits through the hit sparks (several hits can fall into one frame)
		hits = root.get_node("DamageSystem").effects.filter(func(e): return e.get("small", false) and e.pos == p).size() - fx0 - 1
		results.append([si, hits + 1, dur, Config.SPEEDS[si] / 60.0])
		time.set_speed(0)
		_check("Speed %d: destroyed after %d hits in %.0f game seconds (%d frames)" % [si, hits + 1, dur, frames], g.device_at(p) == null)
	var h1: int = results[0][1]
	_check("Same number of hits at all speeds (%s)" % str(results.map(func(r): return r[1])), results.all(func(r): return absi(r[1] - h1) <= 1))
	# Measuring precision: one frame = SPEEDS/60 game seconds (about 0.3 s at ×16)
	_check("Hit interval matches the game time (duration ≈ hits × 1.5 s, ± one frame)", results.all(func(r): return absf(r[2] - (r[1] - 1) * 1.5) <= 3.0 + r[3]))
	_fresh()
	g = ship.grid
	var tp := C(x0 + 13, y0 + 5)
	_click(tp, "destroy")
	for k in 60 * 20:
		gs.step(1.0 / 60.0)
		var j = CS.jobs.get(g.idx(tp))
		if j != null and int(j.get("hits", 0)) >= 3:
			break
	var c_mid: float = g.device_at(tp).cond
	save.save_game(true)
	gs.new_game()
	save.load_game(true)
	g = ship.grid
	var dl = g.device_at(tp)
	var jl = CS.jobs.get(g.idx(tp))
	_check("After loading: damage and job kept (%d %% → %s, job %s)" % [int(c_mid), str(dl.cond if dl != null else -1), str(jl.kind if jl != null else "-")], g.device_at(tp) != null and absf(g.device_at(tp).cond - c_mid) < 0.000001 and CS.jobs.has(g.idx(tp)) and CS.jobs[g.idx(tp)].kind == "destroy")
	_check("Destroyed completely after loading", _until_done(tp) and g.device_at(tp) == null)

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()

func PhysicsSystem_ok(r) -> bool:
	return r.get_node("ShipPowerSystem").main_net().has("production")
