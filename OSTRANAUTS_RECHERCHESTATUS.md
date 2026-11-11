# Ostranauts – Recherchestatus

Sammelt, welches Ostranauts-Verhalten für „Weltraum Game“ belegt ist, woher es stammt
und was davon im Godot-Projekt als eigene Entscheidung umgesetzt wurde.

**Stufen:**
- *gemessen*: am laufenden Spiel selbst beobachtet
- *dokumentiert*: Wiki oder Entwickler, im Volltext gelesen
- *sekundär*: nur aus Suchergebnis-Auszügen oder Fan-Guides, nicht im Volltext
  geprüft und nicht am Spiel gemessen

## Atmosphäre und Raumdruck

Siehe Bauplan „Atmosphäre und Raumdruck“ (Messungen am Release Build 1.0.1.5, Testschiff
`_9x9 Air Test`). Umsetzung: `scripts/ships/atmosphere_system.gd`, Tests: `tests/test_atmosphere.gd`.

## Manuelle Schiffssteuerung (Stand: November 2026)

Der Zugriff auf `ostranauts.wiki.gg` war in der Arbeitsumgebung gesperrt, und ein laufendes
Ostranauts stand nicht zur Verfügung. Alle Befunde unten sind deshalb **sekundär**.
Sie stammen aus Suchergebnis-Auszügen des Wikis (Seiten „Flying“, „Navigation Console“,
Wiki-Stand 0.14.3.8) und aus Fan-Guides.

| Befund | Stufe | Quelle |
|---|---|---|
| Fliegen und Kommunizieren geht nur mit einer Navigationskonsole (Nav Station) | sekundär | Wiki „Navigation Console“ |
| WASD gibt Schub in Bewegungsrichtung (translatorisch), Q/E dreht das Schiff | sekundär | Fan-Guides (gamepretty.com, magicgameworld.com) |
| Tutorial-Text im Wiki: Taste „R“ stoppt die Drehung, „E“ dreht im Uhrzeigersinn | sekundär | Wiki „Flying“ (0.14.3.8) |
| Alle Schiffe haben RCS (langsame Lagedüsen), manche zusätzlich ein Fusionstriebwerk | sekundär | Fan-Guide |
| „Station keeping“: Schiff zeigt aufs Ziel und gleicht die Relativgeschwindigkeit (VREL) auf 0 an | sekundär | Wiki „Flying“ |
| Andocken: Ringe ausrichten, mit W annähern, Klammern, wenn die Klammer-Anzeige grün ist | sekundär | Wiki „Flying“ / Guides |
| Tutorial: Anflug mit VREL unter 100 m/s; Ziel ist eine Relativgeschwindigkeit nahe 0 | sekundär | Wiki „Flying“ |
| RCS-Schubregler für feine Geschwindigkeitsänderungen | sekundär | Wiki „Flying“ |
| Die Schubrichtung ist nicht bei allen Schiffen gleich (In-Game-Spickzettel beachten) | sekundär | Steam-Forum (Suchauszug) |

**Offen** (nicht geprüft):
- die genauen Standardtasten der aktuellen Version
- ob die Drehung ohne Gegenschub weiterläuft
- Grenzwerte für Andockabstand und Andocktempo
- Verhalten bei Zeitraffer

Nachprüfen am laufenden Spiel: Nav Station, RCS-Modus, Tasten im Optionsmenü, Drehung
loslassen und beobachten, Andocken mit verschiedenen VREL.

### Umsetzung in Godot und eigene Entscheidungen

Belegt (sekundär) und übernommen:
- Fliegen nur am Steuerpult
- W/S vor und zurück, A/D seitwärts, Q/E drehen, R Drehung stoppen
- Lagedüsen an jedem Schiff
- Angleichen ans Ziel
- Andocken mit ausgerichteter Schleuse

Eigene Entscheidungen (nicht aus Ostranauts belegt):
- **Drehung mit Schwung:** Drehschub beschleunigt die Drehung (0,5 rad/s², höchstens
  1 rad/s). Ohne Gegenschub dreht das Schiff weiter, R bremst. Das ist abgeleitet aus
  dem Tutorial-Hinweis „R stoppt die Drehung“.
- **Lagedüsen** mit 12 kN, für alle Richtungen und die Drehung. Das **Haupttriebwerk**
  (vorhandene Triebwerke, je 40 kN) schiebt nur vorwärts. Rückwärts und seitwärts
  gibt es nur die Lagedüsen.
- **Treibstoff:** Das Haupttriebwerk verbraucht wie bisher (`burn`), die Lagedüsen
  verbrauchen `rcs_burn` 0,6 pro Spielminute bei vollem Schub.
- **Andocken:** näher als 250 m, langsamer als 6 m/s (vorhandene Projektwerte) und eine
  freie Andockschleuse zeigt auf höchstens 25° zum Ziel.
- **Bewegungsanzeige** relativ zum gewählten Ziel (VREL), dazu Bremswege für Lagedüsen
  und Haupttriebwerk nach dem Wenden.
- **Zeitraffer:** Schub und Drehung laufen in Spielzeit. Eine gehaltene Taste wirkt bei
  ×16 also 16-mal so stark pro echter Sekunde.
- Alle Werte stehen in `data/space.json` (`rcs_thrust`, `rcs_burn`, `rot_accel`,
  `rot_max`, `dock_align_deg`).

### Flug am bedienten Steuerpult (Stand: November 2026)

**Quelle:** offizieller Ostranauts-Startguide auf Steam:
https://steamcommunity.com/sharedfiles/filedetails/?id=3347080066

Laut Nutzer belegt der Guide eine installierte, mit Strom versorgte Navigationskonsole
als Voraussetzung zum Fliegen. `steamcommunity.com` war in der Arbeitsumgebung gesperrt,
der Text konnte deshalb **nicht gelesen** werden.

**Offen:**
- wie Ostranauts bei mehreren Pulten auswählt
- wie ein abgewiesener Einstieg angezeigt wird

Umsetzung (`PhysicsSystem.helm_at`, `manual_ok()`, `UIManager.request_flight()`,
Tests: `tests/test_helm.gd`):
- Schub, Drehschub und Angleichen gibt es nur über das Pult, an dem der Pilot steht.
  Dieses Pult muss intakt sein und Strom haben. Ein anderes versorgtes Pult hilft nicht.
- Das bediente Pult wird als Feldposition gemerkt, nicht als Geräte-Instanz, und nicht
  gespeichert. Nach dem Laden steigt man wie gewohnt per Klick oder N wieder ein.
- **Eigene Entscheidungen:**
  - Klick nimmt das angeklickte Pult, N das nächste.
  - Ist es kaputt oder ohne Strom, wird der Einstieg mit einer Meldung abgewiesen.
  - Fällt das bediente Pult im Flug aus, bleibt das Cockpit offen. Schub, Drehschub und
    Angleichen enden mit Meldung, und das Cockpit zeigt den Grund.
  - Geschwindigkeit und laufende Drehung bleiben erhalten.
- Abdocken, Schnellreise und Auto-Dock starten ebenfalls nur am bedienten Pult, das
  intakt sein und Strom haben muss (`PhysicsSystem.pilot_block_reason()`). Ohne Pilot am
  Pult kommt die Meldung „Das geht nur am Steuerpult: erst ins Cockpit (N).“
- Die Knöpfe „Ausrichten“ und „Angleichen“ in der Zielliste sind ohne versorgtes,
  bedientes Pult gesperrt.
- Andocken mit F oder „Andocken“ geht ebenfalls nur am bedienten Pult.
- **Laufende Schnellreise und Auto-Dock** merken sich das Pult, das sie gestartet hat
  (als Position, auch im Spielstand). Fällt es aus (kaputt, ohne Strom, abgebaut), bricht
  der Vorgang mit Meldung ab. Nach einer abgebrochenen Schnellreise fliegt das Schiff mit
  der Reisegeschwindigkeit frei weiter. Verlässt der Pilot nur das Cockpit, läuft beides
  weiter (eigene Entscheidung). Ältere Spielstände ohne Pult-Angabe: irgendein
  versorgtes Pult genügt.
- **„Ausrichten“** dreht das Schiff mit den Lagedüsen zum Ziel: beschleunigen, rechtzeitig
  bremsen, ohne Restdrehung ankommen (mit Treibstoffverbrauch wie Q/E). Q, E oder R brechen
  ab, ebenso ein Ausfall des Pults.

## Triebwerke, Schub und Masse (Stand: November 2026)

Wiki-Auszug über eine Websuche (Seite „Halvorson RCS Thruster Assembly“), **sekundär**,
nicht im Volltext geöffnet (Wiki in der Arbeitsumgebung gesperrt):

| Befund | Stufe |
|---|---|
| Ein Halvorson-RCS-Thruster liefert etwa 59 kN (entspricht 6 G bei 1 t Masse) | sekundär |
| Maximale Beschleunigung = Anzahl Thruster × 6000 kg·G ÷ Schiffsmasse; der Schub wächst linear mit der Anzahl | sekundär |
| Beispiel: 20-t-Schiff mit 5 Thrustern ≈ 1,5 G; 40-t-Schiff braucht 20 Thruster für 3 G | sekundär |
| Infobox-Masse des Thrusters „28.0“ ohne Einheit | sekundär, Einheit offen |
| RCS ist rund um K-Leg der Hauptantrieb zum Bergen, das Fusionstriebwerk für Reisen zwischen Planeten | sekundär |

**Offen:**
- wie Ostranauts Thruster verschiedener Richtung bei einer Eingabe kombiniert
- ob die Thruster-Masse 28 kg oder etwas anderes bedeutet
- wie ihr Schub beim Drehen des Schiffs wirkt

### Umsetzung in Godot und eigene Entscheidungen

Übernommen (sekundär belegt):
- Beschleunigung = Gesamtschub ÷ Schiffsmasse
- Schub gleich ausgerichteter Triebwerke addiert sich linear

Eigene Entscheidungen:
- **Schub und Masse:** Triebwerk mit 40 kN (bisheriger Projektwert, nicht die 59 kN aus
  dem Wiki) und Masse 1,5 t. Beides steht in `resources/components/thruster.tres`.
- **Richtung:** Drehbar in 90°-Schritten. Ein Triebwerk schiebt in eine von vier
  Richtungen relativ zur Schiffsnase: vor, rechts, zurück, links.
- **Welche Triebwerke feuern:** Bei W feuern alle Triebwerke, die nach vorn schieben,
  bei S die nach hinten, bei D die nach rechts, bei A die nach links. Die Lagedüsen
  (12 kN) helfen in jeder Richtung mit.
- **Treibstoff:** Jedes aktive Triebwerk verbraucht `burn` (4 pro Spielminute bei vollem Schub).
- **Aktiv** heißt: eingebaut, mit Strom (Kabel), nicht kaputt. Ein kaputtes Triebwerk
  bleibt Masse, liefert aber keinen Schub.
- **Masse:** Rumpffeld 0,2 t (`Config.TILE_MASS`), jedes Gerät seine eigene Masse
  (`DeviceData.mass`, Standard 0,5 t, Triebwerk 1,5 t), dazu Ladung in Behältern und
  Haufen an Bord. Was die Crew im Gepäck trägt, zählt nicht mit.

### Masse loser Ladung (Stand: November 2026)

**Quelle:** Ostranauts-Wiki „Getting started“, Abschnitt 40:
https://ostranauts.wiki.gg/wiki/Getting_started?section=40

Vom Nutzer als Quelle genannt. Das Wiki war in der Arbeitsumgebung gesperrt, der Text
konnte deshalb **nicht gelesen** werden.

Umsetzung (`PhysicsSystem.mass()`, Tests: `tests/test_cargo_mass.gd`):
- Ladung zählt genau einmal, egal ob sie in einem eigenen Behälter oder als Haufen auf
  dem eigenen Schiffsboden liegt. Umlagern ändert Masse und Beschleunigung nicht.
- Haufen auf fremden Bereichen (Wrack, Station) zählen nicht zur eigenen Masse.
- Haufen auf Weltraumfeldern neben dem Rumpf zählen ebenfalls nicht (eigene Entscheidung).
- Gespeicherte Bodenhaufen werden mitgeladen. Beim Schiffswechsel zählt nur die Ladung
  des Schiffs, auf dem man gerade ist.
- Nicht Teil dieser Änderung: Crew-Gepäck, Gas und Tankinhalt.
- **Drehen:** Rechtsklick → „Drehen“ ist ein kurzer Crew-Auftrag von etwa einer Spielminute.
- **Bauen:** Schwere Bauteile (Triebwerk: 44 kg Material) holt die Crew in mehreren
  Gängen und legt das Material am Bauplatz ab.

### Inventar, Abbau und 1×3-Triebwerke (Stand: November 2026)

Keine Ostranauts-Quelle in diesem Auftrag. Alles hier sind **Projektvorgaben bzw. eigene
Entscheidungen**:
- **Tab** öffnet das persönliche Inventar, auch im Cockpit. Der Zielwechsel liegt jetzt auf **T**;
  die Ziel-Knöpfe in der Liste gehen weiter.
- **Abbauen** legt genau einen vollständigen Gegenstand auf ein erreichbares Bodenfeld.
  Zustand, Drehung und Inhalt (z. B. Kisteninhalt) bleiben im Gegenstand.
  **Zerlegen** und **Zerstören** bleiben eigene Aktionen.
- **Gewicht** (Entscheidung des Nutzers: „schwer, in den Händen“):
  - Ein abgebautes Gerät wiegt so viel wie seine Masse im Schiff (Standard 500 kg,
    Triebwerk 1500 kg), ein abgebauter Block 200 kg.
  - Eine Figur trägt genau ein solches Stück in den Händen, unabhängig vom Tragelimit
    von 40 kg.
  - Alles, was eine Figur an Bord trägt, zählt zur Schiffsmasse.
- **Triebwerk 1×3:** Innenfeld auf dem Schiffsboden, Mitte auf einer Außenwand (bleibt Wand
  und dicht), Düse im freien All. Schub zeigt von der Düse weg.
  - Abgewiesen werden: Innenwand, vertauschte Seiten, belegtes Düsenfeld und
    Überschneidungen.
  - Nachträgliches Drehen und Versetzen gibt es für 1×3-Geräte nicht mehr (abbauen und
    neu einbauen).
- **Alte Spielstände:**
  - Ein altes 1×1-Triebwerk wird nur umgestellt, wenn an seinem Platz alle drei Felder
    gültig und frei sind.
  - Sonst liegt es einmal als vollständiger Gegenstand an seinem Platz.
  - Gespeichert wird danach die neue Form, die Umstellung greift also nur einmal.
  - Alte Gepäckstücke bleiben vollständig erhalten. Wer mehrere abgebaute Teile im
    Gepäck hatte, behält sie, kann aber erst wieder eines aufnehmen, wenn die Hände frei
    sind.

### Feineres Baufeld-Raster (Stand: November 2026)

**Quelle:** Ostranauts-Screenshot des Nutzers (Figur mit weißen Eckmarkierungen, kleine
Baufelder). Gemessen wurde nichts. Ziel: Die Figur wirkt im Verhältnis zu den Baufeldern
größer.

**Umsetzung:**
- Ein Baufeld ist 16 px groß statt 32 px, das Raster 128×88 statt 64×44.
  Figur (32 px) und Kamera-Zoom bleiben gleich. Ausgewählte Figuren tragen weiße
  Eckmarkierungen.
- Wände sind 1 Feld dick, Türen 1 Feld breit. Ein Gerät belegt 1 Feld, das Triebwerk
  1×3 Felder.
- **An der Feldgröße hängende Werte:**
  - Laufen doppelt so viele Felder pro Zeit (gleiche sichtbare Strecke).
  - Klick- und Gesprächsabstände, Heiz- und Einschlagradius ×2.
  - Rumpfmasse 0,05 t je Feld (= 0,2 t je früherem Feld).
  - Luftschleuse bis 48 Felder.
  - Wrack, Asteroid und Station in doppelten Maßen.
- **Alte Spielstände** werden beim Laden verfeinert (`ShipGrid.refine`):
  - Böden werden 2×2.
  - Wände werden eine dichte Linie auf der Außenseite; abgeschlossene Taschen
    werden Wand.
  - Geräte bleiben dieselben Instanzen (Zustand, Inventar). Triebwerke sitzen
    durch die neue, dünne Wand.
  - Kabel werden eine einfache, verbundene Linie.
  - Positionen von Crew, Aufträgen, Wrack-Schleuse, Stations-Luke und abgelegten
    Wracks werden umgerechnet.
  - Eine angedockte Station oder ein Wrack zählt dabei als „außen“, damit Schleuse und
    Tür direkt aneinander bleiben.
- **Eigene Entscheidungen:**
  - Kosten und Bauzeiten gelten weiter je Feld, eine Fläche kostet also mehr Material.
  - Die Luftwerte (Austausch, Lecks, Lüftung) gelten weiter je Feld. Große Räume
    reagieren deshalb langsamer als früher.
  - Beim Steuern mit WASD rutscht die Figur vor einer Tür zur Türmitte (Einlaufhilfe).

### Andockschleuse 5×2 (Stand: November 2026)

**Vorgabe des Nutzers:** 2×5-Andockschleuse, längs an der Wand, nur Durchgang ohne Pumpe.
Ostranauts-Werte wurden nicht gemessen.

**Umsetzung (eigene Ausgestaltung):**
- Die Außenreihe liegt in der Außenwand: Wand, Wand, Außentür, Wand, Wand. Dahinter liegt
  eine Innenreihe mit der Innentür in der Mitte.
- Gebaut wird an der Stelle der Außentür. Die Richtung ergibt sich aus der Wand.
- Ungekoppelt ist die Außentür dicht und gesperrt, gekoppelt ist sie begehbar. Station und
  Wrack koppeln Tür an Tür an der Außentür.
- **Alte 1-Feld-Schleusen** werden an derselben Stelle auf 5×2 umgestellt, wenn innen Platz
  ist. Sonst wird die Wand geschlossen und die Schleuse liegt als Gegenstand an Bord.

### Steuerpult-Module (Stand: November 2026)

Vorgabe des Nutzers, ohne Ostranauts-Quelle. **Umsetzung:**
- Jedes Steuerpult hat ein Modulfach mit 6 Litern. Es nimmt nur Steuerpultmodule
  (`ItemData.helm_module`).
- Das Autodock-Modul ist ein Gegenstand mit 3 kg. Andere Steuerpultmodule gibt es im
  Spiel noch nicht; weitere bekommen nur ein `helm_module` und eine Abfrage an ihrer
  Funktion.
- **Auto-Dock** ist nur frei, wenn das bediente Pult intakt ist, Strom hat und ein Modul mit
  Zustand über 0 % enthält. Mehrere gleiche Module schalten die Funktion nur einmal frei.
- **Laufendes Manöver:** Es bricht ab, wenn am startenden Pult Strom, Zustand oder Modul
  fehlen. Das Schiff bleibt im freien Flug mit der erreichten Lage, es entsteht keine
  Kopplung.
- **Alte Spielstände:** Das eigenständige Auto-Dock-Gerät wird zum Modul.
  - Es kommt ins Pult desselben Bereichs ohne Modul. Sonst liegt es als Gegenstand an
    seinem Platz.
  - Ein abgebautes Auto-Dock im Inventar wird ebenfalls zum Modul.
- **Neues Startschiff:** Das Modul liegt im Pult.

## Geschwindigkeitsangleichung im Cockpit (Stand: November 2026)

**Quelle:** offizieller Ostranauts-Startguide auf Steam, Abschnitte „Flight Metrics“ und
„Clamping“: https://steamcommunity.com/sharedfiles/filedetails/?id=3347080066

Vom Nutzer als Quelle für die beobachtbare Funktion genannt. In der Arbeitsumgebung war
`steamcommunity.com` gesperrt, der Text konnte deshalb **nicht gelesen** werden.
Bekannt (sekundär, Wiki-Auszug): „Station keeping“ richtet das Schiff aufs Ziel aus und
bringt die Relativgeschwindigkeit (VREL) auf 0.

**Offen:**
- genaue Regelung (Stärke, Kurve)
- ob das Original dabei das Schiff dreht
- Totzone
- Zusammenspiel mit manuellem Schub im Original

### Umsetzung in Godot (eigene Entscheidungen)
- **Ein- und Ausschalten:** X oder der Knopf „Angleichen“ schaltet ein und aus. Die
  Angleichung bleibt aktiv, bis sie mit X ausgeschaltet wird, das Cockpit verlassen oder
  angedockt wird. Nach dem Laden eines Spielstands ist sie immer aus.
- **Schub:** Die Angleichung rechnet den Geschwindigkeitsunterschied zum Ziel in
  Schiffsrichtungen um (vor, zurück, rechts, links). Sie gibt pro Achse so viel Schub,
  wie in diesem Schritt nötig ist, höchstens den vollen Schub. Genutzt werden die
  Triebwerke dieser Richtung plus die Lagedüsen, mit demselben Treibstoffverbrauch wie
  bei den Tasten. **Das Schiff wird dabei nicht gedreht.** Lagedüsen allein genügen.
- **Totzone:** Unter 0,05 m/s Relativgeschwindigkeit feuert die Angleichung nicht.
- **Manueller Schub** (W, A, S, D) hat Vorrang. Solange eine Taste gehalten wird, pausiert
  die Angleichung, danach arbeitet sie wieder auf die Zielgeschwindigkeit hin.
- **Abbruch:** Ohne Strom am Pult endet die Angleichung (mit Meldung). Ohne Treibstoff
  feuert sie nicht.
- Das automatische Andocken (Auto-Dock-Modul) ist ein eigener Ablauf und bleibt unberührt.
