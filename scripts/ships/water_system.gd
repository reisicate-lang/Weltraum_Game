## Water and growing.
## - Drinking and washing produce waste water. Water filters turn it back
##   into drinking water (using up filter capacity).
## - Hydroponics: tend by hand, harvest after 3 days.
## - Auto farm: expensive, harvests on its own; every day with a gene mod.
## - Meat vat: eats rations, yields meat every day.
extends Node

var wastewater := 0.0   ## liters of waste water on the ship

func reset() -> void:
	wastewater = 0.0

func add_waste(liters: float) -> void:
	wastewater += liters

func step(dt: float) -> void:
	var g := ShipSystem.grid
	var h := dt / 60.0
	for i in g.devices:
		var dev: Device = g.devices[i]
		if dev.broken or g.foreign(i):
			continue
		match dev.type:
			"waterfilter":
				if dev.powered and dev.stock > 0.0 and wastewater > 0.0:
					var liters := minf(wastewater, 3.0 * h)
					var target := _driest_water()
					if target != null:
						wastewater -= liters
						target.stock = minf(target.data().stock, target.stock + liters * 0.9)
						dev.stock = maxf(0.0, dev.stock - liters / 10.0)
			"hydro":
				# Growth only with light (power), water and care (last 24 h)
				if dev.powered and dev.stock > 0.0 and GameState.time - dev.tended_at < 1440.0 and dev.growth < 1.0:
					dev.growth = minf(1.0, dev.growth + h / 72.0)
					dev.stock = maxf(0.0, dev.stock - 4.0 * h / 24.0)
				_ensure_job(dev, "tend" if GameState.time - dev.tended_at > 1200.0 and dev.growth < 1.0 else ("harvest" if dev.growth >= 1.0 else ""))
			"autofarm":
				if dev.powered:
					if not dev.genemod and _take_item("genemod"):
						dev.genemod = true
						GameState.toast("The auto farm got a gene mod: daily harvest from now on.")
					dev.growth += h / (24.0 if dev.genemod else 96.0)
					if dev.growth >= 1.0:
						dev.growth = 0.0
						g.drop_items(ShipConstructionSystem.drop_spot(dev.pos), "ration", 2, 100.0)
			"meatvat":
				if dev.powered and dev.stock >= 1.0:
					dev.growth += h / 24.0
					if dev.growth >= 1.0:
						dev.growth = 0.0
						dev.stock -= 1.0
						g.drop_items(ShipConstructionSystem.drop_spot(dev.pos), "meat", 1, 100.0)

func _driest_water() -> Device:
	var best: Device = null
	for dev in ShipSystem.grid.devices.values():
		if dev.type in ["water", "sink", "hydro"] and not dev.broken and dev.stock < dev.data().stock:
			if best == null or dev.stock / dev.data().stock < best.stock / best.data().stock:
				best = dev
	return best

func _take_item(type: String) -> bool:
	for src in ShipConstructionSystem.sources():
		if src.inv.count(type) > 0:
			src.inv.take(type, 1)
			ShipSystem.grid.clean_piles()
			return true
	return false

func _ensure_job(dev: Device, kind: String) -> void:
	if kind == "":
		return
	var g := ShipSystem.grid
	var i := g.idx(dev.pos)
	if not ShipConstructionSystem.jobs.has(i):
		ShipConstructionSystem.jobs[i] = {"kind": kind, "x": dev.pos.x, "y": dev.pos.y, "need": 5.0 if kind == "tend" else 3.0,
			"progress": 0.0, "claimed_by": -1, "retry_at": 0.0, "paid": true}

## Tending or harvesting is done
func finish_farm_job(job: Dictionary) -> void:
	var g := ShipSystem.grid
	var dev := g.device_at(Vector2i(int(job.x), int(job.y)))
	if dev == null:
		return
	if job.kind == "tend":
		dev.tended_at = GameState.time
	elif job.kind == "harvest":
		dev.growth = 0.0
		dev.tended_at = GameState.time
		g.drop_items(ShipConstructionSystem.drop_spot(dev.pos), "ration", 4, 100.0)
		g.drop_items(ShipConstructionSystem.drop_spot(dev.pos), "seeds", 1, 100.0)
		GameState.toast("Harvest: 4 rations from the hydroponics.")
