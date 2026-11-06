# Weltraum_Game

Düstere Weltraum-Survival- und Raumschiff-Simulation von oben, spielmechanisch an Ostranauts angelehnt.

Das Spiel wird mit **Godot 4.3** (GDScript) entwickelt. Die frühere Browser-Version liegt im Ordner `web/`
und dient als Vorlage für die Etappen, die noch nach Godot übertragen werden.

## Starten (Godot)

1. Godot 4.3 herunterladen: https://godotengine.org/download (Standard-Version, nicht .NET)
2. Godot öffnen, **Importieren**, die Datei `project.godot` aus diesem Ordner wählen
3. Mit **F5** (oder dem Play-Knopf oben rechts) starten

## Tests (ohne Fenster)

```
godot --headless --path . --script res://tests/run_tests.gd
```

## Steuerung

| Was | Wie |
|---|---|
| Deine Figur | `WASD`, `Umschalt` = rennen |
| Hinlaufen lassen | Werkzeug **Auswahl**, Klick auf Boden |
| Bauen | Boden `B`, Wand `M`, Tür `T`, Kabel `K`, Geräte-Menü unten |
| Abreißen / Plan löschen | `X` / `C`, Rechtsklick bricht ab |
| Kiste durchsuchen | `E` (daneben stehen) oder draufklicken |
| Luft- / Strom-Ansicht | `L` / `P` |
| Zeit | `Leertaste` Pause, `1`–`4` (1× = Echtzeit) |
| Speichern | `Strg+S`, Autosave jede Minute |

## Projektstruktur

```
res://
  scenes/main/        Hauptszene (Kamera, Eingabe)
  scripts/core/       EventBus, GameState, TimeSystem, Config
  scripts/ships/      ShipSystem, ShipGrid, Device, ShipConstructionSystem,
                      ShipPowerSystem, AtmosphereSystem, OxygenSystem, ShipView
  scripts/character/  CrewMember (Verhalten, Bedürfnisse)
  scripts/crew/       CrewSystem
  scripts/inventory/  ItemSystem, ItemData, Inventory
  scripts/save/       SaveSystem (JSON)
  scripts/ui/         UIManager
  resources/items/    Gegenstände als .tres (ItemData)
  resources/components/ Geräte als .tres (DeviceData)
  tests/              Automatische Tests
  web/                Alte Browser-Version (Vorlage)
```

Neue Gegenstände oder Geräte: einfach eine neue `.tres`-Datei in `resources/items/` bzw. `resources/components/` anlegen.
Das Spiel lädt sie automatisch.

Den Bauplan findest du in [PLAN.md](PLAN.md).
