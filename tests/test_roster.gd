## Tests: crew roster after Ostranauts "Crew" 3 and "Orders" 1 (jobs only in Work shifts,
## fires always, Sleep shift goes to bed early, saving, character window)
##   godot --headless --path . --script res://tests/boot.gd -- test_roster
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

func _initialize() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var SS = root.get_node("SaveSystem")
	SS.slot = 960
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var mira: CrewMember = root.get_node("CrewSystem").player()
	var CS = root.get_node("ShipConstructionSystem")
	var g = root.get_node("ShipSystem").grid

	# 1) Default: all Work, so nothing changes for existing crews and saves
	_check("Default roster: 24 × Work", mira.roster.size() == 24 and mira.roster.count("W") == 24 and mira.on_work_shift())
	var h: int = CrewMember.hour_of(gs.time)
	_check("Hour of the day from the game clock (%d, %s)" % [h, gs.clock_text()], gs.clock_text().contains("%02d:" % h))

	# 2) Jobs only in Work shifts
	var dev: Device = null
	for i in g.devices:
		if not g.foreign(i) and g.devices[i].type == "bed":
			dev = g.devices[i]
	dev.cond = 40.0
	CS.place("repair", dev.pos)
	var repair: Dictionary = CS.jobs[g.idx(dev.pos)]
	_check("Work shift: the repair job is open for Mira", mira._has_open_job() and mira._shift_allows(repair))
	mira.roster[h] = "F"
	_check("Free shift: no repair job", not mira._shift_allows(repair) and not mira._has_open_job())
	_check("Free shift: fire fighting still allowed", mira._shift_allows({"kind": "extinguish"}))
	mira.roster[h] = "S"
	_check("Sleep shift: no work either", not mira._shift_allows(repair) and mira.shift() == "S")
	mira.auto_mode = true
	mira.release_job()
	mira.needs.sleep = 75.0
	_check("Sleep shift: goes to bed at energy 75 (normally only below %d)" % int(Config.NEEDS.sleep.at), mira._start_need() and mira.activity != null)
	mira.activity = null
	mira.roster[h] = "W"
	mira.needs.sleep = 75.0
	_check("Work shift: energy 75 is no reason to sleep", not mira._start_need() or String(mira.activity.get("need", "")) != "sleep")

	# 3) Saving/loading
	for k in 24:
		mira.roster[k] = "S" if k < 8 else ("W" if k < 16 else "F")
	SS.save_game()
	SS.load_game(true)
	var m2: CrewMember = root.get_node("CrewSystem").player()
	_check("Saving/loading keeps the roster", m2.roster.slice(0, 8).count("S") == 8 and m2.roster[12] == "W" and m2.roster[20] == "F")

	# 4) Character window: 24 hour buttons, clicking cycles W → F → S
	var cui = root.get_node("UIManager").char_ui
	gs.selected = m2
	cui.tab = "work"
	cui.panel.visible = true
	cui._last = ""
	cui.refresh()
	var btns: Array = []
	for row in cui.box.get_children():
		for b in row.get_children():
			if b is Button and String(b.text).trim_prefix("▸").substr(0, 2).is_valid_int() and String(b.text).length() <= 5:
				btns.append(b)
	_check("24 hour buttons in the Tasks tab (%d)" % btns.size(), btns.size() == 24)
	if btns.size() == 24:
		btns[12].pressed.emit()
	_check("Clicking 12:00 turns Work into Free", m2.roster[12] == "F")

	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
