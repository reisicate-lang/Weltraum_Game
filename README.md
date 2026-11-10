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
godot --headless --path . --script res://tests/test_skills.gd
godot --headless --path . --script res://tests/test_systems.gd
godot --headless --path . --script res://tests/test_world.gd
godot --headless --path . --script res://tests/test_stations.gd
```

## Steuerung

| Was | Wie |
|---|---|
| Deine Figur | `WASD`, `Umschalt` = rennen |
| Hinlaufen lassen | Werkzeug **Auswahl**, Klick auf Boden |
| Bauen | Boden `B`, Wand `M`, Tür `T`, Kabel `K`, Geräte-Menü unten |
| Abreißen / Plan löschen | `X` / `C`, Rechtsklick bricht ab |
| Kiste durchsuchen | `E` (daneben stehen) oder draufklicken |
| Auf der Station reden | Klick auf eine Figur oder einen Tresen: deine Figur läuft hin, dann beginnt das Gespräch |
| Luft- / Strom- / Wärme-Ansicht | `L` / `P` / `O` |
| Fenster bauen | `Z` |
| Zeit | `Leertaste` Pause, `1`–`4` (1× = Echtzeit) |
| Charaktermenü (Fähigkeiten, Traits, Hobbys, Lebenslauf, Aufgaben) | `I` |
| Navigation | `N`, fliegen mit `WASD`, `F` andocken |
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
  scripts/skills/     SkillSystem, HobbySystem, SkillData, HobbyData
  scripts/traits/     TraitSystem, TraitData
  scripts/character/  CharacterSystem (Lebenslauf), CrewMember
  scripts/npcs/       NPCSystem (Bewerber, Plünderer)
  scripts/dialogue/   DialogueSystem (Gespräche auf Stationen)
  scripts/stations/   StationSystem (begehbare Stationen mit Räumen und Figuren)
  scripts/economy/    EconomySystem
  scripts/salvage/    SalvageSystem (Wracks)
  scripts/physics/    PhysicsSystem (Raumflug)
  scripts/save/       SaveSystem (JSON)
  scripts/ui/         UIManager
  resources/items/    Gegenstände als .tres (ItemData)
  resources/components/ Geräte als .tres (DeviceData)
  resources/skills/   32 Fähigkeiten (SkillData)
  resources/traits/   16 Eigenschaften (TraitData)
  resources/hobbies/  10 Hobbys (HobbyData)
  data/               Rezepte, Raumfahrt, Lebenslauf, Trainingsaktionen (JSON)
  tests/              Automatische Tests
  web/                Alte Browser-Version (Vorlage)
```

## Mods

Eigene Gegenstände, Geräte, Fähigkeiten, Traits oder Hobbys als `.tres`-Dateien in den Godot-Benutzerordner legen:
`user://mods/items/`, `user://mods/components/`, `user://mods/skills/`, `user://mods/traits/`, `user://mods/hobbies/`.
Den genauen Pfad zeigt das Einstellungsfenster (⚙). Als Vorlage dienen die Dateien in `resources/`.

Neue Gegenstände, Geräte, Fähigkeiten, Traits oder Hobbys im Spiel selbst: einfach eine neue `.tres`-Datei in `resources/items/` bzw. `resources/components/` anlegen.
Das Spiel lädt sie automatisch.

Den Bauplan findest du in [PLAN.md](PLAN.md).
