# Weltraum_Game

Düstere Weltraum-Survival- und Raumschiff-Simulation von oben, spielmechanisch an Ostranauts angelehnt.

Das Spiel wird mit **Godot 4.7** (GDScript) entwickelt. Die frühere Browser-Version liegt im Ordner `web/`
und dient als Vorlage für die Etappen, die noch nach Godot übertragen werden.

## Starten (Godot)

1. Godot 4.7 herunterladen: https://godotengine.org/download (Standard-Version, nicht .NET)
2. Godot öffnen, **Importieren**, die Datei `project.godot` aus diesem Ordner wählen
3. Mit **F5** (oder dem Play-Knopf oben rechts) starten

**Aktualisieren:** Doppelklick auf `aktualisieren.bat` holt den neuesten Stand von GitHub
(oder in GitHub Desktop: *Fetch origin*, dann *Pull origin*). Spielstände bleiben dabei erhalten.

## Tests (ohne Fenster)

Alle Testreihen parallel (etwa 100 Sekunden):

```
GODOT=/pfad/zu/godot tests/run_all.sh
```

Einzeln:

```
godot --headless --path . --script res://tests/boot.gd -- run_tests
godot --headless --path . --script res://tests/boot.gd -- test_skills
godot --headless --path . --script res://tests/boot.gd -- test_systems
godot --headless --path . --script res://tests/boot.gd -- test_world
godot --headless --path . --script res://tests/boot.gd -- test_stations
godot --headless --path . --script res://tests/boot.gd -- test_undock
godot --headless --path . --script res://tests/boot.gd -- test_removal
godot --headless --path . --script res://tests/boot.gd -- test_auto
godot --headless --path . --script res://tests/boot.gd -- test_atmosphere
godot --headless --path . --script res://tests/boot.gd -- test_docking
godot --headless --path . --script res://tests/boot.gd -- test_core
```

## Steuerung

| Was | Wie |
|---|---|
| Deine Figur | `WASD`, `Umschalt` = rennen |
| Hinlaufen lassen | Werkzeug **Auswahl**, Klick auf Boden |
| Bauen | Boden `B`, Wand `M`, Tür `T`, Kabel `K`, Geräte-Menü unten |
| Abreißen / Plan löschen | `X` / `C`, Rechtsklick bricht ab |
| Objekt entfernen | Rechtsklick auf Gerät oder Block (Werkzeug **Auswahl**): Abbauen, Zerlegen, Zerstören |
| Abgebautes wieder einbauen | Rechtsklick auf ein freies Feld → „Einbauen“, oder in Kiste/Haufen „Einbauen“ |
| Tür ganz dicht machen | Rechtsklick auf die Tür → „Lüftungsschlitz schließen“ |
| Kiste durchsuchen | `E` (daneben stehen) oder draufklicken |
| Auf der Station reden | Klick auf eine Figur oder einen Tresen: deine Figur läuft hin, dann beginnt das Gespräch |
| Luft- / Strom- / Wärme-Ansicht | `L` / `P` / `O` |
| Fenster bauen | `Z` |
| Zeit | `Leertaste` Pause, `1`–`4` (1× = Echtzeit) |
| Charaktermenü (Fähigkeiten, Traits, Hobbys, Lebenslauf, Aufgaben) | `I` |
| Auto-Modus der ausgewählten Figur an/aus | Knopf „Auto: AN/AUS“ links oder `J` |
| Navigation | `N`, fliegen mit `WASD`, `F` andocken, `U` abdocken |
| Andockschleuse bauen | Geräte-Menü → „Andockschleuse“, Klick auf eine Außenwand (innen Raum, außen All). Stationen docken an jeder freien Schleuse an, Wracks an einer Schleuse in der unteren Außenwand |
| Speichern | `Strg+S`, Autosave jede Minute |

## Entfernen einstellen (`data/removal.json`)

Pro Objekttyp (Geräte-ID wie `generator`, Blöcke als `tile:wall`, `tile:floor`, `tile:door`,
`tile:window`, `tile:rock`). Fehlende Felder kommen aus `defaults`. Alle Werte sind vorläufiges Balancing.

| Feld | Bedeutung |
|---|---|
| `actions` | erlaubte Aktionen: `uninstall` (Abbauen), `dismantle` (Zerlegen), `destroy` (Zerstören) |
| `uninstall_time`, `dismantle_time` | Dauer in Spielminuten (bei normalem Arbeitstempo) |
| `uninstall_tool`, `dismantle_tool`, `destroy_tool` | nötiges Werkzeug (Gegenstands-ID im Gepäck), leer = keins |
| `dismantle` | Zerlege-Ergebnis, z. B. `{"plate": 2, "motor": 1}` |
| `hp` | Trefferpunkte bei 100 % Zustand |
| `debris` | Müll beim Zerstören, z. B. `{"scrap": 3}` |
| `hit_interval`, `hit_damage`, `tool_damage` | (in `defaults`) Sekunden zwischen Schlägen, Grundschaden, Bonus je Werkzeug |

## Vorübergehend abgeschaltet: Station und Wrack

In `scripts/core/config.gd` stehen zwei Schalter:

```
static var ENABLE_STATION := false   # begehbare Station beim Andocken
static var ENABLE_WRECK := false     # Wrack/Asteroid an der unteren Schleuse, Bergung
```

Auf `true` setzen, um sie wieder einzuschalten. Der Code bleibt vollständig erhalten.
Ein Wrack aus einem alten Spielstand wird bei abgeschaltetem Wrack nicht gelöscht,
sondern am Ort abgelegt und kommt beim Wiedereinschalten zurück.

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
