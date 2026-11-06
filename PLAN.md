# Bauplan – Weltraum_Game

Düstere Weltraum-Survival- und Raumschiff-Simulation (Ansicht von oben), spielmechanisch an Ostranauts angelehnt,
mit eigener Welt, eigenen Inhalten und eigenen Ideen. Der Spieler startet als mittelloser Schrotthändler mit Schulden
und arbeitet sich hoch: Wracks bergen, handeln, Schiffe umbauen, Crew anheuern, ein eigenes Unternehmen aufbauen.

Jede Etappe endet mit einer spielbaren, getesteten Version.

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
- [ ] Items mit Schrott verbessern (Idee aus Probably Stolen) – kommt mit dem Händler

### Etappe 5 – Bergung & Wirtschaft (erste vollständige Spielschleife)
- [ ] Start am Mond mit viel Müll und Wracks in der Nähe
- [ ] Wracks betreten, untersuchen, wertvolle Teile erkennen, ausschlachten
- [ ] Station mit Händler: schwankende Preise, Angebot und Nachfrage
- [ ] Schulden mit regelmäßigen Raten, Liegegebühren, Reparaturkosten
- [ ] Brennstoff, Sauerstoff, Essen nachkaufen

### Etappe 6 – Flug & Physik
- [ ] Karte: Mond (Start), Erde als Schwerkraft-Falle (schwächer als real – nach dem Krieg ausgebeutet), Stationen, Asteroiden
- [ ] Schiffe bewegen sich physikalisch: Trägheit, Beschleunigung, Rotation, Orbits
- [ ] Triebwerke und Tanks als Bauteile, Treibstoffverbrauch
- [ ] Manuelles Docking, Auto-Dock-Modul, Kollisionen
- [ ] Mehrere eigene Schiffe, Schiffe kaufen, verkaufen und umbauen
- [ ] Schnellreise als Zusatzoption

### Etappe 7 – Tiefere Schiffssysteme
- [ ] Temperatur, Heizung, Kühlung, Körpertemperatur, Kleidung mit Schutzwerten
- [ ] Wasser und Abwasser, Rohrleitungen, Wasserfilter
- [ ] Feuer (braucht Sauerstoff), Löschen
- [ ] Fenster, Steuerpult
- [ ] Essen anbauen: von Hand und automatisch (teuer, begrenzt, Gen-Mods, tägliche Ernte)
- [ ] Essen als Block-Version, Fleisch als Klumpen oder Käfig-Version, Chemiestation

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
