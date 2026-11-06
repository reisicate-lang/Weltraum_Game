## Zentrale Signale: Systeme reden über den EventBus miteinander,
## statt sich direkt gegenseitig aufzurufen.
extends Node

## Das Schiffsraster hat sich verändert (gebaut, abgerissen, Gerät gesetzt)
signal ship_changed
## Ein neues Spiel wurde gestartet oder ein Spielstand geladen
signal game_loaded
## Meldung für den Spieler (kind: "" oder "bad")
signal toast(text: String, kind: String)
## Werkzeug im Baumenü gewechselt
signal tool_changed(tool: String)
## Geschwindigkeit geändert
signal speed_changed(index: int)
## Ein Charakter wurde ausgewählt
signal character_selected(character)
