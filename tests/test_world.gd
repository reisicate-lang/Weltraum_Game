## Tests for stages 8–10 (crew, world, polish):
##   godot --headless --path . --script res://tests/boot.gd -- test_world
extends "res://tests/test_base.gd"

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
	# Own save slot: tests do not overwrite real saves and can run in parallel
	root.get_node("SaveSystem").slot = 911
	# These tests also check the (temporarily disabled) station and the wreck
	Config.ENABLE_STATION = true
	Config.ENABLE_WRECK = true
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

	# --- Stage 8: crew ---
	var mate = npc.candidates_here()[0]
	npc.hire(mate)
	mate.pos = mira.pos
	mira.hobbies.assign(["music"])
	mate.hobbies.assign(["music"])
	CrewSocial.hourly()
	_check("A shared hobby improves the relationship (%+.1f)" % CrewSocial.relation(mira, mate), CrewSocial.relation(mira, mate) > 0.0)
	mira.stress = 90.0
	mate.stress = 90.0
	CrewSocial.change(mira, mate, -50.0)
	var before: float = CrewSocial.relation(mira, mate)
	for k in 20:
		CrewSocial.hourly()
	_check("A stressed crew with a bad relationship argues", CrewSocial.relation(mira, mate) < before)
	_check("Morale drops with stress (%d)" % int(CrewSocial.morale()), CrewSocial.morale() < 50.0)
	mira.stress = 10.0
	mate.stress = 10.0
	var path: String = CrewSocial.export_character(mate)
	_check("Charakter exportiert", FileAccess.file_exists(path))
	_check("Character in the list", path.get_file() in CrewSocial.exported_list())
	gs.new_game()
	CrewSocial.import_character(path.get_file())
	_check("Character taken over into a new game", crew.player().display_name == mate.display_name and crew.player().is_player)
	_check("The skills taken over stay", crew.player().skills.size() == mate.skills.size())

	# --- Etappe 9: Welt ---
	gs.new_game()
	for k in 30:
		gs.step(1.0 / 60.0)
	econ.credits = 50000
	var offers: Array = Q.offers_here()
	_check("Jobs at the station (%d)" % offers.size(), offers.size() == 3)
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
	_check("Job accepted", deliver_offer in Q.accepted)
	var t = econ.terminal()
	t.inv.add(deliver_offer.item, int(deliver_offer.qty), 100.0)
	var cr0: int = econ.credits
	var rep0: float = Q.reputation.guild
	_check("Job delivered", Q.deliver(deliver_offer))
	_check("Belohnung bezahlt", econ.credits > cr0)
	_check("Reputation with the guild rises", Q.reputation.guild > rep0)
	Q.set_insured(true)
	var cr1: int = econ.credits
	Q.claim_damage("Test")
	_check("Insurance pays for damage", econ.credits == cr1 + Q.INSURANCE_PAYOUT)
	var price_before: float = econ.market_price("plate")
	Q.events.append({"text": "Test", "item": "plate", "station": "", "factor": 1.5, "until": gs.time + 1000.0})
	_check("A world event changes prices", econ.market_price("plate") > price_before * 1.4)
	# An expired job costs reputation
	var late: Dictionary = Q._make_offer("tycho")
	late.deadline = gs.time - 1.0
	Q.accepted.append(late)
	Q._day = -1
	var rep1: float = Q.reputation.guild
	Q.step(0.0)
	_check("A missed job costs reputation", Q.reputation.guild < rep1)
	# Ship loan at the shipyard
	phys.docked = "karman"
	var debt0: int = econ.debt
	fleet.buy("lumen", true)
	_check("Ship bought on credit", fleet.ships.size() == 1 and econ.debt > debt0)
	phys.docked = "tycho"

	# --- Etappe 10: Feinschliff ---
	var S = root.get_node("Settings")
	S.depth = "simple"
	S.save()
	S.depth = "normal"
	S._ready()
	_check("Settings saved and loaded", S.depth == "simple")
	_check("Simulationstiefe wirkt", S.sim_factor() > 1.0)
	# Older settings file with a German level name
	S.depth = "einfach"
	S.save()
	S.depth = "normal"
	S._ready()
	_check("Old level “einfach” becomes “simple”", S.depth == "simple" and S.sim_factor() > 1.0)
	S.depth = "normal"
	S.save()
	# Mod: new item from user://mods/items
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
	# Save slots
	econ.credits = 1111
	save.slot = 912
	save.save_game(true)
	econ.credits = 2222
	save.slot = 913
	save.save_game(true)
	save.slot = 912
	save.load_game(true)
	_check("Speicherplatz 2 geladen (%d Cr)" % econ.credits, econ.credits == 1111)
	_check("Speicherplatz-Info", save.slot_info(913).find("2222") >= 0)

	# --- Play through the goals like a player ---
	gs.new_game()
	var G = root.get_node("GoalSystem")
	var build = root.get_node("ShipConstructionSystem")
	var gg = root.get_node("ShipSystem").grid
	var x0: int = (gg.width / Config.GRID_SCALE - 16) / 2
	var y0: int = (gg.height / Config.GRID_SCALE - 10) / 2
	_check("Erstes Ziel: Raumanzug", G.current().id == "suit")
	# The station hangs at the airlock: undock first, then build outside
	for k in 3:
		gs.step(1.0 / 60.0)   # distribute power
	seat_pilot()
	phys.request_undock()
	var outside := C(x0 - 3, y0 + 7) + Vector2i(-1, -1)   # diagonally next to the outer door (ships dock in front of it)
	build.place("floor", outside)
	for k in 60 * 3:
		gs.step(1.0 / 60.0)
	_check("Ziel Raumanzug erreicht", "suit" in G.done)
	# To the wreck target and couple (the floor piece would be in the wreck's way)
	gg.set_tile(outside, ShipGrid.Tile.SPACE)
	var site = root.get_node("FleetSystem").sites[0]
	for k in 20:
		gs.step(1.0 / 60.0)
	var sst: Dictionary = phys.loc_state(site, phys.secs())
	phys.pos = sst.pos + Vector2(0.05, 0)
	phys.vel = sst.vel
	phys.angle = phys.dock_alignment(site.id).angle
	for c in crew.crew:
		c.pos = Vector2(root.get_node("ShipSystem").spawn_point()) + Vector2(0.5, 0.5)
		c.path.clear()
	_check("Coupled to the wreck", phys.dock(site.id))
	for i in gg.piles.keys():
		if gg.zone[i] == 1:
			build.place("haul", gg.pos(i))
	for k in 60 * 60:
		gs.step(1.0 / 60.0)
		if "junk" in G.done:
			break
	_check("Goal scrap from the wreck reached", "junk" in G.done)
	var cr_goal: int = econ.credits
	_check("Ziele geben Belohnung", G.done.size() >= 2 and cr_goal > 0)
	_check("The goal display shows the next goal (%s)" % G.current().get("id", ""), G.current().id == "strip")

	# --- Neue Orte ---
	gs.new_game()
	for k in 30:
		gs.step(1.0 / 60.0)
	var salv = root.get_node("SalvageSystem")
	_check("7 fixed places in space and the wreck next to Tycho", phys.locations.size() == 8 and phys.locations.filter(func(l): return l.kind == "wreck").size() == 1)
	seat_pilot()   # Pilot at the navigation console (flight commands only there)
	phys.travel_to("kx7")
	for k in int((phys.travel.t1 - phys.travel.t0) / 60.0 + 2.0) * 60:
		gs.step(1.0 / 60.0)
	_check("Docked at the asteroid", phys.docked == "kx7" and salv.is_asteroid())
	var g = root.get_node("ShipSystem").grid
	var rock := Vector2i(-1, -1)
	for i in g.tiles.size():
		if g.zone[i] == 1 and g.tiles[i] == 2:
			rock = g.pos(i)
			break
	var loot: Array = root.get_node("ShipConstructionSystem").salvage(rock, crew.player())
	_check("Rock yields ice or ore", not loot.is_empty() and loot[0][0] in ["ice", "ore"])
	phys.docked = "hephaistos"
	var ore_heph: float = econ.market_price("ore")
	phys.docked = "tycho"
	_check("The refinery pays more for ore (%.0f vs %.0f)" % [ore_heph, econ.market_price("ore")], ore_heph > econ.market_price("ore") * 1.5)
	salv.clear()
	root.get_node("FleetSystem").arrive(phys.loc("kepler"))
	var locked := 0
	for dv in g.devices.values():
		if dv.type == "crate" and g.zone[g.idx(dv.pos)] == 1 and dv.lock_level > 0:
			locked += 1
	_check("Outpost: locked storerooms (%d)" % locked, locked > 0)
	_check("Sounds generated (alarm, message, click, hit)", root.get_node("SoundSystem")._sounds.size() == 4 and root.get_node("SoundSystem")._sounds.has("hit"))

	print("\n%d OK, %d Fehler" % [_ok, _failed])
	quit(1 if _failed > 0 else 0)
