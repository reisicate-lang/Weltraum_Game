## Grundlage aller Testreihen: stellt root, process_frame und quit() bereit,
## damit die Tests wie bisher geschrieben werden können. Gestartet über tests/boot.gd.
extends Node

var root: Window
var process_frame: Signal

func quit(code: int = 0) -> void:
	get_tree().quit(code)
