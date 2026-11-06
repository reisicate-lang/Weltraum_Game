## Stromnetz: Kabel, die sich berühren, bilden ein Netz. Geräte auf
## einem Kabel hängen daran. Überschuss lädt Batterien, Mangel leert sie.
extends Node

var nets: Array[Dictionary] = []
var net_of := PackedInt32Array()
var _dirty := true

func _ready() -> void:
	EventBus.ship_changed.connect(func(): _dirty = true)

func _rebuild() -> void:
	var g := ShipSystem.grid
	net_of.resize(g.tiles.size())
	net_of.fill(-1)
	nets.clear()
	for start in g.tiles.size():
		if g.cables[start] == 0 or net_of[start] != -1:
			continue
		var id := nets.size()
		nets.append({"production": 0.0, "demand": 0.0, "charge": 0.0, "capacity": 0.0, "ok": true})
		var stack: Array[int] = [start]
		net_of[start] = id
		while not stack.is_empty():
			var i: int = stack.pop_back()
			var p := g.pos(i)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = p + d
				if not g.in_bounds(q):
					continue
				var j := g.idx(q)
				if g.cables[j] == 1 and net_of[j] == -1:
					net_of[j] = id
					stack.append(j)
	for i in g.devices:
		g.devices[i].net = net_of[i]
	_dirty = false

func step(dt: float) -> void:
	if _dirty:
		_rebuild()
	var g := ShipSystem.grid
	var consumers := {}
	var batteries := {}
	for net in nets:
		net.production = 0.0; net.demand = 0.0; net.charge = 0.0; net.capacity = 0.0
	for i in g.devices:
		var dev: Device = g.devices[i]
		var d := dev.data()
		dev.producing = false
		if dev.net < 0:
			dev.powered = false
			continue
		var net: Dictionary = nets[dev.net]
		if d.power > 0.0 and not dev.broken and dev.stock > 0.0:
			dev.producing = true
			dev.stock = maxf(0.0, dev.stock - dt / 60.0)  # 1 Brennstoff pro Stunde
			net.production += d.power
		if d.power < 0.0:
			if dev.broken:
				dev.powered = false
			else:
				net.demand += -d.power
				consumers.get_or_add(dev.net, []).append(dev)
		if d.capacity > 0.0:
			batteries.get_or_add(dev.net, []).append(dev)
			net.charge += dev.charge
			net.capacity += d.capacity
	for id in nets.size():
		var net: Dictionary = nets[id]
		var balance: float = net.production - net.demand
		var energy := absf(balance) * dt / 60.0
		if balance >= 0.0:
			net.ok = true
			var left := energy
			for b in batteries.get(id, []):
				var add := minf(left, b.data().capacity - b.charge)
				b.charge += add
				left -= add
		elif net.charge >= energy:
			net.ok = true
			for b in batteries.get(id, []):
				b.charge -= energy * (b.charge / net.charge)
		else:
			net.ok = false
		for c in consumers.get(id, []):
			c.powered = net.ok

func main_net() -> Dictionary:
	var best := {}
	for net in nets:
		if best.is_empty() or net.production + net.capacity > best.production + best.capacity:
			best = net
	return best
