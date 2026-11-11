## Baupläne (Aufträge): bauen, abreißen, Kabel, Geräte.
## Der Spieler plant, die Crew holt Material und arbeitet die Pläne ab.
extends Node

## Feld-Index -> Auftrag (Dictionary)
var jobs: Dictionary = {}
## Drehung für das nächste gebaute drehbare Gerät (0–3, je 90°; Taste G)
var build_rot := 0

const TOOL_TILE := {"floor": 1, "wall": 2, "door": 3, "window": 4}

func can_place(tool: String, p: Vector2i) -> bool:
	var g := ShipSystem.grid
	if not g.in_bounds(p):
		return false
	var i := g.idx(p)
	var t := g.tiles[i]
	var has_dev := g.occupied(p)
	# Die Station gehört dir nicht (die Luke in der Schiffswand auch nicht)
	if (StationSystem.reserved(p) or StationSystem.is_hatch(i)) and not tool in ["haul", "cancel"]:
		return false
	if tool == "dev:dockport":
		# Andockschleuse 5×2: Außentür mitten in einer geraden Außenwand (siehe ShipGrid.dock_check)
		return place_reason(tool, p) == ""
	if tool.begins_with("dev:"):
		var dd := ItemSystem.device(tool.substr(4))
		if not dd.buildable:
			return false
		if dd.length > 1:
			return place_reason(tool, p) == ""
		return t == ShipGrid.Tile.FLOOR and not has_dev
	if tool.begins_with("install:"):
		return RemovalSystem.can_install(tool.substr(8), p)
	if tool in RemovalSystem.KINDS:
		return RemovalSystem.reason(tool, p) == ""
	match tool:
		"repair": return DamageSystem.needs_repair(p)
		"haul": return g.piles.has(i) and not jobs.has(i)
		"hack": return has_dev and g.device_at(p).lock_level > 0 and not jobs.has(g.idx(g.device_at(p).pos))
		"extinguish": return g.fire[i] == 1 and not jobs.has(i)
		"move": return has_dev and not jobs.has(i) and g.device_at(p).type != "dockport" and g.device_at(p).data().length == 1
		"floor": return t == ShipGrid.Tile.SPACE and not has_dev
		"wall", "window": return (t == ShipGrid.Tile.SPACE or t == ShipGrid.Tile.FLOOR) and not has_dev
		"door": return t != ShipGrid.Tile.DOOR and not has_dev
		"cable": return t != ShipGrid.Tile.SPACE and g.cables[i] == 0
		"remove": return t != ShipGrid.Tile.SPACE
		"cancel": return jobs.has(i)
		"rotate": return has_dev and g.device_at(p).data().rotatable and g.device_at(p).data().length == 1 and not jobs.has(i) and not g.foreign(i)
	return false

## Grund, warum ein Mehrfeld-Gerät (Triebwerk 1×3) hier nicht gebaut werden kann ("" = geht).
## p = Innenfeld, Richtung = build_rot.
func place_reason(tool: String, p: Vector2i) -> String:
	var g := ShipSystem.grid
	var type := tool.substr(4)
	if not g.in_bounds(p):
		return "Außerhalb."
	if type == "dockport":
		var chk := g.dock_check(p)
		if chk.reason != "":
			return chk.reason
		for c in ShipGrid.dock_cells(p, chk.dir):
			if jobs.has(g.idx(c)):
				return "Hier läuft schon ein Auftrag."
			if StationSystem.reserved(c) or StationSystem.is_hatch(g.idx(c)):
				return "Gehört der Station."
		return ""
	var why := g.mount_reason(type, p, build_rot)
	if why != "":
		return why
	for c in cells_of(type, p, build_rot):
		if jobs.has(g.idx(c)):
			return "Hier läuft schon ein Auftrag."
		if StationSystem.reserved(c) or StationSystem.is_hatch(g.idx(c)):
			return "Gehört der Station."
	return ""

## Felder eines Geräts dieser Art an p (Innenfeld) mit Drehung rot
func cells_of(type: String, p: Vector2i, rot: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if type == "dockport":
		var chk := ShipSystem.grid.dock_check(p)
		if chk.reason == "":
			return ShipGrid.dock_cells(p, chk.dir)
		out.append(p)
		return out
	for k in maxi(1, ItemSystem.device(type).length):
		out.append(p - Device.PUSH_DIRS[rot % 4] * k)
	return out

func place(tool: String, p: Vector2i) -> bool:
	if not can_place(tool, p):
		return false
	var i := ShipSystem.grid.idx(p)
	if tool == "cancel":
		cancel(jobs[i])
		return true
	if tool in RemovalSystem.KINDS:
		return RemovalSystem.order(tool, p) == ""
	if tool == "rotate":
		jobs[ShipSystem.grid.idx(p)] = {"kind": "rotate", "x": p.x, "y": p.y, "progress": 0.0, "claimed_by": -1,
			"retry_at": 0.0, "paid": true, "need": 1.0}
		return true
	var job := {"x": p.x, "y": p.y, "progress": 0.0, "claimed_by": -1, "retry_at": 0.0, "paid": false}
	if tool == "extinguish":
		job.merge({"kind": "extinguish", "need": 1.0, "paid": true})
	elif tool == "hack":
		job.merge({"kind": "hack", "need": 4.0 * g_lock(p), "paid": true})
	elif tool == "haul":
		job.merge({"kind": "haul", "phase": "pickup", "need": 0.2, "paid": true})
	elif tool == "repair":
		job.merge({"kind": "repair", "need": Config.REPAIR_TIME})
	elif tool == "remove":
		job.merge({"kind": "remove", "need": Config.REMOVE_TIME})
	elif tool == "cable":
		job.merge({"kind": "cable", "need": Config.CABLE_TIME})
	elif tool.begins_with("install:"):
		var pk := tool.substr(8)
		job.merge({"kind": "install", "item": pk, "need": RemovalSystem.install_time(pk)})
		var pkey := RemovalSystem.key_of_packed(pk)
		if pkey.begins_with("dev:") and ItemSystem.device(pkey.substr(4)).rotatable:
			job.rot = build_rot
	elif tool.begins_with("dev:"):
		var dev_id := tool.substr(4)
		job.merge({"kind": "device", "dev": dev_id, "need": ItemSystem.device(dev_id).build_time})
		if ItemSystem.device(dev_id).rotatable:
			job.rot = build_rot
	else:
		var tile: int = TOOL_TILE[tool]
		job.merge({"kind": "build", "tile": tile, "need": Config.TILE_BUILD_TIME[tile]})
	jobs[i] = job
	return true

func g_lock(p: Vector2i) -> int:
	var dev := ShipSystem.grid.device_at(p)
	return dev.lock_level if dev != null else 1

## Gerät versetzen: von src nach dst (ein Charakter trägt es)
func place_move(src: Vector2i, dst: Vector2i) -> bool:
	var g := ShipSystem.grid
	if not can_place("move", src):
		GameState.toast("Dort steht kein Gerät, das man versetzen kann.")
		return false
	if src == dst:
		return false
	if g.get_tile(dst) != ShipGrid.Tile.FLOOR or g.device_at(dst) != null:
		GameState.toast("Das Ziel muss ein freier Boden sein.")
		return false
	jobs[g.idx(src)] = {"kind": "move", "x": src.x, "y": src.y, "tx": dst.x, "ty": dst.y, "phase": "pickup",
		"need": 0.3, "progress": 0.0, "claimed_by": -1, "retry_at": 0.0, "paid": true}
	return true

## Wo muss gerade gearbeitet werden?
func target_of(job: Dictionary) -> Vector2i:
	if (job.kind == "move" or job.kind == "haul") and job.phase == "deliver":
		return Vector2i(int(job.tx), int(job.ty))
	return pos_of(job)

func cost(job: Dictionary) -> Dictionary:
	match job.kind:
		"build": return Config.TILE_COST[int(job.tile)]
		"cable": return Config.CABLE_COST
		"device": return ItemSystem.device(job.dev).cost
		"refill": return {job.item: int(job.qty)}
		"craft": return EconomySystem.recipe(job.recipe)["in"]
		"install": return {job.item: 1}
	return {}

## Was für den Auftrag noch fehlt (Kosten minus schon am Bauplatz abgelegtes Material).
## Schwere Bauteile (z. B. Triebwerk, 44 kg) holt die Crew so in mehreren Gängen.
func remaining_cost(job: Dictionary) -> Dictionary:
	var out := {}
	var got: Dictionary = job.get("delivered", {})
	var c := cost(job)
	for type in c:
		var n := int(c[type]) - int(got.get(type, 0))
		if n > 0:
			out[type] = n
	return out

## Vorräte (Essen, Wasser, Brennstoff, Luft) automatisch aus dem Lager nachfüllen lassen
func scan_refills() -> void:
	var g := ShipSystem.grid
	for i in g.devices:
		var dev: Device = g.devices[i]
		var d := dev.data()
		if g.foreign(i) or d.stock < 0.0 or dev.stock > d.stock * Config.REFILL_AT or jobs.has(i):
			continue
		for item_id in ItemSystem.items:
			var it: ItemData = ItemSystem.item(item_id)
			if not it.refill.has(dev.type):
				continue
			var want := int(ceil((d.stock - dev.stock) / float(it.refill[dev.type])))
			var qty := mini(mini(want, maxi(1, int(Config.CARRY_WEIGHT / it.weight))), available(item_id))
			if qty > 0:
				jobs[i] = {"kind": "refill", "item": item_id, "qty": qty, "x": dev.pos.x, "y": dev.pos.y, "need": 0.5,
					"progress": 0.0, "claimed_by": -1, "retry_at": 0.0, "paid": false}
			break

func pos_of(job: Dictionary) -> Vector2i:
	return Vector2i(int(job.x), int(job.y))

## Abbrechen: schon verbautes Material kommt zurück
func cancel(job: Dictionary) -> void:
	var g := ShipSystem.grid
	jobs.erase(g.idx(pos_of(job)))
	# Einbau abgebrochen: genau das abgebaute Stück (mit Zustand und Daten) zurücklegen
	if job.has("packed"):
		var st: Dictionary = job.packed
		g.drop_items(drop_spot(pos_of(job)), st.type, 1, float(st.cond), st.get("data"))
		return
	if job.paid:
		var spot := drop_spot(pos_of(job))
		var c := cost(job)
		for type in c:
			g.drop_items(spot, type, int(c[type]), 80.0)
	elif not job.get("delivered", {}).is_empty():
		# Schon abgelegtes Material kommt zurück
		var spot2 := drop_spot(pos_of(job))
		for type in job.delivered:
			g.drop_items(spot2, type, int(job.delivered[type]), 80.0)

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
func salvage(p: Vector2i, worker: CrewMember = null) -> Array:
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
		# Kampftechnik: Kriegswracks im Trümmerfeld geben mehr her
		if worker != null and g.zone[i] == 1 and PhysicsSystem.docked == "debris" and randf() < SkillSystem.effect(worker, "military_salvage"):
			out.append([["motor", "circuit", "cell", "boltgun"].pick_random(), 1, randf_range(40.0, 85.0)])
		if dev.inv != null:
			for it in dev.inv.items:
				out.append([it.type, it.qty, it.cond, it.get("data")])
		return out
	var t := g.tiles[i]
	if g.cables[i] == 1 and t == ShipGrid.Tile.FLOOR:
		return [["copper", 1, randf_range(50.0, 90.0)]]
	# Abbau: bessere Ausbeute beim Abreißen von Wänden und Böden
	var yield_bonus := SkillSystem.effect(worker, "demolish_yield") if worker != null else 0.0
	var full := worker != null and SkillSystem.mastered(worker, "excavation")
	# Asteroid: Fels gibt Eis und Erz
	if t == ShipGrid.Tile.WALL and g.zone[i] == 1 and SalvageSystem.is_asteroid():
		out.append(["ice" if randf() < 0.55 else "ore", 1 + (1 if randf() < yield_bonus else 0), randf_range(70.0, 100.0)])
		return out
	match t:
		ShipGrid.Tile.WALL: out.append(["plate", 2, 90.0 if full else minf(100.0, randf_range(40.0, 90.0) * g.cond[i] / 100.0 * (1.0 + yield_bonus))])
		ShipGrid.Tile.DOOR:
			out.append(["plate", 2, randf_range(40.0, 90.0)])
			if randf() < 0.6:
				out.append(["circuit", 1, randf_range(30.0, 80.0)])
		ShipGrid.Tile.FLOOR: out.append(["plate", 1, randf_range(40.0, 90.0)])
		ShipGrid.Tile.WINDOW: out.append(["glass", 2, randf_range(40.0, 90.0)])
	return out

## Auftrag fertig: Schiff verändern. worker_pos = wo der Arbeiter steht.
func complete(job: Dictionary, worker_pos: Vector2i, worker: CrewMember = null) -> void:
	var g := ShipSystem.grid
	var p := pos_of(job)
	var i := g.idx(p)
	jobs.erase(i)
	match job.kind:
		"tend", "harvest":
			WaterSystem.finish_farm_job(job)
		"extinguish":
			TemperatureSystem.extinguish(i)
		"repair":
			DamageSystem.repair(p)
		"refill":
			var dev := g.device_at(p)
			if dev != null:
				var per: float = ItemSystem.item(job.item).refill.get(dev.type, 0)
				dev.stock = minf(dev.data().stock, dev.stock + per * int(job.qty))
		"craft":
			var r := EconomySystem.recipe(job.recipe)
			var spot := drop_spot(worker_pos)
			g.drop_items(spot, r.out[0], int(r.out[1]), float(r.out[2]))
			GameState.toast("Werkbank: %s fertig." % ItemSystem.item(r.out[0]).display_name)
		"build":
			_move_pile_away(i, worker_pos)
			g.set_tile(p, int(job.tile))
		"cable":
			g.cables[i] = 1
		"device":
			_move_pile_away(i, worker_pos)
			var rot := int(job.get("rot", 0))
			var why := ""
			if job.dev == "dockport":
				why = g.dock_check(p).reason
			elif ItemSystem.device(job.dev).length > 1:
				why = g.mount_reason(job.dev, p, rot)
			# Mehrfeld-Gerät: Platz inzwischen ungültig? Material kommt zurück
			if why != "":
				GameState.toast("%s: Bau nicht möglich – %s Material liegt daneben." % [ItemSystem.device(job.dev).display_name, why], "bad")
				var back := drop_spot(worker_pos)
				var c := cost(job)
				for type in c:
					g.drop_items(back, type, int(c[type]), 80.0)
			elif job.dev == "dockport":
				g.build_dock(p)
			else:
				g.place_device(job.dev, p, rot)
		"rotate":
			var rd := g.device_at(p)
			if rd != null and rd.data().rotatable and rd.data().length == 1:
				rd.rot = (rd.rot + 1) % 4
		"remove":
			var loot := salvage(p, worker)
			var t := g.tiles[i]
			var rdev := g.device_at(p)
			var becomes_space := t == ShipGrid.Tile.FLOOR and g.cables[i] == 0 and rdev == null
			if rdev != null:
				if g.zone[i] == 1:
					GoalSystem.stripped += 1
				g.remove_device(rdev)
			elif g.cables[i] == 1 and t == ShipGrid.Tile.FLOOR:
				g.cables[i] = 0
			elif t == ShipGrid.Tile.WALL or t == ShipGrid.Tile.DOOR or t == ShipGrid.Tile.WINDOW:
				g.set_tile(p, ShipGrid.Tile.FLOOR)
			else:
				g.set_tile(p, ShipGrid.Tile.SPACE)
			var spot := worker_pos if becomes_space else p
			for l in loot:
				g.drop_items(spot, l[0], l[1], l[2], l[3] if l.size() > 3 else null)
		"uninstall", "dismantle", "destroy":
			RemovalSystem.finish(job, worker, worker_pos)
		"install":
			RemovalSystem.finish_install(job, worker_pos)
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
		g.drop_items(to, it.type, it.qty, it.cond, it.get("data"))

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
		# Nicht: Handelsterminal, Modulfach des Steuerpults, Mehrfeld-Geräte
		if g.devices[i].inv != null and g.devices[i].lock_level == 0 and g.devices[i].type != "terminal" and g.devices[i].type != "helm" and g.devices[i].data().length == 1:
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
		"repair": return "Repariert"
		"tend": return "Pflegt Pflanzen"
		"harvest": return "Erntet"
		"extinguish": return "Löscht Feuer"
		"hack": return "Hackt Schloss"
		"refill": return "Füllt nach: " + ItemSystem.item(job.item).display_name
		"craft": return "Werkbank: " + String(EconomySystem.recipe(job.recipe).name)
		"haul": return "Bringt Sachen ins Lager" if job.phase == "deliver" else "Sammelt ein"
		"move": return "Trägt Gerät" if job.phase == "deliver" else "Hebt Gerät auf"
		"remove": return "Reißt ab"
		"uninstall": return "Baut ab: " + RemovalSystem.name_of(String(job.target))
		"dismantle": return "Zerlegt: " + RemovalSystem.name_of(String(job.target))
		"destroy": return "Zerstört: " + RemovalSystem.name_of(String(job.target))
		"install": return "Baut ein: " + RemovalSystem.name_of(RemovalSystem.key_of_packed(String(job.item)))
		"cable": return "Verlegt Kabel"
		"device": return "Baut " + ItemSystem.device(job.dev).display_name
		"rotate": return "Dreht Gerät"
		_: return "Baut " + Config.TILE_NAMES[int(job.tile)]

func to_data() -> Array:
	var out: Array = []
	for j in jobs.values():
		if (j.kind == "move" or j.kind == "haul") and j.get("phase", "") == "deliver":
			continue  # wird gerade getragen
		var d: Dictionary = j.duplicate()
		d.claimed_by = -1
		out.append(d)
	return out

func from_data(data: Array) -> void:
	jobs.clear()
	for d in data:
		var j: Dictionary = d.duplicate()
		jobs[ShipSystem.grid.idx(Vector2i(int(j.x), int(j.y)))] = j
