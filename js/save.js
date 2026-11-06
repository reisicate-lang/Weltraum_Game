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
      world: { w: S.world.w, h: S.world.h, tiles: S.world.serialize() },
      time: S.time,
      camera: { ...S.camera },
      selectedId: S.selectedId,
      nextCharId: G.Chars.nextId,
      chars: S.chars.map(c => ({ id: c.id, name: c.name, color: c.color, x: c.x, y: c.y, facing: c.facing })),
      jobs: [...S.jobs.values()].map(j => ({ x: j.x, y: j.y, kind: j.kind, tile: j.tile, progress: j.progress, need: j.need })),
    };
  },

  apply(data) {
    const world = G.World.deserialize(data.world.w, data.world.h, data.world.tiles);
    const jobs = new Map();
    for (const j of data.jobs || []) {
      jobs.set(world.idx(j.x, j.y), { ...j, claimedBy: null, retryAt: 0 });
    }
    const chars = (data.chars || []).map(c => Object.assign(G.Chars.create(c.name, 0, 0, c.color), c));
    G.Chars.nextId = data.nextCharId || chars.length + 1;
    G.state = {
      ...G.state,
      world, jobs, chars,
      time: data.time || 0,
      camera: data.camera || G.state.camera,
      selectedId: data.selectedId ?? (chars[0] && chars[0].id),
    };
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
