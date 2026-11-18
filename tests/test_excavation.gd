## Tests: skill "Excavation" (ID excavation) – course 3 years, mining +4, no other bonuses, old save
##   godot --headless --path . --script res://tests/boot.gd -- test_excavation
extends "res://tests/test_base.gd"

const OLD_SAVE := "res://tests/fixtures/old_save_blueports.json"

var ok_count := 0
var fail_count := 0
var gs
var ui
var SK
var CHS
var CS
var save
var ship
var salv

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FAIL    " + name)

func _texts(n: Node) -> String:
	var out := ""
	for ch in n.get_children():
		if ch.is_queued_for_deletion():
			continue
		if ch is Label:
			out += ch.text + "\n"
		out += _texts(ch)
	return out

func _course_row(id: String) -> Node:
	for ch in ui.char_ui.creation_box.get_children():
		if not ch.is_queued_for_deletion() and ch.get_meta("course", "") == id:
			return ch
	return null

func _press_course(id: String, text: String) -> bool:
	var row := _course_row(id)
	if row == null:
		return false
	for ch in row.get_children():
		if ch is Button and ch.text == text:
			ch.pressed.emit()
			await process_frame
			return true
	return false

func _fresh(p: float) -> CrewMember:
	var c := CrewMember.new(500 + randi() % 1000, "Test", Color.WHITE, Vector2i.ZERO)
	SK.set_progress(c, "excavation", p)
	return c

## Attach an asteroid to the free port (release the station first); return the first rock wall
func _asteroid_wall() -> Vector2i:
	Config.ENABLE_WRECK = true
	root.get_node("StationSystem").clear()
	if salv.wreck_name != "":
		salv.clear()
	if not salv.generate_asteroid():
		return Vector2i(-1, -1)
	var g = ship.grid
	for i in g.tiles.size():
		if g.tiles[i] == ShipGrid.Tile.WALL and g.zone[i] == 1:
			return g.pos(i)
	return Vector2i(-1, -1)

func _initialize() -> void:
	await process_frame
	await process_frame
	gs = root.get_node("GameState")
	ui = root.get_node("UIManager")
	SK = root.get_node("SkillSystem")
	CHS = root.get_node("CharacterSystem")
	CS = root.get_node("ShipConstructionSystem")
	save = root.get_node("SaveSystem")
	ship = root.get_node("ShipSystem")
	salv = root.get_node("SalvageSystem")
	save.slot = 929
	root.get_node("Settings").meteors = false
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	ui.close_help()
	var mira: CrewMember = root.get_node("CrewSystem").player()
	var s: SkillData = SK.skill("excavation")
	_check("Skill vorhanden, ID excavation, englischer Name", s != null and s.skill_name == "Excavation")
	_check("Definition: 3 years, only mining +4, no other effects", s.course_years == 3 and s.work_value_bonus == 4.0 and Array(s.work_categories) == ["mining"] and s.gameplay_effects.is_empty())
	_check("Erwerbswege erhalten (Praxis + Lehrbuch)", "deconstruct_structure" in s.training_actions and "study_excavation" in s.training_actions and ItemSystem.item("book_excavation_1") != null)

	# Character creation: ±3 years, applied once; tooltip
	var cui = ui.char_ui
	CHS.begin(mira)
	CHS.apply_career(mira, "school")
	cui.open_creation()
	await process_frame
	var base: int = mira.age
	var tip: String = _course_row("excavation").tooltip_text if _course_row("excavation") != null else ""
	_check("Tooltip: 3 years and mining +4 (%s)" % tip.replace("\n", " | "), "costs 3 years" in tip and "+4 work value" in tip and "Affected categories: Mining." in tip and "Learning progress" in tip and not "Demolition" in tip)
	_check("Choose: preview +3", await _press_course("excavation", "Add") and CHS.preview_age(mira) == base + 3 and mira.age == base and "(incl. Excavation course +3 years)" in _texts(cui.creation_box))
	_check("Remove: preview −3", await _press_course("excavation", "Remove") and CHS.preview_age(mira) == base)
	await _press_course("excavation", "Add")
	var hist0: int = mira.history.size()
	CHS.confirm(mira)
	CHS.confirm(mira)
	_check("Confirmed: age +3 exactly once, acquired", mira.age == base + 3 and mira.history.size() == hist0 + 1 and SK.acquired(mira, "excavation"))
	cui.creation.visible = false

	# 1) The same mining work without and with the acquired skill
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var rock := _asteroid_wall()
	_check("1: Asteroid docked, rock wall found (%s)" % salv.wreck_name, rock.x >= 0 and salv.is_asteroid())
	_check("1: Demolish job at the rock", CS.place("remove", rock))
	var job: Dictionary = CS.jobs.get(ship.grid.idx(rock), {})
	var a := _fresh(0.0)
	var b := _fresh(100.0)
	_check("1: The job counts as mining", SK.is_mining(job) and SK.job_categories(job) == ["mining"])
	_check("1: Demolishing rock: work value %.2f → %.2f, exactly +4" % [SK.work_value(a, job), SK.work_value(b, job)], is_equal_approx(SK.work_value(b, job) - SK.work_value(a, job), 4.0))
	var ujob := {"kind": "uninstall", "x": rock.x, "y": rock.y, "target": "tile:wall"}
	_check("1: Uninstalling rock (menu): exactly +4", is_equal_approx(SK.work_value(b, ujob) - SK.work_value(a, ujob), 4.0))
	_check("1: No bonus yet at 99.9 %", is_equal_approx(SK.work_value(_fresh(99.9), job), SK.work_value(a, job)))
	var own_wall := Vector2i(-1, -1)
	var g = ship.grid
	for i in g.tiles.size():
		if g.tiles[i] == ShipGrid.Tile.WALL and g.zone[i] == 0 and not g.devices.has(i):
			own_wall = g.pos(i)
			break
	var wjob := {"kind": "remove", "x": own_wall.x, "y": own_wall.y}
	_check("1: Demolishing your own ship wall is not mining (no bonus)", not SK.is_mining(wjob) and is_equal_approx(SK.work_value(b, wjob), SK.work_value(a, wjob)))
	_check("1: Bergbau trainiert Excavation (%s)" % str(SK.job_profile(job).actions), "deconstruct_structure" in SK.job_profile(job).actions)

	# 2) Electrical work: unchanged
	for ej in [{"kind": "device", "dev": "battery", "x": 0, "y": 0}, {"kind": "device", "dev": "heater", "x": 0, "y": 0}, {"kind": "cable", "x": 0, "y": 0}]:
		_check("2: Electrical work (%s): work value unchanged (%.2f / %.2f)" % [ej.get("dev", ej.kind), SK.work_value(a, ej), SK.work_value(b, ej)], is_equal_approx(SK.work_value(a, ej), SK.work_value(b, ej)))
	_check("2: No old demolition/yield effect any more", SK.effect(b, "work_demolish") == 0.0 and SK.effect(b, "demolish_yield") == 0.0)

	# 3) Existing save with Excavation acquired
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
	d.crew[0].skills["excavation"] = {"p": 100.0, "xp": 50.0, "hist": []}
	var f := FileAccess.open(save.path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	gs.new_game()
	_check("3: Old save loaded", save.load_game(true))
	mira = root.get_node("CrewSystem").player()
	_check("3: Excavation stays acquired, other skills kept", SK.acquired(mira, "excavation") and is_equal_approx(SK.progress(mira, "construction"), 33.0))
	var rock2 := _asteroid_wall()
	_check("3: Asteroid docked", rock2.x >= 0)
	var mjob := {"kind": "remove", "x": rock2.x, "y": rock2.y}
	_check("3: Mining bonus without acquiring it again (+%.0f)" % SK.work_value_bonus(mira, mjob), is_equal_approx(SK.work_value_bonus(mira, mjob), 4.0))
	_check("3: Demolish job on asteroid rock asks for the Gott Mining Tool", CS.place("remove", rock2) and String(CS.jobs[ship.grid.idx(rock2)].get("tool", "")) == "mining_tool")
	CS.cancel(CS.jobs[ship.grid.idx(rock2)])
	Config.ENABLE_WRECK = false

	# Asteroid Mining (Ostranauts wiki): minerals with wiki values, kiosk prices, reputation
	var IS = root.get_node("ItemSystem")
	_check("Minerals with wiki values: Regolith 35 (20 kg), Gangue 150 (3 kg), Platinum 15 000, Void Opal 112 000",
		IS.item("mineral_regolith").value == 35 and is_equal_approx(IS.item("mineral_regolith").weight, 20.0) and IS.item("mineral_gangue").value == 150
		and is_equal_approx(IS.item("mineral_gangue").weight, 3.0) and IS.item("mineral_platinum").value == 15000 and IS.item("mineral_void_opal").value == 112000)
	var kinds := {}
	for k in 400:
		var mr: Array = Mining.roll()
		kinds[mr[0]] = true
	_check("Mining yields mostly common minerals (%d kinds in 400 rolls)" % kinds.size(), kinds.has("mineral_regolith") and kinds.has("mineral_silicates") and kinds.size() >= 8)
	var R2 = root.get_node("RemovalSystem")
	_check("Rock: destroying leaves gangue", R2.debris("tile:rock").keys() == ["mineral_gangue"] and int(R2.debris("tile:rock").mineral_gangue) == 1)
	_check("Full price at the kiosks (L4, Kármán), 60 % elsewhere", Mining.price_factor("mineral_gold", "l4") == 1.0 and Mining.price_factor("mineral_gold", "karman") == 1.0
		and is_equal_approx(Mining.price_factor("mineral_gold", "tycho"), 0.6) and Mining.price_factor("plate", "tycho") == 1.0)
	var EE = root.get_node("EconomySystem")
	EE.credits = 100000
	var c_before: int = EE.credits
	EE.buy("mineral_gold", 1)
	_check("Minerals are not sold in the market (only mined)", EE.credits == c_before)
	_check("Reputation +1 per 12 000 Cr sold at a kiosk, none elsewhere", is_equal_approx(Mining.reputation_for("mineral_gold", "l4", 24000), 2.0) and Mining.reputation_for("mineral_gold", "tycho", 24000) == 0.0)

	# Gott Mining Tool (Ostranauts wiki): needed for mining, every use tires
	_check("Gott Mining Tool: 2 500 Cr, 8 kg, in the market", IS.item("mining_tool").value == 2500 and is_equal_approx(IS.item("mining_tool").weight, 8.0))
	_check("Mining rock (MINE/Dismantle) needs the mining tool, not the crowbar", R2.tool_for("dismantle", "tile:rock") == "mining_tool")
	var miner: CrewMember = root.get_node("CrewSystem").player()
	miner.inv.take("mining_tool", 99)
	var rjob := {"kind": "remove", "tool": "mining_tool"}
	_check("Without the tool: no mining job", not R2.worker_ok(miner, rjob))
	miner.inv.add("mining_tool", 1, 100.0)
	_check("With the tool in the pack: mining allowed", R2.worker_ok(miner, rjob))
	miner.needs.sleep = 50.0
	Mining.tire(miner)
	_check("Every use tires: energy 50 → %.1f" % miner.needs.sleep, is_equal_approx(miner.needs.sleep, 49.0))

	print("%d OK, %d failed" % [ok_count, fail_count])
	quit()
