## Removing objects through the right-click menu, in three ways:
##   Uninstall (uninstall) – the whole object as an item, can be installed again,
##                           condition and its own data are kept
##   Dismantle (dismantle) – break it down into the defined materials
##   Destroy (destroy)     – hit it, every hit does damage, scrap at the end
## All values per object type are in res://data/removal.json (preliminary balancing).
## The crew does the actual work through the normal jobs (ShipConstructionSystem).
##
## Regeln:
## - Uninstall: exactly one complete item "… (uninstalled)" ends up on a
##   reachable floor tile (where the device stood, or inside next to it). Condition,
##   rotation and contents (e.g. crate contents) are kept in the item.
##   Its weight = mass of the installed device (DeviceData.mass) or of the block
##   (Config.TILE_MASS) – ship mass and carrying use the same value.
## - Dismantle and Destroy: results go into the working character's pack, the rest as
##   a pile at their feet; crate contents are put next to the object unharmed.
## - Locked containers must be cracked first; a locker with a space suit can
##   only be uninstalled (the suit stays in the uninstalled locker).
## - A character must carry the tool in their pack; only such characters take the job.
extends Node

const KINDS := ["uninstall", "dismantle", "destroy"]
const NAMES := {"uninstall": "Uninstall", "dismantle": "Dismantle", "destroy": "Destroy"}
const TILE_KEYS := {ShipGrid.Tile.FLOOR: "tile:floor", ShipGrid.Tile.WALL: "tile:wall", ShipGrid.Tile.DOOR: "tile:door", ShipGrid.Tile.WINDOW: "tile:window"}

var data: Dictionary = {}
var _last_hit_sound := 0

func _ready() -> void:
	var f := FileAccess.open("res://data/removal.json", FileAccess.READ)
	data = JSON.parse_string(f.get_as_text())
	_register_packed()

# ---------------- Konfiguration ----------------

## Values for an object type (device ID or "tile:wall" ...), filled with defaults
func config(key: String) -> Dictionary:
	var out: Dictionary = data.defaults.duplicate(true)
	var id := key.trim_prefix("dev:")
	out.merge(data.get(id, {}), true)
	return out

## What is on the tile? "dev:generator", "tile:wall", "tile:rock" or ""
func key_at(p: Vector2i) -> String:
	var g := ShipSystem.grid
	if not g.in_bounds(p):
		return ""
	var dev := g.device_at(p)
	if dev != null:
		return "dev:" + dev.type
	var t := g.get_tile(p)
	if t == ShipGrid.Tile.WALL and g.zone[g.idx(p)] == 1 and SalvageSystem.is_asteroid():
		return "tile:rock"
	return TILE_KEYS.get(t, "")

## The tile itself (without a device): "tile:floor", "tile:wall", "tile:rock" ... or ""
func tile_key_at(p: Vector2i) -> String:
	var g := ShipSystem.grid
	if not g.in_bounds(p):
		return ""
	var t := g.get_tile(p)
	if t == ShipGrid.Tile.WALL and g.zone[g.idx(p)] == 1 and SalvageSystem.is_asteroid():
		return "tile:rock"
	return TILE_KEYS.get(t, "")

## Layers of a tile from top to bottom: cable → device → floor/wall.
## Only existing layers, always from the current state of the tile.
## A multi-tile device (thruster 1×3) appears on each of its tiles.
func layers_at(p: Vector2i) -> Array[String]:
	var out: Array[String] = []
	var g := ShipSystem.grid
	if g == null or not g.in_bounds(p):
		return out
	var i := g.idx(p)
	if g.cables[i] == 1 and g.tiles[i] != ShipGrid.Tile.SPACE:
		out.append("cable")
	var dev := g.device_at(p)
	if dev != null:
		out.append("dev:" + dev.type)
	var tk := tile_key_at(p)
	if tk != "":
		out.append(tk)
	return out

## Rank of a layer: 0 cable, 1 device, 2 floor/wall
func layer_rank(key: String) -> int:
	if key == "cable":
		return 0
	if key.begins_with("dev:"):
		return 1
	return 2

## Which layer a right-click on p selects: on a new tile the topmost
## existing one; on the same tile the next existing one below the last chosen one
## (even if that has been removed meanwhile), after the last one the topmost again.
func next_layer(p: Vector2i, prev_tile: Vector2i, prev_key: String) -> String:
	var layers := layers_at(p)
	if layers.is_empty():
		return ""
	if p != prev_tile or prev_key == "":
		return layers[0]
	var rank := layer_rank(prev_key)
	for k in layers:
		if layer_rank(k) > rank:
			return k
	return layers[0]

func name_of(key: String) -> String:
	if key == "cable":
		return "Cable"
	if key.begins_with("dev:"):
		return ItemSystem.device(key.substr(4)).display_name
	if key == "tile:rock":
		return "Rock"
	for t in TILE_KEYS:
		if TILE_KEYS[t] == key:
			return Config.TILE_NAMES[t]
	return "?"

## Item for an uninstalled object
func packed_id(key: String) -> String:
	return "pk_" + key.trim_prefix("dev:").replace(":", "_")

## The object type back from the item
func key_of_packed(pk: String) -> String:
	var id := pk.trim_prefix("pk_")
	if id.begins_with("tile_"):
		return "tile:" + id.substr(5)
	return "dev:" + id

func is_packed(type: String) -> bool:
	return type.begins_with("pk_")

## Create an "(uninstalled)" item for every device and every block
func _register_packed() -> void:
	var d: Dictionary = data.defaults
	var keys: Array = []
	for id in ItemSystem.devices:
		if ItemSystem.device(id).tech != "station":
			keys.append("dev:" + id)
	for t in TILE_KEYS:
		keys.append(TILE_KEYS[t])
	for key in keys:
		if not "uninstall" in config(key).actions:
			continue
		var cost := _build_cost(key)
		var v := 0.0
		var val := 0
		for type in cost:
			var it := ItemSystem.item(type)
			if it == null:
				continue
			v += it.volume * cost[type]
			val += it.value * cost[type]
		if key.begins_with("dev:") and ItemSystem.device(key.substr(4)).item_value > 0:
			val = int(ItemSystem.device(key.substr(4)).item_value / 0.9)
		var item := ItemData.new()
		item.id = packed_id(key)
		item.display_name = name_of(key) + " (uninstalled)"
		item.weight = mass_kg(key)
		item.volume = clampf(v * float(d.packed_weight_factor), 1.0, float(d.packed_max_weight))
		item.value = int(val * 0.9)
		item.description = "Uninstalled, can be installed again (right-click a free tile or “Install”). Condition and contents are kept."
		ItemSystem.items[item.id] = item

## Weight in kg: exactly the mass with which the installed object counts towards the ship mass
func mass_kg(key: String) -> float:
	if key.begins_with("dev:"):
		return ItemSystem.device(key.substr(4)).mass * 1000.0
	for t in TILE_KEYS:
		if TILE_KEYS[t] == key:
			return float(Config.TILE_MASS.get(t, 0.2)) * 1000.0
	return 1.0

func _build_cost(key: String) -> Dictionary:
	if key.begins_with("dev:"):
		return ItemSystem.device(key.substr(4)).cost
	for t in TILE_KEYS:
		if TILE_KEYS[t] == key:
			return Config.TILE_COST[t]
	return {}

func _cable_text() -> String:
	var parts: PackedStringArray = []
	for type in Config.CABLE_COST:
		parts.append("%d× %s" % [int(Config.CABLE_COST[type]), ItemSystem.item(type).display_name])
	return ", ".join(parts)

## What comes out of uninstalling (for the menu)
func uninstall_result(key: String) -> String:
	if key == "cable":
		return _cable_text()
	return ItemSystem.item(packed_id(key)).display_name

func tool_for(kind: String, key: String) -> String:
	return String(config(key).get(kind + "_tool", ""))

func time_for(kind: String, key: String) -> float:
	return float(config(key).get(kind + "_time", 3.0))

## Materials from dismantling (exactly these amounts)
func dismantle_yield(key: String) -> Dictionary:
	var c := config(key)
	if c.has("dismantle"):
		return c.dismantle
	var out := {}
	for type in _build_cost(key):
		out[type] = maxi(1, int(_build_cost(key)[type] * float(c.dismantle_factor)))
	return out

## Scrap from destroying
func debris(key: String) -> Dictionary:
	var c := config(key)
	if c.has("debris"):
		return c.debris
	var total := 0
	for type in _build_cost(key):
		total += int(_build_cost(key)[type])
	return {"scrap": maxi(1, int(round(total * float(c.debris_factor))))}

# ---------------- Who can do it? ----------------

func has_tool(c: CrewMember, tool: String) -> bool:
	return tool == "" or c.inv.count(tool) > 0

## May this character take the job? (tool in the pack)
func worker_ok(c: CrewMember, job: Dictionary) -> bool:
	if not job.kind in KINDS:
		return true
	return has_tool(c, String(job.get("tool", "")))

## Reason why the action is not possible here ("" = possible)
## key: the selected layer ("cable", "dev:…", "tile:…"); empty = device, otherwise tile.
func reason(kind: String, p: Vector2i, key: String = "") -> String:
	var g := ShipSystem.grid
	if not g.in_bounds(p):
		return "Outside the ship."
	if key == "":
		key = key_at(p)
	if key.begins_with("dev:"):
		p = anchor(p)
	var i := g.idx(p)
	if key == "" or not layers_at(p).has(key):
		return "There is nothing here."
	var nm := name_of(key)
	if g.linked.has(i):
		return "The airlock is docked right now. Undock first."
	if StationSystem.reserved(p):
		return "Belongs to the station."
	if ShipConstructionSystem.jobs.has(i):
		return "Already in progress here: " + ShipConstructionSystem.label(ShipConstructionSystem.jobs[i]) + "."
	var cfg := config(key)
	if not kind in cfg.actions:
		return "%s cannot be %s." % [nm, {"uninstall": "uninstalled", "dismantle": "dismantled", "destroy": "destroyed"}[kind]]
	var dev := g.device_at(p) if key.begins_with("dev:") else null
	if key.begins_with("tile:") and g.device_at(p) != null:
		return "%s stands on it. Uninstall the device first (the next right-click selects it)." % g.device_at(p).data().display_name
	if dev != null:
		if dev.lock_level > 0:
			return "Locked – crack it first (hacking)."
		if dev.suit != null and kind != "uninstall":
			return "A space suit hangs in the locker. Only Uninstall is possible."
		if g.linked.has(i):
			return "The airlock is docked right now. Undock first."
	elif key == "tile:floor":
		if g.cables[i] == 1:
			return "There is a cable on the floor. Uninstall the cable first (right-click selects it)."
	# Tool and reachability
	var tool := tool_for(kind, key)
	var with_tool: Array = CrewSystem.crew.filter(func(c): return not c.unconscious and has_tool(c, tool))
	if with_tool.is_empty():
		return "Needs tool: %s (in someone's pack)." % ItemSystem.item(tool).display_name
	for c in with_tool:
		if ShipSystem.nearest_adjacent(c.tile(), [p], 1).ok:
			return ""
	return "Nobody can reach %s." % nm

## Create a job. Returns "" on success, otherwise the reason.
## Multi-tile device (thruster 1×3): each of its tiles stands for the whole device,
## the job sits at the inner tile
func anchor(p: Vector2i) -> Vector2i:
	var dev := ShipSystem.grid.device_at(p)
	return dev.pos if dev != null else p

## key: the selected layer (empty = device, otherwise tile – as before)
func order(kind: String, p: Vector2i, key: String = "") -> String:
	if key == "":
		key = key_at(p)
	if key.begins_with("dev:"):
		p = anchor(p)
	var why := reason(kind, p, key)
	if why != "":
		return why
	var g := ShipSystem.grid
	var job := {"kind": kind, "x": p.x, "y": p.y, "target": key, "tool": tool_for(kind, key), "progress": 0.0,
		"claimed_by": -1, "retry_at": 0.0, "paid": true, "need": time_for(kind, key)}
	if kind == "destroy":
		job.need = 1.0          # progress = damage done (0..1)
		job.hit_acc = 0.0
		job.progress = 1.0 - _cond(p) / 100.0
	ShipConstructionSystem.jobs[g.idx(p)] = job
	return ""

## Is the same object still there?
func target_ok(job: Dictionary) -> bool:
	return layers_at(ShipConstructionSystem.pos_of(job)).has(String(job.target))

## Remove a job without a target (object removed otherwise), without a result
func drop_stale(job: Dictionary) -> void:
	var g := ShipSystem.grid
	var i := g.idx(ShipConstructionSystem.pos_of(job))
	if ShipConstructionSystem.jobs.get(i) == job:
		ShipConstructionSystem.jobs.erase(i)
		GameState.toast("%s is already gone. Job removed." % name_of(String(job.target)))

func _cond(p: Vector2i) -> float:
	var g := ShipSystem.grid
	var dev := g.device_at(p)
	return dev.cond if dev != null else g.cond[g.idx(p)]

func _set_cond(p: Vector2i, v: float) -> void:
	var g := ShipSystem.grid
	var dev := g.device_at(p)
	if dev != null:
		dev.cond = v
		if v <= 0.0:
			dev.broken = true
	else:
		g.cond[g.idx(p)] = v

# ---------------- Destroy: hits ----------------

## Schaden eines Schlags in Trefferpunkten
func hit_damage(c: CrewMember, key: String) -> float:
	var cfg := config(key)
	var best := 0.0
	for tool in cfg.tool_damage:
		if c.inv.count(tool) > 0:
			best = maxf(best, float(cfg.tool_damage[tool]))
	var skill := SkillSystem.effect(c, "combat_armed") if best > 0.0 else SkillSystem.effect(c, "combat_unarmed")
	return (float(cfg.hit_damage) + best) * (1.0 + skill + SkillSystem.effect(c, "work_demolish")) * maxf(0.3, c.health / 100.0)

## Work on destroying for dt game minutes. true = object is broken (done).
func work_destroy(job: Dictionary, c: CrewMember, dt: float) -> bool:
	var p := ShipConstructionSystem.pos_of(job)
	var cfg := config(String(job.target))
	job.hit_acc = float(job.get("hit_acc", 0.0)) + dt * 60.0
	var interval := float(cfg.hit_interval)
	while job.hit_acc >= interval:
		job.hit_acc -= interval
		if not target_ok(job):
			return false
		var dmg := hit_damage(c, String(job.target))
		var left := maxf(0.0, _cond(p) - dmg / float(cfg.hp) * 100.0)
		_set_cond(p, left)
		job.hits = int(job.get("hits", 0)) + 1
		DamageSystem.effects.append({"pos": p, "start": Time.get_ticks_msec(), "small": true})
		if Time.get_ticks_msec() - _last_hit_sound > 90:
			_last_hit_sound = Time.get_ticks_msec()
			SoundSystem.play("hit")
		SkillSystem.train_job(c, job, interval / 60.0)
		job.progress = 1.0 - left / 100.0
		if left <= 0.0:
			return true
	return false

# ---------------- Completion: exactly once ----------------

## Result of a finished job. The job has already been removed from the list.
func finish(job: Dictionary, worker: CrewMember, worker_pos: Vector2i) -> void:
	var g := ShipSystem.grid
	var p := ShipConstructionSystem.pos_of(job)
	var i := g.idx(p)
	if not target_ok(job):
		GameState.toast("%s is already gone." % name_of(String(job.target)))
		return
	var key := String(job.target)
	var kind := String(job.kind)
	if key == "cable":
		# Uninstall a cable: only the cable, device and floor stay; the material is put next to it
		g.cables[i] = 0
		var cspot := p if g.walkable(p) else ShipConstructionSystem.drop_spot(worker_pos)
		for type in Config.CABLE_COST:
			g.drop_items(cspot, type, int(Config.CABLE_COST[type]), 80.0)
		GameState.toast("%s: cable uninstalled – %s is on the floor." % [worker.display_name if worker != null else "Crew", _cable_text()])
		return
	var dev := g.device_at(p) if key.begins_with("dev:") else null
	var cond := dev.cond if dev != null else g.cond[i]
	var results: Array = []   # [type, qty, cond, data]
	var packed: Array = []    # Uninstall: exactly one item with its contents, onto the floor
	match kind:
		"uninstall":
			var d = null
			if dev != null:
				d = dev.to_data()     # with contents (crate) – kept in the item
				d.unknown = false
				d.lock = 0
				# Some parts often break when uninstalled (Ostranauts: VDX-01 transponder)
				if dev.data().uninstall_break > 0.0 and randf() < dev.data().uninstall_break:
					d.broken = true
					d.cond = 0.0
					cond = 0.0
					GameState.toast("%s broke while being uninstalled." % dev.data().display_name, "bad")
			packed = [packed_id(key), 1, cond, d]
		"dismantle":
			var y := dismantle_yield(key)
			for type in y:
				results.append([type, int(y[type]), clampf(cond, 10.0, 100.0), null])
		"destroy":
			var y := debris(key)
			for type in y:
				results.append([type, int(y[type]), 30.0, null])
	# Dismantle/Destroy: put crate contents next to the object unharmed
	var spill: Array = []
	if dev != null and dev.inv != null and kind != "uninstall":
		for it in dev.inv.items:
			spill.append([it.type, it.qty, it.cond, it.get("data")])
	# Whoever is using the device stops
	if dev != null:
		for c in CrewSystem.crew:
			if c.activity != null and c.activity.get("dev") == dev:
				c.stop_activity()
		if g.zone[i] == 1:
			GoalSystem.stripped += 1
		# Docking port: the outer door becomes wall again, the inner row floor again
		if dev.type == "dockport":
			g.remove_dock(dev)
		else:
			g.remove_device(dev)
	else:
		var t := g.tiles[i]
		if t == ShipGrid.Tile.FLOOR:
			ShipConstructionSystem._move_pile_away(i, worker_pos)
			g.set_tile(p, ShipGrid.Tile.SPACE)
		else:
			g.set_tile(p, ShipGrid.Tile.FLOOR)
	var spot := p if g.walkable(p) else ShipConstructionSystem.drop_spot(worker_pos)
	for s in spill:
		g.drop_items(spot, s[0], s[1], s[2], s[3])
	if not packed.is_empty():
		# One complete item on a reachable floor tile (inside)
		var at := p if g.walkable(p) else ShipConstructionSystem.drop_spot(worker_pos)
		g.drop_items(at, packed[0], 1, packed[2], packed[3])
		GameState.toast("%s: uninstall done – %s is on the floor (%.0f kg)." % [worker.display_name if worker != null else "Crew",
			ItemSystem.item(packed[0]).display_name, Inventory.stack_weight({"type": packed[0], "qty": 1, "data": packed[3]})])
		return
	_give(worker, worker_pos, results)
	var parts: PackedStringArray = []
	for r in results:
		parts.append("%d× %s" % [r[1], ItemSystem.item(r[0]).display_name])
	GameState.toast("%s: %s done – %s." % [worker.display_name if worker != null else "Crew", NAMES[kind], ", ".join(parts)])

## Results into the pack, the rest as a pile next to it (full inventory)
func _give(worker: CrewMember, worker_pos: Vector2i, results: Array) -> void:
	var g := ShipSystem.grid
	var spot := worker_pos if g.walkable(worker_pos) else ShipConstructionSystem.drop_spot(worker_pos)
	var dropped := false
	for r in results:
		var left := int(r[1])
		if worker != null:
			if r[3] != null:
				left -= worker.inv.add(r[0], 1, r[2], r[3])
			else:
				left -= worker.inv.add(r[0], left, r[2])
		if left > 0:
			g.drop_items(spot, r[0], left, r[2], r[3])
			dropped = true
	if dropped and worker != null:
		GameState.toast("%s cannot carry everything. The rest is on the floor next to it." % worker.display_name)

# ---------------- Wiedereinbau ----------------

## Can the uninstalled item pk be installed here?
func can_install(pk: String, p: Vector2i) -> bool:
	return install_reason(pk, p) == ""

func install_reason(pk: String, p: Vector2i) -> String:
	var g := ShipSystem.grid
	if not g.in_bounds(p):
		return "Out of bounds."
	var i := g.idx(p)
	if StationSystem.reserved(p) or StationSystem.is_hatch(i):
		return "Belongs to the station."
	if ShipConstructionSystem.jobs.has(i):
		return "There is already a job here."
	var key := key_of_packed(pk)
	var t := g.get_tile(p)
	var has_dev := g.occupied(p)
	var ok := false
	if key == "dev:dockport":
		return "Docking ports are no longer installed – ships dock at the outer door of an airlock."
	elif key.begins_with("dev:") and ItemSystem.device(key.substr(4)).length > 1:
		var why := g.mount_reason(key.substr(4), p, ShipConstructionSystem.build_rot)
		if why != "":
			return why
		for c in _cells(key.substr(4), p, ShipConstructionSystem.build_rot):
			if ShipConstructionSystem.jobs.has(g.idx(c)):
				return "There is already a job here."
		ok = true
	else:
		ok = _fits(key, t, has_dev, p)
	if not ok:
		return "Does not fit here."
	if ShipConstructionSystem.available(pk) <= 0 and not CrewSystem.crew.any(func(c): return c.inv.count(pk) > 0):
		return "No “%s” available." % ItemSystem.item(pk).display_name
	return ""

## Tiles of a device of this type at p with rotation rot (inner tile first)
func _cells(type: String, p: Vector2i, rot: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k in maxi(1, ItemSystem.device(type).length):
		out.append(p - Device.PUSH_DIRS[rot % 4] * k)
	return out

func _fits(key: String, t: int, has_dev: bool, p: Vector2i) -> bool:
	var ok := false
	match key:
		"tile:floor": ok = t == ShipGrid.Tile.SPACE
		"tile:wall", "tile:window": ok = (t == ShipGrid.Tile.SPACE or t == ShipGrid.Tile.FLOOR) and not has_dev
		"tile:door": ok = t != ShipGrid.Tile.DOOR and t != ShipGrid.Tile.SPACE and not has_dev
		_: ok = t == ShipGrid.Tile.FLOOR and not has_dev
	return ok

func install_time(pk: String) -> float:
	var key := key_of_packed(pk)
	if key.begins_with("dev:"):
		return ItemSystem.device(key.substr(4)).build_time
	for t in TILE_KEYS:
		if TILE_KEYS[t] == key:
			return Config.TILE_BUILD_TIME[t]
	return 3.0

## Installing done: put in the uninstalled part (job.packed) with its condition and data
func finish_install(job: Dictionary, worker_pos: Vector2i) -> void:
	var g := ShipSystem.grid
	var p := ShipConstructionSystem.pos_of(job)
	var i := g.idx(p)
	var st: Dictionary = job.get("packed", {"type": job.item, "qty": 1, "cond": 100.0})
	var key := key_of_packed(String(job.item))
	ShipConstructionSystem._move_pile_away(i, worker_pos)
	if key.begins_with("dev:"):
		var dev: Device
		if st.get("data") != null:
			var d: Dictionary = st.data.duplicate(true)
			d.x = p.x
			d.y = p.y
			dev = Device.from_data(d)
		else:
			dev = Device.new(key.substr(4), p)
			dev.cond = float(st.cond)
		if dev.data().rotatable:
			dev.rot = int(job.get("rot", dev.rot))
		var why := ""
		if dev.type == "dockport":
			why = g.dock_check(p).reason
		elif dev.data().length > 1:
			why = g.mount_reason(dev.type, p, dev.rot)
		# Multi-tile device: is the place invalid by now? Then the part is kept
		if why != "":
			GameState.toast("%s: cannot install – %s The part is lying next to it." % [name_of(key), why], "bad")
			g.drop_items(ShipConstructionSystem.drop_spot(worker_pos), String(job.item), 1, float(st.cond), st.get("data"))
			return
		if dev.type == "dockport":
			g.apply_dock(dev, g.dock_check(p).dir)
		else:
			g.put_device(dev)
	else:
		var tile: int = TILE_KEYS.find_key(key)
		g.set_tile(p, tile)
		g.cond[i] = float(st.cond)
	GameState.toast("%s installed (%d %%)." % [name_of(key), int(st.cond)])
