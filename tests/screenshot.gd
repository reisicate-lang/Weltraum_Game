## Macht ein Bildschirmfoto der Hauptszene (zum Prüfen der Darstellung):
##   godot --path . --script res://tests/screenshot.gd -- <ausgabe.png> [frames]
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://screenshot.png"
	var frames := int(args[1]) if args.size() > 1 else 90
	change_scene_to_file("res://scenes/main/main.tscn")
	for i in 5:
		await process_frame
	root.get_node("UIManager").help_panel.visible = false
	# Optional: Spielzeit vorspulen, damit etwas passiert
	if args.size() > 2:
		for k in int(args[2]) * 60:
			root.get_node("GameState").step(1.0 / 60.0)
	for i in frames:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("Gespeichert: ", out)
	quit()
