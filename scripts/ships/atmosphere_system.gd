## Luft pro Feld (O₂, N₂, CO₂ in kPa). Die Gaswerte im ShipGrid bleiben die
## einzige Quelle für Simulation, Anzeige und Spielstand; Räume und Lecks werden
## jederzeit aus der Geometrie abgeleitet.
##
## Kantenregel (für alle vier Kanten eines Feldes, diagonal verbindet nichts):
##   - Wand oder Fenster auf einer Seite      → gesperrt
##   - zwei Luftfelder (Boden/Tür)            → freier Durchgang
##       … mit geschlossener Tür dazwischen   → Lüftungsschlitz (schwach),
##         oder dicht, wenn der Schlitz zu ist bzw. bei Schleusentür und Stationsluke
##   - Luftfeld neben Weltraum oder Rasterrand → Vakuumkante (Leck);
##     eine geschlossene Tür ist zum Weltraum hin immer dicht
## Ein abgebauter Boden wird zu Weltraum und öffnet so ein Leck mitten im Raum.
## Eine abgebaute Wand wird zu Boden und wird wie jeder Boden ausgewertet.
##
## Gasaustausch: Alle Flüsse eines Teilschritts werden aus demselben Zustand
## berechnet und danach angewendet (reihenfolgeunabhängig). Transfers erhalten
## die Menge je Gasart; Verluste gibt es nur an Vakuumkanten (gezählt in `vented`).
extends Node

const E_BLOCK := 0   ## gesperrt
const E_FREE := 1    ## freier Durchgang
const E_VENT := 2    ## geschlossene Tür mit offenem Lüftungsschlitz
const E_VAC := 3     ## Vakuumkante (Leck ins All)
const MAX_SUBSTEPS := 4

## Ins All verlorenes Gas (kPa-Summen) seit Spielstart bzw. im letzten Schritt
var vented := {"o2": 0.0, "n2": 0.0, "co2": 0.0}
var last_vented := 0.0

var _acc := 0.0
# Abgeleitete Raumstruktur (wird neu berechnet, sobald sich Raster, Türen oder Schlitze ändern)
var _topo_key := ""
var room_id := PackedInt32Array()     ## Feld -> Raum (-1: kein Raum, z. B. Tür oder Wand)
var rooms: Array = []                 ## [{cells: Array[int], vac: int, links: {raum: "open"/"vent"}, door_space: bool}]
var _air_cells := PackedInt32Array()
var _doors := PackedInt32Array()
var _cells_key := ""

func step(dt: float) -> void:
	_acc += dt
	# Bündeln: bei 1x etwa alle 1,5 Spielsekunden, bei hoher Geschwindigkeit seltener
	var threshold := 0.025 * maxf(1.0, Config.SPEEDS[TimeSystem.speed_index] / 10.0) * Settings.sim_factor()
	if _acc < threshold:
		return
	var d := _acc
	_acc = 0.0
	simulate(d)

# ---------------- Kanten ----------------

## Art der Kante zwischen Feld a und Feld b (b = -1: außerhalb des Rasters)
func edge(g: ShipGrid, a: int, b: int) -> int:
	var a_air := g.holds_air(a)
	if b < 0:
		return E_VAC if a_air and not _closed_door(g, a) else E_BLOCK
	var ta := g.tiles[a]
	var tb := g.tiles[b]
	if ta == ShipGrid.Tile.WALL or tb == ShipGrid.Tile.WALL or ta == ShipGrid.Tile.WINDOW or tb == ShipGrid.Tile.WINDOW:
		return E_BLOCK
	var b_air := g.holds_air(b)
	if not a_air and not b_air:
		return E_BLOCK
	if a_air != b_air:
		var c := a if a_air else b
		return E_BLOCK if _closed_door(g, c) else E_VAC
	var res := E_FREE
	for d in [a, b]:
		if g.tiles[d] == ShipGrid.Tile.DOOR and not g.door_open(d):
			if sealed(g, d):
				return E_BLOCK
			res = E_VENT
	return res

func _closed_door(g: ShipGrid, i: int) -> bool:
	return g.tiles[i] == ShipGrid.Tile.DOOR and not g.door_open(i)

## Geschlossene Tür ganz dicht? (Schlitz zu, Schleusentür, Stationsluke)
func sealed(g: ShipGrid, d: int) -> bool:
	return g.vent_closed[d] == 1 or AirlockSystem.is_lock_door(d) or StationSystem.is_hatch(d) \
		or (g.devices.has(d) and g.devices[d].type == "dockport")

## Nachbarn eines Feldes (rechts, links, unten, oben); -1 = Rasterrand
func _neighbors(g: ShipGrid, i: int) -> Array[int]:
	var x := i % g.width
	var y := i / g.width
	return [i + 1 if x + 1 < g.width else -1, i - 1 if x > 0 else -1,
		i + g.width if y + 1 < g.height else -1, i - g.width if y > 0 else -1]

## Anzahl Vakuumkanten eines Feldes
func vacuum_edges(i: int) -> int:
	var g := ShipSystem.grid
	var n := 0
	for j in _neighbors(g, i):
		if edge(g, i, j) == E_VAC:
			n += 1
	return n

# ---------------- Simulation ----------------

## Luftfelder neu sammeln, wenn sich das Raster geändert hat
func _ensure_cells(g: ShipGrid) -> void:
	var key := "%d:%d" % [g.get_instance_id(), hash(g.tiles)]
	if key == _cells_key:
		return
	_cells_key = key
	_air_cells = PackedInt32Array()
	_doors = PackedInt32Array()
	for i in g.tiles.size():
		if g.holds_air(i):
			_air_cells.append(i)
		if g.tiles[i] == ShipGrid.Tile.DOOR:
			_doors.append(i)

## dt in Spielminuten. In Teilschritte zerlegt, damit alle Zeitstufen gleich rechnen.
func simulate(dt: float) -> void:
	var g := ShipSystem.grid
	_ensure_cells(g)
	var steps := dt / (1.0 / 3.0)
	var n := clampi(int(ceil(steps)), 1, MAX_SUBSTEPS)
	last_vented = 0.0
	for k in n:
		_substep(g, steps / n)

func _substep(g: ShipGrid, s: float) -> void:
	var k_free := minf(0.2, Config.DIFFUSION * s)
	var k_vent := minf(0.2, Config.DOOR_SLITS * s)
	var keep := pow(1.0 - Config.VENT_LOSS, s)
	var n := g.tiles.size()
	# Zustand zu Beginn des Teilschritts: alle Flüsse werden daraus berechnet
	var o2 := g.o2.duplicate()
	var n2 := g.n2.duplicate()
	var co2 := g.co2.duplicate()
	var d_o2 := PackedFloat32Array()
	var d_n2 := PackedFloat32Array()
	var d_co2 := PackedFloat32Array()
	d_o2.resize(n); d_n2.resize(n); d_co2.resize(n)
	var vac := {}
	for i in _air_cells:
		for j in _neighbors(g, i):
			if j >= 0 and g.holds_air(j) and j < i:
				continue  # Paar zweier Luftfelder nur einmal (vom kleineren Index aus)
			var e := edge(g, i, j)
			if e == E_VAC:
				vac[i] = vac.get(i, 0) + 1
			elif e == E_FREE or e == E_VENT:
				var k := k_free if e == E_FREE else k_vent
				var f := (o2[i] - o2[j]) * k
				d_o2[i] -= f; d_o2[j] += f
				f = (n2[i] - n2[j]) * k
				d_n2[i] -= f; d_n2[j] += f
				f = (co2[i] - co2[j]) * k
				d_co2[i] -= f; d_co2[j] += f
	for i in _air_cells:
		var a := maxf(0.0, o2[i] + d_o2[i])
		var b := maxf(0.0, n2[i] + d_n2[i])
		var c := maxf(0.0, co2[i] + d_co2[i])
		if vac.has(i):
			var kp := pow(keep, vac[i])
			vented.o2 += a * (1.0 - kp); vented.n2 += b * (1.0 - kp); vented.co2 += c * (1.0 - kp)
			last_vented += (a + b + c) * (1.0 - kp)
			a *= kp; b *= kp; c *= kp
		g.o2[i] = a; g.n2[i] = b; g.co2[i] = c

# ---------------- Räume und Vakuumwege ----------------

## Raumstruktur aktuell halten (Raster, offene Türen, Schlitze)
func topology() -> void:
	var g := ShipSystem.grid
	_ensure_cells(g)
	var sig := PackedByteArray()
	for d in _doors:
		sig.append(1 if g.door_open(d) else 0)
		sig.append(g.vent_closed[d])
	var key := "%s|%d|%d|%d|%d" % [_cells_key, hash(sig), StationSystem.hatch, AirlockSystem.locks.size(), hash(g.linked.keys())]
	if key == _topo_key:
		return
	_topo_key = key
	room_id = PackedInt32Array()
	room_id.resize(g.tiles.size())
	room_id.fill(-1)
	rooms.clear()
	# Bodenfelder über freie Kanten zu Räumen gruppieren (Türen bleiben Grenzen)
	for start in _air_cells:
		if room_id[start] != -1 or g.tiles[start] == ShipGrid.Tile.DOOR:
			continue
		var r := rooms.size()
		var room := {"cells": [], "vac": 0, "links": {}, "door_space": false}
		rooms.append(room)
		var stack: Array[int] = [start]
		room_id[start] = r
		while not stack.is_empty():
			var i: int = stack.pop_back()
			room.cells.append(i)
			for j in _neighbors(g, i):
				var e := edge(g, i, j)
				if e == E_VAC:
					room.vac += 1
				elif e == E_FREE and g.tiles[j] != ShipGrid.Tile.DOOR and room_id[j] == -1:
					room_id[j] = r
					stack.append(j)
	# Türen verbinden Räume: offen = Durchfluss, zu mit Schlitz = schwach, dicht = nichts
	for d in _doors:
		var kind := "open" if g.door_open(d) else ("" if sealed(g, d) else "vent")
		var sides: Array[int] = []
		var to_space := false
		for j in _neighbors(g, d):
			var e := edge(g, d, j)
			if e == E_VAC:
				to_space = true
			elif (e == E_FREE or e == E_VENT) and j >= 0 and room_id[j] >= 0 and not room_id[j] in sides:
				sides.append(room_id[j])
		if kind == "":
			continue
		for a in sides:
			if to_space and kind == "open":
				rooms[a].door_space = true
			for b in sides:
				if a != b:
					var old: String = rooms[a].links.get(b, "")
					rooms[a].links[b] = "open" if (kind == "open" or old == "open") else "vent"

func room_of(i: int) -> int:
	topology()
	return room_id[i] if i >= 0 and i < room_id.size() else -1

## Vakuumweg eines Raums: "direkt" (eigene Leckkante), "tür" (über offene Türen),
## "schlitz" (nur schwach über Lüftungsschlitze) oder "" (dicht)
func room_leak(r: int) -> String:
	topology()
	if r < 0 or r >= rooms.size():
		return ""
	if rooms[r].vac > 0 or rooms[r].door_space:
		return "direkt"
	if _reaches_leak(r, false):
		return "tür"
	if _reaches_leak(r, true):
		return "schlitz"
	return ""

func _reaches_leak(start: int, with_vents: bool) -> bool:
	var seen := {start: true}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var r: int = queue.pop_front()
		if rooms[r].vac > 0 or rooms[r].door_space:
			return true
		for o in rooms[r].links:
			if not seen.has(o) and (with_vents or rooms[r].links[o] == "open"):
				seen[o] = true
				queue.append(o)
	return false

## Mittlerer Druck eines Raums in kPa
func room_pressure(r: int) -> float:
	topology()
	if r < 0 or r >= rooms.size() or rooms[r].cells.is_empty():
		return 0.0
	var g := ShipSystem.grid
	var s := 0.0
	for i in rooms[r].cells:
		s += g.pressure(i)
	return s / rooms[r].cells.size()

## Summe je Gasart über Felder: Vector3(O₂, N₂, CO₂)
func gas_sum(cells: Array) -> Vector3:
	var g := ShipSystem.grid
	var v := Vector3.ZERO
	for i in cells:
		v += Vector3(g.o2[i], g.n2[i], g.co2[i])
	return v

## Lüftungsschlitz einer Tür öffnen/schließen
func set_vent(i: int, closed: bool) -> void:
	ShipSystem.grid.vent_closed[i] = 1 if closed else 0

func describe(i: int) -> String:
	var g := ShipSystem.grid
	if not g.holds_air(i):
		return ""
	var text := "O₂ %.1f kPa · CO₂ %.2f kPa · Druck %d kPa" % [g.o2[i], g.co2[i], int(g.pressure(i))]
	var r := room_of(i)
	if r >= 0:
		var leak := room_leak(r)
		text += " · Raum Ø %d kPa" % int(room_pressure(r))
		match leak:
			"direkt": text += " · LECK"
			"tür": text += " · Leck über offene Tür"
			"schlitz": text += " · schwacher Gasweg über Türschlitz"
	elif g.tiles[i] == ShipGrid.Tile.DOOR and g.vent_closed[i] == 1:
		text += " · Schlitz zu"
	return text
