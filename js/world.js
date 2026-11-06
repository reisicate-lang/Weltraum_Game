// ============================================================
// world.js – Die Spielwelt als Raster aus Kacheln
// ============================================================

G.World = class World {
  constructor(w, h) {
    this.w = w;
    this.h = h;
    // Jede Kachel ist eine Zahl (siehe G.T in config.js)
    this.tiles = new Uint8Array(w * h);
  }

  idx(x, y) { return y * this.w + x; }

  inBounds(x, y) { return x >= 0 && y >= 0 && x < this.w && y < this.h; }

  get(x, y) { return this.inBounds(x, y) ? this.tiles[this.idx(x, y)] : G.T.SPACE; }

  set(x, y, t) { if (this.inBounds(x, y)) this.tiles[this.idx(x, y)] = t; }

  // Kann man auf dieser Kachel laufen?
  walkable(x, y) {
    const t = this.get(x, y);
    return t === G.T.FLOOR || t === G.T.DOOR;
  }

  // Wand oder Tür (für die Darstellung von verbundenen Wänden)
  wallLike(x, y) {
    const t = this.get(x, y);
    return t === G.T.WALL || t === G.T.DOOR;
  }

  // Für das Speichern: Welt als Text aus Ziffern
  serialize() { return Array.from(this.tiles).join(''); }

  static deserialize(w, h, text) {
    const world = new G.World(w, h);
    for (let i = 0; i < world.tiles.length && i < text.length; i++) {
      world.tiles[i] = Number(text[i]) || 0;
    }
    return world;
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

  // Trennwand zwischen Frachtraum (links) und Cockpit (rechts)
  const midX = x0 + 10;
  for (let y = y0; y < y0 + shipH; y++) world.set(midX, y, T.WALL);
  world.set(midX, y0 + 5, T.DOOR);

  // Kleine Kabine oben links
  for (let x = x0; x <= midX; x++) world.set(x, y0 + 4, T.WALL);
  world.set(x0 + 5, y0 + 4, T.DOOR);

  // Außentür (später wird daraus eine Luftschleuse)
  world.set(x0, y0 + 7, T.DOOR);

  return { x: x0 + 3, y: y0 + 7 };
};
