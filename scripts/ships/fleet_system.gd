## Deine Flotte und was an den Orten liegt.
## - Wracks bleiben an ihrem Ort, wenn du wegfliegst
## - Schiffe kaufen (Werft am Kármán-Ring), wechseln, verkaufen
## - Ein Wrack als eigenes Schiff anmelden
extends Node

const REGISTER_FEE := 600

var ships: Array[Dictionary] = []   ## geparkte Schiffe {id, name, location, data}
var places: Dictionary = {}         ## Ort -> {"wreck": Daten oder null}
var current_name := "Rostlaube"
var current_id := 1
var next_id := 2

func reset() -> void:
	ships.clear()
	places.clear()
	current_name = "Rostlaube"
	current_id = 1
	next_id = 2

# ---------------- Wrack am Ort ablegen / anhängen ----------------

func leave(l: Dictionary) -> void:
	var g := ShipSystem.grid
	var tiles: Array = []
	var devs: Array = []
	var piles: Array = []
	for i in g.tiles.size():
		if g.zone[i] != 1:
			continue
		tiles.append([i, g.tiles[i], g.cables[i], g.cond[i], g.o2[i], g.n2[i], g.co2[i]])
		if g.devices.has(i):
			devs.append(g.devices[i].to_data())
		if g.piles.has(i):
			piles.append([i, g.piles[i].to_data()])
	places[l.id] = {"wreck": {"name": SalvageSystem.wreck_name, "tiles": tiles, "devices": devs, "piles": piles} if not tiles.is_empty() else null}
	SalvageSystem.clear()

func arrive(l: Dictionary) -> void:
	var g := ShipSystem.grid
	var place: Dictionary = places.get(l.id, {})
	var w = place.get("wreck")
	if w != null:
		for t in w.tiles:
			var i := int(t[0])
			g.tiles[i] = int(t[1]); g.cables[i] = int(t[2]); g.cond[i] = float(t[3])
			g.o2[i] = float(t[4]); g.n2[i] = float(t[5]); g.co2[i] = float(t[6]); g.zone[i] = 1
		for dd in w.devices:
			var dev := Device.from_data(dd)
			g.devices[g.idx(dev.pos)] = dev
		for entry in w.piles:
			var inv := Inventory.new()
			inv.from_data(entry[1])
			g.piles[int(entry[0])] = inv
		SalvageSystem.wreck_name = String(w.name)
		place.wreck = null
		EventBus.ship_changed.emit()
	elif l.kind == "debris":
		SalvageSystem.generate()
		GameState.toast("Ein Wrack aus dem Trümmerfeld treibt heran: " + SalvageSystem.wreck_name)

# ---------------- Schiffe ----------------

func here() -> String:
	return PhysicsSystem.docked

func ships_here() -> Array:
	return ships.filter(func(s): return s.location == here())

func switch_to(id: int) -> void:
	var target: Dictionary = {}
	for s in ships:
		if s.id == id:
			target = s
	if target.is_empty() or target.location != here():
		GameState.toast("Dieses Schiff liegt nicht hier.")
		return
	if not SalvageSystem.clearable():
		GameState.toast("Erst alle Crewmitglieder vom Wrack holen.")
		return
	var l := PhysicsSystem.loc(here())
	leave(l)
	for c in CrewSystem.crew:
		c.release_job()
		c.stop_activity()
		c.order = null
	ships.append({"id": current_id, "name": current_name, "location": l.id, "data": ShipSystem.grid.to_data()})
	ships = ships.filter(func(s): return s.id != id)
	ShipSystem.grid = ShipGrid.from_data(target.data)
	ShipConstructionSystem.jobs.clear()
	current_id = target.id
	current_name = target.name
	EventBus.ship_changed.emit()
	ShipPowerSystem.step(0.0)
	_place_crew()
	arrive(l)
	GameState.toast("Du bist jetzt an Bord der " + current_name + ".")

func _place_crew() -> void:
	var g := ShipSystem.grid
	var spots: Array[Vector2i] = []
	for i in g.tiles.size():
		if g.zone[i] == 0 and g.walkable(g.pos(i)) and g.pressure(i) > 50.0:
			spots.append(g.pos(i))
	if spots.is_empty():
		for i in g.tiles.size():
			if g.zone[i] == 0 and g.walkable(g.pos(i)):
				spots.append(g.pos(i))
	for k in CrewSystem.crew.size():
		var p: Vector2i = spots[mini(spots.size() - 1, k * 3)] if not spots.is_empty() else Vector2i(10, 10)
		CrewSystem.crew[k].pos = Vector2(p) + Vector2(0.5, 0.5)
		CrewSystem.crew[k].path.clear()

func ship_value(g: ShipGrid) -> int:
	var v := 0.0
	for i in g.tiles.size():
		if g.tiles[i] == 0 or g.zone[i] == 1:
			continue
		v += 25.0 if g.tiles[i] == ShipGrid.Tile.FLOOR else 45.0
	for i in g.devices:
		if g.zone[i] != 1:
			v += SalvageSystem.device_value(g.devices[i]) * 1.5
	return int(v)

func register_wreck() -> void:
	var g := ShipSystem.grid
	if SalvageSystem.wreck_name == "":
		GameState.toast("Hier ist kein Wrack.")
		return
	if not EconomySystem.terminal_online():
		GameState.toast("Das Handelsterminal ist offline.")
		return
	if EconomySystem.credits < REGISTER_FEE:
		GameState.toast("Nicht genug Credits für die Registrierung.")
		return
	if not SalvageSystem.clearable():
		GameState.toast("Erst alle Crewmitglieder vom Wrack holen.")
		return
	EconomySystem.credits -= REGISTER_FEE
	EconomySystem.book("Wrack als Schiff angemeldet: " + SalvageSystem.wreck_name, -REGISTER_FEE)
	var nw := ShipGrid.new(g.width, g.height)
	for i in g.tiles.size():
		if g.zone[i] != 1:
			continue
		nw.tiles[i] = g.tiles[i]; nw.cables[i] = g.cables[i]; nw.cond[i] = g.cond[i]
		nw.o2[i] = g.o2[i]; nw.n2[i] = g.n2[i]; nw.co2[i] = g.co2[i]
		if g.devices.has(i):
			g.devices[i].unknown = false
			g.devices[i].claimed_by = -1
			nw.devices[i] = g.devices[i]
		if g.piles.has(i):
			nw.piles[i] = g.piles[i]
	ships.append({"id": next_id, "name": SalvageSystem.wreck_name, "location": here(), "data": nw.to_data()})
	next_id += 1
	SalvageSystem.clear()
	GameState.toast("Angemeldet! Im Handelsterminal unter „Schiffe“ kannst du an Bord wechseln.")

## on_credit: mit Schiffskredit (Preis +20 % auf die Schulden)
func buy(kind: String, on_credit: bool = false) -> void:
	var st := PhysicsSystem.station()
	if st.is_empty() or not st.get("shipyard", false):
		GameState.toast("Hier gibt es keine Werft.")
		return
	var t: Dictionary = {}
	for s in PhysicsSystem.space.shipyard:
		if s.id == kind:
			t = s
	if on_credit:
		EconomySystem.debt += int(int(t.price) * 1.2)
		EconomySystem.book("Schiffskredit: " + t.name + " (+%d Cr Schulden)" % int(int(t.price) * 1.2), 0)
	else:
		if EconomySystem.credits < int(t.price):
			GameState.toast("Nicht genug Credits.")
			return
		EconomySystem.credits -= int(t.price)
		EconomySystem.book("Schiff gekauft: " + t.name, -int(t.price))
	var g := ShipGrid.new()
	_build_template(g, t)
	ships.append({"id": next_id, "name": t.name, "location": here(), "data": g.to_data()})
	next_id += 1
	GameState.toast(t.name + " gehört jetzt dir. Wechseln unter „Schiffe“.")

func sell(id: int) -> void:
	var st := PhysicsSystem.station()
	for s in ships:
		if s.id == id:
			if st.is_empty() or not st.get("shipyard", false) or s.location != here():
				GameState.toast("Schiffe kann man nur an einer Werft verkaufen, an der sie liegen.")
				return
			var v := int(ship_value(ShipGrid.from_data(s.data)) * 0.6)
			EconomySystem.credits += v
			EconomySystem.book("Schiff verkauft: " + s.name, v)
			ships = ships.filter(func(x): return x.id != id)
			return

func _build_template(g: ShipGrid, t: Dictionary) -> void:
	var w := int(t.w)
	var h := int(t.h)
	var x0 := (g.width - w) / 2
	var y0 := (g.height - h) / 2 - 4
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			var edge := x == x0 or y == y0 or x == x0 + w - 1 or y == y0 + h - 1
			g.set_tile(Vector2i(x, y), ShipGrid.Tile.WALL if edge else ShipGrid.Tile.FLOOR)
	var mid := x0 + w / 2
	for y in range(y0, y0 + h):
		g.set_tile(Vector2i(mid, y), ShipGrid.Tile.WALL)
	g.set_tile(Vector2i(mid, y0 + h / 2), ShipGrid.Tile.DOOR)
	var list := [["generator", x0 + 1, y0 + 1], ["battery", x0 + 2, y0 + 1], ["o2gen", x0 + 3, y0 + 1], ["scrubber", x0 + 1, y0 + h - 2],
		["airtank", x0 + 2, y0 + h - 2], ["bed", x0 + 3, y0 + h - 2], ["locker", x0 + 4, y0 + 1], ["helm", x0 + w - 2, y0 + 1],
		["fueltank", mid + 1, y0 + 1], ["thruster", x0 + w - 2, y0 + h - 2], ["crate", mid + 1, y0 + h - 2],
		["terminal", mid + 2, y0 + 1], ["food", mid + 2, y0 + h - 2]]
	if t.id == "bairn":
		list.append_array([["thruster", x0 + w - 3, y0 + h - 2], ["thruster", x0 + w - 4, y0 + h - 2], ["crate", mid + 3, y0 + h - 2],
			["crate", mid + 4, y0 + h - 2], ["bed", x0 + 5, y0 + h - 2], ["water", x0 + 5, y0 + 1]])
	for e in list:
		g.place_device(e[0], Vector2i(e[1], e[2]))
	for x in range(x0 + 1, x0 + w - 1):
		g.cables[g.idx(Vector2i(x, y0 + 1))] = 1
		g.cables[g.idx(Vector2i(x, y0 + h - 2))] = 1
	for y in range(y0 + 1, y0 + h - 1):
		g.cables[g.idx(Vector2i(x0 + 1, y))] = 1
	# Außentür und Steg zur Bergungsleine
	g.set_tile(Vector2i(x0, y0 + h / 2), ShipGrid.Tile.DOOR)
	for y in range(y0 + h / 2, Config.WRECK_TOP):
		g.set_tile(Vector2i(x0 - 1, y), ShipGrid.Tile.FLOOR)
		g.zone[g.idx(Vector2i(x0 - 1, y))] = 2
	for x in range(mini(x0 - 1, Config.WRECK_ENTRY_X), maxi(x0 - 1, Config.WRECK_ENTRY_X) + 1):
		g.set_tile(Vector2i(x, Config.WRECK_TOP - 1), ShipGrid.Tile.FLOOR)
		g.zone[g.idx(Vector2i(x, Config.WRECK_TOP - 1))] = 2
	for i in g.tiles.size():
		if g.holds_air(i) and g.zone[i] == 0:
			g.fill_air(i)
	for dev in g.devices.values():
		if dev.type == "crate":
			dev.inv.add("ration", 10)
			dev.inv.add("fuelcan", 2)
			break

func to_data() -> Dictionary:
	return {"ships": ships, "places": places, "current_name": current_name, "current_id": current_id, "next_id": next_id}

func from_data(d: Dictionary) -> void:
	ships.assign(d.ships)
	places = d.places
	current_name = String(d.current_name)
	current_id = int(d.current_id)
	next_id = int(d.next_id)
