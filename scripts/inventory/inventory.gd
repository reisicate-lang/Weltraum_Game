## An inventory: a list of stacks {type, qty, cond} – uninstalled objects
## also have "data" (their stored state) and are never merged.
## Used for packs, crates and piles on the floor.
##
## Weight: every kind of item has a fixed unit weight (ItemData.weight, kg).
## A stack weighs quantity × unit weight; an uninstalled device with kept
## contents ("data.items") additionally weighs its contents exactly once.
##
## Hands: a character's pack (hands = true) also takes exactly ONE uninstalled
## device or part (kind "pk_…") into the hands – independent of the weight limit.
## The item is kept in items; the limit and free space do not count it.
class_name Inventory
extends RefCounted

var items: Array[Dictionary] = []
var max_weight: float = INF
var max_volume: float = INF
var hands := false
## Module bay of a navigation console: only takes console modules (ItemData.helm_module)
var only_modules := false

func _init(w: float = INF, v: float = INF) -> void:
	max_weight = w
	max_volume = v

## Uninstalled device or part: heavy, carried in the hands
static func is_heavy(type: String) -> bool:
	return type.begins_with("pk_")

## Weight of a stack in kg (with kept contents, exactly once)
static func stack_weight(it: Dictionary) -> float:
	var w: float = ItemSystem.item(it.type).weight * int(it.qty)
	var d = it.get("data")
	if d is Dictionary and d.get("items") is Array:
		for sub in d.items:
			w += stack_weight(sub)
	return w

static func stack_volume(it: Dictionary) -> float:
	var v: float = ItemSystem.item(it.type).volume * int(it.qty)
	var d = it.get("data")
	if d is Dictionary and d.get("items") is Array:
		for sub in d.items:
			v += stack_volume(sub)
	return v

func _in_hand(it: Dictionary) -> bool:
	return hands and is_heavy(String(it.type))

## Total weight in kg (everything, also what is in the hands) – basis of the ship mass
func weight() -> float:
	var s := 0.0
	for it in items:
		s += stack_weight(it)
	return s

func volume() -> float:
	var s := 0.0
	for it in items:
		s += stack_volume(it)
	return s

## Weight that counts against the carry limit (without the piece in the hands)
func load_weight() -> float:
	var s := 0.0
	for it in items:
		if not _in_hand(it):
			s += stack_weight(it)
	return s

func load_volume() -> float:
	var s := 0.0
	for it in items:
		if not _in_hand(it):
			s += stack_volume(it)
	return s

## What the character is carrying in the hands right now ({} = nothing)
func in_hands() -> Dictionary:
	for it in items:
		if _in_hand(it):
			return it
	return {}

func count(type: String) -> int:
	var s := 0
	for it in items:
		if it.type == type:
			s += it.qty
	return s

## How many pieces still fit?
func room(type: String) -> int:
	if hands and is_heavy(type):
		return 1 if in_hands().is_empty() else 0
	var d: ItemData = ItemSystem.item(type)
	if only_modules and d.helm_module == "":
		return 0
	var w := (max_weight - load_weight()) / d.weight
	var v := (max_volume - load_volume()) / d.volume
	var r := minf(w, v)
	# Without a limit (pile on the floor): int(INF) would be negative in Godot
	if is_inf(r) or r > 1000000.0:
		return 1000000
	return maxi(0, int(floor(r + 0.000001)))

## Puts a stack in. Returns how much fitted.
func add(type: String, qty: int, cond: float = 100.0, data = null) -> int:
	var n := mini(qty, room(type))
	if n <= 0:
		return 0
	# Single pieces with their own data (uninstalled devices): one stack per piece.
	# Their kept contents must fit in as well (except in the hands).
	if data != null:
		var st := {"type": type, "qty": 1, "cond": cond, "data": data.duplicate(true)}
		if not _in_hand(st) and (load_weight() + stack_weight(st) > max_weight + 0.000001 or load_volume() + stack_volume(st) > max_volume + 0.000001):
			return 0
		items.append(st)
		return 1
	for it in items:
		if it.has("data"):
			continue
		if it.type == type and absf(it.cond - cond) < 15.0:
			it.cond = (it.cond * it.qty + cond * n) / (it.qty + n)
			it.qty += n
			return n
	items.append({"type": type, "qty": n, "cond": cond})
	return n

## Takes out up to qty pieces (best condition first). Returns the stacks.
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
		var st := {"type": type, "qty": n, "cond": it.cond}
		if it.has("data"):
			st.data = it.data
		out.append(st)
	items.assign(items.filter(func(it): return it.qty > 0))
	return out

## Moves items into another inventory
func move_to(other: Inventory, type: String, qty: int) -> int:
	var n := mini(mini(qty, count(type)), other.room(type))
	if n <= 0:
		return 0
	var moved := 0
	for st in take(type, n):
		var got := other.add(st.type, st.qty, st.cond, st.get("data"))
		moved += got
		# Does not fit (e.g. contents too heavy): put it back, nothing is lost
		if got < int(st.qty):
			var back := st.duplicate(true)
			back.qty = int(st.qty) - got
			items.append(back)
	return moved

func to_data() -> Array:
	return items.duplicate(true)

func from_data(data: Array) -> void:
	items.clear()
	for it in data:
		var st := {"type": String(it.type), "qty": int(it.qty), "cond": float(it.cond)}
		if it.has("data") and it.data != null:
			st.data = it.data
		# Formerly: uninstalled stand-alone auto-dock device → today the Autodock Module
		if st.type == "pk_autodock":
			st = {"type": "mod_autodock", "qty": int(it.qty), "cond": float(it.cond)}
		items.append(st)
