## Power grid: cables that touch form a network. Devices on
## a cable hang on it. A surplus charges batteries, a deficit drains them.
## Power switches only conduct while on. Damaged batteries store
## less (capacity × condition) and slowly lose charge below LEAK_COND.
extends Node

## Below this condition (%) a battery's charge creeps away
const LEAK_COND := 75.0
## Loss per hour at condition 0, as a fraction of the rated capacity
const LEAK_PER_H := 0.1

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
	# Power switches: on = conducts (even without a cable), off = splits (even with a cable)
	var switches := {}
	for i in g.devices:
		if g.devices[i].type == "power_switch":
			switches[i] = g.devices[i].switch_on
	var conducts := func(j: int) -> bool: return bool(switches[j]) if switches.has(j) else g.cables[j] == 1
	for start in g.tiles.size():
		if not conducts.call(start) or net_of[start] != -1:
			continue
		var id := nets.size()
		nets.append({"production": 0.0, "demand": 0.0, "charge": 0.0, "capacity": 0.0, "ok": true, "hours": INF})
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
				if net_of[j] == -1 and conducts.call(j):
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
		if d.power > 0.0 and not dev.broken:
			if dev.type == "solar":
				dev.producing = g.pressure(i) < 5.0  # only outside in vacuum
			elif d.stock >= 0.0:
				dev.producing = dev.stock > 0.0
				if dev.producing:
					dev.stock = maxf(0.0, dev.stock - dt / 60.0)  # 1 generator fuel per hour
			else:
				dev.producing = true
			if dev.producing:
				net.production += d.power
		if d.power < 0.0:
			if dev.broken:
				dev.powered = false
			else:
				# The heater and the airlock pump only need power while they work
				var idle: bool = (dev.type == "heater" and g.temp[i] >= Config.ROOM_TEMP - 0.5) or (dev.type == "pump" and not AirlockSystem.is_pumping(dev))
				if not idle:
					net.demand += -d.power
				consumers.get_or_add(dev.net, []).append(dev)
		if d.capacity > 0.0:
			var cap := capacity_of(dev)
			dev.charge = clampf(dev.charge, 0.0, cap)
			if dev.cond < LEAK_COND:
				dev.charge = maxf(0.0, dev.charge - d.capacity * LEAK_PER_H * (LEAK_COND - dev.cond) / LEAK_COND * dt / 60.0)
			batteries.get_or_add(dev.net, []).append(dev)
			net.charge += dev.charge
			net.capacity += cap
	for id in nets.size():
		var net: Dictionary = nets[id]
		var balance: float = net.production - net.demand
		var energy := absf(balance) * dt / 60.0
		var bats: Array = batteries.get(id, [])
		net.hours = INF if balance >= 0.0 else net.charge / -balance
		if balance >= 0.0:
			net.ok = true
			var left := energy
			for b in bats:
				var add := minf(minf(left, capacity_of(b) - b.charge), rate_limit(b, dt))
				b.charge += maxf(0.0, add)
				left -= maxf(0.0, add)
		else:
			# Each battery delivers at most its discharge limit (kW)
			var avail := 0.0
			var give := []
			for b in bats:
				var x := minf(b.charge, rate_limit(b, dt))
				give.append(x)
				avail += x
			if avail >= energy and avail > 0.0:
				net.ok = true
				for k in bats.size():
					bats[k].charge -= energy * (give[k] / avail)
			else:
				net.ok = false
		for c in consumers.get(id, []):
			c.powered = net.ok

## Usable capacity: rated capacity × condition, broken = 0
func capacity_of(dev: Device) -> float:
	if dev.broken:
		return 0.0
	return dev.data().capacity * clampf(dev.cond, 0.0, 100.0) / 100.0

## How many kWh a battery can charge/deliver at most in dt (minutes)
func rate_limit(dev: Device, dt: float) -> float:
	var r := dev.data().max_rate
	return INF if r <= 0.0 else r * dt / 60.0

## Flip a power switch; the networks are rebuilt
func toggle_switch(dev: Device) -> void:
	dev.switch_on = not dev.switch_on
	_dirty = true
	EventBus.ship_changed.emit()

func main_net() -> Dictionary:
	var best := {}
	for net in nets:
		if best.is_empty() or net.production + net.capacity > best.production + best.capacity:
			best = net
	return best
