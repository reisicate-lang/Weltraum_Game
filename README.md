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
godot --headless --path . --script res://tests/boot.gd -- test_flight
godot --headless --path . --script res://tests/boot.gd -- test_thrusters
godot --headless --path . --script res://tests/boot.gd -- test_match
godot --headless --path . --script res://tests/boot.gd -- test_cargo_mass
godot --headless --path . --script res://tests/boot.gd -- test_helm
godot --headless --path . --script res://tests/boot.gd -- test_parts
godot --headless --path . --script res://tests/boot.gd -- test_select
godot --headless --path . --script res://tests/boot.gd -- test_grid
godot --headless --path . --script res://tests/boot.gd -- test_modules
godot --headless --path . --script res://tests/boot.gd -- test_needs
godot --headless --path . --script res://tests/boot.gd -- test_walk_delay
godot --headless --path . --script res://tests/boot.gd -- test_resume
```

## Steuerung

| Was | Wie |
|---|---|
| Deine Figur | `WASD`, `Umschalt` = rennen |
| Hinlaufen lassen | Werkzeug **Auswahl**, Klick auf Boden. Direkt nach WASD wird der Klick vorgemerkt: die Figur läuft 0,5 echte Sekunden nach dem Loslassen der letzten Taste los |
| Unterbrochene Arbeit fortsetzen | Hat WASD deine Figur bei einem Auftrag unterbrochen, bleibt der Auftrag mit Fortschritt für sie reserviert. Rechtsklick (Werkzeug **Auswahl**) → „Resume Task“: sie läuft sofort (ohne die 0,5-s-Frist) zurück und arbeitet weiter, auch bei ausgeschaltetem Auto-Modus. Ist der Auftrag inzwischen fertig oder das Ziel weg, kommt eine kurze Meldung und es entsteht kein neuer Auftrag |
| Bauen | Boden `B`, Wand `M`, Tür `T`, Kabel `K`, Geräte-Menü unten. Ein Baufeld ist 16 px groß (halb so groß wie früher); die Figur deckt etwa 2×2 Felder. Wände sind 1 Feld dick, Türen 1 Feld breit |
| Abreißen / Plan löschen | `X` / `C`, Rechtsklick bricht ab |
| Objekt entfernen | Rechtsklick (Werkzeug **Auswahl**) wählt eine Ebene der Kachel und öffnet das Menü: Abbauen, Zerlegen, Zerstören. Jeder weitere Rechtsklick auf dieselbe Kachel wechselt Kabel → Gerät → Boden/Wand (leere Ebenen werden übersprungen), danach wieder von oben. Die gewählte Ebene ist gelb markiert und steht oben im Menü |
| Abgebautes wieder einbauen | Abgebaute Geräte liegen als ein Gegenstand am Boden (mit Zustand und Inhalt). Daneben stellen, `E` → „Nehmen“ (in die Hände). Dann Rechtsklick auf ein freies Feld → „Einbauen“, oder im Inventar/Haufen „Einbauen“ |
| Persönliches Inventar | `Tab` öffnet/schließt (auch im Cockpit). Mit offener Kiste: „Nehmen“/„Hineinlegen“, sonst „Ablegen“ auf den Boden. Tragelimit 40 kg, dazu genau ein abgebautes Gerät in den Händen |
| Tür ganz dicht machen | Rechtsklick auf die Tür → „Lüftungsschlitz schließen“ |
| Kiste durchsuchen | `E` (daneben stehen) oder draufklicken |
| Auf der Station reden | Klick auf eine Figur oder einen Tresen: deine Figur läuft hin, dann beginnt das Gespräch |
| Luft- / Strom- / Wärme-Ansicht | `L` / `P` / `O` |
| Fenster bauen | `Z` |
| Zeit | `Leertaste` Pause, `1`–`5`: ×1 (Echtzeit), ×2, ×4, ×8, ×16 |
| Charaktermenü (Fähigkeiten, Traits, Hobbys, Lebenslauf, Aufgaben) | `I` |
| Auto-Modus der ausgewählten Figur an/aus | Knopf „Auto: AN/AUS“ links oder `J` |
| Cockpit (am Steuerpult) | `N` oder Klick aufs Steuerpult: die Figur geht hin und übernimmt das Steuer; `Esc`/`N` verlässt es |
| Fliegen | `W`/`S` Schub vor/zurück, `A`/`D` seitwärts, `Q`/`E` drehen, `R` Drehung stoppen, `X` ans Ziel angleichen, `T` nächstes Ziel (oder „Ziel“ in der Liste), `F` andocken, `U` abdocken |
| Triebwerk einbauen | Geräte-Menü → „Triebwerk“ (1×3 Felder). `G` dreht die Richtung. Klick auf ein Bodenfeld mit Kabel direkt an einer Außenwand: Mitte sitzt auf der Wand, die Düse ragt ins All, Schub vom All weg. Die Vorschau zeigt alle drei Felder. Umsetzen: abbauen und neu einbauen |
| Steuerpult-Module | `E` neben dem Steuerpult (oder im Cockpit „Modulfach [E]“) öffnet das Modulfach: „Hineinlegen“/„Nehmen“ wie bei einer Kiste. Das Autodock-Modul schaltet an genau diesem Pult „Auto-Dock“ im Cockpit frei; ist es gesperrt, steht der Grund darunter |
| Andocken | Einziger Andockport des Startschiffs ist die Außentür der Luftschleuse links. Station und Wrack koppeln dort Tür an Tür – manuell (F/„Andocken“: nah, langsam, Port zum Ziel ausgerichtet) oder mit Auto-Dock. Das Wrack ist ein eigenes Ziel auf der Karte (neben Tycho; ein Bergungsrecht legt ein neues neben die Station). Solange etwas angedockt ist, geht es über die Luftschleuse nicht ins All |
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
