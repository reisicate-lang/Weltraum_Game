// ============================================================
// wreck.js – Wracks zum Ausschlachten
// Unterhalb deines Schiffs hängt an einer Bergungsleine ein Wrack.
// Jedes Wrack wird zufällig erzeugt: Räume, Lecks, beschädigte
// Geräte, Kisten mit unbekanntem Inhalt, Kabel und Schrott.
// Über das Handelsterminal kaufst du Bergungsrechte für neue Wracks.
// ============================================================

G.Wreck = {
  TOP: 30,      // obere Kante des Wracks
  ENTRY_X: 20,  // hier kommt die Bergungsleine an

  rnd(a, b) { return a + Math.floor(Math.random() * (b - a + 1)); },
  pick(list) { return list[Math.floor(Math.random() * list.length)]; },

  // Steg vom Außensteg deines Schiffs hinunter zum Wrack
  buildGangway(world) {
    for (let y = 27; y < this.TOP; y++) {
      world.set(this.ENTRY_X, y, G.T.FLOOR);
      world.zone[world.idx(this.ENTRY_X, y)] = 2;
    }
  },

  generate() {
    const world = G.state.world, T = G.T;
    const w = this.rnd(15, 22), h = this.rnd(7, 10);
    const top = this.TOP;
    const left = Math.max(2, Math.min(world.w - w - 2, this.ENTRY_X - this.rnd(3, w - 4)));
    const tiles = [];
    const put = (x, y, t) => {
      world.set(x, y, t);
      const i = world.idx(x, y);
      world.zone[i] = 1;
      world.cond[i] = this.rnd(25, 95);
    };

    // Hülle
    for (let y = top; y < top + h; y++) {
      for (let x = left; x < left + w; x++) {
        const edge = x === left || y === top || x === left + w - 1 || y === top + h - 1;
        put(x, y, edge ? T.WALL : T.FLOOR);
        if (!edge) tiles.push([x, y]);
      }
    }
    put(this.ENTRY_X, top, T.DOOR); // Eingang an der Bergungsleine

    // Innenwände (1–2 senkrecht), teils mit Tür, teils nur noch ein Loch
    const splits = [];
    let x = left + this.rnd(4, 6);
    while (x < left + w - 4 && splits.length < 2) { splits.push(x); x += this.rnd(5, 8); }
    const doors = [[this.ENTRY_X, top]];
    for (const sx of splits) {
      if (sx === this.ENTRY_X) continue;
      for (let y = top; y < top + h; y++) put(sx, y, T.WALL);
      const dy = this.rnd(top + 2, top + h - 3);
      put(sx, dy, Math.random() < 0.7 ? T.DOOR : T.FLOOR);
      doors.push([sx, dy]);
    }

    // Lecks in der Außenhülle
    const hull = [];
    for (let yy = top; yy < top + h; yy++) for (let xx = left; xx < left + w; xx++) {
      const corner = (xx === left || xx === left + w - 1) && (yy === top || yy === top + h - 1);
      if (!corner && world.get(xx, yy) === T.WALL && (xx === left || yy === top || xx === left + w - 1 || yy === top + h - 1)) hull.push([xx, yy]);
    }
    for (let k = this.rnd(1, 3); k > 0; k--) {
      const [hx, hy] = this.pick(hull);
      if (hx === this.ENTRY_X) continue;
      put(hx, hy, T.FLOOR);
    }

    // Abgestandene Luft in allen Räumen (wo ein Leck ist, entweicht sie)
    for (const [fx, fy] of tiles) {
      const i = world.idx(fx, fy);
      if (!world.holdsAir(i)) continue;
      world.o2[i] = 11; world.n2[i] = 55; world.co2[i] = 2.5;
    }

    // Freie Plätze an den Wänden für Geräte (nicht vor Türen, damit Wege frei bleiben)
    const nearDoor = (fx, fy) => doors.some(([dx, dy]) => Math.abs(dx - fx) <= 1 && Math.abs(dy - fy) <= 1);
    const spots = tiles.filter(([fx, fy]) => world.get(fx, fy) === T.FLOOR && !nearDoor(fx, fy)
      && [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => world.get(fx + dx, fy + dy) === T.WALL)
      && !(world.get(fx, fy - 1) === T.WALL && world.get(fx, fy + 1) === T.WALL));
    spots.sort(() => Math.random() - 0.5);

    const pool = ['generator', 'battery', 'o2gen', 'scrubber', 'bed', 'food', 'airtank', 'locker', 'water', 'sink', 'pump', 'solar', 'charger'];
    const nDev = this.rnd(5, 9);
    for (let k = 0; k < nDev && spots.length; k++) {
      const [dx, dy] = spots.pop();
      const type = this.pick(pool);
      const dev = G.Devices.create(type, dx, dy);
      dev.cond = this.rnd(8, 75);
      dev.broken = Math.random() < 0.35;
      dev.unknown = true;
      if (dev.stock !== undefined) dev.stock = Math.floor(dev.stock * Math.random() * 0.3);
      if (dev.charge !== undefined) dev.charge = 0;
      if (dev.type === 'locker') dev.suit = Math.random() < 0.3 ? { o2: 0, battery: 0 } : null;
      world.devices.set(world.idx(dx, dy), dev);
    }

    // Kisten mit unbekanntem Inhalt
    const loot = [['scrap', 6], ['plate', 5], ['copper', 5], ['circuit', 3], ['motor', 2], ['cell', 2], ['pipe', 4],
      ['glass', 2], ['filter', 2], ['fabric', 3], ['ration', 4], ['fuelcan', 1], ['aircan', 1], ['watercan', 1], ['datachip', 1]];
    for (let k = this.rnd(2, 4); k > 0 && spots.length; k--) {
      const [cx, cy] = spots.pop();
      const crate = G.Devices.create('crate', cx, cy);
      crate.cond = this.rnd(30, 90);
      crate.unknown = true;
      for (let n = this.rnd(2, 5); n > 0; n--) {
        const [type, max] = this.pick(loot);
        if (type === 'datachip' && Math.random() < 0.6) continue; // selten
        G.Items.add(crate.inv, G.Items.make(type, this.rnd(1, max), this.rnd(20, 95)));
      }
      world.devices.set(world.idx(cx, cy), crate);
    }

    // Herumliegender Schrott
    const free = tiles.filter(([fx, fy]) => world.walkable(fx, fy));
    for (let k = this.rnd(2, 5); k > 0; k--) {
      const [px, py] = this.pick(free);
      G.Items.drop(px, py, G.Items.make(this.pick(['scrap', 'scrap', 'copper', 'pipe', 'plate']), this.rnd(1, 3), this.rnd(15, 70)));
    }

    // Alte Kabel quer durchs Wrack
    const cy = top + this.rnd(1, h - 2);
    for (let cx = left + 1; cx < left + w - 1; cx++) if (Math.random() < 0.8) world.cables[world.idx(cx, cy)] = 1;

    G.Power.dirty = true;
    G.Airlock.dirty = true;
    G.state.wreckName = this.pick(['MV Kestrel', 'Frachter Nansen-4', 'Tankschiff Halcyon', 'Bergbauschlepper Ox-12',
      'Shuttle Meridian', 'Kurierschiff Pallas', 'Prospektor Vesna', 'Versorger Hollis']);
  },

  // Darf das Wrack entfernt werden? (Niemand darf darauf stehen)
  clearable() {
    const world = G.state.world;
    return !G.state.chars.some(c => world.zone[G.Chars.tileIdx(c)] === 1);
  },

  clear() {
    const S = G.state, world = S.world;
    for (let i = 0; i < world.tiles.length; i++) {
      if (world.zone[i] !== 1) continue;
      world.devices.delete(i);
      world.piles.delete(i);
      S.jobs.delete(i);
      world.tiles[i] = G.T.SPACE;
      world.cables[i] = 0;
      world.o2[i] = world.n2[i] = world.co2[i] = 0;
      world.zone[i] = 0;
    }
    S.wreckName = null;
    G.Power.dirty = true;
    G.Airlock.dirty = true;
  },

  // Restwert beim Verschrotten
  hullValue() {
    const world = G.state.world, T = G.T;
    let v = 0;
    for (let i = 0; i < world.tiles.length; i++) {
      if (world.zone[i] !== 1) continue;
      const t = world.tiles[i];
      if (t === T.WALL || t === T.DOOR) v += G.ITEMS.plate.value * 2;
      if (t === T.FLOOR) v += G.ITEMS.plate.value;
      const dev = world.devices.get(i);
      if (dev) v += this.deviceValue(dev);
      const pile = world.piles.get(i);
      if (pile) v += pile.items.reduce((s, it) => s + G.Items.value(it), 0);
      if (dev && dev.inv) v += dev.inv.items.reduce((s, it) => s + G.Items.value(it), 0);
    }
    return Math.round(v * G.ECON.HULL_FACTOR);
  },

  // Geschätzter Wert der Bauteile eines Geräts
  deviceValue(dev) {
    const cost = G.DEVICES[dev.type].cost || {};
    const base = Object.entries(cost).reduce((s, [t, q]) => s + G.ITEMS[t].value * q, 0);
    return Math.round(base * (0.3 + 0.7 * dev.cond / 100));
  },

  // Geräte in der Nähe eines Charakters werden erkannt (untersucht)
  reveal(c) {
    for (const dev of G.state.world.devices.values()) {
      if (dev.unknown && Math.abs(dev.x + 0.5 - c.x) <= 2.5 && Math.abs(dev.y + 0.5 - c.y) <= 2.5) dev.unknown = false;
    }
  },
};
