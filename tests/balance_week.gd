## Balance-Simulation: Eine Woche Bergung durch Mira allein.
## Jeden Tag: Wrack-Geräte abreißen, alles einsammeln, verkaufen, bei Bedarf neues Wrack.
##   godot --headless --path . --script res://tests/balance_week.gd
extends SceneTree

func _initialize() -> void:
	await process_frame
	await process_frame
	# Diese Tests prüfen auch die (vorübergehend abgeschaltete) Station und das Wrack
	Config.ENABLE_STATION = true
	Config.ENABLE_WRECK = true
	var gs = root.get_node("GameState")
	var build = root.get_node("ShipConstructionSystem")
	var econ = root.get_node("EconomySystem")
	var salv = root.get_node("SalvageSystem")
	root.get_node("Settings").meteors = false
	root.get_node("Settings").debt_paused = false
	gs.new_game()
	var start: int = econ.credits
	var income := 0
	for day in 7:
		var g = root.get_node("ShipSystem").grid
		for i in g.devices.keys():
			if g.zone[i] == 1 and g.devices[i].lock_level == 0:
				build.place("remove", g.pos(i))
		for half in 4:
			for k in 6 * 60 * 60:
				gs.step(1.0 / 60.0)
			for i in g.piles.keys():
				if g.zone[i] == 1:
					build.place("haul", g.pos(i))
		# Alles Verkaufbare aus den Kisten ins Terminal
		var t = econ.terminal()
		for dv in g.devices.values():
			if dv.type == "crate" and g.zone[g.idx(dv.pos)] == 0:
				for it in dv.inv.items.duplicate():
					if it.type in ["scrap", "plate", "copper", "motor", "circuit", "cell", "pipe", "glass", "datachip", "boltgun"]:
						dv.inv.move_to(t.inv, it.type, it.qty)
		var before: int = econ.credits
		econ.sell_all()
		income += econ.credits - before
		var wreck_devs := 0
		for i in g.devices:
			if g.zone[i] == 1:
				wreck_devs += 1
		if wreck_devs <= 2 and econ.credits > 600:
			econ.buy_claim()
		print("Tag %d: %d Cr (Verkauf heute %d), Schulden %d" % [day + 1, econ.credits, econ.credits - before, econ.debt])
	print("Einnahmen aus Verkäufen in 7 Tagen: %d Cr, Rate: %d Cr, Start: %d Cr" % [income, Config.PAYMENT, start])
	quit()
