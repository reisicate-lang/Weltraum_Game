## Beschreibt eine Geräteart (Bauteil eines Schiffs).
## Neue Geräte: eine neue .tres-Datei in res://resources/components/ anlegen.
class_name DeviceData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
## kW: positiv erzeugt Strom, negativ verbraucht Strom
@export var power: float = 0.0
## Bauzeit in Spielminuten
@export var build_time: float = 3.0
## Baukosten, z. B. {"plate": 2, "circuit": 1}
@export var cost: Dictionary = {}
## Vorrat (z. B. Essensrationen); -1 = kein Vorrat
@export var stock: float = -1.0
@export var stock_unit: String = ""
## Batteriekapazität in kWh (0 = keine Batterie)
@export var capacity: float = 0.0
## Lagerplatz in Litern (0 = kein Lager)
@export var storage: float = 0.0
## Welches Bedürfnis das Gerät erfüllt ("food", "water", "sleep", "hygiene")
@export var need: String = ""
## Nutzt sich das Gerät im Betrieb ab?
@export var wears: bool = false
## Farbe für die einfache Darstellung
@export var color: Color = Color(0.35, 0.4, 0.45)
