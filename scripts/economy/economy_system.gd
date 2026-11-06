## Geld, Markt und Schulden. Handel läuft über das Handelsterminal.
## Preise schwanken täglich und fallen, wenn du viel einer Sorte verkaufst.
## Alle 7 Tage ist eine Kreditrate fällig; nach 3 verpassten Raten Pfändung.
extends Node

signal game_over(title: String, text: String)

var credits := 0
var debt := 0
var next_payment := 0.0
var strikes := 0
var prices := {}   ## Preisfaktor pro Sorte
var supply := {}   ## zuletzt verkaufte Menge (drückt den Preis)
var next_day := 1440.0
var log_entries: Array[Dictionary] = []
var over := false
var recipes: Array = []
## Faktor auf die Kreditrate (Verhandlung mit dem Bankier)
var payment_factor := 1.0

func _ready() -> void:
	var f := FileAccess.open("res://data/recipes.json", FileAccess.READ)
	if f != null:
		recipes = JSON.parse_string(f.get_as_text())

func reset() -> void:
	credits = Config.START_CREDITS
	debt = Config.START_DEBT
	next_payment = Config.PAYMENT_DAYS * 1440.0
	strikes = 0
	next_day = 1440.0
	log_entries.clear()
	over = false
	payment_factor = 1.0
	for id in ItemSystem.items:
		prices[id] = randf_range(0.85, 1.15)
		supply[id] = 0.0

func book(text: String, amount: int) -> void:
	log_entries.push_front({"text": text, "amount": amount})
	if log_entries.size() > 30:
		log_entries.resize(30)

func terminal() -> Device:
	for dev in ShipSystem.grid.devices.values():
		if dev.type == "terminal" and ShipSystem.grid.zone[ShipSystem.grid.idx(dev.pos)] != 1:
			return dev
	return null

## Handel geht nur angedockt an einer Station
func terminal_online() -> bool:
	var t := terminal()
	return t != null and t.powered and not t.broken and not PhysicsSystem.station().is_empty()

# ---------------- Preise ----------------

func market_price(type: String) -> float:
	var glut: float = 1.0 / (1.0 + float(supply.get(type, 0.0)) / 20.0)
	var st := PhysicsSystem.station()
	var local: float = st.get("market", 1.0)
	# Schwarzmarkt: Datenchips bringen dort das Doppelte
	if st.get("black", false) and type == "datachip":
		local *= 2.0
	if st.get("black", false) and ItemSystem.item(type).contraband:
		local *= 2.5
	return ItemSystem.item(type).value * prices.get(type, 1.0) * glut * local * QuestSystem.price_factor(type)

## Wer handelt? Die ausgewählte Figur (sonst die Spielerfigur)
func trader() -> CrewMember:
	return GameState.selected if GameState.selected != null else CrewSystem.player()

func buy_price(type: String) -> int:
	var disc := minf(0.3, SkillSystem.effect(trader(), "buy_discount"))
	return int(ceil(market_price(type) * Config.BUY_MARKUP * (1.0 - disc) * negotiated_factor(false)))

func sell_price(it: Dictionary) -> int:
	var bonus := SkillSystem.effect(trader(), "sell_bonus")
	if PhysicsSystem.station().get("black", false):
		bonus += SkillSystem.effect(trader(), "black_bonus")
	if it.type == "datachip" and SkillSystem.any_mastered("software"):
		bonus += 0.25
	return int(market_price(it.type) * Config.SELL_FACTOR * (0.2 + 0.8 * it.cond / 100.0) * it.qty * (1.0 + bonus) * negotiated_factor(true))

## Ausgehandelte bessere Preise (Überzeugen) gelten bis zum Ende des Tages
var deal_until := 0.0
var deal_bonus := 0.0
func negotiated_factor(selling: bool) -> float:
	if GameState.time > deal_until:
		return 1.0
	return 1.0 + deal_bonus if selling else 1.0 - deal_bonus * 0.5

func inv_value(inv: Inventory) -> int:
	var s := 0
	for it in inv.items:
		s += int(ItemSystem.item(it.type).value * it.qty * (0.25 + 0.75 * it.cond / 100.0))
	return s

# ---------------- Handel ----------------

func sell(type: String, qty: int) -> void:
	var t := terminal()
	if t == null or not terminal_online():
		GameState.toast("Das Handelsterminal ist offline.", "bad")
		return
	var total := 0
	var sold := 0
	# Schmuggelware: Kontrolle möglich
	if ItemSystem.item(type).contraband and not DialogueSystem.smuggle_check(trader()):
		var n := t.inv.count(type)
		t.inv.take(type, n)
		credits -= 300
		book("Schmuggelware beschlagnahmt, Strafe", -300)
		QuestSystem.change_rep("patrol", -10.0)
		GameState.toast("Kontrolle! Die Schmuggelware wurde beschlagnahmt. 300 Cr Strafe.", "bad")
		return
	for st in t.inv.take(type, qty):
		total += sell_price(st)
		sold += st.qty
	if sold == 0:
		return
	credits += total
	supply[type] = supply.get(type, 0.0) + sold
	QuestSystem.change_rep(QuestSystem.faction_of(PhysicsSystem.docked), 0.5)
	if ItemSystem.item(type).contraband:
		QuestSystem.change_rep("syndicate", 3.0)
		QuestSystem.change_rep("patrol", -2.0)
	SkillSystem.train(trader(), "trade", 2.0)
	book("Verkauf: %s ×%d" % [ItemSystem.item(type).display_name, sold], total)

func sell_all() -> void:
	var t := terminal()
	if t == null:
		return
	var types := {}
	for it in t.inv.items:
		types[it.type] = true
	for type in types:
		sell(type, 9999)

func buy(type: String, qty: int) -> void:
	var t := terminal()
	if t == null or not terminal_online():
		GameState.toast("Das Handelsterminal ist offline.", "bad")
		return
	var price := buy_price(type)
	var n := mini(mini(qty, credits / price), t.inv.room(type))
	if n <= 0:
		GameState.toast("Nicht genug Credits." if credits < price else "Im Terminal ist kein Platz mehr.")
		return
	credits -= n * price
	supply[type] = supply.get(type, 0.0) - n * 0.5
	t.inv.add(type, n, 100.0)
	SkillSystem.train(trader(), "trade", 1.0)
	book("Kauf: %s ×%d" % [ItemSystem.item(type).display_name, n], -n * price)

func pay_debt(amount: int) -> void:
	var n := mini(mini(amount, credits), debt)
	if n <= 0:
		return
	credits -= n
	debt -= n
	book("Sondertilgung", -n)
	if debt <= 0:
		GameState.toast("Der Kredit ist abbezahlt! Das Schiff gehört jetzt dir.")

func buy_claim() -> void:
	if not terminal_online():
		GameState.toast("Das Handelsterminal ist offline.", "bad")
		return
	var fee: int = Config.CLAIM_FEE / 2 if DialogueSystem.claim_discount else Config.CLAIM_FEE
	if credits < fee:
		GameState.toast("Nicht genug Credits für ein Bergungsrecht.")
		return
	if not SalvageSystem.clearable():
		GameState.toast("Erst alle Crewmitglieder vom Wrack holen.")
		return
	credits -= fee
	DialogueSystem.claim_discount = false
	book("Bergungsrecht für neues Wrack", -fee)
	SalvageSystem.clear()
	SalvageSystem.generate()
	GameState.toast("Ein neues Wrack wurde an die Bergungsleine geschleppt: " + SalvageSystem.wreck_name)

func scrap_hull() -> void:
	if not terminal_online() or not SalvageSystem.clearable():
		GameState.toast("Geht gerade nicht (Terminal offline oder Crew auf dem Wrack).")
		return
	var v := SalvageSystem.hull_value()
	credits += v
	book("Wrack verschrottet", v)
	SalvageSystem.clear()

## Werkbank-Auftrag anlegen
func craft(recipe_id: String) -> void:
	var g := ShipSystem.grid
	var bench: Device = null
	var station: String = recipe(recipe_id).get("station", "workbench")
	for dev in g.devices.values():
		if dev.type == station and g.zone[g.idx(dev.pos)] != 1:
			bench = dev
	if bench == null:
		GameState.toast("Dafür brauchst du: " + ItemSystem.device(station).display_name)
		return
	var key := g.idx(bench.pos)
	if ShipConstructionSystem.jobs.has(key):
		GameState.toast("An der Werkbank wird schon gearbeitet.")
		return
	ShipConstructionSystem.jobs[key] = {"kind": "craft", "recipe": recipe_id, "x": bench.pos.x, "y": bench.pos.y,
		"need": float(recipe(recipe_id).time), "progress": 0.0, "claimed_by": -1, "retry_at": 0.0, "paid": false}

func recipe(id: String) -> Dictionary:
	for r in recipes:
		if r.id == id:
			return r
	return {}

# ---------------- Zeit ----------------

func step(_dt: float) -> void:
	if over:
		return
	while GameState.time >= next_day:
		next_day += 1440.0
		for id in prices:
			prices[id] = clampf(prices[id] * (1.0 + randf_range(-1.0, 1.0) * Config.PRICE_DRIFT), 0.5, 1.6)
			supply[id] = supply[id] * 0.7
		NPCSystem.pay_wages()
		if PhysicsSystem.station().is_empty():
			continue
		if credits >= Config.DOCK_FEE:
			credits -= Config.DOCK_FEE
			book("Liegegebühr", -Config.DOCK_FEE)
		else:
			debt += Config.DOCK_FEE
			book("Liegegebühr: kein Geld, %d Cr auf die Schulden" % Config.DOCK_FEE, 0)
	if debt > 0 and GameState.time >= next_payment:
		next_payment += Config.PAYMENT_DAYS * 1440.0
		var rate := mini(int(Config.PAYMENT * payment_factor), debt)
		if credits >= rate:
			credits -= rate
			debt -= rate
			book("Kreditrate", -rate)
			GameState.toast("Kreditrate bezahlt: %d Cr." % rate)
		else:
			strikes += 1
			var fee := int(debt * Config.LATE_FEE)
			debt += fee
			book("Rate verpasst: %d Cr Strafzins" % fee, 0)
			if strikes >= Config.MAX_STRIKES:
				over = true
				TimeSystem.set_speed(0)
				game_over.emit("Gepfändet", "Du hast drei Kreditraten verpasst. Die Bank hat dein Schiff beschlagnahmt.")
			else:
				GameState.toast("Rate verpasst! %d Cr Strafzins. Noch %d bis zur Pfändung." % [fee, Config.MAX_STRIKES - strikes], "bad")

func to_data() -> Dictionary:
	return {"payment_factor": payment_factor, "claim_discount": DialogueSystem.claim_discount, "rate_lowered": DialogueSystem.rate_lowered,
		"credits": credits, "debt": debt, "next_payment": next_payment, "strikes": strikes, "prices": prices,
		"supply": supply, "next_day": next_day, "log": log_entries, "wreck": SalvageSystem.wreck_name}

func from_data(d: Dictionary) -> void:
	credits = int(d.credits); debt = int(d.debt); next_payment = float(d.next_payment); strikes = int(d.strikes)
	prices = d.prices; supply = d.supply; next_day = float(d.next_day)
	log_entries.assign(d.log)
	SalvageSystem.wreck_name = String(d.wreck)
	over = false
	payment_factor = float(d.get("payment_factor", 1.0))
	DialogueSystem.claim_discount = bool(d.get("claim_discount", false))
	DialogueSystem.rate_lowered = bool(d.get("rate_lowered", false))
