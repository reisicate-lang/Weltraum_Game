// ============================================================
// config.js – Grundeinstellungen des Spiels
// Hier stehen Zahlen, die man leicht ändern kann, um das Spiel
// anzupassen (z. B. wie lange das Bauen dauert).
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
  1: { name: 'Boden', buildTime: 20 },
  2: { name: 'Wand', buildTime: 30 },
  3: { name: 'Tür', buildTime: 40 },
};

// Wie lange das Abreißen dauert (Spielminuten)
G.REMOVE_TIME = 15;

// Die Werkzeuge im Baumenü
G.TOOLS = {
  select: { name: 'Auswahl', key: 'Esc', hint: 'Klick auf den Boden: Charakter läuft dorthin. Ziehen: Ansicht verschieben.' },
  floor:  { name: 'Boden',   key: 'B',   hint: 'Klicken oder Fläche ziehen. Boden kann nur im Weltraum gebaut werden.' },
  wall:   { name: 'Wand',    key: 'M',   hint: 'Ziehen zeichnet eine Linie oder den Rand eines Rechtecks.' },
  door:   { name: 'Tür',     key: 'T',   hint: 'Klick auf eine Wand oder einen Boden.' },
  remove: { name: 'Abreißen', key: 'X',  hint: 'Wand/Tür wird zu Boden, Boden wird zu Weltraum.' },
  cancel: { name: 'Plan löschen', key: 'C', hint: 'Entfernt Baupläne, die noch nicht gebaut sind.' },
};

// Zeit: 1 echte Sekunde bei Geschwindigkeit 1x = so viele Spielminuten
G.MINUTES_PER_SECOND = 10;

// Mögliche Geschwindigkeiten (0 = Pause)
G.SPEEDS = [0, 1, 2, 4];

// Laufgeschwindigkeit der Charaktere in Kacheln pro Spielminute
G.WALK_SPEED = 0.35;

// Spielbeginn: Tag 1, 08:00 Uhr (in Minuten)
G.START_MINUTES = 8 * 60;

// Name, unter dem der Spielstand im Browser gespeichert wird
G.SAVE_KEY = 'weltraum_game_save_v1';
G.SAVE_VERSION = 1;
