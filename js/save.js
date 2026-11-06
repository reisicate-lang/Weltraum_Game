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
      world: {
        w: S.world.w, h: S.world.h,
        tiles: Array.from(S.world.tiles).join(''),
        cables: Array.from(S.world.cables).join(''),
        o2: Array.from(S.world.o2, v => +v.toFixed(2)),
        n2: Array.from(S.world.n2, v => +v.toFixed(2)),
        co2: Array.from(S.world.co2, v => +v.toFixed(3)),
        devices: [...S.world.devices.values()].map(d => ({ type: d.type, x: d.x, y: d.y, stock: d.stock, charge: d.charge })),
      },
      view: S.view,
      time: S.time,
      camera: { ...S.camera },
      selectedId: S.selectedId,
      nextCharId: G.Chars.nextId,
      chars: S.chars.map(c => ({
        id: c.id, name: c.name, color: c.color, x: c.x, y: c.y, facing: c.facing,
        needs: { ...c.needs }, health: c.health, unconscious: c.unconscious,
      })),
      jobs: [...S.jobs.values()].map(j => ({ x: j.x, y: j.y, kind: j.kind, tile: j.tile, dev: j.dev, progress: j.progress, need: j.need })),
    };
  },

  apply(data) {
    const d = data.world;
    const world = new G.World(d.w, d.h);
    for (let i = 0; i < world.tiles.length; i++) {
      world.tiles[i] = Number(d.tiles[i]) || 0;
      world.cables[i] = Number(d.cables[i]) || 0;
      world.o2[i] = d.o2[i] || 0;
      world.n2[i] = d.n2[i] || 0;
      world.co2[i] = d.co2[i] || 0;
    }
    for (const dv of d.devices || []) {
      const dev = G.Devices.create(dv.type, dv.x, dv.y);
      if (dv.stock !== undefined) dev.stock = dv.stock;
      if (dv.charge !== undefined) dev.charge = dv.charge;
      world.devices.set(world.idx(dv.x, dv.y), dev);
    }
    const jobs = new Map();
    for (const j of data.jobs || []) {
      jobs.set(world.idx(j.x, j.y), { ...j, claimedBy: null, retryAt: 0 });
    }
    const chars = (data.chars || []).map(c => {
      const ch = Object.assign(G.Chars.create(c.name, 0, 0, c.color), c);
      ch.needs = Object.assign(G.Chars.create('', 0, 0).needs, c.needs);
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
    };
    G.Power.dirty = true;
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
