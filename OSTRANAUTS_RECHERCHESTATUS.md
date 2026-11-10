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
- **Drehen:** Rechtsklick → „Drehen“ ist ein kurzer Crew-Auftrag von etwa einer Spielminute.
- **Bauen:** Schwere Bauteile (Triebwerk: 44 kg Material) holt die Crew in mehreren
  Gängen und legt das Material am Bauplatz ab.
