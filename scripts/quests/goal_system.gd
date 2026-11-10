## Ziele (roter Faden für neue Spieler). Jedes Ziel wird automatisch
## erkannt, gibt eine kleine Belohnung und schaltet das nächste frei.
extends Node

## Ziel-Prüfungen. "check" ist der Name einer Funktion unten.
const GOALS := [
	{"id": "suit", "text": "Lass Mira einen Raumanzug anziehen (plane etwas im Wrack unter der Andockschleuse, z. B. Abreißen X)", "check": "_g_suit", "reward": 50},
	{"id": "junk", "text": "Sammle Schrott aus dem Wrack ein (Werkzeug Einsammeln, Q)", "check": "_g_junk", "reward": 80},
	{"id": "strip", "text": "Reiß ein Gerät im Wrack ab (Werkzeug Abreißen, X)", "check": "_g_strip", "reward": 80},
	{"id": "sell", "text": "Verkaufe Bergungsgut am Handelsterminal im Cockpit", "check": "_g_sell", "reward": 100},
	{"id": "solar", "text": "Baue ein Solarpanel draußen im Vakuum, z. B. auf einem Boden vor der Luftschleuse (spart Brennstoff)", "check": "_g_solar", "reward": 150},
	{"id": "book", "text": "Lass jemanden ein Lehrbuch lesen (im Terminal kaufen, in eine Kiste legen)", "check": "_g_book", "reward": 100},
	{"id": "fly", "text": "Fliege zum Kármán-Ring (Taste N, Reisen)", "check": "_g_fly", "reward": 200},
	{"id": "hire", "text": "Heuere ein Crewmitglied an (Terminal, Reiter Crew)", "check": "_g_hire", "reward": 150},
	{"id": "contract", "text": "Erfülle einen Auftrag (Terminal, Reiter Aufträge)", "check": "_g_contract", "reward": 200},
	{"id": "rate", "text": "Bezahle eine Kreditrate pünktlich", "check": "_g_rate", "reward": 250},
	{"id": "debt", "text": "Zahle den Kredit vollständig ab – das Schiff gehört dir", "check": "_g_debt", "reward": 0},
]

var done: Array[String] = []
var _contracts_done := 0
var stripped := 0              ## im Wrack abgerissene Geräte
var junk := 0                  ## aus dem Wrack eingesammelte Haufen
var _timer := 0.0

func reset() -> void:
	done.clear()
	_contracts_done = 0
	stripped = 0
	junk = 0

func current() -> Dictionary:
	for g in GOALS:
		if not g.id in done:
			return g
	return {}

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
		EconomySystem.book("Ziel erreicht", int(g.reward))
	GameState.toast("Ziel erreicht: %s%s" % [g.text.split(" (")[0], " (+%d Cr)" % g.reward if int(g.reward) > 0 else ""])
	if g.id == "debt":
		GameState.toast("Du hast es geschafft: Die Rostlaube gehört dir. Das Weltall steht dir offen.")

func on_contract_done() -> void:
	_contracts_done += 1

# ---------------- Prüfungen ----------------

func _g_suit() -> bool:
	for c in CrewSystem.crew:
		if c.suit != null:
			return true
	return false

func _g_junk() -> bool:
	return junk > 0

func _g_strip() -> bool:
	for e in EconomySystem.log_entries:
		if String(e.text).begins_with("Verkauf"):
			return true
	return stripped > 0

func _g_sell() -> bool:
	for e in EconomySystem.log_entries:
		if String(e.text).begins_with("Verkauf"):
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
		if e.text == "Kreditrate":
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
