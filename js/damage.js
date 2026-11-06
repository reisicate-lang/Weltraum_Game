// ============================================================
// damage.js – Schäden
// - Laufende Geräte nutzen sich ab (siehe devices.js)
// - Mikrometeoriten treffen ab und zu die Außenhülle
// - Was stark beschädigt ist, wird automatisch zur Reparatur markiert
// ============================================================

G.Damage = {
  scanTimer: 0,
  effects: [], // Einschlag-Blitze zum Zeichnen

  update(dt) {
    const S = G.state, D = G.DAMAGE;
    if (S.time / 1440 >= D.FIRST_METEOR_DAY && Math.random() < D.METEORS_PER_DAY * dt / 1440) this.strike();
    this.scanTimer -= dt;
    if (this.scanTimer <= 0) { this.scanTimer = 1; this.scan(); }
  },

  // Ein Mikrometeorit trifft eine zufällige Stelle der Außenhülle
  strike() {
    const world = G.state.world, T = G.T;
    const hull = [];
    for (let y = 0; y < world.h; y++) {
      for (let x = 0; x < world.w; x++) {
        const t = world.get(x, y);
        if (t !== T.WALL && t !== T.DOOR) continue;
        if ([[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => world.get(x + dx, y + dy) === T.SPACE)) hull.push([x, y]);
      }
    }
    if (!hull.length) return;
    const [x, y] = hull[Math.floor(Math.random() * hull.length)];
    const i = world.idx(x, y);
    const wasDoor = world.tiles[i] === T.DOOR;
    world.cond[i] -= 35 + Math.random() * 45;
    this.effects.push({ x, y, start: performance.now() });

    // Splitter beschädigen Geräte in der Nähe
    for (const dev of world.devices.values()) {
      if (Math.abs(dev.x - x) <= 2 && Math.abs(dev.y - y) <= 2 && !dev.broken) {
        dev.cond = Math.max(0, dev.cond - Math.random() * 30);
        if (dev.cond <= 0) dev.broken = true;
      }
    }

    if (world.cond[i] <= 0) {
      // Loch in der Hülle! Luft entweicht. Sofort Reparatur planen.
      world.set(x, y, T.FLOOR);
      G.Power.dirty = true;
      G.Airlock.dirty = true;
      G.Jobs.place(wasDoor ? 'door' : 'wall', x, y);
      G.UI.toast('Hüllenbruch! Ein Mikrometeorit hat ein Loch geschlagen.', 'bad');
    } else {
      G.UI.toast('Mikrometeorit-Einschlag! Die Hülle ist beschädigt.', 'bad');
    }
  },

  needsRepair(x, y) {
    const world = G.state.world;
    if (!world.inBounds(x, y)) return false;
    const dev = world.device(x, y);
    if (dev) return dev.cond < 100;
    const t = world.get(x, y);
    return (t === G.T.WALL || t === G.T.DOOR) && world.cond[world.idx(x, y)] < 100;
  },

  requestRepair(x, y) {
    if (!G.state.jobs.has(G.state.world.idx(x, y))) G.Jobs.place('repair', x, y);
  },

  // Stark Beschädigtes automatisch zur Reparatur markieren
  scan() {
    const world = G.state.world, T = G.T, limit = G.DAMAGE.AUTO_REPAIR_AT;
    for (let i = 0; i < world.tiles.length; i++) {
      const t = world.tiles[i];
      if ((t === T.WALL || t === T.DOOR) && world.cond[i] < limit) this.requestRepair(i % world.w, (i / world.w) | 0);
    }
    for (const dev of world.devices.values()) if (dev.cond < limit) this.requestRepair(dev.x, dev.y);
    G.Jobs.scanRefills();
  },

  repair(x, y) {
    const world = G.state.world;
    const dev = world.device(x, y);
    if (dev) { dev.cond = 100; dev.broken = false; }
    else world.cond[world.idx(x, y)] = 100;
  },
};
