# Schiffe und Orte in Godot bauen

Im rechten Dock **Schiffe und Orte** einen Entwurf doppelklicken. Falls das Dock fehlt, unter Projekt → Projekteinstellungen → Plugins **Schiffe und Orte** aktivieren.

1. `Terrain` im Szenenbaum auswählen. Im TileMap-Fenster unten eine Kachel wählen und im 2D-Fenster malen. Die vier Kacheln sind Boden, Wand, Tür und Fenster. Mit dem Radierer Kacheln entfernen.
2. `Cables` auswählen und Stromleitungen malen.
3. Unter `Devices` ein Gerät auswählen und verschieben. Im Inspector `Component` aus `resources/components` wählen und mit `Direction` die Richtung einstellen. Das Dock kann neue Geräte hinzufügen. Strg+D dupliziert ein Gerät. Gerätepositionen werden auf 16-Pixel-Zellen gerundet. Für präzises Verschieben das Godot-Raster auf 16 × 16 Pixel einstellen.
4. Stationen enthalten zusätzlich grüne Raummarkierungen. Im Inspector lassen sich Funktion, Innenbereich, Vorderbereich, Personalbereich, Schalter und Tür einstellen. Die Werte sind in Kacheln. Beim Verschieben einer Markierung wandern diese Bereiche mit. Schalter und Türen müssen zu den gemalten Kacheln und Geräten passen.
5. Strg+S speichert. Das Plugin speichert zusätzlich alle offenen Szenen alle 30 Sekunden, während kein Spiel läuft. Änderungen lassen sich mit Godots Rückgängig-Funktion bearbeiten. Neue unbenannte Szenen zuerst unter `designs` speichern.

`designs/ships/rostlaube.tscn` ist das Startschiff. `lumen` und `bairn` sind die kaufbaren Schiffe. `wreck` ist die Vorlage neuer Wrackziele. `designs/places` enthält alle sieben festen Orte einschließlich Asteroid, Trümmerfeld und Außenposten.

Schiffsentwürfe sind um den Ursprung zentriert. Die Root-Metadaten `grid_origin` setzen sie im Spiel in die 128 × 88 Kacheln große Welt. Mit dem voreingestellten Ursprung (64, 44) reicht der bearbeitbare Bereich von (-64, -44) bis (63, 43). Orte und Wracks verwenden einen lokalen Andockrahmen. Die Anschlusskachel liegt bei (0, 0), die positive Y-Achse führt vom Schiff weg. Diese Anschlusskachel erhalten und den Entwurf so dimensionieren, dass er neben dem Schiff in die Welt passt. Geräte brauchen einen passenden Untergrund. Triebwerke und Schleusen benötigen ihre vollständige Grundfläche. Ein Schiff benötigt begehbaren Boden für die Besatzung. Die Container Terrain, Cables und Devices am Ursprung belassen, die Kacheln und einzelnen Geräte darin bearbeiten.

Für das Startschiff mit F5 ein neues Spiel starten. Kaufbare Schiffe werden beim Kauf aus den Entwürfen erzeugt. Stationsentwürfe werden beim Andocken geladen. Orte und Wracks werden bei der ersten Erzeugung aus den Szenen geladen. Vorhandene Spielstände und bereits besuchte Wracks behalten ihren gespeicherten Zustand. Für einen vollständigen Entwurfstest ein neues Spiel verwenden. Entwurfsszenen direkt mit F6 zu starten zeigt nur die Szene; der normale Spieleinstieg ist F5.

## Speicherung und Claude Code

Die `.tscn`-Dateien sind die maßgeblichen Baupläne. Claude Code liest die Regeln in `CLAUDE.md` und `AGENTS.md` und soll Codeänderungen an diesen Entwürfen ausrichten. Auf demselben Rechner und im selben Repository stehen gespeicherte Änderungen sofort als Dateien bereit. Eine KI-Regel ersetzt keine Versionssicherung.

Das Plugin legt für jede gespeicherte Fassung eine lokale Sicherung unter `user://design_backups` ab. Der Button **Sicherungsordner öffnen** zeigt den Ordner. Sicherungen nach Dateiinhalts-Hash verhindern doppelte Kopien. Zum Wiederherstellen die gewünschte `.tscn`-Datei bei geschlossenem Entwurf an dessen ursprünglichen Pfad kopieren. Sicherungen ergänzen die Git-Historie und bleiben lokal.

Damit die Entwürfe auch nach einem GitHub-Download oder in einer Claude-Code-Umgebung auf einem anderen Rechner verfügbar sind, die Änderungen in GitHub Desktop committen und pushen. Danach muss die andere Umgebung diesen Stand holen. Das Plugin führt keine Git-Synchronisierung aus. Externe Änderungen an einer geöffneten Szene unterbrechen das automatische Speichern bis zum Neuladen beziehungsweise Prüfen der Szene.

## Entwicklung

`DesignLoader` überträgt TileMap-Kacheln, Kabel und Geräte in `ShipGrid`. Die normale Simulation und Spielstandverwaltung arbeiten weiter mit diesem Raster. Die ursprünglichen Generatoren dienen als Fallback für Projekte ohne passende Entwurfsszene. Bestehende Entwürfe niemals automatisch neu generieren.

Prüfung mit Godot

```text
godot --headless --path . --script res://tests/boot.gd -- test_designs
godot --headless --path . --script res://tests/boot.gd -- test_stations
```
