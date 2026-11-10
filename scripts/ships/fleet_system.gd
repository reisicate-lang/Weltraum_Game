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

## Wrack am Ort ablegen. Gespeichert relativ zur Wracktür, damit es beim
## Wiederkommen an jede freie Schleuse nach unten passt.
func leave(l: Dictionary) -> void:
	places[l.id] = {"wreck": capture()}
	SalvageSystem.clear()

## Das aktuelle Wrack als Daten (relativ zur Wracktür), oder null
func capture():
	var g := ShipSystem.grid
	var e := SalvageSystem.entry
	if e.x < 0:
		e = LEGACY_ENTRY
	var tiles: Array = []
	var devs: Array = []
	var piles: Array = []
	for i in g.tiles.size():
		if g.zone[i] != 1:
			continue
		var r := g.pos(i) - e
		tiles.append([r.x, r.y, g.tiles[i], g.cables[i], g.cond[i], g.o2[i], g.n2[i], g.co2[i]])
		if g.devices.has(i):
			var dd: Dictionary = g.devices[i].to_data()
			dd.x = r.x
			dd.y = r.y
			devs.append(dd)
		if g.piles.has(i):
			piles.append([r.x, r.y, g.piles[i].to_data()])
	if tiles.is_empty():
		return null
	return {"name": SalvageSystem.wreck_name if SalvageSystem.wreck_name != "" else "Altes Wrack", "rel": true, "tiles": tiles,
		"devices": devs, "piles": piles, "investigated": SalvageSystem.investigated, "cause": SalvageSystem.cause}

## Alte Spielstände (vor den Andockschleusen) bereinigen:
## 1) Außensteg und Bergungsleine (Zone 2) entfernen, Haufen darauf ins Schiff legen
## 2) Schiff ohne Andockschleuse: rechts und unten je eine nachrüsten
## 3) Wrack ohne Verbindung an die Schleuse nach unten hängen (sonst am Ort ablegen)
func migrate_docking() -> void:
	var g := ShipSystem.grid
	var changed := false
	var spot := ShipConstructionSystem.drop_spot(ShipSystem.spawn_point())
	for i in g.tiles.size():
		if g.zone[i] != 2:
			continue
		if g.piles.has(i):
			for it in g.piles[i].items:
				g.drop_items(spot, it.type, it.qty, it.cond, it.get("data"))
			g.piles.erase(i)
		g.devices.erase(i)
		ShipConstructionSystem.jobs.erase(i)
		g.tiles[i] = ShipGrid.Tile.SPACE
		g.cables[i] = 0
		g.o2[i] = 0.0; g.n2[i] = 0.0; g.co2[i] = 0.0
		g.zone[i] = 0
		changed = true
	if ShipSystem.ports().is_empty():
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var p := _port_spot(g, d)
			if p.x >= 0:
				g.set_tile(p, ShipGrid.Tile.DOOR)
				g.place_device("dockport", p)
				changed = true
		if changed:
			GameState.toast("Alter Spielstand: Steg entfernt, Andockschleusen nachgerüstet.")
	# Wrack abgeschaltet: vorhandenes Wrack am Ort ablegen (nicht löschen), Felder entfernen
	if not Config.ENABLE_WRECK:
		var parked = capture()
		if parked != null:
			places[PhysicsSystem.docked if PhysicsSystem.docked != "" else "tycho"] = {"wreck": parked}
			SalvageSystem.clear()
			changed = true
	elif SalvageSystem.port < 0:
		var w = capture()
		if w != null:
			SalvageSystem.clear()
			if not _attach_stored(w):
				places[PhysicsSystem.docked if PhysicsSystem.docked != "" else "tycho"] = {"wreck": w}
	if changed:
		EventBus.ship_changed.emit()

## Bester Platz für eine Schleuse in Richtung d: gültige Außenwand, Innenfeld frei, möglichst mittig
func _port_spot(g: ShipGrid, d: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var center := Vector2.ZERO
	var n := 0
	for i in g.tiles.size():
		if g.zone[i] == 0 and g.tiles[i] != ShipGrid.Tile.SPACE:
			center += Vector2(g.pos(i))
			n += 1
	center /= maxf(1.0, n)
	for i in g.tiles.size():
		var p := g.pos(i)
		if g.tiles[i] != ShipGrid.Tile.WALL or g.zone[i] != 0 or g.devices.has(i):
			continue
		if ShipSystem.port_dir(p) != d or not g.walkable(p - d):
			continue
		if best.x < 0 or Vector2(p).distance_to(center) < Vector2(best).distance_to(center):
			best = p
	return best

## Frühere Spielstände: Wracktür lag fest bei (20, 30)
const LEGACY_ENTRY := Vector2i(20, 30)

## Gespeichertes Wrack an eine freie Schleuse nach unten hängen. false = passt nicht.
func _attach_stored(w: Dictionary) -> bool:
	var g := ShipSystem.grid
	var pt := SalvageSystem.free_port()
	if pt.is_empty():
		return false
	var e: Vector2i = pt.pos + Vector2i(0, 1)
	var rel: bool = w.get("rel", false)
	# Alte Daten: absolute Feld-Indizes, Tür bei LEGACY_ENTRY
	var cells: Array = []
	for t in w.tiles:
		var q: Vector2i = (Vector2i(int(t[0]), int(t[1])) if rel else g.pos(int(t[0])) - LEGACY_ENTRY) + e
		if not g.in_bounds(q) or g.get_tile(q) != ShipGrid.Tile.SPACE or g.zone[g.idx(q)] != 0:
			return false
		cells.append([q, t])
	for c in cells:
		var i := g.idx(c[0])
		var t: Array = c[1]
		var o := 1 if rel else 0
		g.tiles[i] = int(t[o + 1]); g.cables[i] = int(t[o + 2]); g.cond[i] = float(t[o + 3])
		g.o2[i] = float(t[o + 4]); g.n2[i] = float(t[o + 5]); g.co2[i] = float(t[o + 6]); g.zone[i] = 1
	for dd in w.devices:
		var d2: Dictionary = dd.duplicate()
		var q: Vector2i = (Vector2i(int(dd.x), int(dd.y)) if rel else Vector2i(int(dd.x), int(dd.y)) - LEGACY_ENTRY) + e
		d2.x = q.x
		d2.y = q.y
		var dev := Device.from_data(d2)
		g.devices[g.idx(dev.pos)] = dev
	for entry in w.piles:
		var inv := Inventory.new()
		var q: Vector2i
		if rel:
			q = Vector2i(int(entry[0]), int(entry[1])) + e
			inv.from_data(entry[2])
		else:
			q = g.pos(int(entry[0])) - LEGACY_ENTRY + e
			inv.from_data(entry[1])
		g.piles[g.idx(q)] = inv
	SalvageSystem._link(g, pt, e)
	SalvageSystem.wreck_name = String(w.name)
	SalvageSystem.investigated = bool(w.get("investigated", false))
	SalvageSystem.cause = String(w.get("cause", ""))
	return true

func arrive(l: Dictionary) -> void:
	if not Config.ENABLE_WRECK:
		return
	var place: Dictionary = places.get(l.id, {})
	var w = place.get("wreck")
	if w != null:
		# Das Wrack wartet am Ort, bis eine freie Schleuse nach unten da ist
		if _attach_stored(w):
			place.wreck = null
			EventBus.ship_changed.emit()
		else:
			GameState.toast("Das Wrack „%s“ liegt hier. Zum Andocken fehlt eine freie Andockschleuse nach unten." % String(w.name))
	elif l.kind == "asteroid":
		if SalvageSystem.generate_asteroid():
			GameState.toast("Ein Felsbrocken hängt an der Schleuse. Abreißen bringt Eis und Erz.")
	elif l.kind == "outpost":
		if not SalvageSystem.generate():
			return
		# Außenposten: mehr Schlösser, mehr Beute
		for dev in ShipSystem.grid.devices.values():
			if dev.type == "crate" and ShipSystem.grid.zone[ShipSystem.grid.idx(dev.pos)] == 1:
				dev.lock_level = maxi(dev.lock_level, randi_range(1, 3))
				dev.inv.add(["datachip", "cell", "motor", "boltgun", "genemod"].pick_random(), 1, randf_range(60.0, 95.0))
		GameState.toast("Der Außenposten ist verlassen. Die Lagerräume sind verschlossen.")
	elif l.kind == "debris":
		if SalvageSystem.generate():
			GameState.toast("Ein Wrack aus dem Trümmerfeld dockt an der Schleuse an: " + SalvageSystem.wreck_name)

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
	if not StationSystem.clearable():
		GameState.toast("Erst alle Crewmitglieder von der Station zurück an Bord holen.")
		return
	var l := PhysicsSystem.loc(here())
	StationSystem.clear()
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
	StationSystem.build(l.id)
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
		if g.tiles[i] == 0 or g.foreign(i):
			continue
		v += 25.0 if g.tiles[i] == ShipGrid.Tile.FLOOR else 45.0
	for i in g.devices:
		if not g.foreign(i):
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
	# Zwei Andockschleusen: rechts für Stationen, unten für Wracks
	for p in [Vector2i(x0 + w - 1, y0 + h / 2), Vector2i(mid - 1, y0 + h - 1)]:
		g.set_tile(p, ShipGrid.Tile.DOOR)
		g.place_device("dockport", p)
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
