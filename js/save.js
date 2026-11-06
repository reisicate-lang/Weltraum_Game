// ============================================================
// save.js – Speichern und Laden (im Browser)
// ============================================================

G.Save = {
  // Macht aus dem Spielzustand ein einfaches Objekt, das man speichern kann
  serialize() {
    const S = G.state;
    return {
      version: G.SAVE_VERSION,
      savedAt: new Date().toISOString(),
      world: this.worldToData(S.world),
      view: S.view,
      time: S.time,
      camera: { ...S.camera },
      selectedId: S.selectedId,
      nextCharId: G.Chars.nextId,
      chars: S.chars.map(c => ({
        id: c.id, name: c.name, color: c.color, x: c.x, y: c.y, facing: c.facing,
        needs: { ...c.needs }, health: c.health, unconscious: c.unconscious,
        suit: c.suit, carrying: c.carrying ? { ...c.carrying, claimedBy: null } : null,
        items: c.inv.items, isPlayer: c.isPlayer,
      })),
      econ: S.econ,
      wreckName: S.wreckName,
      nav: S.nav,
      fleet: S.fleet,
      jobs: [...S.jobs.values()].filter(j => !((j.kind === 'move' || j.kind === 'haul') && j.phase === 'deliver'))
        .map(j => ({ x: j.x, y: j.y, kind: j.kind, tile: j.tile, dev: j.dev, tx: j.tx, ty: j.ty, phase: j.phase,
          item: j.item, qty: j.qty, paid: j.paid, auto: j.auto, recipe: j.recipe, progress: j.progress, need: j.need })),
    };
  },

  // Eine Schiffswelt in einfache Daten umwandeln (auch für weitere Schiffe der Flotte)
  worldToData(w) {
    return {
      w: w.w, h: w.h,
      tiles: Array.from(w.tiles).join(''),
      cables: Array.from(w.cables).join(''),
      o2: Array.from(w.o2, v => +v.toFixed(2)),
      n2: Array.from(w.n2, v => +v.toFixed(2)),
      co2: Array.from(w.co2, v => +v.toFixed(3)),
      cond: Array.from(w.cond, v => Math.round(v)),
      piles: [...w.piles].map(([i, inv]) => [i, inv.items]),
      zone: Array.from(w.zone).join(''),
      devices: [...w.devices.values()].map(d => ({
        type: d.type, x: d.x, y: d.y, stock: d.stock, charge: d.charge,
        cond: d.cond, broken: d.broken, suit: d.suit, store: d.store, items: d.inv ? d.inv.items : undefined, unknown: d.unknown,
      })),
    };
  },

  dataToWorld(d) {
    d = JSON.parse(JSON.stringify(d)); // Kopie, damit gespeicherte Daten unverändert bleiben
    const world = new G.World(d.w, d.h);
    for (let i = 0; i < world.tiles.length; i++) {
      world.tiles[i] = Number(d.tiles[i]) || 0;
      world.cables[i] = Number(d.cables[i]) || 0;
      world.o2[i] = d.o2[i] || 0;
      world.n2[i] = d.n2[i] || 0;
      world.co2[i] = d.co2[i] || 0;
      world.cond[i] = d.cond ? d.cond[i] : 100;
      world.zone[i] = d.zone ? Number(d.zone[i]) || 0 : 0;
    }
    for (const dv of d.devices || []) {
      const dev = G.Devices.create(dv.type, dv.x, dv.y);
      if (dv.stock !== undefined) dev.stock = dv.stock;
      if (dv.charge !== undefined) dev.charge = dv.charge;
      for (const k of ['cond', 'broken', 'suit', 'store', 'unknown']) if (dv[k] !== undefined) dev[k] = dv[k];
      if (dv.items && dev.inv) dev.inv.items = dv.items;
      world.devices.set(world.idx(dv.x, dv.y), dev);
    }
    for (const [i, items] of d.piles || []) { const inv = G.Items.newInv(); inv.items = items; world.piles.set(i, inv); }
    return world;
  },

  apply(data) {
    const world = this.dataToWorld(data.world);
    const jobs = new Map();
    for (const j of data.jobs || []) {
      jobs.set(world.idx(j.x, j.y), { ...j, claimedBy: null, retryAt: 0 });
    }
    const chars = (data.chars || []).map(c => {
      const ch = Object.assign(G.Chars.create(c.name, 0, 0, c.color), c);
      ch.needs = Object.assign(G.Chars.create('', 0, 0).needs, c.needs);
      ch.inv = G.Items.newInv(G.CARRY.weight, G.CARRY.volume);
      ch.inv.items = c.items || [];
      delete ch.items;
      return ch;
    });
    G.Chars.nextId = data.nextCharId || chars.length + 1;
    G.state = {
      ...G.state,
      world, jobs, chars,
      time: data.time || 0,
      view: data.view || 'normal',
      camera: data.camera || G.state.camera,
      selectedId: data.selectedId ?? (chars[0] && chars[0].id),
      openSource: null,
      econ: data.econ || G.Econ.create(),
      nav: data.nav || G.Nav.create(),
      fleet: data.fleet || G.Fleet.create(),
      wreckName: data.wreckName || null,
    };
    G.Power.dirty = true;
    G.Airlock.dirty = true;
    // Wer beim Speichern etwas getragen hat, stellt es jetzt ab
    for (const c of chars) if (c.carrying) G.Chars.dropCarried(c);
  },

  save(silent) {
    try {
      localStorage.setItem(G.SAVE_KEY, JSON.stringify(this.serialize()));
      if (!silent) G.UI.toast('Spiel gespeichert.');
      return true;
    } catch (err) {
      if (!silent) G.UI.toast('Speichern hat nicht geklappt. Der Browser blockiert vielleicht den Speicher.');
      return false;
    }
  },

  hasSave() {
    try { return !!localStorage.getItem(G.SAVE_KEY); } catch (err) { return false; }
  },

  load(silent) {
    try {
      const text = localStorage.getItem(G.SAVE_KEY);
      if (!text) { if (!silent) G.UI.toast('Es gibt noch keinen Spielstand.'); return false; }
      this.apply(JSON.parse(text));
      if (!silent) G.UI.toast('Spielstand geladen.');
      return true;
    } catch (err) {
      if (!silent) G.UI.toast('Der Spielstand konnte nicht geladen werden.');
      return false;
    }
  },
};
