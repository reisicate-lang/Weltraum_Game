# Weltraum_Game

Ein Weltraum-Survival- und Bauspiel für den Browser.

## Spielen

Die Datei `index.html` im Browser öffnen (Doppelklick genügt).

## Steuerung

| Was | Wie |
|---|---|
| Laufen | Werkzeug **Auswahl**, auf einen Boden klicken |
| Bauen | Werkzeug wählen (Boden `B`, Wand `M`, Tür `T`), klicken oder Fläche ziehen |
| Abreißen / Plan löschen | `X` / `C` |
| Ansicht bewegen | Maus ziehen, `WASD` oder Pfeiltasten, Mausrad zoomt |
| Zeit | `Leertaste` Pause, `1` `2` `3` Geschwindigkeit |
| Speichern | `Strg+S` (außerdem automatisch jede Minute) |

## Aufbau des Codes

| Datei | Aufgabe |
|---|---|
| `js/config.js` | Einstellungen (Bauzeiten, Geschwindigkeiten, Weltgröße) |
| `js/world.js` | Die Welt aus Kacheln und das Startschiff |
| `js/pathfinding.js` | Wegfindung der Charaktere |
| `js/jobs.js` | Baupläne |
| `js/characters.js` | Verhalten der Charaktere |
| `js/render.js` | Zeichnen |
| `js/input.js` | Maus, Touch, Tastatur |
| `js/save.js` | Speichern und Laden |
| `js/ui.js` | Menüs und Anzeigen |
| `js/main.js` | Start und Spielschleife |

Den Bauplan findest du in [PLAN.md](PLAN.md).
