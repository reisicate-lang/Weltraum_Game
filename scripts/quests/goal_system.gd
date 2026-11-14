## Goals (a guiding thread for new players). Every goal is detected
## automatically, gives a small reward and unlocks the next one.
extends Node

## Goal checks. "check" is the name of a function below.
const GOALS := [
	{"id": "suit", "text": "Have Mira put on a space suit (undock, then plan something outside in space, e.g. a floor diagonally next to the airlock's outer door – ships dock right in front of it)", "check": "_g_suit", "reward": 50},
	{"id": "junk", "text": "Collect scrap from the wreck (Haul tool, Q)", "check": "_g_junk", "reward": 80, "needs": "wreck"},
	{"id": "strip", "text": "Demolish a device in the wreck (Demolish tool, U)", "check": "_g_strip", "reward": 80, "needs": "wreck"},
	{"id": "sell", "text": "Sell something at the trade terminal in the cockpit", "check": "_g_sell", "reward": 100},
	{"id": "solar", "text": "Build a solar panel outside in vacuum, e.g. on a floor next to the airlock, not directly in front of its outer door (saves generator fuel)", "check": "_g_solar", "reward": 150},
	{"id": "book", "text": "Have someone read a textbook (buy it at the terminal, put it in a crate)", "check": "_g_book", "reward": 100},
	{"id": "fly", "text": "Fly to the Kármán Ring (key N, Travel)", "check": "_g_fly", "reward": 200},
	{"id": "hire", "text": "Hire a crew member (terminal, Crew tab)", "check": "_g_hire", "reward": 150},
	{"id": "contract", "text": "Complete a job (terminal, Jobs tab)", "check": "_g_contract", "reward": 200},
	{"id": "rate", "text": "Pay a loan instalment on time", "check": "_g_rate", "reward": 250},
	{"id": "debt", "text": "Pay off the loan completely – the ship is yours", "check": "_g_debt", "reward": 0},
]

var done: Array[String] = []
var _contracts_done := 0
var stripped := 0              ## devices demolished in the wreck
var junk := 0                  ## piles collected from the wreck
var _timer := 0.0

func reset() -> void:
	done.clear()
	_contracts_done = 0
	stripped = 0
	junk = 0

func current() -> Dictionary:
	for g in GOALS:
		if not g.id in done and _available(g):
			return g
	return {}

## Goals that need a disabled game part are skipped
func _available(g: Dictionary) -> bool:
	match String(g.get("needs", "")):
		"wreck": return Config.ENABLE_WRECK
		"station": return Config.ENABLE_STATION
	return true

func step(dt: float) -> void:
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = 0.5
	var g := current()
	if g.is_empty() or not call(g.check):
		return
	done.append(g.id)
	if int(g.reward) > 0:
		EconomySystem.credits += int(g.reward)
		EconomySystem.book("Goal reached", int(g.reward))
	GameState.toast("Goal reached: %s%s" % [g.text.split(" (")[0], " (+%d Cr)" % g.reward if int(g.reward) > 0 else ""])
	if g.id == "debt":
		GameState.toast("You made it: the Rustbucket is yours. Space is open to you.")

func on_contract_done() -> void:
	_contracts_done += 1

# ---------------- Checks ----------------

func _g_suit() -> bool:
	for c in CrewSystem.crew:
		if c.suit != null:
			return true
	return false

func _g_junk() -> bool:
	return junk > 0

func _g_strip() -> bool:
	for e in EconomySystem.log_entries:
		if String(e.text).begins_with("Sale"):
			return true
	return stripped > 0

func _g_sell() -> bool:
	for e in EconomySystem.log_entries:
		if String(e.text).begins_with("Sale"):
			return true
	return false

func _g_solar() -> bool:
	return not PhysicsSystem.ship_devices("solar").is_empty()

func _g_book() -> bool:
	for c in CrewSystem.crew:
		if c.activity != null and c.activity.get("kind", "") == "study":
			return true
	return false

func _g_fly() -> bool:
	return PhysicsSystem.docked == "karman"

func _g_hire() -> bool:
	return CrewSystem.crew.size() > 1

func _g_contract() -> bool:
	return _contracts_done > 0

func _g_rate() -> bool:
	for e in EconomySystem.log_entries:
		if e.text == "Loan instalment":
			return true
	return false

func _g_debt() -> bool:
	return EconomySystem.debt <= 0

func to_data() -> Dictionary:
	return {"done": done, "contracts": _contracts_done, "stripped": stripped, "junk": junk}

func from_data(d: Dictionary) -> void:
	done.assign(d.get("done", []))
	_contracts_done = int(d.get("contracts", 0))
	stripped = int(d.get("stripped", 0))
	junk = int(d.get("junk", 0))
