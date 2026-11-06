// ============================================================
// world.js – Die Spielwelt als Raster aus Kacheln
// Jede Kachel hat: Bauart (Boden/Wand/...), evtl. ein Kabel,
// evtl. ein Gerät und ihre eigene Luft (O2, N2, CO2).
// ============================================================

G.World = class World {
  constructor(w, h) {
    this.w = w;
    this.h = h;
    const n = w * h;
    this.tiles = new Uint8Array(n);   // Bauart (siehe G.T)
    this.cables = new Uint8Array(n);  // 1 = Kabel liegt hier
    this.devices = new Map();         // Kachel-Index -> Gerät
    this.piles = new Map();           // Kachel-Index -> Haufen mit Gegenständen (Inventar)
    this.doorOpenUntil = new Float64Array(n); // bis wann eine Tür offen steht
    // Luft pro Kachel in kPa
    this.o2 = new Float32Array(n);
    this.n2 = new Float32Array(n);
    this.co2 = new Float32Array(n);
    // Zustand von Wänden und Türen (100 = wie neu, 0 = kaputt)
    this.cond = new Float32Array(n).fill(100);
    // Bereich: 0 = dein Schiff/frei, 1 = Wrack, 2 = Bergungsleine
    this.zone = new Uint8Array(n);
  }

  idx(x, y) { return y * this.w + x; }

  inBounds(x, y) { return x >= 0 && y >= 0 && x < this.w && y < this.h; }

  get(x, y) { return this.inBounds(x, y) ? this.tiles[this.idx(x, y)] : G.T.SPACE; }

  set(x, y, t) {
    if (!this.inBounds(x, y)) return;
    const i = this.idx(x, y);
    this.tiles[i] = t;
    this.cond[i] = 100;
    if (t === G.T.SPACE) { this.cables[i] = 0; this.o2[i] = this.n2[i] = this.co2[i] = 0; }
  }

  device(x, y) { return this.inBounds(x, y) ? this.devices.get(this.idx(x, y)) || null : null; }

  // Kann man auf dieser Kachel laufen? (Geräte stehen im Weg)
  walkable(x, y) {
    const t = this.get(x, y);
    return (t === G.T.FLOOR || t === G.T.DOOR) && !this.devices.has(this.idx(x, y));
  }

  // Wand oder Tür (für die Darstellung von verbundenen Wänden)
  wallLike(x, y) {
    const t = this.get(x, y);
    return t === G.T.WALL || t === G.T.DOOR;
  }

  doorOpen(i) { return this.doorOpenUntil[i] > G.state.time; }

  // Ist die Kachel ein Luftraum? (Boden oder Tür)
  holdsAir(i) {
    const t = this.tiles[i];
    return t === G.T.FLOOR || t === G.T.DOOR;
  }

  pressure(i) { return this.o2[i] + this.n2[i] + this.co2[i]; }

  // Normale Luft auf eine Kachel setzen
  fillAir(i) {
    this.o2[i] = G.AIR.O2; this.n2[i] = G.AIR.N2; this.co2[i] = G.AIR.CO2;
  }
};

// Baut das Startschiff in die Mitte der Welt.
// Gibt die Position zurück, an der der erste Charakter startet.
G.createStartShip = function (world) {
  const T = G.T;
  const shipW = 16, shipH = 10;
  const x0 = Math.floor((world.w - shipW) / 2);
  const y0 = Math.floor((world.h - shipH) / 2);

  for (let y = y0; y < y0 + shipH; y++) {
    for (let x = x0; x < x0 + shipW; x++) {
      const edge = x === x0 || y === y0 || x === x0 + shipW - 1 || y === y0 + shipH - 1;
      world.set(x, y, edge ? T.WALL : T.FLOOR);
    }
  }

  // Trennwand zwischen linker Hälfte und Cockpit (rechts)
  const midX = x0 + 10;
  for (let y = y0; y < y0 + shipH; y++) world.set(midX, y, T.WALL);
  world.set(midX, y0 + 6, T.DOOR);

  // Wohnkabine oben links
  for (let x = x0; x <= midX; x++) world.set(x, y0 + 4, T.WALL);
  world.set(x0 + 8, y0 + 4, T.DOOR);

  // Innentür der Luftschleuse
  world.set(x0, y0 + 7, T.DOOR);

  // Luftschleuse links am Schiff (2x2 Felder innen)
  for (let y = y0 + 5; y <= y0 + 8; y++) {
    for (let x = x0 - 3; x <= x0 - 1; x++) {
      const edge = x === x0 - 3 || y === y0 + 5 || y === y0 + 8;
      world.set(x, y, edge ? T.WALL : T.FLOOR);
    }
  }
  world.set(x0 - 3, y0 + 7, T.DOOR); // Außentür

  // Außensteg im Vakuum, von hier aus kann man außen bauen
  for (let y = y0 + 1; y <= y0 + 9; y++) world.set(x0 - 4, y, T.FLOOR);

  // Einrichtung
  const place = (type, x, y) => world.devices.set(world.idx(x, y), G.Devices.create(type, x, y));
  // Wohnkabine mit Lebenserhaltung (hier wird geschlafen, also hier die Luft aufbereiten)
  place('bed', x0 + 1, y0 + 1);
  place('sink', x0 + 3, y0 + 1);
  place('food', x0 + 5, y0 + 1);
  place('water', x0 + 6, y0 + 1);
  place('o2gen', x0 + 9, y0 + 1);
  place('scrubber', x0 + 9, y0 + 3);
  // Technikraum unten links
  place('generator', x0 + 1, y0 + 5);
  place('battery', x0 + 2, y0 + 5);
  place('airtank', x0 + 7, y0 + 5);
  place('locker', x0 + 1, y0 + 8);
  place('charger', x0 + 2, y0 + 8);
  place('pump', x0 - 1, y0 + 6);
  // Handelsterminal und Werkbank im Cockpit (am Kabel)
  place('terminal', x0 + 12, y0 + 5);
  place('workbench', x0 + 13, y0 + 5);
  // Flugsystem: Steuerpult, Treibstofftank, zwei Triebwerke, Auto-Dock
  place('helm', x0 + 14, y0 + 1);
  place('fueltank', x0 + 11, y0 + 1);
  place('autodock', x0 + 14, y0 + 3);
  place('thruster', x0 + 11, y0 + 8);
  place('thruster', x0 + 12, y0 + 8);
  for (let y = y0 + 1; y <= y0 + 4; y++) world.cables[world.idx(x0 + 14, y)] = 1;
  for (let y = y0 + 6; y <= y0 + 8; y++) world.cables[world.idx(x0 + 11, y)] = 1;
  world.cables[world.idx(x0 + 12, y0 + 8)] = 1;
  // Frachtkisten im Cockpit mit Startmaterial
  place('crate', x0 + 14, y0 + 8);
  place('crate', x0 + 13, y0 + 8);
  const fill = (x, y, list) => {
    const inv = world.devices.get(world.idx(x, y)).inv;
    for (const [type, qty, cond] of list) G.Items.add(inv, G.Items.make(type, qty, cond));
  };
  fill(x0 + 14, y0 + 8, [['plate', 12, 80], ['copper', 8, 90], ['circuit', 3, 70], ['pipe', 4, 85], ['scrap', 6, 50]]);
  fill(x0 + 13, y0 + 8, [['ration', 10, 100], ['watercan', 3, 100], ['fuelcan', 2, 100], ['aircan', 1, 100], ['filter', 2, 90]]);
  // Mondmüll draußen am Steg: lohnt sich einzusammeln
  const junk = (x, y, list) => { for (const [type, qty, cond] of list) G.Items.drop(x, y, G.Items.make(type, qty, cond)); };
  junk(x0 - 4, y0 + 1, [['scrap', 4, 30], ['copper', 2, 40]]);
  junk(x0 - 4, y0 + 9, [['plate', 3, 45], ['circuit', 1, 35], ['datachip', 1, 60]]);
  junk(x0 - 4, y0 + 4, [['glass', 2, 55], ['motor', 1, 25]]);

  // Kabel vom Generator bis ins Cockpit und hoch in die Wohnkabine
  for (let x = x0 + 1; x <= x0 + 14; x++) world.cables[world.idx(x, y0 + 5)] = 1;
  for (let y = y0 + 1; y <= y0 + 5; y++) world.cables[world.idx(x0 + 9, y)] = 1;
  // ... zum Anzugschrank, zur Ladestation und zur Schleusenpumpe
  for (let y = y0 + 6; y <= y0 + 8; y++) world.cables[world.idx(x0 + 1, y)] = 1;
  world.cables[world.idx(x0 + 2, y0 + 8)] = 1;
  for (let x = x0 - 1; x <= x0; x++) world.cables[world.idx(x, y0 + 5)] = 1;
  world.cables[world.idx(x0 - 1, y0 + 6)] = 1;

  // Überall im Schiff normale Luft (der Außensteg bleibt Vakuum)
  for (let i = 0; i < world.tiles.length; i++) {
    if (world.holdsAir(i) && i % world.w !== x0 - 4) world.fillAir(i);
  }

  return { x: x0 + 4, y: y0 + 7 };
};
