## Objekte entfernen per Rechtsklick-Menü, auf drei Arten:
##   Abbauen  (uninstall) – das ganze Objekt als Gegenstand, wieder einbaubar,
##                          Zustand und eigene Daten bleiben erhalten
##   Zerlegen (dismantle) – in die festgelegten Materialien zerlegen
##   Zerstören (destroy)  – draufschlagen, jeder Schlag macht Schaden, am Ende Müll
## Alle Werte pro Objekttyp stehen in res://data/removal.json (vorläufiges Balancing).
## Die Arbeit selbst erledigt die Crew über die normalen Aufträge (ShipConstructionSystem).
##
## Regeln:
## - Ergebnisse kommen ins Gepäck der arbeitenden Figur; was nicht passt, landet
##   als Haufen zu ihren Füßen (volles Inventar).
## - Kisteninhalt wird bei allen drei Arten unversehrt neben das Objekt gelegt.
## - Verschlossene Behälter muss man erst knacken; ein Spind mit Raumanzug kann
##   nur abgebaut werden (der Anzug bleibt im abgebauten Spind).
## - Werkzeug muss eine Figur im Gepäck tragen; nur solche Figuren übernehmen den Auftrag.
extends Node

const KINDS := ["uninstall", "dismantle", "destroy"]
const NAMES := {"uninstall": "Abbauen", "dismantle": "Zerlegen", "destroy": "Zerstören"}
const TILE_KEYS := {ShipGrid.Tile.FLOOR: "tile:floor", ShipGrid.Tile.WALL: "tile:wall", ShipGrid.Tile.DOOR: "tile:door", ShipGrid.Tile.WINDOW: "tile:window"}

var data: Dictionary = {}
var _last_hit_sound := 0

func _ready() -> void:
	var f := FileAccess.open("res://data/removal.json", FileAccess.READ)
	data = JSON.parse_string(f.get_as_text())
	_register_packed()

# ---------------- Konfiguration ----------------

## Werte für einen Objekttyp (Gerät-ID oder "tile:wall" ...), mit Vorgaben aufgefüllt
func config(key: String) -> Dictionary:
	var out: Dictionary = data.defaults.duplicate(true)
	var id := key.trim_prefix("dev:")
	out.merge(data.get(id, {}), true)
	return out

## Was steht auf dem Feld? "dev:generator", "tile:wall", "tile:rock" oder ""
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

func name_of(key: String) -> String:
	if key.begins_with("dev:"):
		return ItemSystem.device(key.substr(4)).display_name
	if key == "tile:rock":
		return "Fels"
	for t in TILE_KEYS:
		if TILE_KEYS[t] == key:
			return Config.TILE_NAMES[t]
	return "?"

## Gegenstand für ein abgebautes Objekt
func packed_id(key: String) -> String:
	return "pk_" + key.trim_prefix("dev:").replace(":", "_")

## Aus dem Gegenstand wieder den Objekttyp
func key_of_packed(pk: String) -> String:
	var id := pk.trim_prefix("pk_")
	if id.begins_with("tile_"):
		return "tile:" + id.substr(5)
	return "dev:" + id

func is_packed(type: String) -> bool:
	return type.begins_with("pk_")

## Für jedes Gerät und jeden Block einen Gegenstand "(abgebaut)" anlegen
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
		var w := 0.0
		var v := 0.0
		var val := 0
		for type in cost:
			var it := ItemSystem.item(type)
			if it == null:
				continue
			w += it.weight * cost[type]
			v += it.volume * cost[type]
			val += it.value * cost[type]
		var item := ItemData.new()
		item.id = packed_id(key)
		item.display_name = name_of(key) + " (abgebaut)"
		item.weight = clampf(w * float(d.packed_weight_factor), 1.0, float(d.packed_max_weight))
		item.volume = clampf(v * float(d.packed_weight_factor), 1.0, float(d.packed_max_weight))
		item.value = int(val * 0.9)
		item.description = "Abgebaut, kann wieder eingebaut werden (Rechtsklick auf ein freies Feld oder „Einbauen“). Zustand und Inhalt bleiben erhalten."
		ItemSystem.items[item.id] = item

func _build_cost(key: String) -> Dictionary:
	if key.begins_with("dev:"):
		return ItemSystem.device(key.substr(4)).cost
	for t in TILE_KEYS:
		if TILE_KEYS[t] == key:
			return Config.TILE_COST[t]
	return {}

func tool_for(kind: String, key: String) -> String:
	return String(config(key).get(kind + "_tool", ""))

func time_for(kind: String, key: String) -> float:
	return float(config(key).get(kind + "_time", 3.0))

## Materialien beim Zerlegen (genau diese Mengen)
func dismantle_yield(key: String) -> Dictionary:
	var c := config(key)
	if c.has("dismantle"):
		return c.dismantle
	var out := {}
	for type in _build_cost(key):
		out[type] = maxi(1, int(_build_cost(key)[type] * float(c.dismantle_factor)))
	return out

## Müll beim Zerstören
func debris(key: String) -> Dictionary:
	var c := config(key)
	if c.has("debris"):
		return c.debris
	var total := 0
	for type in _build_cost(key):
		total += int(_build_cost(key)[type])
	return {"scrap": maxi(1, int(round(total * float(c.debris_factor))))}

# ---------------- Wer kann es? ----------------

func has_tool(c: CrewMember, tool: String) -> bool:
	return tool == "" or c.inv.count(tool) > 0

## Darf diese Figur den Auftrag übernehmen? (Werkzeug im Gepäck)
func worker_ok(c: CrewMember, job: Dictionary) -> bool:
	if not job.kind in KINDS:
		return true
	return has_tool(c, String(job.get("tool", "")))

## Grund, warum die Aktion hier nicht geht ("" = es geht)
func reason(kind: String, p: Vector2i) -> String:
	var g := ShipSystem.grid
	if not g.in_bounds(p):
		return "Außerhalb des Schiffs."
	var i := g.idx(p)
	var key := key_at(p)
	if key == "":
		return "Hier ist nichts."
	var nm := name_of(key)
	if g.linked.has(i):
		return "Die Schleuse ist gerade angedockt. Erst abdocken."
	if StationSystem.reserved(p):
		return "Gehört der Station."
	if ShipConstructionSystem.jobs.has(i):
		return "Hier läuft schon: " + ShipConstructionSystem.label(ShipConstructionSystem.jobs[i]) + "."
	var cfg := config(key)
	if not kind in cfg.actions:
		return "%s lässt sich nicht %s." % [nm, {"uninstall": "abbauen", "dismantle": "zerlegen", "destroy": "zerstören"}[kind]]
	var dev := g.device_at(p)
	if dev != null:
		if dev.lock_level > 0:
			return "Verschlossen – erst knacken (Hacken)."
		if dev.suit != null and kind != "uninstall":
			return "Im Spind hängt ein Raumanzug. Nur Abbauen ist möglich."
		if g.linked.has(i):
			return "Die Schleuse ist gerade angedockt. Erst abdocken."
	elif key == "tile:floor":
		if g.cables[i] == 1:
			return "Auf dem Boden liegt ein Kabel. Erst das Kabel entfernen (Abreißen X)."
	# Werkzeug und Erreichbarkeit
	var tool := tool_for(kind, key)
	var with_tool: Array = CrewSystem.crew.filter(func(c): return not c.unconscious and has_tool(c, tool))
	if with_tool.is_empty():
		return "Braucht Werkzeug: %s (im Gepäck einer Figur)." % ItemSystem.item(tool).display_name
	for c in with_tool:
		if ShipSystem.nearest_adjacent(c.tile(), [p], 1).ok:
			return ""
	return "Niemand kommt an %s heran." % nm

## Auftrag anlegen. Gibt "" bei Erfolg zurück, sonst den Grund.
func order(kind: String, p: Vector2i) -> String:
	var why := reason(kind, p)
	if why != "":
		return why
	var g := ShipSystem.grid
	var key := key_at(p)
	var job := {"kind": kind, "x": p.x, "y": p.y, "target": key, "tool": tool_for(kind, key), "progress": 0.0,
		"claimed_by": -1, "retry_at": 0.0, "paid": true, "need": time_for(kind, key)}
	if kind == "destroy":
		job.need = 1.0          # Fortschritt = angerichteter Schaden (0..1)
		job.hit_acc = 0.0
		job.progress = 1.0 - _cond(p) / 100.0
	ShipConstructionSystem.jobs[g.idx(p)] = job
	return ""

## Steht noch dasselbe Objekt da?
func target_ok(job: Dictionary) -> bool:
	return key_at(ShipConstructionSystem.pos_of(job)) == String(job.target)

## Auftrag ohne Ziel (Objekt anderweitig entfernt) auflösen, ohne Ergebnis
func drop_stale(job: Dictionary) -> void:
	var g := ShipSystem.grid
	var i := g.idx(ShipConstructionSystem.pos_of(job))
	if ShipConstructionSystem.jobs.get(i) == job:
		ShipConstructionSystem.jobs.erase(i)
		GameState.toast("%s ist schon weg. Auftrag aufgelöst." % name_of(String(job.target)))

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

# ---------------- Zerstören: Schläge ----------------

## Schaden eines Schlags in Trefferpunkten
func hit_damage(c: CrewMember, key: String) -> float:
	var cfg := config(key)
	var best := 0.0
	for tool in cfg.tool_damage:
		if c.inv.count(tool) > 0:
			best = maxf(best, float(cfg.tool_damage[tool]))
	var skill := SkillSystem.effect(c, "combat_armed") if best > 0.0 else SkillSystem.effect(c, "combat_unarmed")
	return (float(cfg.hit_damage) + best) * (1.0 + skill + SkillSystem.effect(c, "work_demolish")) * maxf(0.3, c.health / 100.0)

## Arbeit am Zerstören für dt Spielminuten. true = Objekt ist kaputt (fertig).
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

# ---------------- Abschluss: genau einmal ----------------

## Ergebnis eines fertigen Auftrags. Der Auftrag ist schon aus der Liste entfernt.
func finish(job: Dictionary, worker: CrewMember, worker_pos: Vector2i) -> void:
	var g := ShipSystem.grid
	var p := ShipConstructionSystem.pos_of(job)
	var i := g.idx(p)
	if not target_ok(job):
		GameState.toast("%s ist schon weg." % name_of(String(job.target)))
		return
	var key := String(job.target)
	var kind := String(job.kind)
	var dev := g.device_at(p)
	var cond := _cond(p)
	var results: Array = []   # [type, qty, cond, data]
	match kind:
		"uninstall":
			var d = null
			if dev != null:
				d = dev.to_data()
				d.items = []          # Inhalt kommt auf den Boden (siehe unten)
				d.unknown = false
				d.lock = 0
			results.append([packed_id(key), 1, cond, d])
		"dismantle":
			var y := dismantle_yield(key)
			for type in y:
				results.append([type, int(y[type]), clampf(cond, 10.0, 100.0), null])
		"destroy":
			var y := debris(key)
			for type in y:
				results.append([type, int(y[type]), 30.0, null])
	# Kisteninhalt unversehrt neben das Objekt legen
	var spill: Array = []
	if dev != null and dev.inv != null:
		for it in dev.inv.items:
			spill.append([it.type, it.qty, it.cond, it.get("data")])
	# Wer das Gerät gerade benutzt, hört damit auf
	if dev != null:
		for c in CrewSystem.crew:
			if c.activity != null and c.activity.get("dev") == dev:
				c.stop_activity()
		if g.zone[i] == 1:
			GoalSystem.stripped += 1
		g.devices.erase(i)
		# Andockschleuse: das Loch in der Außenwand wird wieder Wand
		if dev.type == "dockport":
			g.set_tile(p, ShipGrid.Tile.WALL)
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
	_give(worker, worker_pos, results)
	var parts: PackedStringArray = []
	for r in results:
		parts.append("%d× %s" % [r[1], ItemSystem.item(r[0]).display_name])
	GameState.toast("%s: %s fertig – %s." % [worker.display_name if worker != null else "Crew", NAMES[kind], ", ".join(parts)])

## Ergebnisse ins Gepäck, Rest als Haufen daneben (volles Inventar)
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
		GameState.toast("%s kann nicht alles tragen. Der Rest liegt daneben auf dem Boden." % worker.display_name)

# ---------------- Wiedereinbau ----------------

## Kann der abgebaute Gegenstand pk hier eingebaut werden?
func can_install(pk: String, p: Vector2i) -> bool:
	return install_reason(pk, p) == ""

func install_reason(pk: String, p: Vector2i) -> String:
	var g := ShipSystem.grid
	if not g.in_bounds(p):
		return "Außerhalb."
	var i := g.idx(p)
	if StationSystem.reserved(p) or StationSystem.is_hatch(i):
		return "Gehört der Station."
	if ShipConstructionSystem.jobs.has(i):
		return "Hier läuft schon ein Auftrag."
	var key := key_of_packed(pk)
	var t := g.get_tile(p)
	var has_dev := g.devices.has(i)
	var ok := false
	match key:
		"dev:dockport": ok = t == ShipGrid.Tile.WALL and not has_dev and ShipSystem.port_dir(p) != Vector2i.ZERO
		"tile:floor": ok = t == ShipGrid.Tile.SPACE
		"tile:wall", "tile:window": ok = (t == ShipGrid.Tile.SPACE or t == ShipGrid.Tile.FLOOR) and not has_dev
		"tile:door": ok = t != ShipGrid.Tile.DOOR and t != ShipGrid.Tile.SPACE and not has_dev
		_: ok = t == ShipGrid.Tile.FLOOR and not has_dev
	if not ok:
		return "Passt hier nicht hin."
	if ShipConstructionSystem.available(pk) <= 0 and not CrewSystem.crew.any(func(c): return c.inv.count(pk) > 0):
		return "Kein „%s“ vorhanden." % ItemSystem.item(pk).display_name
	return ""

func install_time(pk: String) -> float:
	var key := key_of_packed(pk)
	if key.begins_with("dev:"):
		return ItemSystem.device(key.substr(4)).build_time
	for t in TILE_KEYS:
		if TILE_KEYS[t] == key:
			return Config.TILE_BUILD_TIME[t]
	return 3.0

## Einbauen fertig: das abgebaute Stück (job.packed) mit Zustand und Daten einsetzen
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
		if dev.type == "dockport":
			g.set_tile(p, ShipGrid.Tile.DOOR)
		g.devices[i] = dev
	else:
		var tile: int = TILE_KEYS.find_key(key)
		g.set_tile(p, tile)
		g.cond[i] = float(st.cond)
	GameState.toast("%s eingebaut (%d %%)." % [name_of(key), int(st.cond)])
