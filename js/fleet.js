// ============================================================
// fleet.js – Deine Flotte und was an den Orten liegt
// - Wracks bleiben an ihrem Ort, wenn du wegfliegst
// - Weitere Schiffe kaufen (Werft am Kármán-Ring), wechseln, verkaufen
// - Ein ausgeschlachtetes Wrack als eigenes Schiff übernehmen
// Geparkte Schiffe werden als Daten gespeichert und ruhen.
// ============================================================

G.Fleet = {
  create() {
    return { ships: [], places: {}, nextId: 2, currentId: 1, currentName: 'Rostlaube' };
  },

  st() { return G.state.fleet; },

  // ---------- Wrack am Ort ablegen / wieder anhängen ----------
  leave(loc) {
    const f = this.st(), world = G.state.world;
    const place = f.places[loc.id] = f.places[loc.id] || {};
    // Wrack-Felder als Daten merken
    const tiles = [];
    for (let i = 0; i < world.tiles.length; i++) {
      if (world.zone[i] !== 1) continue;
      tiles.push([i, world.tiles[i], world.cables[i], Math.round(world.cond[i]), +world.o2[i].toFixed(2), +world.n2[i].toFixed(2), +world.co2[i].toFixed(2)]);
    }
    if (tiles.length) {
      const set = new Set(tiles.map(t => t[0]));
      place.wreck = {
        name: G.state.wreckName,
        tiles,
        devices: [...world.devices].filter(([i]) => set.has(i)).map(([, d]) => ({ ...d, inv: d.inv ? d.inv.items : undefined, claimedBy: null })),
        piles: [...world.piles].filter(([i]) => set.has(i)).map(([i, inv]) => [i, inv.items]),
      };
    } else place.wreck = null;
    G.Wreck.clear();
  },

  arrive(loc) {
    const f = this.st(), world = G.state.world;
    const place = f.places[loc.id];
    if (place && place.wreck) {
      const w = place.wreck;
      for (const [i, t, cab, cond, o2, n2, co2] of w.tiles) {
        world.tiles[i] = t; world.cables[i] = cab; world.cond[i] = cond;
        world.o2[i] = o2; world.n2[i] = n2; world.co2[i] = co2; world.zone[i] = 1;
      }
      for (const dv of w.devices) {
        const dev = Object.assign(G.Devices.create(dv.type, dv.x, dv.y), dv);
        if (dev.inv !== undefined) { const inv = G.Items.newInv(Infinity, G.DEVICES[dv.type].storage); inv.items = dv.inv || []; dev.inv = inv; }
        world.devices.set(world.idx(dv.x, dv.y), dev);
      }
      for (const [i, items] of w.piles) { const inv = G.Items.newInv(); inv.items = items; world.piles.set(i, inv); }
      G.state.wreckName = w.name;
      place.wreck = null;
      G.Power.dirty = true; G.Airlock.dirty = true;
    } else if (loc.kind === 'debris') {
      G.Wreck.generate(); // im Trümmerfeld gibt es immer ein Wrack, gratis
      G.UI.toast('Ein Wrack aus dem Trümmerfeld treibt heran: ' + G.state.wreckName);
    }
  },

  // ---------- Schiffe ----------
  here() { return G.state.nav.docked; },

  shipsHere() { return this.st().ships.filter(s => s.location === this.here()); },

  // Wert eines Schiffs: Rumpf und Geräte
  worldValue(world, zoneFilter = z => z !== 1) {
    let v = 0;
    for (let i = 0; i < world.tiles.length; i++) {
      if (!world.tiles[i] || !zoneFilter(world.zone[i])) continue;
      v += world.tiles[i] === G.T.FLOOR ? 25 : 45;
    }
    for (const d of world.devices.values()) {
      if (!zoneFilter(world.zone[world.idx(d.x, d.y)])) continue;
      v += G.Wreck.deviceValue(d) * 1.5;
    }
    return Math.round(v);
  },

  // Zu einem anderen Schiff am selben Ort wechseln. Die ganze Crew kommt mit.
  switchTo(id) {
    const f = this.st(), S = G.state;
    const target = f.ships.find(s => s.id === id);
    if (!target || target.location !== this.here()) return G.UI.toast('Dieses Schiff liegt nicht hier.');
    if (!G.Wreck.clearable()) return G.UI.toast('Erst alle Crewmitglieder vom Wrack holen.');
    const loc = G.Nav.loc(this.here());
    // Wrack bleibt am Ort, aktuelles Schiff wird geparkt
    this.leave(loc);
    for (const c of S.chars) { G.Chars.releaseJob(c); G.Chars.stopActivity(c); c.order = null; c.transfer = null; }
    f.ships.push({ id: f.currentId, name: f.currentName, location: loc.id, data: G.Save.worldToData(S.world) });
    f.ships = f.ships.filter(s => s.id !== id);
    S.world = G.Save.dataToWorld(target.data);
    S.jobs = new Map();
    f.currentId = target.id; f.currentName = target.name;
    G.Power.dirty = true; G.Airlock.dirty = true;
    G.Power.update(0); // Strom sofort neu berechnen (sonst wirkt das Steuerpult kurz stromlos)
    this.placeCrew();
    this.arrive(loc);
    S.openSource = null;
    G.UI.toast('Du bist jetzt an Bord der ' + target.name + '.');
  },

  // Crew auf freie Bodenfelder mit Luft stellen
  placeCrew() {
    const S = G.state, world = S.world;
    const spots = [];
    for (let i = 0; i < world.tiles.length; i++) {
      if (world.zone[i] !== 0) continue;
      const x = i % world.w, y = (i / world.w) | 0;
      if (world.walkable(x, y) && world.pressure(i) > 50) spots.push([x, y]);
    }
    if (!spots.length) for (let i = 0; i < world.tiles.length; i++) {
      const x = i % world.w, y = (i / world.w) | 0;
      if (world.zone[i] === 0 && world.walkable(x, y)) spots.push([x, y]);
    }
    S.chars.forEach((c, k) => {
      const [x, y] = spots[Math.min(spots.length - 1, k * 3)] || [10, 10];
      c.x = x + 0.5; c.y = y + 0.5; c.path = [];
    });
    if (spots.length) { S.camera.x = spots[0][0]; S.camera.y = spots[0][1]; }
  },

  // Wrack als eigenes Schiff registrieren (es bleibt hier liegen und kann repariert werden)
  registerWreck() {
    const S = G.state, world = S.world, E = G.Econ.state();
    const fee = G.ECON.REGISTER_FEE;
    if (!S.wreckName) return G.UI.toast('Hier ist kein Wrack.');
    if (!G.Econ.terminalOnline()) return G.UI.toast('Das Handelsterminal ist offline.');
    if (E.credits < fee) return G.UI.toast('Nicht genug Credits für die Registrierung.');
    if (!G.Wreck.clearable()) return G.UI.toast('Erst alle Crewmitglieder vom Wrack holen.');
    E.credits -= fee;
    G.Econ.book('Wrack als Schiff registriert: ' + S.wreckName, -fee);
    // Neue Welt mit nur dem Wrack, das Wrack wird zum normalen Schiff
    const nw = new G.World(world.w, world.h);
    for (let i = 0; i < world.tiles.length; i++) {
      if (world.zone[i] !== 1) continue;
      nw.tiles[i] = world.tiles[i]; nw.cables[i] = world.cables[i]; nw.cond[i] = world.cond[i];
      nw.o2[i] = world.o2[i]; nw.n2[i] = world.n2[i]; nw.co2[i] = world.co2[i];
      const d = world.devices.get(i);
      if (d) { d.unknown = false; d.claimedBy = null; nw.devices.set(i, d); }
      const p = world.piles.get(i);
      if (p) nw.piles.set(i, p);
    }
    const f = this.st();
    f.ships.push({ id: f.nextId++, name: S.wreckName, location: this.here(), data: G.Save.worldToData(nw) });
    G.Wreck.clear();
    G.UI.toast('Registriert! Unter "Schiffe" kannst du an Bord wechseln.');
  },

  buy(kind) {
    const S = G.state, E = G.Econ.state(), t = G.SHIPYARD.find(s => s.id === kind);
    const loc = G.Nav.loc(this.here());
    if (!loc || !loc.shipyard) return G.UI.toast('Hier gibt es keine Werft.');
    if (E.credits < t.price) return G.UI.toast('Nicht genug Credits.');
    E.credits -= t.price;
    G.Econ.book('Schiff gekauft: ' + t.name, -t.price);
    const world = new G.World(G.WORLD_W, G.WORLD_H);
    const prev = S.world; S.world = world; // Bauhelfer brauchen die Welt
    G.ShipTemplates.build(world, t);
    S.world = prev;
    const f = this.st();
    f.ships.push({ id: f.nextId++, name: t.name, location: loc.id, data: G.Save.worldToData(world) });
    G.UI.toast(t.name + ' gehört jetzt dir. Wechseln unter "Schiffe".');
  },

  sell(id) {
    const f = this.st(), E = G.Econ.state();
    const s = f.ships.find(x => x.id === id);
    const loc = G.Nav.loc(this.here());
    if (!s || !loc || !loc.shipyard || s.location !== loc.id) return G.UI.toast('Schiffe kann man nur an einer Werft verkaufen, an der sie liegen.');
    const value = Math.round(this.worldValue(G.Save.dataToWorld(s.data)) * 0.6);
    E.credits += value;
    G.Econ.book('Schiff verkauft: ' + s.name, value);
    f.ships = f.ships.filter(x => x.id !== id);
  },
};

// ------------------------------------------------------------
// Schiffe der Werft
// ------------------------------------------------------------
G.SHIPYARD = [
  { id: 'lumen', name: 'Shuttle Lumen', price: 9000, w: 10, h: 7, desc: 'Klein und sparsam. Zwei Räume, ein Triebwerk.' },
  { id: 'bairn', name: 'Frachter Bairn', price: 26000, w: 18, h: 11, desc: 'Viel Frachtraum, drei Triebwerke, Platz für Crew.' },
];

G.ShipTemplates = {
  build(world, t) {
    const T = G.T;
    const x0 = Math.floor((world.w - t.w) / 2), y0 = Math.floor((world.h - t.h) / 2) - 4;
    for (let y = y0; y < y0 + t.h; y++) for (let x = x0; x < x0 + t.w; x++) {
      const edge = x === x0 || y === y0 || x === x0 + t.w - 1 || y === y0 + t.h - 1;
      world.set(x, y, edge ? T.WALL : T.FLOOR);
    }
    const mid = x0 + Math.floor(t.w / 2);
    for (let y = y0; y < y0 + t.h; y++) world.set(mid, y, T.WALL);
    world.set(mid, y0 + Math.floor(t.h / 2), T.DOOR);
    const place = (type, x, y) => world.devices.set(world.idx(x, y), G.Devices.create(type, x, y));
    const left = [['generator', x0 + 1, y0 + 1], ['battery', x0 + 2, y0 + 1], ['o2gen', x0 + 3, y0 + 1], ['scrubber', x0 + 1, y0 + t.h - 2],
      ['airtank', x0 + 2, y0 + t.h - 2], ['bed', x0 + 3, y0 + t.h - 2], ['locker', x0 + 4, y0 + 1]];
    const right = [['helm', x0 + t.w - 2, y0 + 1], ['fueltank', mid + 1, y0 + 1], ['thruster', x0 + t.w - 2, y0 + t.h - 2],
      ['crate', mid + 1, y0 + t.h - 2], ['terminal', mid + 2, y0 + 1], ['food', mid + 2, y0 + t.h - 2]];
    if (t.id === 'bairn') right.push(['thruster', x0 + t.w - 3, y0 + t.h - 2], ['thruster', x0 + t.w - 4, y0 + t.h - 2],
      ['crate', mid + 3, y0 + t.h - 2], ['crate', mid + 4, y0 + t.h - 2], ['bed', x0 + 5, y0 + t.h - 2], ['water', x0 + 5, y0 + 1]);
    for (const [type, x, y] of [...left, ...right]) place(type, x, y);
    // Kabel: einmal oben und unten entlang, dazu Verbindung durch die Mitte
    for (let x = x0 + 1; x < x0 + t.w - 1; x++) { world.cables[world.idx(x, y0 + 1)] = 1; world.cables[world.idx(x, y0 + t.h - 2)] = 1; }
    for (let y = y0 + 1; y < y0 + t.h - 1; y++) world.cables[world.idx(x0 + 1, y)] = 1;
    // Außentür links und ein Steg zur Bergungsleine
    world.set(x0, y0 + Math.floor(t.h / 2), T.DOOR);
    for (let y = y0 + t.h; y < G.Wreck.TOP; y++) { world.set(x0 - 1, y, T.FLOOR); world.zone[world.idx(x0 - 1, y)] = 2; }
    for (let x = x0 - 1; x <= G.Wreck.ENTRY_X; x++) { world.set(x, G.Wreck.TOP - 1, T.FLOOR); world.zone[world.idx(x, G.Wreck.TOP - 1)] = 2; }
    for (let y = y0 + Math.floor(t.h / 2); y < y0 + t.h; y++) { world.set(x0 - 1, y, T.FLOOR); world.zone[world.idx(x0 - 1, y)] = 2; }
    for (let i = 0; i < world.tiles.length; i++) if (world.holdsAir(i) && world.zone[i] === 0) world.fillAir(i);
    const inv = [...world.devices.values()].find(d => d.type === 'crate').inv;
    G.Items.add(inv, G.Items.make('ration', 10, 100));
    G.Items.add(inv, G.Items.make('fuelcan', 2, 100));
  },
};
