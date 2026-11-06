## Lebenserhaltung: Sauerstoff-Generator, CO2-Filter und Lufttank
## verändern die Luft auf ihrem Feld. Die Verteilung übernimmt das
## AtmosphereSystem.
extends Node

func step(dt: float) -> void:
	var g := ShipSystem.grid
	for i in g.devices:
		var dev: Device = g.devices[i]
		if dev.broken:
			continue
		match dev.type:
			"o2gen":
				if dev.powered and g.o2[i] < Config.AIR_O2:
					g.o2[i] = minf(Config.AIR_O2, g.o2[i] + Config.O2GEN_RATE * dt)
			"scrubber":
				if dev.powered and g.co2[i] > Config.AIR_CO2:
					g.co2[i] = maxf(Config.AIR_CO2, g.co2[i] - Config.SCRUB_RATE * dt)
			"airtank":
				if dev.stock > 0.0 and g.pressure(i) < Config.TANK_TARGET:
					var add := minf(dev.stock, Config.TANK_RATE * dt)
					g.o2[i] += add * 0.21
					g.n2[i] += add * 0.79
					dev.stock -= add
