## Life support: oxygen generator, CO2 scrubber and air tank (switched by pressure alarms, see Hvac)
## change the air on their tile. The distribution is handled by the
## AtmosphereSystem.
extends Node

func step(dt: float) -> void:
	var g := ShipSystem.grid
	# Pressure alarms switch the machines in their room (Ostranauts Ideal Atmosphere 3)
	Hvac.update(g)
	Emergency.step(g, dt)
	for i in g.devices:
		var dev: Device = g.devices[i]
		if dev.broken:
			continue
		match dev.type:
			"o2gen":
				var top := Hvac.cap(dev) if Hvac.controlled(dev) else Config.AIR_O2
				if dev.powered and Hvac.runs(dev) and g.o2[i] < top:
					g.o2[i] = minf(top, g.o2[i] + Config.O2GEN_RATE * dt)
			"scrubber":
				if dev.powered and Hvac.runs(dev) and g.co2[i] > Config.AIR_CO2:
					var c0 := g.co2[i]
					g.co2[i] = maxf(Config.AIR_CO2, g.co2[i] - Config.SCRUB_RATE * dt)
					_waste(g, dev, c0 - g.co2[i], dt)
			"tox_scrubber":
				if dev.powered and Hvac.runs(dev) and g.tox[i] > 0.0:
					var t0 := g.tox[i]
					g.tox[i] = maxf(0.0, g.tox[i] - Config.TOX_SCRUB_RATE * dt)
					_waste(g, dev, t0 - g.tox[i], dt)
			"pressure_locker":
				# A pressure suit takes in fresh room air: only where the air is breathable
				if dev.suit != null and g.holds_air(i) and g.o2[i] >= Config.O2_LOW:
					dev.suit.o2 = 100.0
			"locker":
				if dev.powered and dev.suit != null:
					dev.suit.o2 = minf(100.0, dev.suit.o2 + Config.SUIT_REFILL * dt)
					dev.suit.battery = minf(100.0, dev.suit.battery + Config.SUIT_REFILL * dt)
			"airtank":
				if dev.stock > 0.0 and g.pressure(i) < Config.TANK_TARGET:
					var add := minf(dev.stock, Config.TANK_RATE * dt)
					g.o2[i] += add * 0.21
					g.n2[i] += add * 0.79
					dev.stock -= add

# ---------------- Gas Canister (Ostranauts Ideal Atmosphere 3) ----------------
# A scrubber pumps the removed gas into a Gas Canister right next to it. Without one (or with
# full ones) it vents overboard in emergency mode and wears faster.

## Free gas canister next to the scrubber, or null
func canister_for(g: ShipGrid, dev: Device) -> Device:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = dev.pos + d
		if not g.in_bounds(q):
			continue
		var c := g.device_at(q)
		if c != null and c.type == "gas_canister" and not c.broken and c.store < Config.GAS_CANISTER_MAX - 0.001 and not g.foreign(g.idx(c.pos)):
			return c
	return null

## Is a gas canister (full or not) next to the scrubber?
func has_canister(g: ShipGrid, dev: Device) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = dev.pos + d
		if g.in_bounds(q) and g.device_at(q) != null and g.device_at(q).type == "gas_canister":
			return true
	return false

var _full_warned := {}

func _waste(g: ShipGrid, dev: Device, kpa: float, dt: float) -> void:
	if kpa <= 0.0:
		return
	var can := canister_for(g, dev)
	if can != null:
		can.store = minf(Config.GAS_CANISTER_MAX, can.store + kpa)
		if can.store >= Config.GAS_CANISTER_MAX - 0.001 and not g.foreign(g.idx(can.pos)) and not _full_warned.has(can):
			_full_warned[can] = true
			GameState.toast("Gas Canister full: the scrubber vents overboard and wears faster. Empty it at a station or vent it outside.", "bad")
		return
	# Emergency mode: overboard, extra wear (on top of the normal wear in the DamageSystem)
	dev.cond = maxf(0.0, dev.cond - Config.WEAR_PER_DAY * (Config.SCRUB_NO_CANISTER_WEAR - 1.0) * dt / 1440.0)
	if dev.cond <= 0.0:
		dev.broken = true

## Vent a gas canister into open space: only where it touches vacuum
func vent_canister(dev: Device) -> bool:
	var g := ShipSystem.grid
	if dev == null or dev.type != "gas_canister":
		return false
	if not DamageSystem.exposed(g, dev.pos):
		GameState.toast("The Gas Canister must touch open space to vent it (or empty it at a station).", "bad")
		return false
	dev.store = 0.0
	_full_warned.erase(dev)
	GameState.toast("Gas Canister vented into space.")
	return true

func clear_warning(dev: Device) -> void:
	_full_warned.erase(dev)
