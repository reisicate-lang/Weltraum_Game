## NPCs: Bewerber auf den Stationen (anheuern, Lohn) und Begegnungen
## mit Plünderern (kämpfen, verhandeln, bezahlen).
extends Node

signal encounter_started(enc: Dictionary)

var candidates: Dictionary = {}   ## Station -> Array[CrewMember]
var _cand_day := -1
var encounter: Dictionary = {}    ## aktuelle Begegnung oder leer
var unpaid := {}                  ## crew id -> Tage ohne Lohn

func reset() -> void:
	candidates.clear()
	_cand_day = -1
	encounter = {}
	unpaid.clear()

## Bewerber an der aktuellen Station (jeden Tag neue)
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
		GameState.toast("Nicht genug Credits (Handgeld %d Cr)." % fee)
		return
	EconomySystem.credits -= fee
	EconomySystem.book("Angeheuert: " + c.display_name, -fee)
	candidates[PhysicsSystem.station().id].erase(c)
	var p := CrewSystem.player()
	c.pos = p.pos if p != null else Vector2(ShipSystem.spawn_point()) + Vector2(0.5, 0.5)
	CrewSystem.crew.append(c)
	c.push_out_if_stuck()
	GameState.toast(c.display_name + " gehört jetzt zur Crew (%d Cr pro Tag)." % c.salary)

## Jeden Tag Lohn zahlen. Wer 3 Tage keinen Lohn bekommt, geht.
func pay_wages() -> void:
	for c in CrewSystem.crew.duplicate():
		if c.is_player or c.salary <= 0:
			continue
		if EconomySystem.credits >= c.salary:
			EconomySystem.credits -= c.salary
			EconomySystem.book("Lohn " + c.display_name, -c.salary)
			unpaid[c.id] = 0
		else:
			unpaid[c.id] = int(unpaid.get(c.id, 0)) + 1
			c.stress = minf(100.0, c.stress + 20.0)
			GameState.toast("Kein Lohn für %s! (%d. Tag)" % [c.display_name, unpaid[c.id]], "bad")
			if unpaid[c.id] >= 3 and PhysicsSystem.station().size() > 0:
				c.release_job()
				CrewSystem.crew.erase(c)
				GameState.toast(c.display_name + " hat gekündigt und das Schiff verlassen.", "bad")

# ---------------- Begegnungen ----------------

## Beim Andocken im Trümmerfeld oder an L4 können Plünderer auftauchen
func on_docked(loc_id: String) -> void:
	var chance := {"debris": 0.35, "l4": 0.2}.get(loc_id, 0.0) as float
	chance *= 1.0 - minf(0.6, SkillSystem.best_effect("threat"))
	if randf() < chance:
		start_plunderers()

func start_plunderers() -> void:
	encounter = {"kind": "plunderer", "strength": randf_range(20.0, 65.0), "demand": 200}
	TimeSystem.set_speed(0)
	encounter_started.emit(encounter)

## Kämpfer: die drei stärksten an Bord
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
		text = "%s und die Crew schlagen die Plünderer in die Flucht. Sie lassen etwas zurück." % p.display_name
	else:
		for c in team:
			c.health = maxf(5.0, c.health - randf_range(20.0, 40.0) / TraitSystem.factor(c, "toughness"))
		var loss := int(EconomySystem.credits * 0.2)
		EconomySystem.credits -= loss
		EconomySystem.book("Von Plünderern ausgeraubt", -loss)
		text = "Die Plünderer sind stärker. Die Crew ist verletzt, %d Cr sind weg." % loss
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
		return "%s redet auf die Plünderer ein. Sie ziehen ab." % c.display_name
	return "„Netter Versuch.“ Die Plünderer lassen sich nicht abwimmeln. " + fight()

func pay() -> String:
	var d: int = encounter.demand
	if EconomySystem.credits < d:
		return "Zu wenig Geld. " + fight()
	EconomySystem.credits -= d
	EconomySystem.book("Schutzgeld an Plünderer", -d)
	encounter = {}
	return "Du zahlst %d Cr. Die Plünderer verschwinden." % d
