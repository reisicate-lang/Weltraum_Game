## Begehbare Stationen. Beim Andocken entsteht rechts neben dem Schiff ein
## Druckschlauch mit Luft und dahinter die Station: ein langer Gang mit
## Räumen (Markt, Bar, Auftragsbrett, Heuerbüro, Bergungsamt, Kreditbüro,
## Werft). In jedem Raum steht jemand hinter dem Tresen. Klick auf die Figur
## oder den Tresen: Die ausgewählte Figur läuft hin, dann beginnt das Gespräch.
## Beim Abdocken verschwindet alles wieder, die Schiffswand wird geschlossen.
extends Node

const ZONE := 3
const PITCH := 5            ## Höhe eines Raums samt Wand
const ROOM_W := 9           ## Innenbreite eines Raums
const DEFAULT_ROOMS := ["market", "bar", "board", "hiring", "claims", "bank"]

## Raumarten: Tresen-Gerät, Reiter im Handelsfenster, wer dort arbeitet, was sie sagen
const ROOMS := {
	"market": {"name": "Markt", "desk": "st_market", "tab": "sell", "role": "Händler",
		"lines": ["Frische Ware, kaum gebraucht!", "Platten, Kupfer, Rationen – alles da.", "Zeig mal, was du im Gepäck hast."]},
	"bar": {"name": "Bar", "desk": "st_bar", "tab": "station", "role": "Barkeeper",
		"lines": ["Noch einen? Geht aufs Haus. Nein, war ein Witz.", "Hier hört man alles, wenn man still ist.", "Die Bühne ist frei, falls du singen willst."]},
	"board": {"name": "Auftragsbrett", "desk": "st_board", "tab": "jobs", "role": "Vermittlerin",
		"lines": ["Neue Aushänge, frisch von heute.", "Pünktlich liefern, dann gibt es Ansehen.", "Die Gilde zahlt gut, die Patrouille pünktlich."]},
	"hiring": {"name": "Heuerbüro", "desk": "st_hiring", "tab": "crew", "role": "Heuerbeamter",
		"lines": ["Brauchst du Leute? Die da hinten suchen eine Koje.", "Handgeld vorab, Lohn jeden Tag.", "Gute Mechaniker sind selten geworden."]},
	"claims": {"name": "Bergungsamt", "desk": "st_claims", "tab": "salvage", "role": "Sachbearbeiter",
		"lines": ["Bergungsrechte gibt es nur gegen Gebühr.", "Formular B-7, dreifach. Kleiner Scherz.", "Draußen treibt wieder was Neues."]},
	"bank": {"name": "Kreditbüro", "desk": "st_bank", "tab": "bank", "role": "Bankangestellte",
		"lines": ["Ihre nächste Rate ist bald fällig.", "Pünktliche Zahler sind uns die liebsten.", "Möchten Sie heute etwas tilgen?"]},
	"shipyard": {"name": "Werft", "desk": "st_shipyard", "tab": "ships", "role": "Werftmeisterin",
		"lines": ["Ein neues Schiff? Ich hab da was Schönes.", "Dein Kahn sieht aus, als hält er nur noch aus Gewohnheit.", "Wracks melden wir auch an."]},
}
const NAMES := ["Ada", "Bo", "Cass", "Dario", "Edda", "Fenn", "Gita", "Hal", "Ines", "Jory", "Kemal", "Lu",
	"Mads", "Nia", "Oskar", "Pia", "Rune", "Suri", "Teo", "Wen", "Yara", "Zeno"]
const VISITOR_LINES := ["Schon gehört? Im Trümmerfeld treiben Plünderer.", "Die Luft hier riecht nach Maschinenöl.",
	"Mein Schiff steht seit drei Wochen im Dock.", "Am Kármán-Ring zahlen sie mehr für Schrott.", "Wer hat hier schon wieder geraucht?"]
const COLORS := [Color(0.55, 0.7, 0.85), Color(0.85, 0.6, 0.45), Color(0.6, 0.8, 0.55), Color(0.8, 0.55, 0.75),
	Color(0.85, 0.8, 0.5), Color(0.55, 0.75, 0.75)]

var station_id := ""
var rooms: Array[Dictionary] = []   ## {kind, inner: Rect2i, desk: Vector2i, door: Vector2i}
var npcs: Array[Dictionary] = []    ## {name, kind, room, pos, home, path, wait, line, line_until, color, ref}
var tiles: Array[int] = []          ## alle Felder der Station und des Schlauchs
var _own: Dictionary = {}           ## dieselben Felder zum schnellen Nachschlagen
var area := Rect2i()                ## gesperrt für Bauen (Station und Schlauch)
var hatch := -1                     ## Tür in der Schiffswand
var corridor_x := 0
var pending: Dictionary = {}        ## {crew, npc} – Figur läuft gerade zu einem Gespräch
var _sync := 0.0
var _rng := RandomNumberGenerator.new()

## Zustand vergessen, ohne das Gitter anzufassen (neues Spiel, neues Gitter)
func reset() -> void:
	tiles.clear()
	_own.clear()
	rooms.clear()
	npcs.clear()
	pending = {}
	hatch = -1
	station_id = ""
	area = Rect2i()

func active() -> bool:
	return station_id != ""

func is_hatch(i: int) -> bool:
	return i == hatch and hatch >= 0

## Gehört das Feld zur Station (dort darf man nichts bauen)?
func reserved(p: Vector2i) -> bool:
	return active() and _own.has(ShipSystem.grid.idx(p))

# ---------------- Aufbauen und Abbauen ----------------

## Baut die Station zum Ort id. Gibt false zurück, wenn kein Platz ist.
func build(id: String) -> bool:
	clear()
	var l := PhysicsSystem.loc(id)
	if l.is_empty() or String(l.get("kind", "")) != "station":
		return false
	var g := ShipSystem.grid
	# Wie weit reicht das Schiff (samt Wrack) nach rechts?
	var max_x := -1
	var ys: Array[int] = []
	for i in g.tiles.size():
		if g.tiles[i] != ShipGrid.Tile.SPACE and g.zone[i] != ZONE:
			max_x = maxi(max_x, g.pos(i).x)
			if g.zone[i] == 0:
				ys.append(g.pos(i).y)
	if ys.is_empty():
		return false
	var mid_y: float = (ys.min() + ys.max()) / 2.0
	# Luke: eine Außenwand des Schiffs mit Innenraum links und freiem All rechts
	var best := Vector2i(-1, -1)
	for i in g.tiles.size():
		var p := g.pos(i)
		if g.tiles[i] != ShipGrid.Tile.WALL or g.zone[i] != 0:
			continue
		var inner := p + Vector2i(-1, 0)
		if not g.in_bounds(inner) or not g.walkable(inner) or g.zone[g.idx(inner)] != 0 or g.pressure(g.idx(inner)) < 50.0:
			continue
		if AirlockSystem.is_lock_tile(g.idx(inner)):
			continue
		var free := true
		for x in range(p.x + 1, g.width):
			if g.get_tile(Vector2i(x, p.y)) != ShipGrid.Tile.SPACE:
				free = false
				break
		if not free:
			continue
		if best.x < 0 or p.x > best.x or (p.x == best.x and absf(p.y - mid_y) < absf(best.y - mid_y)):
			best = p
	var sx := max_x + 3
	if best.x < 0 or sx + ROOM_W + 4 > g.width - 1:
		GameState.toast("Kein Platz für den Andockschlauch. Handel geht nur über das Terminal.")
		return false
	var kinds: Array = l.get("rooms", DEFAULT_ROOMS).duplicate()
	if l.get("shipyard", false) and not "shipyard" in kinds:
		kinds.append("shipyard")
	var h := kinds.size() * PITCH + 1
	var top := clampi(best.y - h / 2, 1, g.height - 1 - h)
	if best.y <= top or best.y >= top + h - 1:
		GameState.toast("Kein Platz für den Andockschlauch. Handel geht nur über das Terminal.")
		return false
	station_id = id
	_rng.seed = hash(id)
	var right := sx + 3 + ROOM_W + 1
	area = Rect2i(best.x + 1, top, right - best.x, h)
	corridor_x = sx + 1
	# Hülle, Gang (2 breit) und Raumwände
	for y in range(top, top + h):
		for x in range(sx, right + 1):
			var edge := x == sx or x == right or y == top or y == top + h - 1 or x == sx + 3
			_put(g, Vector2i(x, y), ShipGrid.Tile.WALL if edge else ShipGrid.Tile.FLOOR)
	for k in kinds.size():
		var r := top + k * PITCH
		for x in range(sx + 3, right + 1):
			_put(g, Vector2i(x, r), ShipGrid.Tile.WALL)
		var door := Vector2i(sx + 3, r + 2)
		_put(g, door, ShipGrid.Tile.DOOR)
		var inner := Rect2i(sx + 4, r + 1, ROOM_W, PITCH - 1)
		var desk := Vector2i(sx + 4 + ROOM_W - 3, r + 2)
		var info: Dictionary = ROOMS[kinds[k]]
		g.place_device(info.desk, desk)
		rooms.append({"kind": kinds[k], "inner": inner, "desk": desk, "door": door})
	# Druckschlauch von der Schiffswand zum Gang
	for x in range(best.x + 1, sx):
		_put(g, Vector2i(x, best.y), ShipGrid.Tile.FLOOR)
		for dy in [-1, 1]:
			var q := Vector2i(x, best.y + dy)
			if g.get_tile(q) == ShipGrid.Tile.SPACE:
				_put(g, q, ShipGrid.Tile.WALL)
	_put(g, Vector2i(sx, best.y), ShipGrid.Tile.DOOR)
	hatch = g.idx(best)
	g.set_tile(best, ShipGrid.Tile.DOOR)
	for i in tiles:
		if g.holds_air(i):
			g.fill_air(i)
	_spawn_npcs()
	EventBus.ship_changed.emit()
	return true

func _put(g: ShipGrid, p: Vector2i, t: int) -> void:
	var i := g.idx(p)
	g.set_tile(p, t)
	g.zone[i] = ZONE
	g.cables[i] = 0
	if not _own.has(i):
		tiles.append(i)
		_own[i] = true

## Station entfernen, Luke wieder zur Wand machen
func clear() -> void:
	var g := ShipSystem.grid
	if g != null:
		for i in tiles:
			if i < 0 or i >= g.tiles.size():
				continue
			g.devices.erase(i)
			g.piles.erase(i)
			ShipConstructionSystem.jobs.erase(i)
			g.tiles[i] = ShipGrid.Tile.SPACE
			g.o2[i] = 0.0; g.n2[i] = 0.0; g.co2[i] = 0.0
			g.temp[i] = Config.SPACE_TEMP
			g.fire[i] = 0
			g.zone[i] = 0
		# Reste aus einem Spielstand (Liste nicht gespeichert)
		for i in g.tiles.size():
			if g.zone[i] == ZONE:
				g.devices.erase(i)
				g.piles.erase(i)
				g.tiles[i] = ShipGrid.Tile.SPACE
				g.o2[i] = 0.0; g.n2[i] = 0.0; g.co2[i] = 0.0
				g.zone[i] = 0
		if hatch >= 0 and hatch < g.tiles.size():
			g.tiles[hatch] = ShipGrid.Tile.WALL
		EventBus.ship_changed.emit()
	tiles.clear()
	_own.clear()
	rooms.clear()
	npcs.clear()
	pending = {}
	hatch = -1
	station_id = ""
	area = Rect2i()

## Ist niemand von der Crew mehr auf der Station?
func clearable() -> bool:
	if not active():
		return true
	var g := ShipSystem.grid
	for c in CrewSystem.crew:
		if g.zone[g.idx(c.tile())] == ZONE:
			return false
	return true

# ---------------- Figuren ----------------

func _spawn_npcs() -> void:
	npcs.clear()
	var used: Array = []
	for r in rooms:
		var info: Dictionary = ROOMS[r.kind]
		var inner: Rect2i = r.inner
		var behind := Rect2i(r.desk.x + 1, inner.position.y, inner.end.x - r.desk.x - 1, inner.size.y)
		_add_npc(_name(used) + " (" + info.role + ")", "staff", r, behind, info.lines)
		if r.kind == "bar":
			var con: Dictionary = DialogueSystem.CONTACTS.get(station_id, {})
			if not con.is_empty():
				_add_npc(String(con.name), "contact", r, _front(r), [])
	for k in 2:
		var top := area.position.y + 1
		_add_npc(_name(used), "visitor", {}, Rect2i(corridor_x, top, 2, area.size.y - 2), VISITOR_LINES)
	_sync_candidates()

func _front(r: Dictionary) -> Rect2i:
	var inner: Rect2i = r.inner
	return Rect2i(inner.position.x, inner.position.y, r.desk.x - inner.position.x, inner.size.y)

func _name(used: Array) -> String:
	for k in 30:
		var n: String = NAMES[_rng.randi() % NAMES.size()]
		if not n in used:
			used.append(n)
			return n
	return "Gast"

func _add_npc(n: String, kind: String, room: Dictionary, home: Rect2i, lines: Array, ref = null) -> Dictionary:
	var g := ShipSystem.grid
	var spot := _random_spot(home)
	var npc := {"name": n, "kind": kind, "room": room.get("kind", ""), "pos": Vector2(spot) + Vector2(0.5, 0.5),
		"home": home, "path": [], "wait": _rng.randf_range(1.0, 8.0), "line": "", "line_until": 0.0,
		"bark_in": _rng.randf_range(20.0, 90.0), "lines": lines, "ref": ref,
		"color": COLORS[_rng.randi() % COLORS.size()] if ref == null else ref.color}
	if not g.walkable(spot):
		npc.pos = Vector2(home.position) + Vector2(0.5, 0.5)
	npcs.append(npc)
	return npc

func _random_spot(home: Rect2i) -> Vector2i:
	var g := ShipSystem.grid
	for k in 20:
		var p := Vector2i(_rng.randi_range(home.position.x, home.end.x - 1), _rng.randi_range(home.position.y, home.end.y - 1))
		if g.walkable(p):
			return p
	return home.position

## Bewerber stehen leibhaftig im Heuerbüro
func _sync_candidates() -> void:
	var hiring := {}
	for r in rooms:
		if r.kind == "hiring":
			hiring = r
	if hiring.is_empty():
		return
	var cands: Array = NPCSystem.candidates_here()
	npcs.assign(npcs.filter(func(n): return n.kind != "candidate" or n.ref in cands))
	for c in cands:
		if not npcs.any(func(n): return n.ref == c):
			_add_npc(c.display_name, "candidate", hiring, _front(hiring), ["Ich suche Arbeit. %d Cr am Tag, und ich bin dabei." % c.salary], c)

func step(dt: float) -> void:
	if not active():
		return
	var g := ShipSystem.grid
	# Die Station hält ihre Luft selbst
	for i in tiles:
		if g.holds_air(i):
			g.fill_air(i)
	_sync -= dt
	if _sync <= 0.0:
		_sync = 1.0
		_sync_candidates()
	var secs := dt * 60.0
	for n in npcs:
		_move_npc(n, secs)
	# Wartet jemand auf ein Gespräch?
	if not pending.is_empty():
		var c: CrewMember = pending.crew
		var npc: Dictionary = pending.npc
		var spot: Vector2 = Vector2(pending.target) + Vector2(0.5, 0.5)
		if not c in CrewSystem.crew or not npc in npcs:
			pending = {}
		elif c.pos.distance_to(npc.pos) <= 2.3 or c.pos.distance_to(spot) <= 1.6:
			pending = {}
			talk(npc, c)
		elif c.order == null and c.path.is_empty():
			pending = {}

func _move_npc(n: Dictionary, secs: float) -> void:
	n.bark_in -= secs
	if n.bark_in <= 0.0 and not n.lines.is_empty():
		n.bark_in = _rng.randf_range(60.0, 180.0)
		n.line = String(n.lines[_rng.randi() % n.lines.size()])
		n.line_until = GameState.time + 0.1
	var path: Array = n.path
	if path.is_empty():
		n.wait -= secs
		if n.wait <= 0.0:
			n.wait = _rng.randf_range(4.0, 14.0)
			var from := Vector2i(n.pos)
			var to := _random_spot(n.home)
			if to != from:
				n.path = ShipSystem.find_path(from, to)
		return
	var left := secs * 1.2
	while left > 0.0 and not path.is_empty():
		var target := Vector2(path[0]) + Vector2(0.5, 0.5)
		var d: float = n.pos.distance_to(target)
		if d <= left:
			n.pos = target
			left -= d
			path.pop_front()
		else:
			n.pos += (target - n.pos) / d * left
			left = 0.0

func npc_at(world: Vector2) -> Dictionary:
	for n in npcs:
		if n.pos.distance_to(world) < 0.5:
			return n
	return {}

## Wer steht hinter diesem Tresen?
func npc_for_desk(p: Vector2i) -> Dictionary:
	for r in rooms:
		if r.desk == p:
			for n in npcs:
				if n.kind == "staff" and n.room == r.kind:
					return n
	return {}

# ---------------- Gespräche ----------------

## Klick auf eine Figur oder einen Tresen der Station. true = erledigt.
func click(t: Vector2i, world: Vector2) -> bool:
	if not active():
		return false
	var npc := npc_at(world)
	if npc.is_empty():
		npc = npc_for_desk(t)
	if npc.is_empty():
		return false
	var c: CrewMember = GameState.selected if GameState.selected != null else CrewSystem.player()
	if c == null:
		return true
	approach(c, npc)
	return true

## Figur zum Gesprächspartner schicken (oder gleich reden, wenn sie nah genug ist)
func approach(c: CrewMember, npc: Dictionary) -> void:
	if c.pos.distance_to(npc.pos) <= 2.3:
		talk(npc, c)
		return
	var target := Vector2i(npc.pos)
	if npc.kind == "staff":
		for r in rooms:
			if r.kind == npc.room:
				target = r.desk
	var res := ShipSystem.nearest_adjacent(c.tile(), [target], 1)
	if not res.ok or not c.order_move(res.path[-1] if not res.path.is_empty() else c.tile()):
		GameState.toast(c.display_name + " findet keinen Weg zu " + String(npc.name) + ".")
		return
	pending = {"crew": c, "npc": npc, "target": target}
	GameState.toast(c.display_name + " geht zu " + String(npc.name) + ".")

## Gespräch beginnen: passendes Fenster öffnen, Figur grüßt
func talk(npc: Dictionary, c: CrewMember) -> void:
	GameState.selected = c
	var tab := "station"
	var line := ""
	match npc.kind:
		"staff":
			var info: Dictionary = ROOMS[npc.room]
			tab = info.tab
			line = "%s: „%s“" % [String(npc.name).split(" (")[0], _greeting(npc.room, c)]
		"contact":
			tab = "station"
			line = "%s: „Setz dich. Was führt dich her?“" % String(npc.name).split(",")[0]
		"candidate":
			tab = "crew"
			line = "%s: „%s“" % [npc.name, npc.lines[0]]
		_:
			npc.line = String(npc.lines[_rng.randi() % npc.lines.size()])
			npc.line_until = GameState.time + 0.1
			GameState.toast("%s: „%s“" % [npc.name, npc.line])
			return
	SkillSystem.train(c, "folk", 0.5)
	UIManager.open_talk(tab, line, npc.room if npc.kind == "staff" else npc.kind)

func _greeting(kind: String, c: CrewMember) -> String:
	match kind:
		"market":
			return "Willkommen, %s. Ich kaufe, was du tragen kannst." % c.display_name.split(" ")[0]
		"bank":
			return "Restschuld %d Cr. Die nächste Rate ist in %.1f Tagen fällig." % [EconomySystem.debt, maxf(0.0, (EconomySystem.next_payment - GameState.time) / 1440.0)]
		"claims":
			return "Ein neues Bergungsrecht kostet %d Cr." % Config.CLAIM_FEE
		"hiring":
			return "%d Leute suchen gerade Arbeit." % NPCSystem.candidates_here().size()
		"board":
			return "%d Aufträge hängen aus." % QuestSystem.offers_here().size()
	var lines: Array = ROOMS[kind].lines
	return String(lines[_rng.randi() % lines.size()])

# ---------------- Speichern ----------------

func to_data() -> Dictionary:
	var g := ShipSystem.grid
	return {"id": station_id, "hatch": hatch, "hatch_pos": [g.pos(hatch).x, g.pos(hatch).y] if hatch >= 0 else []}

## Nach dem Laden: alte Stationsfelder weg, Station frisch aufbauen
func from_data(d: Dictionary) -> void:
	tiles.clear()
	hatch = int(d.get("hatch", -1))
	station_id = "x"
	clear()
	if PhysicsSystem.docked != "":
		build(PhysicsSystem.docked)
