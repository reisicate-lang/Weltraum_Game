## NPCs: applicants on the stations (hiring, wages) and encounters
## with plunderers (fight, negotiate, pay).
extends Node

signal encounter_started(enc: Dictionary)

var candidates: Dictionary = {}   ## Station -> Array[CrewMember]
var _cand_day := -1
var encounter: Dictionary = {}    ## current encounter or empty
var unpaid := {}                  ## crew id -> days without wages

func reset() -> void:
	candidates.clear()
	_cand_day = -1
	encounter = {}
	unpaid.clear()

## Applicants at the current station (new ones every day)
func candidates_here() -> Array:
	var st := PhysicsSystem.station()
	if st.is_empty():
		return []
	var day := int(GameState.time / 1440.0)
	if day != _cand_day:
		candidates.clear()
		_cand_day = day
	if not candidates.has(st.id):
		var list: Array = []
		for k in 3:
			list.append(CharacterSystem.generate_npc())
		candidates[st.id] = list
	return candidates[st.id]

func hire(c: CrewMember) -> void:
	var fee := c.salary * 2
	if EconomySystem.credits < fee:
		GameState.toast("Not enough credits (signing money %d Cr)." % fee)
		return
	EconomySystem.credits -= fee
	EconomySystem.book("Hired: " + c.display_name, -fee)
	candidates[PhysicsSystem.station().id].erase(c)
	var p := CrewSystem.player()
	c.pos = p.pos if p != null else Vector2(ShipSystem.spawn_point()) + Vector2(0.5, 0.5)
	CrewSystem.crew.append(c)
	c.push_out_if_stuck()
	GameState.toast(c.display_name + " is now part of the crew (%d Cr per day)." % c.salary)

## Pay wages every day. Whoever gets no wages for 3 days leaves.
func pay_wages() -> void:
	for c in CrewSystem.crew.duplicate():
		if c.is_player or c.salary <= 0:
			continue
		if EconomySystem.credits >= c.salary:
			EconomySystem.credits -= c.salary
			EconomySystem.book("Wages " + c.display_name, -c.salary)
			unpaid[c.id] = 0
		else:
			unpaid[c.id] = int(unpaid.get(c.id, 0)) + 1
			c.stress = minf(100.0, c.stress + 20.0)
			GameState.toast("No wages for %s! (day %d)" % [c.display_name, unpaid[c.id]], "bad")
			if unpaid[c.id] >= 3 and PhysicsSystem.station().size() > 0:
				c.release_job()
				CrewSystem.crew.erase(c)
				GameState.toast(c.display_name + " quit and left the ship.", "bad")

# ---------------- Begegnungen ----------------

## Plunderers can show up when docking in the debris field or at L4
func on_docked(loc_id: String) -> void:
	var chance := {"debris": 0.35, "l4": 0.2}.get(loc_id, 0.0) as float
	chance *= 1.0 - minf(0.6, SkillSystem.best_effect("threat"))
	if randf() < chance:
		start_plunderers()

func start_plunderers() -> void:
	encounter = {"kind": "plunderer", "strength": randf_range(20.0, 65.0), "demand": 200}
	TimeSystem.set_speed(0)
	encounter_started.emit(encounter)

## Fighters: the three strongest aboard
func fighters() -> Array:
	var list := CrewSystem.crew.filter(func(c): return not c.unconscious)
	list.sort_custom(func(a, b): return SkillSystem.combat_power(a) > SkillSystem.combat_power(b))
	return list.slice(0, 3)

func fight() -> String:
	var team := fighters()
	var power := 0.0
	for c in team:
		power += SkillSystem.combat_power(c)
	var win := randf() < power / (power + float(encounter.strength))
	for c in team:
		var w := ""
		for it in c.inv.items:
			if ItemSystem.item(it.type).weapon != "":
				w = ItemSystem.item(it.type).weapon
		SkillSystem.train(c, {"armed": "fight_armed", "ranged": "fight_ranged"}.get(w, "fight_unarmed"), 15.0)
		c.stress = minf(100.0, c.stress + 15.0)
	var text := ""
	if win:
		var p: CrewMember = team[0]
		ShipSystem.grid.drop_items(p.tile(), ["scrap", "circuit", "datachip"].pick_random(), randi_range(1, 2), 60.0)
		text = "%s and the crew drive off the plunderers. They leave something behind." % p.display_name
	else:
		for c in team:
			c.health = maxf(5.0, c.health - randf_range(20.0, 40.0) / TraitSystem.factor(c, "toughness"))
		var loss := int(EconomySystem.credits * 0.2)
		EconomySystem.credits -= loss
		EconomySystem.book("Robbed by plunderers", -loss)
		text = "The plunderers are stronger. The crew is hurt and %d Cr are gone." % loss
	encounter = {}
	return text

func negotiate() -> String:
	var c: CrewMember = EconomySystem.trader()
	var chance := 0.15 + SkillSystem.effect(c, "negotiate") * 0.6 + SkillSystem.effect(c, "talk_street") * 0.3 + SkillSystem.effect(c, "bluff") * 0.3
	chance *= TraitSystem.factor(c, "social")
	if SkillSystem.mastered(c, "persuasion"):
		chance = maxf(chance, 0.85)
	SkillSystem.train(c, "negotiate", 10.0)
	SkillSystem.train(c, "talk_street", 5.0)
	if randf() < chance:
		encounter = {}
		return "%s talks the plunderers down. They leave." % c.display_name
	return "“Nice try.” The plunderers will not be brushed off. " + fight()

func pay() -> String:
	var d: int = encounter.demand
	if EconomySystem.credits < d:
		return "Not enough money. " + fight()
	EconomySystem.credits -= d
	EconomySystem.book("Protection money to plunderers", -d)
	encounter = {}
	return "You pay %d Cr. The plunderers disappear." % d
