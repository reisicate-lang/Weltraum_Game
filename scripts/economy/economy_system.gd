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
	local *= float(st.get("buys", {}).get(type, 1.0))
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
		s += item_value(it)
	return s

## Gegenstandswert eines Stapels aus den Spieldaten (Grundwert × Menge, nach Zustand).
## Unabhängig von Markt und Fähigkeiten; das Handelsangebot kann davon abweichen.
func item_value(it: Dictionary) -> int:
	return int(ItemSystem.item(it.type).value * int(it.get("qty", 1)) * (0.25 + 0.75 * float(it.get("cond", 100.0)) / 100.0))

## „Item Value: …“ für Figuren mit Business Admin, sonst leer (bisherige Anzeige bleibt)
func value_text(viewer: CrewMember, it: Dictionary) -> String:
	if not SkillSystem.acquired(viewer, SkillSystem.BUSINESS):
		return ""
	var v := item_value(it)
	var qty := int(it.get("qty", 1))
	if qty > 1:
		return "Item Value: %d Cr (%d Cr each)" % [v, item_value({"type": it.type, "qty": 1, "cond": it.get("cond", 100.0)})]
	return "Item Value: %d Cr" % v

# ---------------- Handel ----------------

## Verkaufen aus dem Terminal oder (am Markttresen der Station) aus einem Gepäck
func sell(type: String, qty: int, from: Inventory = null) -> void:
	var t := terminal()
	if from == null and (t == null or not terminal_online()):
		GameState.toast("The trade terminal is offline.", "bad")
		return
	if from != null and PhysicsSystem.station().is_empty():
		GameState.toast("You can only sell at a station.", "bad")
		return
	var src: Inventory = t.inv if from == null else from
	var total := 0
	var sold := 0
	# Schmuggelware: Kontrolle möglich
	if ItemSystem.item(type).contraband and not DialogueSystem.smuggle_check(trader()):
		var n := src.count(type)
		src.take(type, n)
		credits -= 300
		book("Contraband seized, fine", -300)
		QuestSystem.change_rep("patrol", -10.0)
		GameState.toast("Inspection! The contraband was seized. 300 Cr fine.", "bad")
		return
	for st in src.take(type, qty):
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
	book("Sale: %s ×%d" % [ItemSystem.item(type).display_name, sold], total)

func sell_all() -> void:
	var t := terminal()
	if t == null:
		return
	var types := {}
	for it in t.inv.items:
		types[it.type] = true
	for type in types:
		sell(type, 9999)

## Fertige Geräte, die jeder Stationsmarkt verkauft (Ostranauts: Ersatz-Transponder beim Ship Broker)
const SHOP_PACKED := ["pk_transponder"]

func buy(type: String, qty: int) -> void:
	var t := terminal()
	if t == null or not terminal_online():
		GameState.toast("The trade terminal is offline.", "bad")
		return
	var price := buy_price(type)
	var n := mini(mini(qty, credits / price), t.inv.room(type))
	if n <= 0:
		GameState.toast("Not enough credits." if credits < price else "There is no room left in the terminal.")
		return
	credits -= n * price
	supply[type] = supply.get(type, 0.0) - n * 0.5
	t.inv.add(type, n, 100.0)
	SkillSystem.train(trader(), "trade", 1.0)
	book("Purchase: %s ×%d" % [ItemSystem.item(type).display_name, n], -n * price)

func pay_debt(amount: int) -> void:
	var n := mini(mini(amount, credits), debt)
	if n <= 0:
		return
	credits -= n
	debt -= n
	book("Extra repayment", -n)
	if debt <= 0:
		GameState.toast("The loan is paid off! The ship is yours now.")

func buy_claim() -> void:
	if not Config.ENABLE_WRECK:
		GameState.toast("Salvage is temporarily disabled.")
		return
	if not terminal_online():
		GameState.toast("The trade terminal is offline.", "bad")
		return
	var fee: int = Config.CLAIM_FEE / 2 if DialogueSystem.claim_discount else Config.CLAIM_FEE
	if credits < fee:
		GameState.toast("Not enough credits for a salvage claim.")
		return
	credits -= fee
	DialogueSystem.claim_discount = false
	book("Salvage claim for a new wreck", -fee)
	# Das Wrack ist ein eigenes Ziel neben der Station: anfliegen und ankoppeln
	var site := FleetSystem.add_site(PhysicsSystem.docked if PhysicsSystem.docked != "" else "tycho")
	GameState.toast("Salvage claim bought: %s is now drifting next to the station (navigation → targets)." % String(site.name))

func scrap_hull() -> void:
	if not Config.ENABLE_WRECK:
		return
	if not terminal_online() or not SalvageSystem.clearable():
		GameState.toast("Not possible right now (terminal offline or crew on the wreck).")
		return
	var v := SalvageSystem.hull_value()
	credits += v
	book("Wreck scrapped", v)
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
		GameState.toast("For this you need: " + ItemSystem.device(station).display_name)
		return
	var key := g.idx(bench.pos)
	if ShipConstructionSystem.jobs.has(key):
		GameState.toast("Someone is already working at the workbench.")
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
	# Schulden pausiert: die Frist bis zur nächsten Rate bleibt stehen
	if Settings.debt_paused and debt > 0:
		next_payment += _dt
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
			book("Docking fee", -Config.DOCK_FEE)
		elif not Settings.debt_paused:
			debt += Config.DOCK_FEE
			book("Docking fee: no money, %d Cr added to the debt" % Config.DOCK_FEE, 0)
	if debt > 0 and GameState.time >= next_payment:
		next_payment += Config.PAYMENT_DAYS * 1440.0
		var rate := mini(int(Config.PAYMENT * payment_factor), debt)
		if credits >= rate:
			credits -= rate
			debt -= rate
			book("Loan instalment", -rate)
			GameState.toast("Loan instalment paid: %d Cr." % rate)
		else:
			strikes += 1
			var fee := int(debt * Config.LATE_FEE)
			debt += fee
			book("Instalment missed: %d Cr penalty interest" % fee, 0)
			if strikes >= Config.MAX_STRIKES:
				over = true
				TimeSystem.set_speed(0)
				game_over.emit("Repossessed", "You missed three loan instalments. The bank has seized your ship.")
			else:
				GameState.toast("Instalment missed! %d Cr penalty interest. %d more until repossession." % [fee, Config.MAX_STRIKES - strikes], "bad")

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
