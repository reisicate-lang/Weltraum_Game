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

## Feld der Startschiff-Vorlage im feinen Raster. x, y in den Feldern früherer Versionen
## (doppelt so groß), wie die Vorlage beschrieben ist: Wand → ihre Wandlinie, Gerät → sein Feld,
## Boden → ein Teilfeld. So treffen die Tests dieselben Objekte wie vor der Verfeinerung.
func C(x: int, y: int) -> Vector2i:
	return root.get_node("ShipSystem").template_cell(Vector2i(x, y))

## Kabel lückenlos im feinen Raster von a nach b legen (erst waagerecht, dann senkrecht)
func cable_line(g, a: Vector2i, b: Vector2i) -> void:
	var x := a.x
	var step := 1 if b.x >= a.x else -1
	while true:
		g.cables[g.idx(Vector2i(x, a.y))] = 1
		if x == b.x:
			break
		x += step
	var y := a.y
	step = 1 if b.y >= a.y else -1
	while true:
		g.cables[g.idx(Vector2i(b.x, y))] = 1
		if y == b.y:
			break
		y += step

## Feines Feld direkt innen an einer Wand der Vorlage: (x, y) ist das Wandstück (frühere Felder),
## out die Richtung nach außen. Hier sitzt z. B. das Innenfeld eines 1×3-Triebwerks.
func inside_wall(x: int, y: int, out: Vector2i) -> Vector2i:
	return C(x, y) - out
