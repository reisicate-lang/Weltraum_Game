## Ein Inventar: Liste von Stapeln {type, qty, cond}.
## Wird für Gepäck, Kisten und Haufen auf dem Boden benutzt.
class_name Inventory
extends RefCounted

var items: Array[Dictionary] = []
var max_weight: float = INF
var max_volume: float = INF

func _init(w: float = INF, v: float = INF) -> void:
	max_weight = w
	max_volume = v

func weight() -> float:
	var s := 0.0
	for it in items:
		s += ItemSystem.item(it.type).weight * it.qty
	return s

func volume() -> float:
	var s := 0.0
	for it in items:
		s += ItemSystem.item(it.type).volume * it.qty
	return s

func count(type: String) -> int:
	var s := 0
	for it in items:
		if it.type == type:
			s += it.qty
	return s

## Wie viele Stück passen noch hinein?
func room(type: String) -> int:
	var d: ItemData = ItemSystem.item(type)
	var w := (max_weight - weight()) / d.weight
	var v := (max_volume - volume()) / d.volume
	var r := minf(w, v)
	# Ohne Grenze (Haufen auf dem Boden): int(INF) wäre in Godot negativ
	if is_inf(r) or r > 1000000.0:
		return 1000000
	return maxi(0, int(floor(r + 0.000001)))

## Legt einen Stapel hinein. Gibt zurück, wie viel hineingepasst hat.
func add(type: String, qty: int, cond: float = 100.0) -> int:
	var n := mini(qty, room(type))
	if n <= 0:
		return 0
	for it in items:
		if it.type == type and absf(it.cond - cond) < 15.0:
			it.cond = (it.cond * it.qty + cond * n) / (it.qty + n)
			it.qty += n
			return n
	items.append({"type": type, "qty": n, "cond": cond})
	return n

## Nimmt bis zu qty Stück heraus (bester Zustand zuerst). Gibt die Stapel zurück.
func take(type: String, qty: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stacks := items.filter(func(it): return it.type == type)
	stacks.sort_custom(func(a, b): return a.cond > b.cond)
	for it in stacks:
		if qty <= 0:
			break
		var n := mini(qty, it.qty)
		it.qty -= n
		qty -= n
		out.append({"type": type, "qty": n, "cond": it.cond})
	items.assign(items.filter(func(it): return it.qty > 0))
	return out

## Verschiebt Gegenstände in ein anderes Inventar
func move_to(other: Inventory, type: String, qty: int) -> int:
	var n := mini(mini(qty, count(type)), other.room(type))
	if n <= 0:
		return 0
	for st in take(type, n):
		other.add(st.type, st.qty, st.cond)
	return n

func to_data() -> Array:
	return items.duplicate(true)

func from_data(data: Array) -> void:
	items.clear()
	for it in data:
		items.append({"type": String(it.type), "qty": int(it.qty), "cond": float(it.cond)})
