## Baupläne (Aufträge): bauen, abreißen, Kabel, Geräte.
## Der Spieler plant, die Crew holt Material und arbeitet die Pläne ab.
extends Node

## Feld-Index -> Auftrag (Dictionary)
var jobs: Dictionary = {}

const TOOL_TILE := {"floor": 1, "wall": 2, "door": 3}

func can_place(tool: String, p: Vector2i) -> bool:
	var g := ShipSystem.grid
	if not g.in_bounds(p):
		return false
	var i := g.idx(p)
	var t := g.tiles[i]
	var has_dev := g.devices.has(i)
	if tool.begins_with("dev:"):
		return t == ShipGrid.Tile.FLOOR and not has_dev
	match tool:
		"floor": return t == ShipGrid.Tile.SPACE
		"wall": return (t == ShipGrid.Tile.SPACE or t == ShipGrid.Tile.FLOOR) and not has_dev
		"door": return t != ShipGrid.Tile.DOOR and not has_dev
		"cable": return t != ShipGrid.Tile.SPACE and g.cables[i] == 0
		"remove": return t != ShipGrid.Tile.SPACE
		"cancel": return jobs.has(i)
	return false

func place(tool: String, p: Vector2i) -> bool:
	if not can_place(tool, p):
		return false
	var i := ShipSystem.grid.idx(p)
	if tool == "cancel":
		cancel(jobs[i])
		return true
	var job := {"x": p.x, "y": p.y, "progress": 0.0, "claimed_by": -1, "retry_at": 0.0, "paid": false}
	if tool == "remove":
		job.merge({"kind": "remove", "need": Config.REMOVE_TIME})
	elif tool == "cable":
		job.merge({"kind": "cable", "need": Config.CABLE_TIME})
	elif tool.begins_with("dev:"):
		var dev_id := tool.substr(4)
		job.merge({"kind": "device", "dev": dev_id, "need": ItemSystem.device(dev_id).build_time})
	else:
		var tile: int = TOOL_TILE[tool]
		job.merge({"kind": "build", "tile": tile, "need": Config.TILE_BUILD_TIME[tile]})
	jobs[i] = job
	return true

func cost(job: Dictionary) -> Dictionary:
	match job.kind:
		"build": return Config.TILE_COST[int(job.tile)]
		"cable": return Config.CABLE_COST
		"device": return ItemSystem.device(job.dev).cost
	return {}

func pos_of(job: Dictionary) -> Vector2i:
	return Vector2i(int(job.x), int(job.y))

## Abbrechen: schon verbautes Material kommt zurück
func cancel(job: Dictionary) -> void:
	var g := ShipSystem.grid
	jobs.erase(g.idx(pos_of(job)))
	if job.paid:
		var spot := drop_spot(pos_of(job))
		var c := cost(job)
		for type in c:
			g.drop_items(spot, type, int(c[type]), 80.0)

## Ein Bodenfeld in der Nähe, auf dem man etwas ablegen kann
func drop_spot(p: Vector2i) -> Vector2i:
	var g := ShipSystem.grid
	for r in 6:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := p + Vector2i(dx, dy)
				if g.get_tile(q) == ShipGrid.Tile.FLOOR and g.device_at(q) == null:
					return q
	return p

## Teile, die man beim Abreißen zurückbekommt
func salvage(p: Vector2i) -> Array:
	var g := ShipSystem.grid
	var i := g.idx(p)
	var out: Array = []
	var dev := g.device_at(p)
	if dev != null:
		var c := dev.data().cost
		for type in c:
			var n := int(round(c[type] * randf_range(0.4, 1.0)))
			if n > 0:
				out.append([type, n, randf_range(25.0, 90.0) * maxf(0.3, dev.cond / 100.0)])
		out.append(["scrap", 1 + randi() % 2, 40.0])
		if dev.inv != null:
			for it in dev.inv.items:
				out.append([it.type, it.qty, it.cond])
		return out
	var t := g.tiles[i]
	if g.cables[i] == 1 and t == ShipGrid.Tile.FLOOR:
		return [["copper", 1, randf_range(50.0, 90.0)]]
	match t:
		ShipGrid.Tile.WALL: out.append(["plate", 2, randf_range(40.0, 90.0) * g.cond[i] / 100.0])
		ShipGrid.Tile.DOOR:
			out.append(["plate", 2, randf_range(40.0, 90.0)])
			if randf() < 0.6:
				out.append(["circuit", 1, randf_range(30.0, 80.0)])
		ShipGrid.Tile.FLOOR: out.append(["plate", 1, randf_range(40.0, 90.0)])
	return out

## Auftrag fertig: Schiff verändern. worker_pos = wo der Arbeiter steht.
func complete(job: Dictionary, worker_pos: Vector2i) -> void:
	var g := ShipSystem.grid
	var p := pos_of(job)
	var i := g.idx(p)
	jobs.erase(i)
	match job.kind:
		"build":
			_move_pile_away(i, worker_pos)
			g.set_tile(p, int(job.tile))
		"cable":
			g.cables[i] = 1
		"device":
			_move_pile_away(i, worker_pos)
			g.place_device(job.dev, p)
		"remove":
			var loot := salvage(p)
			var t := g.tiles[i]
			var becomes_space := t == ShipGrid.Tile.FLOOR and g.cables[i] == 0 and not g.devices.has(i)
			if g.devices.has(i):
				g.devices.erase(i)
			elif g.cables[i] == 1 and t == ShipGrid.Tile.FLOOR:
				g.cables[i] = 0
			elif t == ShipGrid.Tile.WALL or t == ShipGrid.Tile.DOOR:
				g.set_tile(p, ShipGrid.Tile.FLOOR)
			else:
				g.set_tile(p, ShipGrid.Tile.SPACE)
			var spot := worker_pos if becomes_space else p
			for l in loot:
				g.drop_items(spot, l[0], l[1], l[2])
	EventBus.ship_changed.emit()
	for c in CrewSystem.crew:
		c.push_out_if_stuck()

func _move_pile_away(i: int, to: Vector2i) -> void:
	var g := ShipSystem.grid
	if not g.piles.has(i):
		return
	var pile: Inventory = g.piles[i]
	g.piles.erase(i)
	for it in pile.items:
		g.drop_items(to, it.type, it.qty, it.cond)

## Wie viel gibt es von einer Sorte in Kisten und Haufen?
func available(type: String) -> int:
	var s := 0
	for src in sources():
		s += src.inv.count(type)
	return s

## Alle Lager: Kisten und Haufen. [{pos, inv}]
func sources() -> Array:
	var g := ShipSystem.grid
	var out: Array = []
	for i in g.devices:
		if g.devices[i].inv != null:
			out.append({"pos": g.pos(i), "inv": g.devices[i].inv})
	for i in g.piles:
		out.append({"pos": g.pos(i), "inv": g.piles[i]})
	return out

func missing(c: Dictionary, inv: Inventory) -> Dictionary:
	var out := {}
	for type in c:
		var have := inv.count(type)
		if have < int(c[type]):
			out[type] = int(c[type]) - have
	return out

func label(job: Dictionary) -> String:
	match job.kind:
		"remove": return "Reißt ab"
		"cable": return "Verlegt Kabel"
		"device": return "Baut " + ItemSystem.device(job.dev).display_name
		_: return "Baut " + Config.TILE_NAMES[int(job.tile)]

func to_data() -> Array:
	var out: Array = []
	for j in jobs.values():
		var d: Dictionary = j.duplicate()
		d.claimed_by = -1
		out.append(d)
	return out

func from_data(data: Array) -> void:
	jobs.clear()
	for d in data:
		var j: Dictionary = d.duplicate()
		jobs[ShipSystem.grid.idx(Vector2i(int(j.x), int(j.y)))] = j
