# Bauplan – Weltraum_Game

Düstere Weltraum-Survival- und Raumschiff-Simulation (Ansicht von oben), spielmechanisch an Ostranauts angelehnt,
mit eigener Welt, eigenen Inhalten und eigenen Ideen. Der Spieler startet als mittelloser Schrotthändler mit Schulden
und arbeitet sich hoch: Wracks bergen, handeln, Schiffe umbauen, Crew anheuern, ein eigenes Unternehmen aufbauen.

Jede Etappe endet mit einer spielbaren, getesteten Version.

## Umstieg auf Godot 4

Ab jetzt wird das Spiel in Godot 4.3 mit GDScript gebaut. Die Etappen 1–6 existieren als Browser-Version in `web/`
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
- [x] Start am Tycho-Schrottplatz im Mondorbit, Wrack an der Bergungsleine
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

### Etappe 8 – Crew
- [ ] Mehrere Charaktere, übertragbar zwischen Spielständen
- [ ] Persönlichkeiten, Fähigkeiten, Beziehungen, Moral, Stress, Konflikte
- [ ] Zufriedenheitssystem, Gehaltsforderungen, Crew anheuern
- [ ] Geschichten und Dialoge nur über die Charaktere, keine Textbildschirme

### Etappe 9 – Lebendige Welt
- [ ] Fraktionen, Handelsrouten, Aufträge, Handelsverträge
- [ ] Schwarzmarkt, Versicherungen, Schiffskredite, Miete
- [ ] Verlassene Außenposten, Industrieanlagen, Bergungsgebiete
- [ ] Stationssystem (wie die Ostranauts-Mod), Welt entwickelt sich weiter

### Etappe 10 – Feinschliff
- [ ] Einstellbare Simulationstiefe
- [ ] Mod-Unterstützung (Gegenstände, Geräte, Schiffe als Datendateien)
- [ ] Mehrere Speicherplätze, Export/Import
- [ ] Bessere Grafik, Sound, Balancing
