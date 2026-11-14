## Tests: hiring crew after Ostranauts "Crew" 2 (salary 200–500, signing bonus from 0,
## death pay 10 000–100 000 held in trust and returned when someone quits or is let go)
##   godot --headless --path . --script res://tests/boot.gd -- test_hire
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
	root.get_node("SaveSystem").slot = 958
	root.get_node("Settings").meteors = false
	gs.new_game()
	root.get_node("TimeSystem").set_speed(0)
	var N = root.get_node("NPCSystem")
	var E = root.get_node("EconomySystem")
	var CS = root.get_node("CrewSystem")
	var CH = root.get_node("CharacterSystem")

	# 1) Applicants: terms in the wiki ranges
	var ok_ranges := true
	for k in 40:
		var n: CrewMember = CH.generate_npc()
		ok_ranges = ok_ranges and n.salary >= 200 and n.salary <= 500 and N.want_death(n) >= 10000 and N.want_death(n) <= 100000 and N.want_death(n) % 5000 == 0
	_check("40 applicants: salary 200–500, death pay 10 000–100 000", ok_ranges)
	var c: CrewMember = N.candidates_here()[0]
	c.salary = 300
	c.set_meta("want_death", 30000)
	var o: Dictionary = N.offer_of(c)
	_check("The offer starts at the asking salary, bonus 0, death pay 10 000", o.salary == 300 and o.bonus == 0 and o.death == 10000)

	# 2) Negotiation
	E.credits = 100000
	_check("Too little death pay without a bonus: refused", not N.make_offer(c) and E.credits == 100000 and not c in CS.crew)
	N.adjust_offer(c, "salary", -50)
	N.adjust_offer(c, "death", 20000)
	_check("50 less per day: refused without a bonus", not N.make_offer(c))
	for k in 6:
		N.adjust_offer(c, "bonus", 250)
	_check("A signing bonus of 1 500 (30 days × 50) makes up for it", N.offer_score(c, N.offer_of(c)) >= 0.0)
	_check("Accepted: 1 500 + 30 000 paid, salary 250", N.make_offer(c) and E.credits == 100000 - 31500 and c in CS.crew and c.salary == 250 and c.death_pay == 30000)
	_check("Bonus and death pay booked", E.log_entries.slice(0, 2).map(func(l): return l.amount) == [-30000, -1500])
	N.adjust_offer(c, "death", 999999)
	_check("Death pay is capped at 100 000", int(N.offer_of(c).death) == 100000)

	# 3) Saving/loading keeps the death pay
	var SS = root.get_node("SaveSystem")
	SS.save_game()
	SS.load_game(true)
	var c2: CrewMember = null
	for m in CS.crew:
		if m.display_name == c.display_name:
			c2 = m
	_check("Saving/loading: death pay in trust stays", c2 != null and c2.death_pay == 30000 and c2.salary == 250)

	# 4) Let go at the station: the death pay comes back
	var cr: int = E.credits
	_check("Let go at the station: 30 000 back", N.fire(c2) and E.credits == cr + 30000 and not c2 in CS.crew and c2.death_pay == 0)
	_check("The player cannot be let go", not N.fire(CS.player()))

	# 5) Quitting after 3 days without wages: death pay back too
	var d: CrewMember = N.candidates_here()[0]
	E.credits = 200000
	N.hire(d)
	var dp: int = d.death_pay
	E.credits = 0
	for k in 3:
		N.pay_wages()
	_check("Quit after 3 days without wages, %d Cr death pay back" % dp, not d in CS.crew and E.credits == dp)

	# 6) The Crew tab shows the three terms with buttons and the offer
	var ui = root.get_node("UIManager")
	ui.trade_tab = "crew"
	ui.open_window("terminal")
	var texts := []
	for row in ui.window_box.get_children():
		if row.is_queued_for_deletion():
			continue
		for x in [row] + row.get_children():
			if x is Button or x is Label:
				texts.append(x.text)
	_check("Crew tab: salary, bonus, death pay and “Offer”", texts.any(func(t): return String(t).begins_with("Salary ")) and texts.any(func(t): return String(t).begins_with("Death pay "))
		and texts.any(func(t): return String(t).begins_with("Offer (")))
	print("%d OK, %d Fehler" % [ok_count, fail_count])
	quit()
