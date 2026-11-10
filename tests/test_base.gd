## Grundlage aller Testreihen: stellt root, process_frame und quit() bereit,
## damit die Tests wie bisher geschrieben werden können. Gestartet über tests/boot.gd.
extends Node

var root: Window
var process_frame: Signal

func quit(code: int = 0) -> void:
	get_tree().quit(code)

## Pilot steht am (ersten) eigenen Steuerpult: nur dann gehen Flugbefehle wie
## Abdocken, Schnellreise, Auto-Dock und Schub. Ersetzt den Weg über das Cockpit (N),
## wo ein Test nicht das Cockpit selbst prüft. Nach new_game() erneut aufrufen.
func seat_pilot() -> void:
	var P = root.get_node("PhysicsSystem")
	var helms: Array = P.ship_devices("helm")
	if not helms.is_empty():
		P.helm_at = helms[0].pos
