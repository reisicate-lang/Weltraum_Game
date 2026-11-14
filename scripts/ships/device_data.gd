## Describes a device type (a ship component).
## New devices: create a new .tres file in res://resources/components/.
class_name DeviceData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
## kW: positive produces power, negative consumes power
@export var power: float = 0.0
## Bauzeit in Spielminuten
@export var build_time: float = 3.0
## Build cost, e.g. {"plate": 2, "circuit": 1}
@export var cost: Dictionary = {}
## Stock (e.g. food rations); -1 = no stock
@export var stock: float = -1.0
@export var stock_unit: String = ""
## Battery capacity in kWh (0 = no battery)
@export var capacity: float = 0.0
## Lade-/Entladegrenze in kW (0 = unbegrenzt), z. B. Ship Battery 81 kW
@export var max_rate: float = 0.0
## Can be repaired (Ostranauts: the VDX-01 transponder cannot)
@export var repairable: bool = true
## Chance to break when uninstalled (transponder: 0.5)
@export var uninstall_break: float = 0.0
## Fixed base value in Cr (0 = from the build cost): Base Value from the wiki's salvage
## value/space cheat sheet, e.g. transponder 29 000, Halvorson RCS thruster 5 520
@export var item_value: int = 0
## Storage in liters (0 = no storage)
@export var storage: float = 0.0
## Which need the device fulfils ("food", "water", "sleep", "hygiene")
@export var need: String = ""
## Does the device wear out in operation?
@export var wears: bool = false
## Technology type for skills: "mechanical", "electrical", "robotic", "computer", "propulsion", "furniture"
@export var tech: String = "furniture"
## Device category (English keys): "appliance" (appliances), "control" (controls),
## "furniture" (furniture), "hvac" (climate and ventilation), "misc" (miscellaneous), "sensor" (sensors), "power", "propulsion",
## "docking", "water", "farming", "production", "station". Skills can act on them.
@export var category: String = ""
## Additional categories (e.g. "suit" for the suit locker and charger); bonuses of all categories count
@export var extra_categories: PackedStringArray = []
## Thrust in kN (thrusters only)
@export var thrust: float = 0.0
## Mass in tonnes (for the ship's acceleration)
@export var mass: float = 0.5
## Can be rotated in 90° steps while building and afterwards (e.g. thrusters)
@export var rotatable: bool = false
## Length in tiles (1 = one tile). Longer (e.g. thruster 1×3) = a straight line from inside
## to outside through an outer wall: inner tile (ship floor), wall tile (mount),
## outer tile (nozzle in space). See ShipGrid.mount_reason().
@export var length: int = 1
## Width in tiles across the mounting direction (docking port: 5, centred on pos)
@export var width: int = 1
## Buildable from the device menu (false: only kept for old saves)
@export var buildable: bool = true
## Colour for the simple drawing
@export var color: Color = Color(0.35, 0.4, 0.45)
