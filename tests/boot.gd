## Starts a test series as soon as all global systems (autoloads) are ready.
## Needed from Godot 4.4+: a test script loaded directly with --script would compile the
## game classes before GameState & co. are known.
##   godot --headless --path . --script res://tests/boot.gd -- test_core
extends SceneTree

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("Please give the name of the test series, e.g. -- test_core")
		quit(1)
		return
	var script = load("res://tests/%s.gd" % args[0])
	if script == null or not script.can_instantiate():
		print("Test series cannot be loaded: " + args[0])
		quit(1)
		return
	var t: Node = script.new()
	t.root = root
	t.process_frame = process_frame
	root.add_child(t)
	t._initialize()
