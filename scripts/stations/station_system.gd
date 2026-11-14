## Walkable stations. When docking, the station is built right at a free airlock
## (door to door, no corridor in between): a long hall with
## rooms (market, bar, job board, hiring office, salvage office, credit office,
## shipyard). In every room someone stands behind the counter. Click the character
## or the counter: the selected character walks there, then the conversation starts.
## When undocking everything disappears again and the airlock is released.
extends Node

const ZONE := 3
## Sizes in the fine grid (as before 5 and 9 of the twice as large tiles)
const PITCH := 5 * Config.GRID_SCALE    ## Height of a room including the wall
const ROOM_W := 9 * Config.GRID_SCALE   ## inner width of a room
const CORR := 2 * Config.GRID_SCALE     ## Width of the hall
const WALL_V := 1 + CORR                ## Room wall with the doors
const RS := 2 + CORR                    ## first row inside the rooms
const DEFAULT_ROOMS := ["market", "bar", "board", "hiring", "claims", "bank"]

## Room kinds: counter device, tab in the trade window, who works there, what they say
const ROOMS := {
	"market": {"name": "Market", "desk": "st_market", "tab": "sell", "role": "Trader",
		"lines": ["Fresh goods, barely used!", "Plates, copper, rations – all here.", "Show me what's in your pack."]},
	"bar": {"name": "Bar", "desk": "st_bar", "tab": "station", "role": "Bartender",
		"lines": ["Another one? On the house. No, just kidding.", "You hear everything here if you keep quiet.", "The stage is free if you want to sing."]},
	"board": {"name": "Job Board", "desk": "st_board", "tab": "jobs", "role": "Broker",
		"lines": ["New notices, fresh today.", "Deliver on time and you earn reputation.", "The guild pays well, the patrol pays on time."]},
	"hiring": {"name": "Hiring Office", "desk": "st_hiring", "tab": "crew", "role": "Hiring clerk",
		"lines": ["Need people? Those over there are looking for a berth.", "Signing money up front, wages every day.", "Good mechanics have become rare."]},
	"claims": {"name": "Salvage Office", "desk": "st_claims", "tab": "salvage", "role": "Clerk",
		"lines": ["No permit, no salvage. N.A.S.S. checks transponders.", "Form B-7, in triplicate. Just kidding.", "Something new is drifting outside again."]},
	"bank": {"name": "Credit Office", "desk": "st_bank", "tab": "bank", "role": "Bank clerk",
		"lines": ["Your next instalment is due soon.", "We like punctual payers best.", "Would you like to pay something off today?"]},
	"shipyard": {"name": "Shipyard", "desk": "st_shipyard", "tab": "ships", "role": "Shipyard master",
		"lines": ["A new ship? I've got something nice.", "Your tub looks like it only holds together out of habit.", "We register wrecks too."]},
}
const NAMES := ["Ada", "Bo", "Cass", "Dario", "Edda", "Fenn", "Gita", "Hal", "Ines", "Jory", "Kemal", "Lu",
	"Mads", "Nia", "Oskar", "Pia", "Rune", "Suri", "Teo", "Wen", "Yara", "Zeno"]
const VISITOR_LINES := ["Heard? There are plunderers in the debris field.", "The air here smells of machine oil.",
	"My ship has been in dock for three weeks.", "They pay more for scrap at the Kármán Ring.", "Who's been smoking in here again?"]
const COLORS := [Color(0.55, 0.7, 0.85), Color(0.85, 0.6, 0.45), Color(0.6, 0.8, 0.55), Color(0.8, 0.55, 0.75),
	Color(0.85, 0.8, 0.5), Color(0.55, 0.75, 0.75)]

var station_id := ""
var rooms: Array[Dictionary] = []   ## {kind, inner: Rect2i, desk: Vector2i, door: Vector2i}
var npcs: Array[Dictionary] = []    ## {name, kind, room, pos, home, path, wait, line, line_until, color, ref}
var tiles: Array[int] = []          ## all tiles of the station
var _own: Dictionary = {}           ## the same tiles for fast lookup
var area := Rect2i()                ## outline of the station
var hatch := -1                     ## connected docking port of the ship (tile index)
var corridor := Rect2i()
var pending: Dictionary = {}        ## {crew, npc} – a character is walking to a conversation
var _sync := 0.0
var _rng := RandomNumberGenerator.new()

## Forget the state without touching the grid (new game, new grid)
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

## Does the tile belong to the station (nothing may be built there)?
func reserved(p: Vector2i) -> bool:
	return active() and _own.has(ShipSystem.grid.idx(p))

# ---------------- Building and removing ----------------

## Docking points of the station: which way its docking door faces.
## "west" means: the station lies to the east, the ship docks with an airlock facing east.
const DOCK_DIRS := {"west": Vector2i(1, 0), "east": Vector2i(-1, 0), "north": Vector2i(0, 1), "south": Vector2i(0, -1)}

## Builds the station for place id at a free docking port of the ship:
## the station's docking door right in front of the airlock (door to door), no corridors in between.
## Returns false (with a message) if no airlock fits.
func build(id: String) -> bool:
	clear()
	if not Config.ENABLE_STATION:
		return false
	var l := PhysicsSystem.loc(id)
	if l.is_empty() or String(l.get("kind", "")) != "station":
		return false
	var design := DesignLoader.read_design("places/" + id)
	if not design.is_empty():
		return _build_design(id, design)
	var g := ShipSystem.grid
	# Every free port (outer door of an airlock) fits, in any direction; the one
	# aligned when clamping comes first (ShipSystem.dock_pref)
	var ports: Array = ShipSystem.free_ports()
	if ShipSystem.ports().is_empty():
		GameState.toast("No docking port: ships dock at the outer door of an airlock.", "bad")
		return false
	var kinds: Array = l.get("rooms", DEFAULT_ROOMS).duplicate()
	if l.get("shipyard", false) and not "shipyard" in kinds:
		kinds.append("shipyard")
	var length := kinds.size() * PITCH + 1
	for port in ports:
		var ud := _fit(g, port, length)
		if ud >= 0:
			_build_at(g, id, port, ud, kinds)
			return true
	GameState.toast("No free docking port fits %s (space or direction). Trade only through the terminal." % l.name, "bad")
	return false

func _build_design(id: String, design: Dictionary) -> bool:
	var g := ShipSystem.grid
	for pt in ShipSystem.free_ports():
		var d: Vector2i = pt.dir
		var a := Vector2i(d.y, -d.x)
		var origin: Vector2i = pt.pos + d
		if not DesignLoader.fits(design, g, origin, a, d):
			continue
		DesignLoader.apply(design, g, origin, a, d, ZONE)
		station_id = id
		_rng.seed = hash(id)
		var first := true
		for cell in design.tiles:
			var p: Vector2i = origin + a * int(cell[0]) + d * int(cell[1])
			var i := g.idx(p)
			tiles.append(i)
			_own[i] = true
			area = Rect2i(p, Vector2i.ONE) if first else area.expand(p)
			first = false
		for source in design.rooms:
			var room: Dictionary = source.duplicate()
			for key in ["inner", "front", "behind"]:
				room[key] = DesignLoader.map_rect(source[key], origin, a, d)
			for key in ["desk", "door"]:
				room[key] = origin + a * source[key].x + d * source[key].y
			rooms.append(room)
		corridor = area
		hatch = int(pt.i)
		g.linked[hatch] = true
		_spawn_npcs()
		EventBus.ship_changed.emit()
		return true
	GameState.toast("The station design does not fit a free docking port.", "bad")
	return false

## Station in its own grid: u along the hall, v away from the ship.
## v=0 outer wall with the docking door, v=1..CORR hall, v=WALL_V room wall with doors, then the rooms, then the back wall.
const DEPTH := RS + ROOM_W + 1

## Position in the ship grid: docking door D lies right in front of the airlock
func _map(port: Dictionary, ud: int, u: int, v: int) -> Vector2i:
	var d: Vector2i = port.dir
	var along := Vector2i(-d.y, d.x)
	return port.pos + d + along * (u - ud) + d * v

## Suitable spot for the docking door along the hall (as central as possible), -1 = does not fit
func _fit(g: ShipGrid, port: Dictionary, length: int) -> int:
	var order: Array = range(1, length - 1)
	order.sort_custom(func(a, b): return absi(a - length / 2) < absi(b - length / 2))
	for ud in order:
		var ok := true
		for u in length:
			for v in DEPTH:
				var q := _map(port, ud, u, v)
				if q.x < 1 or q.y < 1 or q.x > g.width - 2 or q.y > g.height - 2 or g.get_tile(q) != ShipGrid.Tile.SPACE or g.zone[g.idx(q)] != 0 or g.occupied(q):
					ok = false
					break
			if not ok:
				break
		if ok:
			return ud
	return -1

func _rect(port: Dictionary, ud: int, u0: int, v0: int, u1: int, v1: int) -> Rect2i:
	var a := _map(port, ud, u0, v0)
	var b := _map(port, ud, u1, v1)
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)

func _build_at(g: ShipGrid, id: String, port: Dictionary, ud: int, kinds: Array) -> void:
	station_id = id
	_rng.seed = hash(id)
	var length := kinds.size() * PITCH + 1
	for u in length:
		for v in DEPTH:
			var edge := u == 0 or u == length - 1 or v == 0 or v == DEPTH - 1 or v == WALL_V or (v > WALL_V and u % PITCH == 0)
			_put(g, _map(port, ud, u, v), ShipGrid.Tile.WALL if edge else ShipGrid.Tile.FLOOR)
	for k in kinds.size():
		var r := k * PITCH
		var door := _map(port, ud, r + PITCH / 2, WALL_V)
		_put(g, door, ShipGrid.Tile.DOOR)
		var desk := _map(port, ud, r + PITCH / 2, RS + ROOM_W - 3 * Config.GRID_SCALE)
		var info: Dictionary = ROOMS[kinds[k]]
		g.place_device(info.desk, desk)
		var K := Config.GRID_SCALE
		rooms.append({"kind": kinds[k], "inner": _rect(port, ud, r + 1, RS, r + PITCH - 1, RS + ROOM_W - 1), "desk": desk, "door": door,
			"behind": _rect(port, ud, r + 1, RS + ROOM_W - 2 * K, r + PITCH - 1, RS + ROOM_W - 1),
			"front": _rect(port, ud, r + 1, RS, r + PITCH - 1, RS + ROOM_W - 4 * K)})
	# the station's docking door right in front of the airlock
	_put(g, _map(port, ud, ud, 0), ShipGrid.Tile.DOOR)
	corridor = _rect(port, ud, 1, 1, length - 2, CORR)
	area = _rect(port, ud, 0, 0, length - 1, DEPTH - 1)
	hatch = int(port.i)
	g.linked[hatch] = true
	for i in tiles:
		if g.holds_air(i):
			g.fill_air(i)
	_spawn_npcs()
	EventBus.ship_changed.emit()

func _put(g: ShipGrid, p: Vector2i, t: int) -> void:
	var i := g.idx(p)
	g.set_tile(p, t)
	g.zone[i] = ZONE
	g.cables[i] = 0
	if not _own.has(i):
		tiles.append(i)
		_own[i] = true

## Remove the station and release the airlock
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
		# Leftovers from a save (list not saved)
		for i in g.tiles.size():
			if g.zone[i] == ZONE:
				g.devices.erase(i)
				g.piles.erase(i)
				g.tiles[i] = ShipGrid.Tile.SPACE
				g.o2[i] = 0.0; g.n2[i] = 0.0; g.co2[i] = 0.0
				g.zone[i] = 0
		# Only release the connection: the airlock stays, no tiles remain
		g.linked.erase(hatch)
		# Old save: turn the former hatch (door without an airlock) back into a wall –
		# but never the outer door of an airlock (that is the docking port)
		if hatch >= 0 and hatch < g.tiles.size() and g.tiles[hatch] == ShipGrid.Tile.DOOR and not g.devices.has(hatch) and not AirlockSystem.is_lock_door(hatch):
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

## Is nobody from the crew left on the station?
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
		_add_npc(_name(used) + " (" + info.role + ")", "staff", r, r.behind, info.lines)
		if r.kind == "bar":
			var con: Dictionary = DialogueSystem.CONTACTS.get(station_id, {})
			if not con.is_empty():
				_add_npc(String(con.name), "contact", r, _front(r), [])
	for k in 2:
		_add_npc(_name(used), "visitor", {}, corridor, VISITOR_LINES)
	_sync_candidates()

func _front(r: Dictionary) -> Rect2i:
	return r.front

func _name(used: Array) -> String:
	for k in 30:
		var n: String = NAMES[_rng.randi() % NAMES.size()]
		if not n in used:
			used.append(n)
			return n
	return "Guest"

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

## Applicants stand in person in the hiring office
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
			_add_npc(c.display_name, "candidate", hiring, _front(hiring), ["I'm looking for work. %d Cr a day, and %d Cr death pay in trust." % [c.salary, NPCSystem.want_death(c)]], c)

func step(dt: float) -> void:
	if not Config.ENABLE_STATION or not active():
		return
	var g := ShipSystem.grid
	# The station keeps its own air
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
	# Is anyone waiting for a conversation?
	if not pending.is_empty():
		var c: CrewMember = pending.crew
		var npc: Dictionary = pending.npc
		var spot: Vector2 = Vector2(pending.target) + Vector2(0.5, 0.5)
		if not c in CrewSystem.crew or not npc in npcs:
			pending = {}
		elif c.pos.distance_to(npc.pos) <= 2.3 * Config.GRID_SCALE or c.pos.distance_to(spot) <= 1.6 * Config.GRID_SCALE:
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
	var left := secs * 1.2 * Config.GRID_SCALE
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
		if n.pos.distance_to(world) < 0.5 * Config.GRID_SCALE:
			return n
	return {}

## Who stands behind this counter?
func npc_for_desk(p: Vector2i) -> Dictionary:
	for r in rooms:
		if r.desk == p:
			for n in npcs:
				if n.kind == "staff" and n.room == r.kind:
					return n
	return {}

# ---------------- Conversations ----------------

## Click on a character or a counter of the station. true = handled.
func click(t: Vector2i, world: Vector2) -> bool:
	if not Config.ENABLE_STATION or not active():
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

## Send the character to the conversation partner (or talk right away if close enough)
func approach(c: CrewMember, npc: Dictionary) -> void:
	if c.pos.distance_to(npc.pos) <= 2.3 * Config.GRID_SCALE:
		talk(npc, c)
		return
	var target := Vector2i(npc.pos)
	if npc.kind == "staff":
		for r in rooms:
			if r.kind == npc.room:
				target = r.desk
	var res := ShipSystem.nearest_adjacent(c.tile(), [target], 1)
	if not res.ok or not c.order_move(res.path[-1] if not res.path.is_empty() else c.tile()):
		GameState.toast(c.display_name + " finds no way to " + String(npc.name) + ".")
		return
	pending = {"crew": c, "npc": npc, "target": target}
	GameState.toast(c.display_name + " walks to " + String(npc.name) + ".")

## Start a conversation: open the matching window, the character greets
func talk(npc: Dictionary, c: CrewMember) -> void:
	GameState.selected = c
	var tab := "station"
	var line := ""
	match npc.kind:
		"staff":
			var info: Dictionary = ROOMS[npc.room]
			tab = info.tab
			line = "%s: “%s”" % [String(npc.name).split(" (")[0], _greeting(npc.room, c)]
		"contact":
			tab = "station"
			line = "%s: “Have a seat. What brings you here?”" % String(npc.name).split(",")[0]
		"candidate":
			tab = "crew"
			line = "%s: “%s”" % [npc.name, npc.lines[0]]
		_:
			npc.line = String(npc.lines[_rng.randi() % npc.lines.size()])
			npc.line_until = GameState.time + 0.1
			GameState.toast("%s: “%s”" % [npc.name, npc.line])
			return
	SkillSystem.train(c, "folk", 0.5)
	UIManager.open_talk(tab, line, npc.room if npc.kind == "staff" else npc.kind)

func _greeting(kind: String, c: CrewMember) -> String:
	match kind:
		"market":
			return "Welcome, %s. I buy whatever you can carry." % c.display_name.split(" ")[0]
		"bank":
			return "Remaining debt %d Cr. The next instalment is due in %.1f days." % [EconomySystem.debt, maxf(0.0, (EconomySystem.next_payment - GameState.time) / 1440.0)]
		"claims":
			return "A Yellow salvage permit costs %d Cr for 24 hours; longer ones are cheaper per day." % Config.PERMIT_TIERS[0].cost
		"hiring":
			return "%d people are looking for work right now." % NPCSystem.candidates_here().size()
		"board":
			return "%d jobs are posted." % QuestSystem.offers_here().size()
	var lines: Array = ROOMS[kind].lines
	return String(lines[_rng.randi() % lines.size()])

# ---------------- Saving ----------------

func to_data() -> Dictionary:
	var g := ShipSystem.grid
	return {"id": station_id, "hatch": hatch, "hatch_pos": [g.pos(hatch).x, g.pos(hatch).y] if hatch >= 0 else []}

## After loading: remove old station tiles, build the station afresh
func from_data(d: Dictionary) -> void:
	tiles.clear()
	hatch = int(d.get("hatch", -1))
	var old_hatch := hatch
	station_id = "x"
	clear()
	if PhysicsSystem.docked != "":
		# Rebuild at the same door (also at a former docking port; that one is
		# only removed after a regular undock)
		ShipSystem.dock_pref = old_hatch
		build(PhysicsSystem.docked)
