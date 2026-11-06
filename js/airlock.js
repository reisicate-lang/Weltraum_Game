// ============================================================
// airlock.js – Luftschleusen
// Ein kleiner geschlossener Raum mit einer Schleusenpumpe ist
// eine Schleuse. Eine Schleusentür geht erst auf, wenn der Druck
// in der Schleuse zum Druck auf der anderen Seite der Tür passt.
// Die Pumpe saugt die Luft dafür ab (und speichert sie) oder
// lässt sie wieder hinein. So geht keine Luft verloren.
// ============================================================

G.Airlock = {
  dirty: true,
  locks: [],
  doorLock: new Map(), // Tür-Index -> { lock, outside }

  rebuild() {
    const world = G.state.world, T = G.T, L = G.AIRLOCK;
    this.locks = [];
    this.doorLock = new Map();
    for (const [start, dev] of world.devices) {
      if (dev.type !== 'pump') continue;
      // Raum um die Pumpe herum suchen (Türen und Wände sind Grenzen)
      const tiles = [], seen = new Set([start]), stack = [start];
      let ok = true;
      while (stack.length && ok) {
        const j = stack.pop();
        tiles.push(j);
        if (tiles.length > L.MAX_SIZE) { ok = false; break; }
        const x = j % world.w, y = (j / world.w) | 0;
        for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
          if (!world.inBounds(x + dx, y + dy)) { ok = false; break; }
          const n = world.idx(x + dx, y + dy);
          const t = world.tiles[n];
          if (t === T.SPACE) { ok = false; break; }   // offen zum All: keine Schleuse
          if (t === T.FLOOR && !seen.has(n)) { seen.add(n); stack.push(n); }
        }
      }
      if (!ok) continue;
      const lock = { pump: dev, tiles, doors: [], target: null, requestUntil: 0 };
      for (const j of tiles) {
        const x = j % world.w, y = (j / world.w) | 0;
        for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
          const dxp = x + dx, dyp = y + dy;
          const d = world.idx(dxp, dyp);
          if (world.tiles[d] !== T.DOOR || this.doorLock.has(d)) continue;
          const ox = dxp + dx, oy = dyp + dy;
          const outside = world.inBounds(ox, oy) ? world.idx(ox, oy) : -1;
          this.doorLock.set(d, { lock, outside });
          lock.doors.push(d);
        }
      }
      this.locks.push(lock);
    }
    this.dirty = false;
  },

  ensure() { if (this.dirty) this.rebuild(); },

  lockOfPump(dev) {
    this.ensure();
    return this.locks.find(l => l.pump === dev) || null;
  },

  isLockTile(i) {
    this.ensure();
    return this.locks.some(l => l.tiles.includes(i));
  },

  pressure(lock) {
    const world = G.state.world;
    let sum = 0;
    for (const j of lock.tiles) sum += world.pressure(j);
    return sum / lock.tiles.length;
  },

  pumpWorks(lock) { return lock.pump.powered && !lock.pump.broken; },

  // Darf ein Charakter jetzt durch diese Tür? Wenn nicht, wird gepumpt.
  canPass(i) {
    this.ensure();
    const e = this.doorLock.get(i);
    if (!e) return true;
    const world = G.state.world, lock = e.lock;
    if (world.doorOpen(i)) return true;
    // Nie beide Türen gleichzeitig offen
    for (const d of lock.doors) if (d !== i && world.doorOpen(d)) return false;
    // Ohne Pumpe: Tür geht trotzdem auf (Notöffnung), aber Luft geht verloren
    if (!this.pumpWorks(lock)) return true;
    const target = e.outside >= 0 && world.holdsAir(e.outside) ? world.pressure(e.outside) : 0;
    lock.target = target;
    lock.requestUntil = G.state.time + 0.1;
    return Math.abs(this.pressure(lock) - target) < G.AIRLOCK.TOLERANCE;
  },

  update(dt) {
    this.ensure();
    const world = G.state.world, L = G.AIRLOCK;
    for (const lock of this.locks) {
      if (lock.requestUntil < G.state.time || !this.pumpWorks(lock)) continue;
      const pump = lock.pump, n = lock.tiles.length;
      const avg = this.pressure(lock);
      const diff = lock.target - avg;
      if (Math.abs(diff) < 1) continue;
      const amount = Math.min(L.PUMP_RATE * dt, Math.abs(diff) * n);
      if (diff < 0) {
        // Abpumpen: Luft in den Speicher der Pumpe
        const f = Math.min(1, amount / (avg * n));
        for (const j of lock.tiles) {
          world.o2[j] -= world.o2[j] * f; world.n2[j] -= world.n2[j] * f; world.co2[j] -= world.co2[j] * f;
        }
        pump.store = Math.min(L.STORE_MAX, pump.store + amount);
      } else {
        // Befüllen aus dem Speicher
        const add = Math.min(amount, pump.store);
        pump.store -= add;
        for (const j of lock.tiles) {
          world.o2[j] += add / n * 0.21; world.n2[j] += add / n * 0.79;
        }
      }
    }
  },
};
