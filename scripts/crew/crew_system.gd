## Verwaltet alle Charaktere an Bord und lässt sie jeden Schritt handeln.
extends Node

var crew: Array[CrewMember] = []
var next_id := 1

func create_start_crew() -> void:
	crew.clear()
	next_id = 1
	var mira := CrewMember.new(next_id, "Mira Okafor", Color("#f2a33a"), ShipSystem.spawn_point())
	next_id += 1
	mira.is_player = true
	crew.append(mira)

func player() -> CrewMember:
	for c in crew:
		if c.is_player:
			return c
	return null

func step(dt: float) -> void:
	for c in crew:
		c.update(dt)

func at(world_pos: Vector2) -> CrewMember:
	for c in crew:
		if c.pos.distance_to(world_pos) < 0.5:
			return c
	return null

func to_data() -> Array:
	var out: Array = []
	for c in crew:
		out.append(c.to_data())
	return out

func from_data(data: Array) -> void:
	crew.clear()
	for d in data:
		var c := CrewMember.from_data(d)
		crew.append(c)
		next_id = maxi(next_id, c.id + 1)
