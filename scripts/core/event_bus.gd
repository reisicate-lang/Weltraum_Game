## Central signals: systems talk to each other through the EventBus
## instead of calling each other directly.
extends Node

## The ship grid has changed (built, demolished, device placed)
signal ship_changed
## A new game was started or a save was loaded
signal game_loaded
## Message for the player (kind: "" or "bad")
signal toast(text: String, kind: String)
## Tool changed in the build menu
signal tool_changed(tool: String)
## Speed changed
signal speed_changed(index: int)
## A character was selected
signal character_selected(character)
