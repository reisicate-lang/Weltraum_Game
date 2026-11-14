## Lebendige Welt: Fraktionen mit Ansehen, Aufträge (Liefern, Bergen,
## Transport), Versicherung und tägliche Weltereignisse.
extends Node

const FACTIONS := {
	"guild": {"name": "Tycho Traders' Guild", "station": "tycho"},
	"consortium": {"name": "Kármán Consortium", "station": "karman"},
	"syndicate": {"name": "L4 Syndicate", "station": "l4"},
	"patrol": {"name": "Space Patrol", "station": ""},
}
const DELIVERABLE := ["plate", "copper", "circuit", "motor", "cell", "pipe", "glass", "filter", "ration", "fuelcan", "datachip"]
const INSURANCE_PREMIUM := 120   ## Cr pro Woche
const INSURANCE_PAYOUT := 400    ## Cr pro Schaden (Hüllenbruch, Feuer)

var reputation := {}             ## Fraktion -> -100..100
var offers := {}                 ## Station -> Array[Dictionary]
var accepted: Array[Dictionary] = []
var insured := false
var next_premium := 0.0
var events: Array[Dictionary] = []  ## aktive Weltereignisse {text, item, station, factor, until}
var _day := -1

func reset() -> void:
	reputation = {"guild": 0.0, "consortium": 0.0, "syndicate": 0.0, "patrol": 0.0}
	offers.clear()
	accepted.clear()
	insured = false
	events.clear()
	_day = -1

func faction_of(station_id: String) -> String:
	for f in FACTIONS:
		if FACTIONS[f].station == station_id:
			return f
	return ""

func change_rep(f: String, amount: float) -> void:
	if f == "":
		return
	reputation[f] = clampf(float(reputation.get(f, 0.0)) + amount, -100.0, 100.0)

## Preisfaktor aus Ansehen (gutes Ansehen = bessere Preise) und Weltereignissen
func price_factor(type: String) -> float:
	var st := PhysicsSystem.station()
	var f := 1.0
	if not st.is_empty():
		f *= 1.0 + float(reputation.get(faction_of(st.id), 0.0)) / 1000.0
	for e in events:
		if e.item == type and (e.station == "" or e.station == st.get("id", "")):
			f *= float(e.factor)
	return f

# ---------------- Aufträge ----------------

func offers_here() -> Array:
	var st := PhysicsSystem.station()
	if st.is_empty():
		return []
	if not offers.has(st.id):
		var list: Array = []
		for k in 3:
			list.append(_make_offer(st.id))
		offers[st.id] = list
	return offers[st.id]

func _make_offer(station_id: String) -> Dictionary:
	var item: String = DELIVERABLE.pick_random()
	var qty := randi_range(2, 8)
	var dest := station_id
	var kind := ["deliver", "deliver", "transport"].pick_random() as String
	if kind == "transport":
		var others := PhysicsSystem.locations.filter(func(l): return l.kind == "station" and l.id != station_id)
		dest = others.pick_random().id
		item = "cargo"
		qty = randi_range(1, 3)
	var value: float = (ItemSystem.item(item).value if item != "cargo" else 60.0) * qty
	return {"kind": kind, "item": item, "qty": qty, "from": station_id, "to": dest,
		"reward": int(value * randf_range(1.3, 1.8) + (150 if kind == "transport" else 0)),
		"deadline": GameState.time + randf_range(3.0, 7.0) * 1440.0, "faction": faction_of(station_id)}

func describe(o: Dictionary) -> String:
	var dest_name: String = PhysicsSystem.loc(o.to).name
	if o.kind == "transport":
		return "Transport: %d× cargo to %s · %d Cr · by day %d" % [o.qty, dest_name, o.reward, int(o.deadline / 1440.0) + 1]
	return "Deliver: %d× %s to %s · %d Cr · by day %d" % [o.qty, ItemSystem.item(o.item).display_name, dest_name, o.reward, int(o.deadline / 1440.0) + 1]

func accept(o: Dictionary) -> void:
	offers[o.from].erase(o)
	accepted.append(o)
	if o.kind == "transport":
		var t := EconomySystem.terminal()
		if t != null:
			t.inv.add("cargo", int(o.qty), 100.0)
	GameState.toast("Job accepted: " + describe(o))

## Abliefern: Ware muss im Handelsterminal liegen, am Zielort
func deliver(o: Dictionary) -> bool:
	var st := PhysicsSystem.station()
	var t := EconomySystem.terminal()
	if st.is_empty() or st.id != o.to or t == null:
		GameState.toast("Delivery only at the destination: " + PhysicsSystem.loc(o.to).name)
		return false
	if t.inv.count(o.item) < int(o.qty):
		GameState.toast("The terminal is still missing %d× %s." % [int(o.qty) - t.inv.count(o.item), ItemSystem.item(o.item).display_name])
		return false
	t.inv.take(o.item, int(o.qty))
	EconomySystem.credits += int(o.reward)
	EconomySystem.book("Job completed", int(o.reward))
	change_rep(o.faction, 8.0)
	accepted.erase(o)
	GoalSystem.on_contract_done()
	SkillSystem.train(EconomySystem.trader(), "trade", 10.0)
	GameState.toast("Job completed: +%d Cr, reputation with %s rises." % [o.reward, FACTIONS.get(o.faction, {"name": "?"}).name])
	return true

# ---------------- Versicherung ----------------

func set_insured(on: bool) -> void:
	insured = on
	next_premium = GameState.time
	GameState.toast("Insurance " + ("abgeschlossen" if on else "cancelled") + ".")

## Schaden melden (Hüllenbruch, Feuer)
func claim_damage(what: String) -> void:
	if not insured:
		return
	EconomySystem.credits += INSURANCE_PAYOUT
	EconomySystem.book("Insurance pays: " + what, INSURANCE_PAYOUT)

# ---------------- Täglich ----------------

func step(_dt: float) -> void:
	var day := int(GameState.time / 1440.0)
	if day == _day:
		return
	_day = day
	# Abgelaufene Aufträge kosten Ansehen
	for o in accepted.duplicate():
		if GameState.time > float(o.deadline):
			accepted.erase(o)
			change_rep(o.faction, -10.0)
			GameState.toast("Job missed. Your reputation suffers.", "bad")
	# Neue Angebote an allen Stationen
	offers.clear()
	# Versicherungsprämie
	if insured and GameState.time >= next_premium:
		next_premium += 7.0 * 1440.0
		EconomySystem.credits -= INSURANCE_PREMIUM
		EconomySystem.book("Insurance premium", -INSURANCE_PREMIUM)
	# Weltereignisse
	events = events.filter(func(e): return float(e.until) > GameState.time)
	if randf() < 0.35:
		_new_event()

func _new_event() -> void:
	var options := [
		{"text": "Strike at the lunar shipyard: steel plates are scarce and expensive.", "item": "plate", "station": "", "factor": 1.5},
		{"text": "A freighter full of electronics is stranded: circuit boards are cheap.", "item": "circuit", "station": "", "factor": 0.6},
		{"text": "Fuel shortage at the Kármán Ring.", "item": "fuelcan", "station": "karman", "factor": 1.6},
		{"text": "Patrol raid on L4: contraband is in demand like never before.", "item": "contraband", "station": "l4", "factor": 1.4},
		{"text": "Hunger winter in the lunar settlements: rations are expensive.", "item": "ration", "station": "tycho", "factor": 1.5},
		{"text": "Data leak at the Consortium: data chips are in hot demand.", "item": "datachip", "station": "", "factor": 1.5},
	]
	var e: Dictionary = options.pick_random().duplicate()
	e.until = GameState.time + randf_range(2.0, 5.0) * 1440.0
	events.append(e)
	GameState.toast("News: " + e.text)

func to_data() -> Dictionary:
	return {"reputation": reputation, "accepted": accepted, "insured": insured, "next_premium": next_premium, "events": events}

func from_data(d: Dictionary) -> void:
	reputation = d.reputation
	accepted.assign(d.accepted)
	insured = bool(d.insured)
	next_premium = float(d.next_premium)
	events.assign(d.events)
	offers.clear()
	_day = int(GameState.time / 1440.0)
