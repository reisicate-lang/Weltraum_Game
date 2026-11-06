// ============================================================
// jobs.js – Baupläne (Aufträge)
// Wenn du im Baumodus etwas platzierst, entsteht ein Bauplan.
// Die Charaktere laufen hin und bauen ihn nach und nach.
// ============================================================

G.Jobs = {
  key(x, y) { return G.state.world.idx(x, y); },

  TOOL_TILE: { floor: G.T.FLOOR, wall: G.T.WALL, door: G.T.DOOR },

  // Darf das Werkzeug auf diese Kachel angewendet werden?
  canPlace(tool, x, y) {
    const world = G.state.world, T = G.T;
    if (!world.inBounds(x, y)) return false;
    const i = world.idx(x, y);
    const t = world.tiles[i];
    const hasDev = world.devices.has(i);
    if (tool.startsWith('dev:')) return t === T.FLOOR && !hasDev;
    switch (tool) {
      case 'floor': return t === T.SPACE;
      case 'wall': return (t === T.SPACE || t === T.FLOOR) && !hasDev;
      case 'door': return t !== T.DOOR && !hasDev;
      case 'cable': return t !== T.SPACE && !world.cables[i];
      case 'remove': return t !== T.SPACE;
      case 'cancel': return G.state.jobs.has(i);
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

    let job;
    if (tool === 'remove') job = { kind: 'remove', need: G.REMOVE_TIME };
    else if (tool === 'cable') job = { kind: 'cable', need: G.CABLE_TIME };
    else if (tool.startsWith('dev:')) {
      const dev = tool.slice(4);
      job = { kind: 'device', dev, need: G.DEVICES[dev].buildTime };
    } else {
      const tile = this.TOOL_TILE[tool];
      job = { kind: 'build', tile, need: G.TILE_INFO[tile].buildTime };
    }
    const old = jobs.get(k);
    if (old && old.kind === job.kind && old.tile === job.tile && old.dev === job.dev) return false;

    jobs.set(k, Object.assign(job, { x, y, progress: 0, claimedBy: null, retryAt: 0 }));
    return true;
  },

  // Auftrag ist fertig: Welt verändern
  complete(job) {
    const S = G.state, world = S.world, T = G.T;
    const i = world.idx(job.x, job.y);
    S.jobs.delete(i);
    // Hat sich die Lage geändert, seit der Plan gemacht wurde? Dann nichts tun.
    const toolName = job.kind === 'build' ? ['', 'floor', 'wall', 'door'][job.tile]
      : job.kind === 'device' ? 'dev:' + job.dev : job.kind;
    if (!this.canPlace(toolName, job.x, job.y)) return;

    switch (job.kind) {
      case 'build':
        world.set(job.x, job.y, job.tile);
        break;
      case 'cable':
        world.cables[i] = 1;
        break;
      case 'device':
        world.devices.set(i, G.Devices.create(job.dev, job.x, job.y));
        break;
      case 'remove': {
        const t = world.tiles[i];
        if (world.devices.has(i)) world.devices.delete(i);
        else if (world.cables[i] && t === T.FLOOR) world.cables[i] = 0;
        else if (t === T.WALL || t === T.DOOR) world.set(job.x, job.y, T.FLOOR);
        else world.set(job.x, job.y, T.SPACE);
        break;
      }
    }
    G.Power.dirty = true;
    // Steht jemand auf einer Kachel, die jetzt blockiert ist? Dann zur Seite schieben.
    for (const c of S.chars) G.Chars.pushOutIfStuck(c);
  },

  // Sucht für einen Charakter den nächsten erreichbaren Bauplan
  assign(c) {
    const S = G.state;
    if (!S.jobs.size) return false;
    const candidates = [];
    for (const job of S.jobs.values()) {
      if (job.claimedBy && job.claimedBy !== c.id) continue;
      if (job.retryAt > S.time) continue;
      candidates.push(job);
    }
    const res = G.Path.nearestAdjacent(c, candidates);
    // Unerreichbare Pläne eine Weile nicht mehr probieren
    for (const job of res.unreachable) job.retryAt = S.time + 30;
    if (!res.target) return false;
    res.target.claimedBy = c.id;
    c.job = res.target;
    c.path = res.path;
    return true;
  },

  label(job) {
    switch (job.kind) {
      case 'remove': return 'Reißt ab';
      case 'cable': return 'Verlegt Kabel';
      case 'device': return 'Baut ' + G.DEVICES[job.dev].name;
      default: return 'Baut ' + G.TILE_INFO[job.tile].name;
    }
  },

  describe(job) {
    switch (job.kind) {
      case 'remove': return 'abreißen';
      case 'cable': return 'Kabel';
      case 'device': return G.DEVICES[job.dev].name;
      default: return G.TILE_INFO[job.tile].name;
    }
  },
};
