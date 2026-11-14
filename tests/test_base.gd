## Base of all test series: provides root, process_frame and quit()
## so the tests can be written as before. Started through tests/boot.gd.
extends Node

var root: Window
var process_frame: Signal

func quit(code: int = 0) -> void:
	get_tree().quit(code)

## Pilot stands at the (first) navigation console of your own ship: only then do flight commands such as
## undocking, fast travel, Auto-Dock and thrust work. Replaces the way through the cockpit (N)
## where a test does not check the cockpit itself. Call again after new_game().
func seat_pilot() -> void:
	var P = root.get_node("PhysicsSystem")
	var helms: Array = P.ship_devices("helm")
	if not helms.is_empty():
		P.helm_at = helms[0].pos

## Tile of the starter ship template in the fine grid. x, y in the tiles of earlier versions
## (twice as large), as the template is described: wall → its wall line, device → its tile,
## floor → a sub-tile. So the tests hit the same objects as before the refinement.
func C(x: int, y: int) -> Vector2i:
	return root.get_node("ShipSystem").template_cell(Vector2i(x, y))

## Lay cable without gaps in the fine grid from a to b (first horizontal, then vertical)
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

## Fine tile right inside a wall of the template: (x, y) is the wall piece (former tiles),
## out the outward direction. E.g. the inner tile of a 1×3 thruster sits here.
func inside_wall(x: int, y: int, out: Vector2i) -> Vector2i:
	return C(x, y) - out
