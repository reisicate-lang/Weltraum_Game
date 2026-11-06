## Tests für Etappe 8–10 (Crew, Welt, Feinschliff):
##   godot --headless --path . --script res://tests/test_world.gd
extends SceneTree

var _failed := 0
var _ok := 0

func _check(name: String, ok: bool) -> void:
	if ok:
		_ok += 1
	else:
		_failed += 1
	print(("OK    " if ok else "FEHLER") + "  " + name)

func _initialize() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node("GameState")
	var crew = root.get_node("CrewSystem")
	var Q = root.get_node("QuestSystem")
	var econ = root.get_node("EconomySystem")
	var npc = root.get_node("NPCSystem")
	var save = root.get_node("SaveSystem")
	var fleet = root.get_node("FleetSystem")
	var phys = root.get_node("PhysicsSystem")
	gs.new_game()
	for k in 30:
		gs.step(1.0 / 60.0)
	var mira = crew.player()
	econ.credits = 50000

	# --- Etappe 8: Crew ---
	var mate = npc.candidates_here()[0]
	npc.hire(mate)
	mate.pos = mira.pos
	mira.hobbies.assign(["music"])
	mate.hobbies.assign(["music"])
	CrewSocial.hourly()
	_check("Gemeinsames Hobby verbessert die Beziehung (%+.1f)" % CrewSocial.relation(mira, mate), CrewSocial.relation(mira, mate) > 0.0)
	mira.stress = 90.0
	mate.stress = 90.0
	CrewSocial.change(mira, mate, -50.0)
	var before: float = CrewSocial.relation(mira, mate)
	for k in 20:
		CrewSocial.hourly()
	_check("Gestresste Crew mit schlechter Beziehung streitet", CrewSocial.relation(mira, mate) < before)
	_check("Moral sinkt bei Stress (%d)" % int(CrewSocial.morale()), CrewSocial.morale() < 50.0)
	mira.stress = 10.0
	mate.stress = 10.0
	var path: String = CrewSocial.export_character(mate)
	_check("Charakter exportiert", FileAccess.file_exists(path))
	_check("Charakter in der Liste", path.get_file() in CrewSocial.exported_list())
	gs.new_game()
	CrewSocial.import_character(path.get_file())
	_check("Charakter in neues Spiel übernommen", crew.player().display_name == mate.display_name and crew.player().is_player)
	_check("Übernommene Fähigkeiten bleiben", crew.player().skills.size() == mate.skills.size())

	# --- Etappe 9: Welt ---
	gs.new_game()
	for k in 30:
		gs.step(1.0 / 60.0)
	econ.credits = 50000
	var offers: Array = Q.offers_here()
	_check("Aufträge an der Station (%d)" % offers.size(), offers.size() == 3)
	var deliver_offer = null
	for o in offers:
		if o.kind == "deliver" and o.to == "tycho":
			deliver_offer = o
	if deliver_offer == null:
		deliver_offer = Q._make_offer("tycho")
		deliver_offer.kind = "deliver"
		deliver_offer.to = "tycho"
		Q.offers["tycho"].append(deliver_offer)
	Q.accept(deliver_offer)
	_check("Auftrag angenommen", deliver_offer in Q.accepted)
	var t = econ.terminal()
	t.inv.add(deliver_offer.item, int(deliver_offer.qty), 100.0)
	var cr0: int = econ.credits
	var rep0: float = Q.reputation.guild
	_check("Auftrag abgeliefert", Q.deliver(deliver_offer))
	_check("Belohnung bezahlt", econ.credits > cr0)
	_check("Ansehen bei der Gilde steigt", Q.reputation.guild > rep0)
	Q.set_insured(true)
	var cr1: int = econ.credits
	Q.claim_damage("Test")
	_check("Versicherung zahlt bei Schaden", econ.credits == cr1 + Q.INSURANCE_PAYOUT)
	var price_before: float = econ.market_price("plate")
	Q.events.append({"text": "Test", "item": "plate", "station": "", "factor": 1.5, "until": gs.time + 1000.0})
	_check("Weltereignis verändert Preise", econ.market_price("plate") > price_before * 1.4)
	# Abgelaufener Auftrag kostet Ansehen
	var late: Dictionary = Q._make_offer("tycho")
	late.deadline = gs.time - 1.0
	Q.accepted.append(late)
	Q._day = -1
	var rep1: float = Q.reputation.guild
	Q.step(0.0)
	_check("Verpasster Auftrag kostet Ansehen", Q.reputation.guild < rep1)
	# Schiffskredit an der Werft
	phys.docked = "karman"
	var debt0: int = econ.debt
	fleet.buy("lumen", true)
	_check("Schiff auf Kredit gekauft", fleet.ships.size() == 1 and econ.debt > debt0)
	phys.docked = "tycho"

	# --- Etappe 10: Feinschliff ---
	var S = root.get_node("Settings")
	S.depth = "einfach"
	S.save()
	S.depth = "normal"
	S._ready()
	_check("Einstellungen gespeichert und geladen", S.depth == "einfach")
	_check("Simulationstiefe wirkt", S.sim_factor() > 1.0)
	S.depth = "normal"
	S.save()
	# Mod: neuer Gegenstand aus user://mods/items
	DirAccess.make_dir_recursive_absolute("user://mods/items")
	var mod := ItemData.new()
	mod.id = "modtest"
	mod.display_name = "Mod-Testteil"
	mod.weight = 1.0
	mod.volume = 1.0
	mod.value = 5
	ResourceSaver.save(mod, "user://mods/items/modtest.tres")
	root.get_node("ItemSystem")._load_dir("user://mods/items/", root.get_node("ItemSystem").items, true)
	_check("Mod-Gegenstand geladen", root.get_node("ItemSystem").item("modtest") != null)
	DirAccess.remove_absolute("user://mods/items/modtest.tres")
	# Speicherplätze
	econ.credits = 1111
	save.slot = 2
	save.save_game(true)
	econ.credits = 2222
	save.slot = 3
	save.save_game(true)
	save.slot = 2
	save.load_game(true)
	_check("Speicherplatz 2 geladen (%d Cr)" % econ.credits, econ.credits == 1111)
	_check("Speicherplatz-Info", save.slot_info(3).find("2222") >= 0)

	print("\n%d OK, %d Fehler" % [_ok, _failed])
	quit(1 if _failed > 0 else 0)
