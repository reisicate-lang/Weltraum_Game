## Your fleet and what lies at the places.
## - wrecks stay at their place when you fly away
## - buy ships (shipyard at the Kármán Ring), switch, sell
## - register a wreck as your own ship
extends Node

const REGISTER_FEE := 600

var ships: Array[Dictionary] = []   ## parked ships {id, name, location, data}
var places: Dictionary = {}         ## place -> {"wreck": data or null}
## Wrecks as their own navigation targets: places {id, kind: "wreck", name, near, off, desc}.
## The wreck itself is in places[id]; it is only attached to the ship when coupling.
var sites: Array = []
var next_site := 1
const WRECK_KINDS := ["wreck", "debris", "outpost", "asteroid"]
var current_name := "Rustbucket"
## Name in the public register (Ostranauts: Ogiso's Register). Renaming at the
## navigation console only changes the ship's name; it is registered with the shipyard's Ship Rating service.
var registered_name := "Rustbucket"
## Hull registry ID (Ostranauts Ship Building 2), e.g. "J-YV16": fixed, also when renaming
var registry_id := ""
var current_id := 1
var next_id := 2

func reset() -> void:
	ships.clear()
	places.clear()
	current_name = "Rustbucket"
	registered_name = "Rustbucket"
	registry_id = new_registry_id()
	current_id = 1
	next_id = 2
	sites.clear()
	next_site = 1
	PhysicsSystem.set_extra_locations(sites)

# ---------------- Storing / attaching the wreck at a place ----------------

## Store the wreck at the place. Saved relative to the wreck door (x along the port, y outwards),
## so it fits any free port when you come back. If it hung at a station
## (old save), it becomes its own wreck target next to this station.
func leave(l: Dictionary) -> void:
	var w = capture()
	if String(l.get("kind", "")) in WRECK_KINDS:
		places[l.id] = {"wreck": w}
	elif w != null:
		add_site(String(l.id), w)
	SalvageSystem.clear()

## New wreck target next to the place near (about 8 km away), optionally with a finished wreck
func add_site(near: String, data = null) -> Dictionary:
	var ang := randf() * TAU
	var name := String(data.get("name", "")) if data is Dictionary else ""
	if name == "":
		name = SalvageSystem.NAMES.pick_random()
	var l := {"id": "wreck_%d" % next_site, "kind": "wreck", "name": "Wreck " + name, "wreck_name": name, "near": near,
		"off": [cos(ang) * 8.0, sin(ang) * 8.0], "desc": "Drifting wreck. Fly there, slow down, line up the port and dock; then you can walk aboard."}
	next_site += 1
	sites.append(l)
	places[l.id] = {"wreck": data}
	PhysicsSystem.set_extra_locations(sites)
	return l

## Coupling to a wreck target: attach the stored wreck to the port or create a new one.
## false = no free port or no room (then no wreck zone at the ship)
func attach_site(l: Dictionary) -> bool:
	var place: Dictionary = places.get(l.id, {})
	var w = place.get("wreck")
	if w != null:
		if not _attach_stored(w):
			GameState.toast("The wreck does not fit the docking port.", "bad")
			return false
		place.wreck = null
	else:
		if not SalvageSystem.generate():
			return false
		SalvageSystem.wreck_name = String(l.get("wreck_name", SalvageSystem.wreck_name))
	EventBus.ship_changed.emit()
	return true

## The current wreck as data (relative to the wreck door), or null
func capture():
	var g := ShipSystem.grid
	var e := SalvageSystem.entry
	if e.x < 0:
		e = LEGACY_ENTRY
	# Port frame: d = away from the ship (port → wreck door), a = along it
	var d := Vector2i(0, 1)
	if SalvageSystem.port >= 0 and SalvageSystem.entry.x >= 0:
		var dd := SalvageSystem.entry - g.pos(SalvageSystem.port)
		if absi(dd.x) + absi(dd.y) == 1:
			d = dd
	var a := Vector2i(d.y, -d.x)
	var tiles: Array = []
	var devs: Array = []
	var piles: Array = []
	for i in g.tiles.size():
		if g.zone[i] != 1:
			continue
		var rw := g.pos(i) - e
		var r := Vector2i(rw.x * a.x + rw.y * a.y, rw.x * d.x + rw.y * d.y)
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
	return {"name": SalvageSystem.wreck_name if SalvageSystem.wreck_name != "" else "Old wreck", "rel": true, "scale": Config.GRID_SCALE, "tiles": tiles,
		"devices": devs, "piles": piles, "investigated": SalvageSystem.investigated, "cause": SalvageSystem.cause}

## Clean up old saves (from before the docking ports):
## 1) remove the outer gangway and the salvage line (zone 2), put piles on them into the ship
## 2) ship without a docking port: retrofit one each on the right and at the bottom
## 3) store an unconnected wreck as its own wreck target; seal old docking ports
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
	if changed:
		GameState.toast("Old save: gangway removed. Ships now dock at the airlock.")
	var here_id := PhysicsSystem.docked if PhysicsSystem.docked != "" else "tycho"
	# Wreck disabled or without a connection (very old save): store it as its own wreck target
	if not Config.ENABLE_WRECK or SalvageSystem.port < 0:
		var parked = capture()
		if parked != null:
			SalvageSystem.clear()
			if String(PhysicsSystem.loc(here_id).get("kind", "")) in WRECK_KINDS:
				places[here_id] = {"wreck": parked}
			else:
				add_site(here_id, parked)
			changed = true
	# Wrecks that used to lie at a station: their own wreck targets next to it
	for id in places.keys():
		var pw = places[id].get("wreck") if places[id] is Dictionary else null
		if pw != null and not id in sites.map(func(x): return x.id) and not String(PhysicsSystem.loc(String(id)).get("kind", "")) in WRECK_KINDS:
			places[id].wreck = null
			add_site(String(id), pw)
	# Seal former docking ports without a connection right away (connected ones after releasing)
	ShipSystem.retire_legacy_ports()
	if changed:
		EventBus.ship_changed.emit()

## Best place for an airlock in direction d: valid outer wall, inner tile free, as central as possible
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
		if g.tiles[i] != ShipGrid.Tile.WALL or g.zone[i] != 0 or g.occupied(g.pos(i)):
			continue
		if g.dock_check(p).dir != d:
			continue
		if best.x < 0 or Vector2(p).distance_to(center) < Vector2(best).distance_to(center):
			best = p
	return best

## Earlier saves: the wreck door was fixed at (20, 30)
const LEGACY_ENTRY := Vector2i(20, 30)

## Attach a stored wreck to a free docking port (any direction). false = does not fit.
func _attach_stored(w: Dictionary) -> bool:
	# Stored in an earlier save (twice as large tiles): refine first
	if int(w.get("scale", 1)) < Config.GRID_SCALE:
		w = refine_stored(w)
	var g := ShipSystem.grid
	var pt := SalvageSystem.free_port()
	if pt.is_empty():
		return false
	var d: Vector2i = pt.dir
	var a := Vector2i(d.y, -d.x)
	var e: Vector2i = pt.pos + d
	# Port frame → grid (x along, y outwards)
	var to_grid := func(r: Vector2i) -> Vector2i:
		return e + a * r.x + d * r.y
	var rel: bool = w.get("rel", false)
	# Old data: absolute tile indices, door at LEGACY_ENTRY
	var cells: Array = []
	for t in w.tiles:
		var q: Vector2i = to_grid.call(Vector2i(int(t[0]), int(t[1])) if rel else g.pos(int(t[0])) - LEGACY_ENTRY)
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
		var q: Vector2i = to_grid.call(Vector2i(int(dd.x), int(dd.y)) if rel else Vector2i(int(dd.x), int(dd.y)) - LEGACY_ENTRY)
		d2.x = q.x
		d2.y = q.y
		var dev := Device.from_data(d2)
		g.devices[g.idx(dev.pos)] = dev
	for entry in w.piles:
		var inv := Inventory.new()
		var q: Vector2i
		if rel:
			q = to_grid.call(Vector2i(int(entry[0]), int(entry[1])))
			inv.from_data(entry[2])
		else:
			q = to_grid.call(g.pos(int(entry[0])) - LEGACY_ENTRY)
			inv.from_data(entry[1])
		g.piles[g.idx(q)] = inv
	SalvageSystem._link(g, pt, e)
	SalvageSystem.wreck_name = String(w.name)
	SalvageSystem.investigated = bool(w.get("investigated", false))
	SalvageSystem.cause = String(w.get("cause", ""))
	return true

## Stored wreck from an earlier save into the fine grid (relative to the wreck door)
func refine_stored(w: Dictionary) -> Dictionary:
	var k := Config.GRID_SCALE
	var rel: bool = w.get("rel", false)
	var o := 1 if rel else 0
	var cw := Config.WORLD_W / k
	var at := func(t) -> Vector2i:
		return Vector2i(int(t[0]), int(t[1])) if rel else Vector2i(int(t[0]) % cw, int(t[0]) / cw) - LEGACY_ENTRY
	var lo := Vector2i(0, 0)
	var hi := Vector2i(0, 0)
	for t in w.tiles:
		var r: Vector2i = at.call(t)
		lo = Vector2i(mini(lo.x, r.x), mini(lo.y, r.y))
		hi = Vector2i(maxi(hi.x, r.x), maxi(hi.y, r.y))
	var off := -lo + Vector2i(2, 2)
	var cg := ShipGrid.new(hi.x - lo.x + 5, hi.y - lo.y + 5)
	for t in w.tiles:
		var i := cg.idx(at.call(t) + off)
		cg.tiles[i] = int(t[o + 1]); cg.cables[i] = int(t[o + 2]); cg.cond[i] = float(t[o + 3])
		cg.o2[i] = float(t[o + 4]); cg.n2[i] = float(t[o + 5]); cg.co2[i] = float(t[o + 6]); cg.zone[i] = 1
	for dd in w.devices:
		var d2: Dictionary = dd.duplicate()
		var q: Vector2i = (Vector2i(int(dd.x), int(dd.y)) if rel else Vector2i(int(dd.x), int(dd.y)) - LEGACY_ENTRY) + off
		d2.x = q.x
		d2.y = q.y
		var dev := Device.from_data(d2)
		cg.devices[cg.idx(dev.pos)] = dev
	for entry in w.piles:
		var inv := Inventory.new()
		var q: Vector2i
		if rel:
			q = Vector2i(int(entry[0]), int(entry[1])) + off
			inv.from_data(entry[2])
		else:
			q = Vector2i(int(entry[0]) % cw, int(entry[0]) / cw) - LEGACY_ENTRY + off
			inv.from_data(entry[1])
		cg.piles[cg.idx(q)] = inv
	var fg := ShipGrid.refine(cg)
	var e := fg.fine_of_coarse(off)
	var tiles: Array = []
	var devs: Array = []
	var piles: Array = []
	for i in fg.tiles.size():
		if fg.zone[i] != 1:
			continue
		var r := fg.pos(i) - e
		tiles.append([r.x, r.y, fg.tiles[i], fg.cables[i], fg.cond[i], fg.o2[i], fg.n2[i], fg.co2[i]])
		if fg.devices.has(i):
			var dd: Dictionary = fg.devices[i].to_data()
			dd.x = r.x
			dd.y = r.y
			devs.append(dd)
		if fg.piles.has(i):
			piles.append([r.x, r.y, fg.piles[i].to_data()])
	var out := w.duplicate()
	out.rel = true
	out.scale = k
	out.tiles = tiles
	out.devices = devs
	out.piles = piles
	return out

## Arrived (docked). Stations bring no wreck: wrecks are their own targets
## (kind "wreck", already attached when clamping) or hang at the debris field, outpost, asteroid.
func arrive(l: Dictionary) -> void:
	if not Config.ENABLE_WRECK or not String(l.get("kind", "")) in WRECK_KINDS or l.kind == "wreck":
		return
	var place: Dictionary = places.get(l.id, {})
	var w = place.get("wreck")
	if w != null:
		if _attach_stored(w):
			place.wreck = null
			EventBus.ship_changed.emit()
		else:
			GameState.toast("The wreck “%s” is here. Coupling needs a free docking port (airlock)." % String(w.name))
	elif l.kind == "asteroid":
		if SalvageSystem.generate_asteroid():
			GameState.toast("A chunk of rock hangs at the airlock. Demolishing it yields ice and ore.")
	elif l.kind == "outpost":
		if not SalvageSystem.generate():
			return
		# Outpost: more locks, more loot
		for dev in ShipSystem.grid.devices.values():
			if dev.type == "crate" and ShipSystem.grid.zone[ShipSystem.grid.idx(dev.pos)] == 1:
				dev.lock_level = maxi(dev.lock_level, randi_range(1, 3))
				dev.inv.add(["datachip", "cell", "motor", "boltgun", "genemod"].pick_random(), 1, randf_range(60.0, 95.0))
		GameState.toast("The outpost is abandoned. The storerooms are locked.")
	elif l.kind == "debris":
		if SalvageSystem.generate():
			GameState.toast("A wreck from the debris field docks at the airlock: " + SalvageSystem.wreck_name)

# ---------------- Schiffe ----------------

func here() -> String:
	return PhysicsSystem.docked

func ships_here() -> Array:
	return ships.filter(func(s): return s.location == here())

func switch_to(id: int) -> void:
	# Switching ships only while docked (that is where the other ships are)
	if here() == "":
		GameState.toast("You can only switch ships while docked.")
		return
	var target: Dictionary = {}
	for s in ships:
		if s.id == id:
			target = s
	if target.is_empty() or target.location != here():
		GameState.toast("This ship is not here.")
		return
	if not SalvageSystem.clearable():
		GameState.toast("Bring all crew members back from the wreck first.")
		return
	if not StationSystem.clearable():
		GameState.toast("Bring all crew members back aboard from the station first.")
		return
	var l := PhysicsSystem.loc(here())
	StationSystem.clear()
	leave(l)
	for c in CrewSystem.crew:
		c.release_job()
		c.stop_activity()
		c.order = null
	ships.append({"id": current_id, "name": current_name, "registered": registered_name, "registry": registry_id, "location": l.id, "data": ShipSystem.grid.to_data()})
	ships = ships.filter(func(s): return s.id != id)
	ShipSystem.grid = ShipGrid.from_data(target.data)
	ShipSystem.retire_legacy_ports()
	ShipConstructionSystem.jobs.clear()
	current_id = target.id
	current_name = target.name
	registered_name = String(target.get("registered", target.name))
	registry_id = String(target.get("registry", ""))
	if registry_id == "":
		registry_id = new_registry_id()
	EventBus.ship_changed.emit()
	ShipPowerSystem.step(0.0)
	_place_crew()
	arrive(l)
	StationSystem.build(l.id)
	GameState.toast("You are now aboard the " + current_name + ".")

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
	# Room types (Ostranauts Rooms) multiply the value of the devices installed in them
	var mods := RoomTypes.modifiers(g)
	for i in g.devices:
		if not g.foreign(i):
			v += SalvageSystem.device_value(g.devices[i]) * 1.5 * float(mods.get(i, 1.0))
	return int(v)

# ---------------- Starter ship from "Seek Ship" (Ostranauts 2.4) ----------------

## Start the game with the ship bought in the life story: replaces the Rustbucket, loan = price.
## "rostlaube" or "": the starter ship stays, loan as before.
func start_with(id: String) -> void:
	var t: Dictionary = CharacterSystem.starter_ship(id)
	if t.is_empty() or id == "rostlaube":
		return
	StationSystem.clear()
	ShipSystem.grid = build_template(t)
	ShipSystem.retire_legacy_ports()
	ShipConstructionSystem.jobs.clear()
	current_name = String(t.name)
	registered_name = current_name
	EconomySystem.debt = int(t.price)
	PhysicsSystem.helm_at = PhysicsSystem.NO_HELM
	EventBus.ship_changed.emit()
	ShipPowerSystem.step(0.0)
	_place_crew()
	StationSystem.build(PhysicsSystem.docked)

# ---------------- Ship name (Ostranauts Ship Building 1.4) ----------------

const NAME_MAX := 32
const REG_LETTERS := "ABCDEFGHJKLMNPRSTUVWXYZ"

## New hull ID like "J-YV16" (letter, hyphen, two letters, two digits), unique
func new_registry_id() -> String:
	var used := {registry_id: true}
	for s in ships:
		used[String(s.get("registry", ""))] = true
	while true:
		var L := func() -> String: return REG_LETTERS[randi() % REG_LETTERS.length()]
		var id := "%s-%s%s%02d" % [L.call(), L.call(), L.call(), randi() % 100]
		if not used.has(id):
			return id
	return ""

## Reason against renaming ("" = possible): needs your own navigation console with power
func rename_block_reason() -> String:
	for d in PhysicsSystem.ship_devices("helm"):
		if not d.broken and d.powered and not d.unknown:
			return ""
	return "Renaming needs a powered navigation console aboard."

## Change the ship's name at the navigation console. Returns "" on success, otherwise the reason.
func rename(new_name: String) -> String:
	var n := new_name.strip_edges().substr(0, NAME_MAX)
	if n == "":
		return "The name must not be empty."
	var why := rename_block_reason()
	if why != "":
		return why
	current_name = n
	GameState.toast("Vessel renamed to %s. Register the new name with the Ship Rating service at a shipyard." % n if n != registered_name else "Vessel name: %s." % n)
	return ""

## The shipyard's Ship Rating service: new rating and name into the register. "" = done.
func register_name() -> String:
	var st := PhysicsSystem.station()
	if st.is_empty() or not st.get("shipyard", false):
		return "The Ship Rating service is only available at a shipyard."
	registered_name = current_name
	GameState.toast("Ship Rating %s accepted. %s is now registered." % [ShipRating.rating(ShipSystem.grid, PhysicsSystem.mass() * 1000.0), current_name])
	return ""

func register_wreck() -> void:
	var g := ShipSystem.grid
	if SalvageSystem.wreck_name == "":
		GameState.toast("There is no wreck here.")
		return
	if not EconomySystem.terminal_online():
		GameState.toast("The trade terminal is offline.")
		return
	if EconomySystem.credits < REGISTER_FEE:
		GameState.toast("Not enough credits for the registration.")
		return
	if not SalvageSystem.clearable():
		GameState.toast("Bring all crew members back from the wreck first.")
		return
	EconomySystem.credits -= REGISTER_FEE
	EconomySystem.book("Wreck registered as a ship: " + SalvageSystem.wreck_name, -REGISTER_FEE)
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
	ships.append({"id": next_id, "name": SalvageSystem.wreck_name, "registry": new_registry_id(), "location": here(), "data": nw.to_data()})
	next_id += 1
	SalvageSystem.clear()
	GameState.toast("Registered! Switch aboard in the trade terminal under “Ships”.")

## on_credit: with a ship loan (price +20 % on the debt)
func buy(kind: String, on_credit: bool = false) -> void:
	var st := PhysicsSystem.station()
	if st.is_empty() or not st.get("shipyard", false):
		GameState.toast("There is no shipyard here.")
		return
	var t: Dictionary = {}
	for s in PhysicsSystem.space.shipyard:
		if s.id == kind:
			t = s
	if on_credit:
		EconomySystem.debt += int(int(t.price) * 1.2)
		EconomySystem.book("Ship loan: " + t.name + " (+%d Cr debt)" % int(int(t.price) * 1.2), 0)
	else:
		if EconomySystem.credits < int(t.price):
			GameState.toast("Not enough credits.")
			return
		EconomySystem.credits -= int(t.price)
		EconomySystem.book("Ship bought: " + t.name, -int(t.price))
	var g := build_template(t)
	ships.append({"id": next_id, "name": t.name, "registry": new_registry_id(), "location": here(), "data": g.to_data()})
	next_id += 1
	GameState.toast(t.name + " is yours now. Switch aboard under “Ships”.")

func sell(id: int) -> void:
	var st := PhysicsSystem.station()
	for s in ships:
		if s.id == id:
			if st.is_empty() or not st.get("shipyard", false) or s.location != here():
				GameState.toast("Ships can only be sold at a shipyard where they are moored.")
				return
			var v := int(ship_value(ShipGrid.from_data(s.data)) * 0.6)
			EconomySystem.credits += v
			EconomySystem.book("Ship sold: " + s.name, v)
			ships = ships.filter(func(x): return x.id != id)
			return

## Shipyard ship ready in the fine grid (template in former tiles, then refined)
func build_template(t: Dictionary) -> ShipGrid:
	var cg := ShipGrid.new(Config.WORLD_W / Config.GRID_SCALE, Config.WORLD_H / Config.GRID_SCALE)
	_build_template(cg, t)
	return ShipGrid.refine(cg)

## Template in the tiles of earlier versions (twice as large)
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
		["fueltank", mid + 1, y0 + 1], ["thruster", x0 + 1, y0 + 2], ["crate", mid + 1, y0 + h - 2],
		["terminal", mid + 2, y0 + 1], ["food", mid + 2, y0 + h - 2],
		["transponder", x0 + 4, y0 + h - 2], ["antenna", x0 + w - 2, y0 + h - 2]]
	if t.id == "bairn":
		list.append_array([["thruster", x0 + 1, y0 + 3], ["thruster", x0 + 1, y0 + 4], ["crate", mid + 3, y0 + h - 2],
			["crate", mid + 4, y0 + h - 2], ["bed", x0 + 5, y0 + h - 2], ["water", x0 + 5, y0 + 1]])
	for e in list:
		g.place_device(e[0], Vector2i(e[1], e[2]))
	for x in range(x0 + 1, x0 + w - 1):
		g.cables[g.idx(Vector2i(x, y0 + 1))] = 1
		g.cables[g.idx(Vector2i(x, y0 + h - 2))] = 1
	for y in range(y0 + 1, y0 + h - 1):
		g.cables[g.idx(Vector2i(x0 + 1, y))] = 1
	# Airlock on the left (room with a pump): its outer door is the docking port for station and wreck
	var top := y0 + h - 4 - (1 if h > 8 else 0)
	for y in range(top, top + 4):
		for x in range(x0 - 3, x0):
			var edge := x == x0 - 3 or y == top or y == top + 3
			g.set_tile(Vector2i(x, y), ShipGrid.Tile.WALL if edge else ShipGrid.Tile.FLOOR)
	g.set_tile(Vector2i(x0, top + 1), ShipGrid.Tile.DOOR)       # inner door
	g.set_tile(Vector2i(x0 - 3, top + 1), ShipGrid.Tile.DOOR)   # outer door = docking port
	g.place_device("pump", Vector2i(x0 - 1, top + 2))
	for x in range(x0 - 1, x0 + 1):
		g.cables[g.idx(Vector2i(x, top + 2))] = 1
	for i in g.tiles.size():
		if g.holds_air(i) and g.zone[i] == 0:
			g.fill_air(i)
	for dev in g.devices.values():
		if dev.type == "crate":
			dev.inv.add("ration", 10)
			dev.inv.add("fuelcan", 2)
			break

func to_data() -> Dictionary:
	return {"ships": ships, "places": places, "current_name": current_name, "registered_name": registered_name, "registry_id": registry_id, "current_id": current_id, "next_id": next_id,
		"sites": sites, "next_site": next_site}

func from_data(d: Dictionary) -> void:
	ships.assign(d.ships)
	places = d.places
	sites.assign(d.get("sites", []))
	next_site = int(d.get("next_site", sites.size() + 1))
	PhysicsSystem.set_extra_locations(sites)
	current_name = String(d.current_name)
	registered_name = String(d.get("registered_name", current_name))
	registry_id = String(d.get("registry_id", ""))
	if registry_id == "":
		registry_id = new_registry_id()
	for s in ships:
		if String(s.get("registry", "")) == "":
			s.registry = new_registry_id()
	current_id = int(d.current_id)
	next_id = int(d.next_id)
