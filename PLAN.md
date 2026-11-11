# Bauplan – Weltraum_Game

Düstere Weltraum-Survival- und Raumschiff-Simulation (Ansicht von oben), spielmechanisch an Ostranauts angelehnt,
mit eigener Welt, eigenen Inhalten und eigenen Ideen. Der Spieler startet als mittelloser Schrotthändler mit Schulden
und arbeitet sich hoch: Wracks bergen, handeln, Schiffe umbauen, Crew anheuern, ein eigenes Unternehmen aufbauen.

Jede Etappe endet mit einer spielbaren, getesteten Version.

## Umstieg auf Godot 4

Ab jetzt wird das Spiel in Godot 4.7 mit GDScript gebaut. Die Etappen 1–6 existieren als Browser-Version in `web/`
und werden Schritt für Schritt übertragen.

- [x] Godot-Projekt mit Ordnerstruktur, Autoloads, Resources (Gegenstände, Geräte), Signals (EventBus)
- [x] Übertragen: Schiffsraster, Bauen mit Material, Abreißen, Wegfindung (AStarGrid2D), Crew mit Bedürfnissen,
      Luft pro Feld mit Lecks, Strom, Lebenserhaltung, Inventar, Kisten, Speichern (JSON), Oberfläche, WASD
- [x] Übertragen: Luftschleuse, Raumanzüge, Ladestation, Versetzen, Solarpanel, Schäden, Reparatur (Etappe 3) – 20 Tests
- [x] Übertragen: Nachfüllen, Einsammeln, Werkbank (Rezepte in data/recipes.json), Wracks, Handelsterminal, Markt, Kredit, Pfändung (Etappe 4–5) – 32 Tests
- [x] Übertragen: Raumflug mit Schwerkraft, Navigationskarte, Andocken, Auto-Dock, Schnellreise, Absturz, Flotte, Wrack anmelden (Etappe 6) – 54 Tests
- [x] Skill-, Hobby- und Trait-System (eigener Prompt) – 144 Tests
  - 32 Fähigkeiten als Resources (Technik, Kampf, Praxis, Soziales), 83 Trainingsaktionen in `data/skill_actions.json`
  - Lernen nur durch passende Tätigkeiten, Schwierigkeit, Abschwächung bei Wiederholung, Voraussetzungen (Stopp bei 40 %), 0–100 %, Meisterschaft
  - Wirkungen: Arbeitstempo je Technik-Art, Treibstoff, Reisezeit, Anzug-Sauerstoff, Handel, Schätzgenauigkeit, Hacken (verschlossene Kisten),
    Kampfkraft (Plünderer), Gespräche je Etikette, Bar (Gesang, Tanz, Schauspiel, Glücksspiel), Kochen, Forensik, Schmuggel, Psychologie
  - 64 Lehrbücher (Grundlagen bis 40 %, Fortgeschritten bis 75 %), Lesen in Ruhezeiten
  - 16 Eigenschaften (Traits), 10 Hobbys, Stress
  - Lebenslauf mit 14 Stationen, Zufallsereignissen, Kontakten, Feinden, Startgeld
  - Crew anheuern (Lohn, Kündigung), Aufgabenverteilung, Charaktermenü mit Details und Lernhistorie

## Erledigt

### Etappe 1 – Fundament
- [x] Schiff aus Kacheln, Kamera (verschieben, zoomen)
- [x] Charakter mit Wegfindung, Baumodus (Boden, Wand, Tür, Abreißen), Baupläne
- [x] Zeitsteuerung, Speichern/Laden, Autosave

### Etappe 2 – Lebenserhaltung
- [x] Luft pro Feld (O₂, N₂, CO₂ in kPa), Druck, Lecks ins All
- [x] Sauerstoff-Generator, CO₂-Filter, Lufttank
- [x] Strom: Generator, Batterien, Kabel, Stromnetze
- [x] Bedürfnisse: Hunger, Durst, Energie, Hygiene, Atmung, Gesundheit

### Etappe 3 – Weltraum & Schäden
- [x] Luftschleuse mit Pumpe, Raumanzüge, Anzugschrank, Außeneinsätze
- [x] Tragbare Ladestation, Gerät versetzen
- [x] Brennstoff für den Generator, Solarpanel
- [x] Verschleiß, Mikrometeoriten, sichtbare Risse, Reparatur
- [x] Echtzeit (1 s = 1 s), Vorspulen bis 300×, Rechtsklick bricht ab

## Geplant

### Etappe 4 – Gegenstände & Inventar
- [x] 15 Gegenstände mit Gewicht, Volumen, Zustand und Marktwert (datengetrieben in items.js)
- [x] Gepäck für Charaktere, Frachtkisten, Haufen auf dem Boden
- [x] Aufheben, ablegen, Kisten durchsuchen (Taste E), Material holen
- [x] Abreißen gibt Teile zurück (Geräte zerlegen, Kabel ausbauen)
- [x] Bauen kostet Material, abgebrochene Pläne geben es zurück
- [x] Vorräte (Essen, Wasser, Brennstoff, Luft) werden automatisch aus dem Lager nachgefüllt
- [x] Deine Figur direkt mit WASD steuern, die Crew arbeitet selbstständig
- [x] Items mit Schrott verbessern: siehe Werkbank in Etappe 5

### Etappe 5 – Bergung & Wirtschaft (erste vollständige Spielschleife)
- [x] Start am Tycho-Schrottplatz im Mondorbit, Wrack an der unteren Andockschleuse (früher Bergungsleine und Außensteg)
- [x] Zufällige Wracks: Räume, Lecks, abgestandene Luft, beschädigte Geräte, Kisten, Schrott, alte Kabel
- [x] Geräte und Kisten erst erkennbar, wenn jemand nahe herangeht; geschätzter Bergungswert
- [x] Einsammeln-Werkzeug: Crew bringt Haufen in die Frachtkisten
- [x] Handelsterminal: verkaufen, kaufen, schwankende Preise, Angebot und Nachfrage
- [x] Kredit mit Raten alle 7 Tage, Liegegebühr, Strafzins, Pfändung nach 3 verpassten Raten
- [x] Bergungsrechte kaufen, Wrack verschrotten
- [x] Werkbank: aus Schrott Platten, Rohre, Platinen, Filter, Akkuzellen, Stoff (Idee aus Probably Stolen)

### Etappe 6 – Flug & Physik (Web-Version erledigt)
- [x] Verkleinertes Erde-Mond-System: Tycho-Schrottplatz, Kármán-Ring (Werft), Habitat L4 (Schwarzmarkt), Trümmerfeld Achilles
- [x] Schwerkraft von Erde und Mond, Trägheit, Umlaufbahnen, Stationen kreisen
- [x] Triebwerke, Treibstofftank, Masse aus Rumpf/Geräten/Ladung, Treibstoffverbrauch
- [x] Lose Ladung auf dem eigenen Schiffsboden zählt genau einmal zur Masse (fremde Bereiche nicht)
- [x] Manueller Flug nur am bedienten Steuerpult (intakt, mit Strom, Pilot steht dort)
- [x] Abdocken, Schnellreise und Auto-Dock ebenfalls nur am bedienten Steuerpult
- [x] Andocken nur am bedienten Pult; Schnellreise/Auto-Dock brechen bei Pultausfall ab; „Ausrichten“ mit Drehschub
- [x] Persönliches Inventar per Tab (auch im Cockpit; Zielwechsel jetzt T)
- [x] Abbauen legt genau einen vollständigen Gegenstand (Zustand, Inhalt) auf den Boden; eine Figur trägt ein Gerät in den Händen
- [x] Einheitliches Gewicht: Gegenstand = Gerätemasse; Getragenes an Bord zählt zur Schiffsmasse
- [x] Triebwerke als 1×3-Geräte durch die Außenwand; alte 1×1-Triebwerke werden beim Laden umgestellt
- [x] Rechtsklick-Auswahl in Ebenen (Kabel → Gerät → Boden), Abbauen wirkt genau auf die markierte Ebene
- [x] Feineres Baufeld-Raster (16 px statt 32 px); alte Spielstände werden beim Laden verfeinert
- [x] Navigationskarte mit vorausberechneter Flugbahn, manuelles Fliegen (WASD), Geschwindigkeit angleichen
- [x] Manuelles Andocken, Auto-Dock-Modul, Schnellreise, Zusammenstöße
- [x] Erde als Schwerkraft-Falle (Absturz), Mond-Absturz
- [x] Mehrere Schiffe: kaufen, wechseln, verkaufen; Wrack als eigenes Schiff anmelden
- [x] Wracks bleiben an ihrem Ort; Trümmerfeld liefert gratis Wracks

### Etappe 7 – Tiefere Schiffssysteme (Godot, 19 Tests)
- [x] Temperatur pro Feld, Wärmeverlust ans All, Heizung (mit Thermostat), Abwärme des Generators
- [x] Körpertemperatur, Unterkühlung, Überhitzung, Thermojacke, Raumanzug schützt
- [x] Feuer (braucht Sauerstoff, springt über, beschädigt Geräte), Löschen, Feuerlöscher-Station, Vakuum erstickt Feuer
- [x] Fenster (senken Stress, kosten Wärme)
- [x] Wasserkreislauf: Abwasser, Wasserfilter mit Filterkartuschen (Rohrleitungen vereinfacht als Schiffsnetz)
- [x] Hydrokultur von Hand (Pflege, Ernte), Auto-Farm (teuer, mit Gen-Mod täglich), Fleischtank (Käfig-Version)
- [x] Nahrungsblock, Fleischklumpen, Saatgut, Chemiestation (Filter, Brennstoff, Gen-Mods)

### Etappe 8 – Crew (Godot)
- [x] Mehrere Charaktere: Crew anheuern, Lohn, Kündigung bei fehlendem Lohn
- [x] Persönlichkeiten (Traits), Fähigkeiten, Hobbys, Stress, Moral
- [x] Beziehungen (Nähe, gemeinsame Hobbys, Geselligkeit), Streit bei Stress, Schlichten (Psychologie/Überzeugen)
- [x] Geschichten über die Charaktere: kurze Sätze aus ihrem Lebenslauf, keine Textbildschirme
- [x] Charaktere exportieren und in andere Spielstände übernehmen

### Etappe 9 – Lebendige Welt (Godot)
- [x] Fraktionen mit Ansehen (Händlergilde, Konsortium, Syndikat, Patrouille)
- [x] Aufträge: Liefern und Transport mit Frist, Belohnung und Ansehen
- [x] Schwarzmarkt, Schmuggel mit Kontrollen, Versicherung, Schiffskredit, Liegegebühr
- [x] Tägliche Weltereignisse verändern Preise
- [x] Neue Orte: Eisbrocken KX-7 (Eis und Erz abbauen), Außenposten Kepler (verschlossene Beute), Raffinerie Hephaistos (zahlt gut für Erz)
- [x] Begehbare Stationen: Druckschlauch vom Schiff, Gang mit Markt, Bar, Auftragsbrett, Heuerbüro, Bergungsamt, Kreditbüro und Werft; Figuren hinter den Tresen, Kontakte in der Bar, Bewerber im Heuerbüro; am Markt direkt aus dem Gepäck verkaufen

### Etappe 10 – Feinschliff (Godot)
- [x] Einstellbare Simulationstiefe, Autosave-Intervall, Meteoriten an/aus
- [x] Mod-Unterstützung: eigene .tres-Dateien in user://mods/ (Gegenstände, Geräte, Fähigkeiten, Traits, Hobbys)
- [x] Drei Speicherplätze
- [x] Gezeichnete Symbole für alle Geräte, erzeugte Geräusche (Alarm, Meldung, Bauen)
- [x] Zielführung: 11 Ziele vom ersten Raumanzug bis zur abbezahlten Schuld, mit Belohnungen
- [x] Balancing: Wochen-Simulation (`tests/balance_week.gd`) – Bergung allein reicht knapp für die erste Rate (Bergungsrecht 200 Cr, Verkauf 85 %)
- [ ] Sprites aus Grafikdateien

## Tests (Godot, ohne Fenster)
- `tests/run_tests.gd` – Kernspiel, Etappe 1–6 (54 Prüfungen)
- `tests/test_skills.gd` – Fähigkeiten, Traits, Hobbys, Lebenslauf, NPCs, Stationen (144)
- `tests/test_systems.gd` – Temperatur, Feuer, Wasser, Anbau, Chemie (21)
- `tests/test_world.gd` – Crew-Beziehungen, Aufträge, Fraktionen, Einstellungen, Mods, Speicherplätze, neue Orte, Ziele (32)
- `tests/test_stations.gd` – begehbare Stationen: Aufbau, Luft, Gespräche, Verkauf, Speichern, Abdocken (36)
- `tests/test_undock.gd` – manuelles Abdocken: Gründe, Sperre gegen Wieder-Andocken, alle Zeitstufen, Speichern (49)
- `tests/test_docking.gd` – Andockschleusen: ohne Schleuse kein Andocken, Tür an Tür, keine Extra-Felder, Abdocken ohne Rest, Wrack, Bau, alte Spielstände (40)
- `tests/test_core.gd` – Kernspiel mit abgeschalteter Station und abgeschaltetem Wrack (21)
- `tests/test_flight.gd` – manuelle Schiffssteuerung: Cockpit, Drift, Drehung, Gegenschub, Anflug und Andocken, Zeitstufen, Speichern (36)
- `tests/test_thrusters.gd` – Triebwerke (1×3): Schub addiert sich, Masse bremst, Richtungen, Aus- und Einbau, Speichern, Zeitstufen, Drift (32)
- `tests/test_grid.gd` – Feineres Raster: 4 Felder pro altem Feld bauen/abbauen, Ebenen, Laufstrecke, Türdurchgang, alter Spielstand (Schleuse, Druckhülle, Ports, Andocken) (45)
- `tests/test_select.gd` – Rechtsklick-Ebenen mit echten Mausklicks: Reihenfolge, Abbau Ebene für Ebene, leere Ebenen, Kachelwechsel, Triebwerk (22)
- `tests/test_parts.gd` – Tab-Inventar (auch Cockpit), Abbau als Gegenstand am Boden, Gewicht beim Umlagern und von Bord, 1×3-Einbau und Abweisungen, alte Spielstände (60)
- `tests/test_match.gd` – Angleichen (X): manueller Puls, Lagedüsen allein, kein Treibstoff, Ausstieg, Laden (22)
- `tests/test_cargo_mass.gd` – Masse loser Ladung: Behälter ↔ Boden, fremder Bereich, Haufen im All, Laden, Schiffswechsel (24)
- `tests/test_helm.gd` – Flug am bedienten Pult: kaputtes/stromloses Pult weist ab, Pultwechsel, Stromausfall unter Schub, Angleichen, Abdocken/Reise/Auto-Dock, Andocken, Abbruch bei Pultausfall, Ausrichten, Laden (70)
- Alle Reihen parallel: `tests/run_all.sh` (etwa 100 s)
- `tests/test_removal.gd` – Rechtsklick-Menü: Abbauen, Zerlegen, Zerstören, Einbauen, Gründe, Inhalt, Zeitstufen, Speichern (52)
- `tests/test_auto.gd` – Auto-Modus: Aufgaben wählen, sofort anhalten, neu bewerten, Tragen, Notfall, Speichern (24)
- `tests/test_atmosphere.gd` – Atmosphäre und Raumdruck: dichte Kabine, Tür, Innen-/Außenwand, Bodenloch, Abdichten/Wiederbefüllen, zwei Lecks und Laden (38)
