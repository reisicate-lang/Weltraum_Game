// ============================================================
// config.js – Grundeinstellungen des Spiels
// Hier stehen Zahlen, die man leicht ändern kann, um das Spiel
// anzupassen (z. B. wie lange das Bauen dauert).
// Zeiten sind immer in Spielminuten angegeben.
// ============================================================

window.G = window.G || {};

// Größe einer Kachel in Pixeln (bei Zoom 1)
G.TILE = 32;

// Größe der Welt in Kacheln
G.WORLD_W = 64;
G.WORLD_H = 44;

// Kachel-Arten. Jede Kachel in der Welt ist eine dieser Zahlen.
G.T = {
  SPACE: 0, // leerer Weltraum
  FLOOR: 1, // Boden
  WALL: 2,  // Wand
  DOOR: 3,  // Tür
};

// Infos zu jeder Kachel-Art. buildTime = Bauzeit in Spielminuten.
G.TILE_INFO = {
  0: { name: 'Weltraum' },
  1: { name: 'Boden', buildTime: 2 },
  2: { name: 'Wand', buildTime: 3 },
  3: { name: 'Tür', buildTime: 4 },
};

G.REMOVE_TIME = 1.5;    // Abreißen
G.CABLE_TIME = 1;       // Kabel verlegen

// ------------------------------------------------------------
// Geräte. power: + erzeugt Strom, - verbraucht Strom (in kW)
// ------------------------------------------------------------
G.DEVICES = {
  generator: { name: 'Generator', power: 6, stock: 240, unit: 'Brennstoff', buildTime: 6, wears: true, desc: 'Erzeugt 6 kW Strom. Verbraucht 1 Brennstoff pro Stunde.' },
  solar:     { name: 'Solarpanel', power: 1.5, buildTime: 5, desc: 'Erzeugt 1,5 kW ohne Brennstoff. Funktioniert nur draußen im Vakuum.' },
  battery:   { name: 'Batterie', capacity: 30, buildTime: 4, desc: 'Speichert bis zu 30 kWh überschüssigen Strom.' },
  o2gen:     { name: 'Sauerstoff-Generator', power: -1.5, buildTime: 5, wears: true, desc: 'Füllt Sauerstoff nach (bis 21 kPa). Braucht 1,5 kW.' },
  scrubber:  { name: 'CO₂-Filter', power: -1, buildTime: 5, wears: true, desc: 'Entfernt ausgeatmetes CO₂. Braucht 1 kW.' },
  airtank:   { name: 'Lufttank', stock: 4000, unit: 'kPa', buildTime: 4, desc: 'Füllt Luft nach, wenn der Druck unter 95 kPa fällt.' },
  bed:       { name: 'Bett', buildTime: 4, need: 'sleep', desc: 'Zum Schlafen.' },
  food:      { name: 'Vorratsschrank', stock: 40, unit: 'Rationen', buildTime: 3, need: 'food', desc: 'Enthält Essensrationen.' },
  water:     { name: 'Wasserspender', stock: 80, unit: 'L', buildTime: 3, need: 'water', desc: 'Trinkwasser.' },
  sink:      { name: 'Waschbecken', stock: 80, unit: 'L', buildTime: 3, need: 'hygiene', desc: 'Zum Waschen.' },
  locker:    { name: 'Anzugschrank', power: -0.5, buildTime: 4, desc: 'Bewahrt einen Raumanzug auf und füllt Sauerstoff und Akku auf. Braucht 0,5 kW.' },
  charger:   { name: 'Tragbare Ladestation', capacity: 10, buildTime: 3, portable: true, desc: 'Akku mit 10 kWh. Lädt Raumanzüge auch draußen. Am Kabel lädt sie sich selbst auf. Mit "Versetzen" umstellbar.' },
  pump:      { name: 'Schleusenpumpe', power: -1, buildTime: 6, wears: true, desc: 'Macht einen kleinen Raum zur Luftschleuse: pumpt die Luft ab und wieder hinein. Braucht 1 kW.' },
};

// ------------------------------------------------------------
// Atmosphäre (Werte in kPa, so wie auf der Erde)
// ------------------------------------------------------------
G.AIR = {
  O2: 21, N2: 79, CO2: 0.04,  // normale Luft
  O2_OK: 18,        // ab hier atmet man gut
  O2_LOW: 16,       // darunter: Atemnot
  CO2_BAD: 3,       // darüber: ungesund
  BREATH_O2: 0.12,  // so viel O2 verbraucht ein Mensch pro Minute (kPa)
  DIFFUSION: 0.2,   // wie schnell sich Luft zwischen Kacheln verteilt
  DOOR_SLITS: 0.05, // geschlossene Innentüren lassen ein bisschen Luft durch
  VENT_LOSS: 0.35,  // wie schnell Luft ins All entweicht
  O2GEN_RATE: 0.8,  // kPa pro Minute
  SCRUB_RATE: 0.8,
  TANK_RATE: 4,
  TANK_TARGET: 95,
};

// ------------------------------------------------------------
// Bedürfnisse (0 = ganz schlecht, 100 = bestens)
// decay = Verlust pro Stunde, at = ab diesem Wert kümmert sich der Charakter darum
// ------------------------------------------------------------
G.NEEDS = {
  food:    { name: 'Hunger',  decay: 4, at: 45, gain: 45, useTime: 20, verb: 'Isst' },
  water:   { name: 'Durst',   decay: 6, at: 50, gain: 50, useTime: 5, verb: 'Trinkt' },
  sleep:   { name: 'Energie', decay: 4, at: 30, gain: 13, useTime: 0, verb: 'Schläft' },  // gain pro Stunde im Bett
  hygiene: { name: 'Hygiene', decay: 3, at: 35, gain: 70, useTime: 15, verb: 'Wäscht sich' },
  air:     { name: 'Atmung' },
};

// ------------------------------------------------------------
// Raumanzüge (Werte in Prozent, Verbrauch pro Minute)
// ------------------------------------------------------------
G.SUIT = {
  O2_USE: 100 / 120,      // Sauerstoff reicht 2 Stunden
  BATTERY_USE: 100 / 150, // Akku reicht 2,5 Stunden
  REFILL: 10,             // Anzugschrank füllt 10 % pro Minute auf
  CHARGE: 10,             // Ladestation lädt 10 % pro Minute
  KWH_PER_100: 0.5,       // so viel Strom braucht eine volle Akkuladung
  RETURN_AT: 30,          // darunter geht der Charakter zurück
};

// ------------------------------------------------------------
// Schleuse
// ------------------------------------------------------------
G.AIRLOCK = {
  MAX_SIZE: 12,     // größer darf ein Raum nicht sein, um als Schleuse zu zählen
  PUMP_RATE: 600,   // kPa (summiert über alle Felder) pro Minute
  TOLERANCE: 6,     // so nah muss der Druck passen, damit die Tür aufgeht
  STORE_MAX: 3000,  // so viel Luft kann die Pumpe speichern
};

// ------------------------------------------------------------
// Schäden
// ------------------------------------------------------------
G.DAMAGE = {
  WEAR_PER_DAY: 4,       // laufende Geräte verlieren so viel Zustand pro Tag
  METEORS_PER_DAY: 0.7,  // durchschnittliche Einschläge pro Tag
  FIRST_METEOR_DAY: 1,   // vorher gibt es keine Einschläge
  AUTO_REPAIR_AT: 50,    // darunter wird automatisch repariert
  REPAIR_TIME: 3,
  FUEL_PER_HOUR: 1,
};

// Die Werkzeuge im Baumenü
G.TOOLS = {
  select: { name: 'Auswahl', hint: 'Klick auf den Boden: Charakter läuft dorthin. Ziehen: Ansicht verschieben.' },
  floor:  { name: 'Boden', hint: 'Klicken oder Fläche ziehen. Boden kann nur im Weltraum gebaut werden.' },
  wall:   { name: 'Wand', hint: 'Ziehen zeichnet eine Linie oder den Rand eines Rechtecks.' },
  door:   { name: 'Tür', hint: 'Klick auf eine Wand oder einen Boden.' },
  move:   { name: 'Versetzen', hint: 'Vom Gerät zum Zielfeld ziehen. Ein Charakter trägt es dorthin.' },
  repair: { name: 'Reparieren', hint: 'Auf beschädigte Wände, Türen oder Geräte klicken. Stark Beschädigtes wird automatisch repariert.' },
  cable:  { name: 'Kabel', hint: 'Kabel verbinden Geräte mit Strom. Ein Gerät braucht ein Kabel auf seinem eigenen Feld.' },
  remove: { name: 'Abreißen', hint: 'Schicht für Schicht: erst Gerät, dann Kabel, dann Wand/Tür (wird Boden), dann Boden.' },
  cancel: { name: 'Plan löschen', hint: 'Entfernt Baupläne, die noch nicht gebaut sind.' },
};
for (const [type, d] of Object.entries(G.DEVICES)) {
  G.TOOLS['dev:' + type] = { name: d.name, hint: d.desc + ' Auf freien Boden klicken.' };
}

// Zeit: Bei 1x ist eine Sekunde im Spiel eine echte Sekunde.
// Im Spiel wird in Minuten gerechnet, darum 1/60 Minute pro Sekunde.
G.MINUTES_PER_SECOND = 1 / 60;
G.SPEEDS = [0, 1, 10, 60, 300];         // 0 = Pause

// Laufgeschwindigkeit: 1,5 Kacheln pro Sekunde (in Kacheln pro Minute)
G.WALK_SPEED = 90;

// Spielbeginn: Tag 1, 08:00 Uhr (in Minuten)
G.START_MINUTES = 8 * 60;

// Name, unter dem der Spielstand im Browser gespeichert wird
G.SAVE_KEY = 'weltraum_game_save_v3';
G.SAVE_VERSION = 3;
