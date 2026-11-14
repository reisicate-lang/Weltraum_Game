## Room types after Ostranauts "Rooms" (docs/ostranauts/ostranauts-rooms.md, data in data/rooms.json).
## Room = own floor tiles enclosed on all sides by walls, windows or doors. The type follows
## from the installed devices, the size and the pressure; the first matching row wins.
## The type multiplies the value of the devices installed in it (ship value when selling).
class_name RoomTypes
extends RefCounted

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/rooms.json", FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text())
	return _data

## Tags of a device, e.g. battery → ["battery", "engineering"]
static func tags_of(type: String) -> Array:
	return data().tags.get(type, [])

## All enclosed rooms of your own ship:
## [{cells, size, devices, pressure, pressurized, id, name, modifier, rect}]
static func classify(g: ShipGrid) -> Array:
	var room_of := PackedInt32Array()
	room_of.resize(g.tiles.size())
	room_of.fill(-1)
	var rooms: Array = []
	var open_rooms := {}
	for start in g.tiles.size():
		if g.tiles[start] != ShipGrid.Tile.FLOOR or g.foreign(start) or room_of[start] != -1:
			continue
		var r := rooms.size()
		var cells: Array[int] = [start]
		room_of[start] = r
		var stack: Array[int] = [start]
		var enclosed := true
		var lo := g.pos(start)
		var hi := lo
		while not stack.is_empty():
			var i: int = stack.pop_back()
			var p := g.pos(i)
			lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
			hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = p + d
				if not g.in_bounds(q):
					enclosed = false
					continue
				var j := g.idx(q)
				var t := g.tiles[j]
				if t == ShipGrid.Tile.SPACE or (t == ShipGrid.Tile.FLOOR and g.foreign(j)):
					enclosed = false
				elif t == ShipGrid.Tile.FLOOR and room_of[j] == -1:
					room_of[j] = r
					cells.append(j)
					stack.append(j)
		rooms.append({"cells": cells, "size": cells.size(), "devices": [], "rect": Rect2i(lo, hi - lo + Vector2i.ONE)})
		if not enclosed:
			open_rooms[r] = true
	# Assign devices to the room of their tile (otherwise to an adjacent one, e.g. a docking port at the door)
	for i in g.devices:
		var dev: Device = g.devices[i]
		if g.foreign(i) or dev.type == "thruster":
			continue
		var r := room_of[i]
		if r < 0:
			var p := g.pos(i)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if g.in_bounds(p + d) and room_of[g.idx(p + d)] >= 0:
					r = room_of[g.idx(p + d)]
					break
		if r >= 0:
			rooms[r].devices.append(dev)
	var out: Array = []
	var kpa: float = data().pressurized_kpa
	for r in rooms.size():
		if open_rooms.has(r):
			continue
		var room: Dictionary = rooms[r]
		var sum := 0.0
		for i in room.cells:
			sum += g.pressure(i)
		room.pressure = sum / maxf(1.0, room.size)
		room.pressurized = room.pressure >= kpa
		_assign(room)
		out.append(room)
	return out

## Type in wiki order: requirements met, nothing forbidden, pressure, minimum size
static func _assign(room: Dictionary) -> void:
	var count := {}
	for dev in room.devices:
		for t in tags_of(dev.type):
			count[t] = int(count.get(t, 0)) + 1
	room.tags = count
	for t in data().types:
		if bool(t.pressurized) and not room.pressurized:
			continue
		if room.size < int(t.min_size):
			continue
		var ok := true
		for need in t.requires:
			if int(count.get(need, 0)) < int(t.requires[need]):
				ok = false
				break
		for bad in t.forbidden:
			if count.has(bad):
				ok = false
				break
		if ok:
			room.id = t.id
			room.name = t.name
			room.modifier = float(t.modifier)
			return
	room.id = "blank" if room.pressurized else "unpressurized"
	room.name = "Blank" if room.pressurized else "Unpressurized"
	room.modifier = 1.0

## Device tile → value factor of its room (only devices in enclosed rooms)
static func modifiers(g: ShipGrid) -> Dictionary:
	var out := {}
	for room in classify(g):
		for dev in room.devices:
			out[g.idx(dev.pos)] = room.modifier
	return out

## Number of different specialized room types (X of the ship rating)
static func unique_count(g: ShipGrid) -> int:
	var ids := {}
	for room in classify(g):
		if room.id != "blank" and room.id != "unpressurized":
			ids[room.id] = true
	return ids.size()
