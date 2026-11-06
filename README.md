# Weltraum_Game

Ein Weltraum-Survival- und Bauspiel für den Browser.

## Spielen

Die Datei `index.html` im Browser öffnen (Doppelklick genügt).

## Steuerung

| Was | Wie |
|---|---|
| Deine Figur steuern | `WASD`, mit `Umschalt` rennen |
| Laufen lassen | Werkzeug **Auswahl**, auf einen Boden klicken |
| Kiste/Haufen durchsuchen | `E` (daneben stehen) oder draufklicken |
| Gepäck ein-/ausblenden | `I` |
| Bauen | Werkzeug wählen (Boden `B`, Wand `M`, Tür `T`), klicken oder Fläche ziehen |
| Abreißen / Plan löschen | `X` / `C` |
| Versetzen / Reparieren / Einsammeln | `V` / `R` / `Q` |
| Handeln | Klick auf das Handelsterminal im Cockpit |
| Aufgabe abbrechen | Rechtsklick auf Bauplan oder Charakter |
| Ansicht bewegen | Maus ziehen oder Pfeiltasten, Mausrad zoomt |
| Kabel / Geräte | `K` / `G` |
| Luft- / Strom-Ansicht | `L` / `P` |
| Zeit | `Leertaste` Pause, `1` bis `4` für 1×, 10×, 60×, 300× (1× = Echtzeit) |
| Speichern | `Strg+S` (außerdem automatisch jede Minute) |

## Aufbau des Codes

| Datei | Aufgabe |
|---|---|
| `js/config.js` | Einstellungen (Bauzeiten, Geschwindigkeiten, Weltgröße) |
| `js/items.js` | Gegenstände und Inventare |
| `js/world.js` | Die Welt aus Kacheln und das Startschiff |
| `js/devices.js` | Geräte (Generator, Bett, Sauerstoff ...) |
| `js/power.js` | Stromnetz |
| `js/atmosphere.js` | Luft und Lecks |
| `js/airlock.js` | Luftschleusen |
| `js/damage.js` | Verschleiß, Mikrometeoriten, Reparaturen |
| `js/economy.js` | Geld, Markt, Kredit, Werkbank-Aufträge |
| `js/wreck.js` | Zufällige Wracks zum Ausschlachten |
| `js/pathfinding.js` | Wegfindung der Charaktere |
| `js/jobs.js` | Baupläne |
| `js/characters.js` | Verhalten der Charaktere |
| `js/render.js` | Zeichnen |
| `js/input.js` | Maus, Touch, Tastatur |
| `js/save.js` | Speichern und Laden |
| `js/ui.js` | Menüs und Anzeigen |
| `js/main.js` | Start und Spielschleife |

Den Bauplan findest du in [PLAN.md](PLAN.md).
