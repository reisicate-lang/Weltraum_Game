## Startet eine Testreihe, sobald alle globalen Systeme (Autoloads) bereit sind.
## Nötig ab Godot 4.4+: Ein direkt per --script geladenes Testskript würde die
## Spielklassen übersetzen, bevor GameState & Co. bekannt sind.
##   godot --headless --path . --script res://tests/boot.gd -- test_core
extends SceneTree

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("Bitte den Namen der Testreihe angeben, z. B. -- test_core")
		quit(1)
		return
	var script = load("res://tests/%s.gd" % args[0])
	if script == null or not script.can_instantiate():
		print("Testreihe nicht ladbar: " + args[0])
		quit(1)
		return
	var t: Node = script.new()
	t.root = root
	t.process_frame = process_frame
	root.add_child(t)
	t._initialize()
