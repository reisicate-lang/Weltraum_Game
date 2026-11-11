## Bildschirmfoto: ausgewählte Figur neben einer Bauvorschau (Verhältnis Figur zu Baufeld)
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --script res://tests/shot_build.gd -- <voll.png> <ausschnitt.png>
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://shot_build.png"
	var crop_out := args[1] if args.size() > 1 else "user://shot_build_crop.png"
	change_scene_to_file("res://scenes/main/main.tscn")
	for i in 5:
		await process_frame
	var ui = root.get_node("UIManager")
	ui.char_ui.creation.visible = false
	ui.help_panel.visible = false
	root.get_node("TimeSystem").set_speed(0)
	var gs = root.get_node("GameState")
	var mira = root.get_node("CrewSystem").player()
	gs.selected = mira
	mira.path.clear()
	var g = root.get_node("ShipSystem").grid
	var cam: Camera2D = current_scene.get_node("Camera2D")
	cam.position = mira.pos * Config.TILE_SIZE
	ui.set_tool("wall")
	# Zielfeld der Vorschau: zwei Felder rechts neben der Figur (feines Raster) bzw. eins (früher)
	var step := 2 if Config.TILE_SIZE < 32 else 1
	var target: Vector2i = mira.tile() + Vector2i(step, 0)
	for i in 3:
		await process_frame
	var sp: Vector2 = root.get_viewport().get_canvas_transform() * ((Vector2(target) + Vector2(0.5, 0.5)) * Config.TILE_SIZE)
	Input.warp_mouse(sp)
	for i in 20:
		await process_frame
	print("Feldgröße %d px, Zoom %.2f, Figur bei %s, Vorschau bei %s (Maus auf %s)" % [Config.TILE_SIZE, cam.zoom.x, str(mira.tile()), str(target), str(current_scene.call("_tile_at_mouse"))])
	var img: Image = root.get_texture().get_image()
	img.save_png(out)
	var mp: Vector2 = root.get_viewport().get_canvas_transform() * (mira.pos * Config.TILE_SIZE)
	var r := Rect2i(Vector2i(mp) - Vector2i(160, 110), Vector2i(320, 220)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(r)
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png(crop_out)
	print("gespeichert: ", out, " ", crop_out)
	quit()
