## Tests: worn vs. damaged after Ostranauts "Salvaging" 3.2 (worn: time and work; damaged:
## components, e.g. motor + scrap for a thruster), display, wrecks, saving
##   godot --headless --path . --script res://tests/boot.gd -- test_wear
extends "res://tests/test_base.gd"

var ok_count := 0
var fail_count := 0

func _check(name: String, ok: bool) -> void:
	if ok:
		ok_count += 1
		print("OK      " + name)
	else:
		fail_count += 1
		print("FAIL    " + name)

func _initialize() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var SS = root.get_node("SaveSystem")
	SS.slot = 962
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var g: ShipGrid = root.get_node("ShipSystem").grid
	var CS = root.get_node("ShipConstructionSystem")
	var DS = root.get_node("DamageSystem")
	var thr: Device = null
	for i in g.devices:
		if g.devices[i].type == "thruster" and not g.foreign(i):
			thr = g.devices[i]

	# 1) Worn: repair only takes time
	thr.cond = 60.0
	_check("Worn thruster: no parts needed, shown as worn (%s)" % thr.status_text(), DS.repair_parts(thr).is_empty() and thr.status_text().contains("(worn)"))
	CS.place("repair", thr.pos)
	var job: Dictionary = CS.jobs[g.idx(thr.pos)]
	_check("Repair job of a worn device costs nothing", CS.cost(job).is_empty())
	CS.cancel(job)

	# 2) Damaged: motor + scrap (wiki tip for RCS thrusters)
	thr.damaged = true
	_check("Damaged thruster needs 1 motor + 1 scrap (%s)" % str(DS.repair_parts(thr)), DS.repair_parts(thr) == {"motor": 1, "scrap": 1} and thr.status_text().contains("damaged: repair needs 1× "))
	CS.place("repair", thr.pos)
	job = CS.jobs[g.idx(thr.pos)]
	_check("Repair job of a damaged device costs the parts", CS.cost(job) == {"motor": 1, "scrap": 1})
	CS.complete(job, thr.pos)
	_check("Finished repair: 100 %, no longer damaged", thr.cond == 100.0 and not thr.damaged)
	var bed: Device = null
	for i in g.devices:
		if g.devices[i].type == "bed" and not g.foreign(i):
			bed = g.devices[i]
	bed.damaged = true
	_check("Damaged bed: its most valuable component besides plates, 1 fabric + 1 scrap (%s)" % str(DS.repair_parts(bed)), DS.repair_parts(bed) == {"fabric": 1, "scrap": 1})
	bed.damaged = false

	# 3) What damages: wear does not, an impact does
	root.get_node("ShipPowerSystem")._dirty = true
	root.get_node("ShipPowerSystem").step(0.01)
	var gen: Device = null
	for i in g.devices:
		if g.devices[i].data().wears and not g.foreign(i) and g.devices[i].needs_power() and g.devices[i].powered:
			gen = g.devices[i]
	var c0: float = gen.cond if gen != null else 0.0
	for k in 60:
		DS.step(60.0)
	_check("Wear lowers the condition but does not damage (%s %.1f → %.1f)" % [gen.type if gen else "-", c0, gen.cond if gen else 0.0], gen != null and gen.cond < c0 and not gen.damaged)
	var any := false
	for k in 30:
		DS.strike()
	for d in g.devices.values():
		any = any or d.damaged
	_check("Micrometeorite impacts damage devices nearby", any)

	# 4) Saving/loading and the real crew fetching parts
	thr.damaged = true
	thr.cond = 40.0
	SS.save_game()
	SS.load_game(true)
	g = root.get_node("ShipSystem").grid
	var t2: Device = g.device_at(thr.pos)
	_check("Saving/loading keeps “damaged”", t2 != null and t2.damaged)

	print("%d OK, %d failed" % [ok_count, fail_count])
	quit()
