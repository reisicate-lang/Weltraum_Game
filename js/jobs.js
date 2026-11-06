// ============================================================
// jobs.js – Baupläne (Aufträge)
// Wenn du im Baumodus etwas platzierst, entsteht ein Bauplan.
// Die Charaktere laufen hin und bauen ihn nach und nach.
// ============================================================

G.Jobs = {
  key(x, y) { return G.state.world.idx(x, y); },

  // Welche Kachel entsteht durch ein Werkzeug?
  TOOL_TILE: { floor: G.T.FLOOR, wall: G.T.WALL, door: G.T.DOOR },

  // Darf das Werkzeug auf diese Kachel angewendet werden?
  canPlace(tool, x, y) {
    const world = G.state.world, T = G.T;
    if (!world.inBounds(x, y)) return false;
    const t = world.get(x, y);
    switch (tool) {
      case 'floor': return t === T.SPACE;
      case 'wall': return t === T.SPACE || t === T.FLOOR;
      case 'door': return t !== T.DOOR;
      case 'remove': return t !== T.SPACE;
      case 'cancel': return G.state.jobs.has(this.key(x, y));
      default: return false;
    }
  },

  // Wendet ein Werkzeug auf eine Kachel an
  place(tool, x, y) {
    if (!this.canPlace(tool, x, y)) return false;
    const jobs = G.state.jobs;
    const k = this.key(x, y);

    if (tool === 'cancel') {
      jobs.delete(k);
      return true;
    }

    const kind = tool === 'remove' ? 'remove' : 'build';
    const tile = kind === 'build' ? this.TOOL_TILE[tool] : null;
    const old = jobs.get(k);
    if (old && old.kind === kind && old.tile === tile) return false; // gibt es schon

    jobs.set(k, {
      x, y, kind, tile,
      progress: 0,
      need: kind === 'remove' ? G.REMOVE_TIME : G.TILE_INFO[tile].buildTime,
      claimedBy: null, // welcher Charakter gerade daran arbeitet
      retryAt: 0,      // wann wieder versucht wird, falls unerreichbar
    });
    return true;
  },

  // Was wird aus der Kachel, wenn der Auftrag fertig ist?
  resultTile(job) {
    const T = G.T;
    if (job.kind === 'build') return job.tile;
    const t = G.state.world.get(job.x, job.y);
    return (t === T.WALL || t === T.DOOR) ? T.FLOOR : T.SPACE;
  },

  complete(job) {
    const S = G.state;
    S.world.set(job.x, job.y, this.resultTile(job));
    S.jobs.delete(this.key(job.x, job.y));
    // Steht jemand auf einer Kachel, die jetzt eine Wand ist? Dann zur Seite schieben.
    for (const c of S.chars) G.Chars.pushOutIfStuck(c);
  },

  // Sucht für einen Charakter den nächsten erreichbaren Bauplan
  assign(c) {
    const S = G.state, world = S.world;
    if (!S.jobs.size) return false;
    const tx = Math.floor(c.x), ty = Math.floor(c.y);
    const { dist, prev } = G.Path.fromPoint(tx, ty);
    const startIdx = world.idx(tx, ty);

    let best = null, bestDist = Infinity, bestSpot = -1;
    for (const job of S.jobs.values()) {
      if (job.claimedBy && job.claimedBy !== c.id) continue;
      if (job.retryAt > S.time) continue;
      let found = false;
      for (const [dx, dy] of G.Path.DIRS) {
        const nx = job.x + dx, ny = job.y + dy;
        if (!world.walkable(nx, ny)) continue;
        const ni = world.idx(nx, ny);
        if (dist[ni] < bestDist) {
          bestDist = dist[ni];
          best = job;
          bestSpot = ni;
        }
        if (dist[ni] < Infinity) found = true;
      }
      // Nicht erreichbar: eine Weile nicht mehr probieren
      if (!found) job.retryAt = S.time + 30;
    }

    if (!best) return false;
    best.claimedBy = c.id;
    c.job = best;
    c.path = bestSpot === startIdx ? [] : G.Path.buildPath(prev, bestSpot);
    return true;
  },

  label(job) {
    if (job.kind === 'remove') return 'Reißt ab';
    return 'Baut ' + G.TILE_INFO[job.tile].name;
  },
};
