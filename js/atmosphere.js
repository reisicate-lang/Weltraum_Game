// ============================================================
// atmosphere.js – Luft
// Jede Boden-Kachel hat ihre eigene Luft. Luft verteilt sich zu
// den Nachbarn. Wände halten sie auf, offene Türen nicht.
// Grenzt eine Luft-Kachel an den Weltraum, entweicht die Luft.
// ============================================================

G.Atmo = {
  update(dt) {
    const world = G.state.world, A = G.AIR, T = G.T;
    const { w, h, tiles, o2, n2, co2 } = world;
    const steps = dt / (1 / 3); // Werte sind auf Schritte von 1/3 Minute abgestimmt

    // Wie gut kann Luft zwischen zwei Kacheln fließen? (0 = gar nicht)
    const flow = (a, b) => {
      const ta = tiles[a], tb = tiles[b];
      if (ta === T.WALL || tb === T.WALL) return 0;
      const aAir = ta === T.FLOOR || ta === T.DOOR, bAir = tb === T.FLOOR || tb === T.DOOR;
      if (!aAir && !bAir) return 0;
      const aClosed = ta === T.DOOR && !world.doorOpen(a);
      const bClosed = tb === T.DOOR && !world.doorOpen(b);
      if (!aAir || !bAir) return (aClosed || bClosed) ? 0 : -1; // -1 = Leck ins All
      // Schleusentüren sind ganz dicht, normale Türen haben Lüftungsschlitze
      if ((aClosed && G.Airlock.doorLock.has(a)) || (bClosed && G.Airlock.doorLock.has(b))) return 0;
      if (aClosed || bClosed) return A.DOOR_SLITS;
      return A.DIFFUSION;
    };

    const exchange = (a, b, k) => {
      let d = (o2[a] - o2[b]) * k; o2[a] -= d; o2[b] += d;
      d = (n2[a] - n2[b]) * k; n2[a] -= d; n2[b] += d;
      d = (co2[a] - co2[b]) * k; co2[a] -= d; co2[b] += d;
    };

    const vent = (i) => {
      const keep = Math.pow(1 - A.VENT_LOSS, steps);
      o2[i] *= keep; n2[i] *= keep; co2[i] *= keep;
    };

    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const i = y * w + x;
        // Rand der Welt zählt als Weltraum
        if ((x === 0 || y === 0 || x === w - 1 || y === h - 1) && world.holdsAir(i)) {
          if (!(tiles[i] === T.DOOR && !world.doorOpen(i))) vent(i);
        }
        if (x + 1 < w) this.pair(i, i + 1, flow, exchange, vent, steps);
        if (y + 1 < h) this.pair(i, i + w, flow, exchange, vent, steps);
      }
    }
  },

  pair(a, b, flow, exchange, vent, steps) {
    const k = flow(a, b);
    if (k === 0) return;
    if (k === -1) {
      // Eine Seite ist Weltraum: die Luft-Seite verliert Luft
      vent(G.state.world.holdsAir(a) ? a : b);
      return;
    }
    exchange(a, b, Math.min(0.25, k * steps));
  },

  // Beschreibung der Luft auf einer Kachel
  describe(i) {
    const world = G.state.world;
    if (!world.holdsAir(i)) return '';
    return `O₂ ${world.o2[i].toFixed(1)} kPa · CO₂ ${world.co2[i].toFixed(2)} kPa · Druck ${world.pressure(i).toFixed(0)} kPa`;
  },
};
