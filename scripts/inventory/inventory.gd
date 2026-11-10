## Ein Inventar: Liste von Stapeln {type, qty, cond} – abgebaute Objekte
## haben zusätzlich "data" (ihr gespeicherter Zustand) und werden nie zusammengelegt.
## Wird für Gepäck, Kisten und Haufen auf dem Boden benutzt.
##
## Gewicht: Jede Gegenstandssorte hat ein festes Einzelgewicht (ItemData.weight, kg).
## Ein Stapel wiegt Stückzahl × Einzelgewicht; ein abgebautes Gerät mit erhaltenem
## Inhalt ("data.items") wiegt zusätzlich genau einmal seinen Inhalt.
##
## Hände: Das Gepäck einer Figur (hands = true) nimmt außerdem genau EIN abgebautes
## Gerät oder Bauteil (Sorte "pk_…") in die Hände – unabhängig vom Gewichtslimit.
## Der Gegenstand liegt mit in items; Limit und freier Platz rechnen ihn nicht mit.
class_name Inventory
extends RefCounted

var items: Array[Dictionary] = []
var max_weight: float = INF
var max_volume: float = INF
var hands := false

func _init(w: float = INF, v: float = INF) -> void:
	max_weight = w
	max_volume = v

## Abgebautes Gerät oder Bauteil: schwer, wird in den Händen getragen
static func is_heavy(type: String) -> bool:
	return type.begins_with("pk_")

## Gewicht eines Stapels in kg (mit erhaltenem Inhalt, genau einmal)
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

## Gesamtgewicht in kg (alles, auch was in den Händen liegt) – Grundlage der Schiffsmasse
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

## Gewicht, das gegen das Tragelimit zählt (ohne das Stück in den Händen)
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

## Was die Figur gerade in den Händen trägt ({} = nichts)
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

## Wie viele Stück passen noch hinein?
func room(type: String) -> int:
	if hands and is_heavy(type):
		return 1 if in_hands().is_empty() else 0
	var d: ItemData = ItemSystem.item(type)
	var w := (max_weight - load_weight()) / d.weight
	var v := (max_volume - load_volume()) / d.volume
	var r := minf(w, v)
	# Ohne Grenze (Haufen auf dem Boden): int(INF) wäre in Godot negativ
	if is_inf(r) or r > 1000000.0:
		return 1000000
	return maxi(0, int(floor(r + 0.000001)))

## Legt einen Stapel hinein. Gibt zurück, wie viel hineingepasst hat.
func add(type: String, qty: int, cond: float = 100.0, data = null) -> int:
	var n := mini(qty, room(type))
	if n <= 0:
		return 0
	# Einzelstücke mit eigenen Daten (abgebaute Geräte): je Stück ein Stapel.
	# Ihr erhaltener Inhalt muss mit hineinpassen (außer in den Händen).
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
		var st := {"type": type, "qty": n, "cond": it.cond}
		if it.has("data"):
			st.data = it.data
		out.append(st)
	items.assign(items.filter(func(it): return it.qty > 0))
	return out

## Verschiebt Gegenstände in ein anderes Inventar
func move_to(other: Inventory, type: String, qty: int) -> int:
	var n := mini(mini(qty, count(type)), other.room(type))
	if n <= 0:
		return 0
	var moved := 0
	for st in take(type, n):
		var got := other.add(st.type, st.qty, st.cond, st.get("data"))
		moved += got
		# Passt nicht (z. B. Inhalt zu schwer): zurücklegen, nichts geht verloren
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
		items.append(st)
