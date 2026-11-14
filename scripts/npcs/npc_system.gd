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
	offers.clear()

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

# ---------------- Hiring (Ostranauts Crew 2) ----------------
# Three terms: daily salary (usually 200–500), a one-time signing bonus (starts at 0) and the
# death pay, paid up front and held in trust (10 000–100 000): it comes back when the
# crewmember quits or is fired and would go to their nominated parties on death (crew cannot
# die in this game yet: unconscious at 0 health).
# The wiki's negotiation is a social combat; here it is a simple offer: a lower salary must be
# made up by the signing bonus (30 days of the difference), a lower death pay counts 10 %.

const SALARY_MIN := 200
const SALARY_MAX := 500
const DEATH_MIN := 10000
const DEATH_MAX := 100000
const BONUS_DAYS := 30.0
const DEATH_WEIGHT := 0.1

## Death pay the applicant wants
func want_death(c: CrewMember) -> int:
	return int(c.get_meta("want_death", DEATH_MIN))

## Current offer for an applicant: {salary, bonus, death}; starts with their asking salary,
## no signing bonus and the minimum death pay
var offers := {}
func offer_of(c: CrewMember) -> Dictionary:
	if not offers.has(c.id):
		offers[c.id] = {"salary": c.salary, "bonus": 0, "death": DEATH_MIN}
	return offers[c.id]

func adjust_offer(c: CrewMember, term: String, delta: int) -> void:
	var o := offer_of(c)
	match term:
		"salary":
			o.salary = clampi(int(o.salary) + delta, 0, SALARY_MAX * 2)
		"bonus":
			o.bonus = maxi(0, int(o.bonus) + delta)
		"death":
			o.death = clampi(int(o.death) + delta, DEATH_MIN, DEATH_MAX)

## How good the offer is for the applicant (>= 0: they accept)
func offer_score(c: CrewMember, o: Dictionary) -> float:
	return (float(o.salary) - c.salary) * BONUS_DAYS + float(o.bonus) + (float(o.death) - want_death(c)) * DEATH_WEIGHT

## Make the offer. Accepted → bonus and death pay are paid now, the NPC joins the crew.
func make_offer(c: CrewMember, o: Dictionary = {}) -> bool:
	if o.is_empty():
		o = offer_of(c)
	var cost := int(o.bonus) + int(o.death)
	if EconomySystem.credits < cost:
		GameState.toast("Not enough credits: signing bonus %d Cr + death pay %d Cr." % [int(o.bonus), int(o.death)])
		return false
	if offer_score(c, o) < 0.0:
		GameState.toast("%s turns the offer down." % c.display_name, "bad")
		return false
	EconomySystem.credits -= cost
	if int(o.bonus) > 0:
		EconomySystem.book("Signing bonus: " + c.display_name, -int(o.bonus))
	EconomySystem.book("Death pay held in trust: " + c.display_name, -int(o.death))
	c.salary = int(o.salary)
	c.death_pay = int(o.death)
	offers.erase(c.id)
	var st := PhysicsSystem.station()
	if not st.is_empty() and candidates.has(st.id):
		candidates[st.id].erase(c)
	var p := CrewSystem.player()
	c.pos = p.pos if p != null else Vector2(ShipSystem.spawn_point()) + Vector2(0.5, 0.5)
	CrewSystem.crew.append(c)
	c.push_out_if_stuck()
	GameState.toast(c.display_name + " is now part of the crew (%d Cr per day)." % c.salary)
	return true

## Hire on the applicant's own terms (asking salary, no bonus, the death pay they want)
func hire(c: CrewMember) -> bool:
	return make_offer(c, {"salary": c.salary, "bonus": 0, "death": want_death(c)})

## Leaving the crew (quit or fired): the death pay held in trust comes back
func _leave(c: CrewMember, why: String) -> void:
	c.release_job()
	CrewSystem.crew.erase(c)
	if c.death_pay > 0:
		EconomySystem.credits += c.death_pay
		EconomySystem.book("Death pay returned: " + c.display_name, c.death_pay)
	GameState.toast("%s %s. Death pay returned: %d Cr." % [c.display_name, why, c.death_pay], "bad" if why == "quit" else "")
	c.death_pay = 0

## Fire a crewmember (only at a station, so they can get off)
func fire(c: CrewMember) -> bool:
	if c.is_player or not c in CrewSystem.crew:
		return false
	if PhysicsSystem.station().is_empty():
		GameState.toast("Crew can only be let go at a station.")
		return false
	_leave(c, "was let go")
	return true

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
				_leave(c, "quit")

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
