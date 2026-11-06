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
    if (tool === 'repair') return G.Damage.needsRepair(x, y);
    if (tool === 'refill') return hasDev;
    if (tool === 'move') return hasDev && !G.state.jobs.has(i);
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
      this.cancel(jobs.get(k));
      return true;
    }

    let job;
    if (tool === 'repair') job = { kind: 'repair', need: G.DAMAGE.REPAIR_TIME };
    else if (tool === 'remove') job = { kind: 'remove', need: G.REMOVE_TIME };
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
    if (old && old.kind === 'move' && old.phase === 'deliver') return false; // wird gerade getragen

    jobs.set(k, Object.assign(job, { x, y, progress: 0, claimedBy: null, retryAt: 0 }));
    return true;
  },

  // Welche Materialien braucht ein Auftrag?
  cost(job) {
    switch (job.kind) {
      case 'build': return G.TILE_INFO[job.tile].cost;
      case 'cable': return G.CABLE_COST;
      case 'device': return G.DEVICES[job.dev].cost;
      case 'refill': return { [job.item]: job.qty };
      default: return null;
    }
  },

  // Auftrag abbrechen. Schon verbautes Material kommt zurück.
  cancel(job) {
    if (!job) return;
    const S = G.state, world = S.world;
    S.jobs.delete(this.key(job.x, job.y));
    if (!job.paid) return;
    const spot = this.dropSpot(job.x, job.y);
    for (const [type, qty] of Object.entries(this.cost(job) || {})) G.Items.drop(spot.x, spot.y, G.Items.make(type, qty, 80));
  },

  // Ein Bodenfeld in der Nähe, auf dem man etwas ablegen kann
  dropSpot(x, y) {
    const world = G.state.world;
    for (let r = 0; r < 6; r++) {
      for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
        const nx = x + dx, ny = y + dy;
        if (world.get(nx, ny) === G.T.FLOOR && !world.device(nx, ny)) return { x: nx, y: ny };
      }
    }
    return { x, y };
  },

  // Was bekommt man beim Abreißen zurück?
  salvage(job) {
    const world = G.state.world, T = G.T;
    const i = world.idx(job.x, job.y);
    const r = (a, b) => a + Math.random() * (b - a);
    const out = [];
    const dev = world.devices.get(i);
    if (dev) {
      for (const [type, qty] of Object.entries(G.DEVICES[dev.type].cost || {})) {
        const n = Math.round(qty * r(0.4, 1));
        if (n > 0) out.push(G.Items.make(type, n, Math.round(r(25, 90) * Math.max(0.3, dev.cond / 100))));
      }
      out.push(G.Items.make('scrap', 1 + Math.floor(Math.random() * 2), 40));
      if (dev.inv) out.push(...dev.inv.items);
      return out;
    }
    const t = world.tiles[i];
    if (world.cables[i] && t === T.FLOOR) return [G.Items.make('copper', 1, Math.round(r(50, 90)))];
    const cond = t === T.WALL || t === T.DOOR ? world.cond[i] : 100;
    if (t === T.WALL) out.push(cond < 30 ? G.Items.make('scrap', 3, 40) : G.Items.make('plate', 2, Math.round(r(40, 90) * cond / 100)));
    if (t === T.DOOR) {
      out.push(G.Items.make('plate', 2, Math.round(r(40, 90))));
      if (Math.random() < 0.6) out.push(G.Items.make('circuit', 1, Math.round(r(30, 80))));
    }
    if (t === T.FLOOR) out.push(G.Items.make('plate', 1, Math.round(r(40, 90))));
    return out;
  },

  // Vorräte von Geräten automatisch auffüllen lassen
  scanRefills() {
    const S = G.state, world = S.world;
    for (const dev of world.devices.values()) {
      const def = G.DEVICES[dev.type];
      if (dev.stock === undefined || dev.stock > def.stock * G.REFILL_AT) continue;
      const key = world.idx(dev.x, dev.y);
      if (S.jobs.has(key)) continue;
      const entry = Object.entries(G.ITEMS).find(([, d]) => d.refill && d.refill[dev.type]);
      if (!entry) continue;
      const [item, idef] = entry;
      const want = Math.ceil((def.stock - dev.stock) / idef.refill[dev.type]);
      const byWeight = Math.max(1, Math.floor(G.CARRY.weight / idef.weight));
      const qty = Math.min(want, byWeight, G.Items.available(item));
      if (qty <= 0) continue;
      S.jobs.set(key, { kind: 'refill', x: dev.x, y: dev.y, item, qty, need: 0.5, progress: 0, claimedBy: null, retryAt: 0, auto: true });
    }
  },

  // Gerät versetzen: von (sx,sy) nach (tx,ty)
  placeMove(sx, sy, tx, ty) {
    const world = G.state.world;
    if (!this.canPlace('move', sx, sy)) { G.UI.toast('Dort steht kein Gerät, das man versetzen kann.'); return false; }
    if (sx === tx && sy === ty) return false;
    if (world.get(tx, ty) !== G.T.FLOOR || world.device(tx, ty)) { G.UI.toast('Das Ziel muss ein freier Boden sein.'); return false; }
    G.state.jobs.set(this.key(sx, sy), {
      kind: 'move', x: sx, y: sy, tx, ty, phase: 'pickup', need: 0.3,
      progress: 0, claimedBy: null, retryAt: 0,
    });
    return true;
  },

  // Wo muss der Charakter gerade arbeiten?
  target(job) {
    return job.kind === 'move' && job.phase === 'deliver' ? { x: job.tx, y: job.ty } : { x: job.x, y: job.y };
  },

  // Gerät aufheben (Teil 1 von "Versetzen")
  pickUp(c, job) {
    const world = G.state.world;
    const i = world.idx(job.x, job.y);
    const dev = world.devices.get(i);
    if (!dev) { G.state.jobs.delete(i); return false; }
    world.devices.delete(i);
    if (dev.claimedBy) {
      const user = G.state.chars.find(ch => ch.id === dev.claimedBy);
      if (user) G.Chars.stopActivity(user);
    }
    c.carrying = dev;
    job.phase = 'deliver';
    job.progress = 0;
    this.changed();
    return true;
  },

  // Gerät abstellen (Teil 2 von "Versetzen")
  deliver(c, job) {
    const world = G.state.world;
    G.state.jobs.delete(this.key(job.x, job.y));
    const dev = c.carrying;
    c.carrying = null;
    if (world.get(job.tx, job.ty) === G.T.FLOOR && !world.device(job.tx, job.ty)) {
      dev.x = job.tx; dev.y = job.ty;
      world.devices.set(world.idx(job.tx, job.ty), dev);
      this.changed();
    } else {
      c.carrying = dev;
      G.Chars.dropCarried(c);
    }
  },

  changed() {
    G.Power.dirty = true;
    G.Airlock.dirty = true;
    for (const c of G.state.chars) G.Chars.pushOutIfStuck(c);
  },

  // Auftrag ist fertig: Welt verändern
  complete(job, c) {
    const S = G.state, world = S.world, T = G.T;
    const i = world.idx(job.x, job.y);
    S.jobs.delete(i);
    if (job.kind === 'refill') {
      const dev = world.devices.get(i);
      if (dev && dev.stock !== undefined) {
        const per = G.ITEMS[job.item].refill[dev.type] || 0;
        dev.stock = Math.min(G.DEVICES[dev.type].stock, dev.stock + per * job.qty);
      }
      return;
    }
    // Hat sich die Lage geändert, seit der Plan gemacht wurde? Dann nichts tun.
    const toolName = job.kind === 'build' ? ['', 'floor', 'wall', 'door'][job.tile]
      : job.kind === 'device' ? 'dev:' + job.dev : job.kind;
    if (!this.canPlace(toolName, job.x, job.y)) return;
    if (job.kind === 'repair') { G.Damage.repair(job.x, job.y); return; }

    // Wo Wand, Tür oder Gerät hinkommt, werden herumliegende Sachen beiseitegeräumt
    if ((job.kind === 'build' && job.tile !== T.FLOOR) || job.kind === 'device') {
      const pile = world.piles.get(i);
      if (pile) {
        world.piles.delete(i);
        const spot = c ? { x: G.Chars.tileX(c), y: G.Chars.tileY(c) } : this.dropSpot(job.x, job.y);
        for (const it of pile.items) G.Items.drop(spot.x, spot.y, it);
      }
    }
    if (job.kind === 'remove') {
      // Teile zurückbekommen
      const loot = this.salvage(job);
      // Boden wird zu Weltraum: Teile neben dem Arbeiter ablegen, sonst auf dem Feld selbst
      const spot = world.tiles[i] === T.FLOOR && !world.cables[i] && !world.devices.has(i)
        ? (c ? { x: G.Chars.tileX(c), y: G.Chars.tileY(c) } : this.dropSpot(job.x, job.y))
        : { x: job.x, y: job.y };
      for (const it of loot) G.Items.drop(spot.x, spot.y, it);
    }

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
    this.changed();
  },

  // Sucht für einen Charakter den nächsten erreichbaren Bauplan.
  // Antwort: true (los geht's), false (nichts zu tun) oder 'suit' (Raumanzug nötig)
  assign(c) {
    const S = G.state;
    if (!S.jobs.size) return false;
    const candidates = [];
    for (const job of S.jobs.values()) {
      if (job.claimedBy && job.claimedBy !== c.id) continue;
      if (job.retryAt > S.time) continue;
      if (job.kind === 'move' && job.phase === 'deliver') continue;
      // Gibt es genug Material (im eigenen Gepäck oder irgendwo im Lager)?
      job.missing = false;
      if (!job.paid) {
        for (const [type, qty] of Object.entries(this.cost(job) || {})) {
          if (G.Items.count(c.inv, type) + G.Items.available(type) < qty) job.missing = true;
        }
        if (job.missing) continue;
      }
      candidates.push(job);
    }
    const res = G.Path.nearestAdjacent(c, candidates);
    // Unerreichbare Pläne eine Weile nicht mehr probieren
    for (const job of res.unreachable) job.retryAt = S.time + 0.5;
    if (!res.target) return false;
    const job = res.target;

    // Führt der Weg durchs Vakuum? Dann erst einen Raumanzug holen.
    if (!G.Chars.suitOk(c)) {
      const tiles = res.path.map(p => S.world.idx(p.x, p.y));
      tiles.push(G.Chars.tileIdx(c));
      if (job.kind === 'move') tiles.push(S.world.idx(job.tx, job.ty));
      if (tiles.some(i => !G.Chars.safeAir(i))) {
        if (G.Chars.startSuitUp(c)) { job.retryAt = 0; return 'suit'; }
        job.retryAt = S.time + 1;
        G.Chars.warn(c, 'need-suit', true, c.name + ' braucht einen Raumanzug für diese Arbeit (Anzugschrank fehlt oder ist leer).', false);
        return false;
      }
    }
    job.claimedBy = c.id;
    c.job = job;
    c.path = res.path;
    // Fehlt noch Material im Gepäck? Dann erst holen.
    if (!job.paid && Object.keys(G.Items.missing(this.cost(job), c.inv)).length) {
      if (!G.Chars.startFetch(c)) { G.Chars.releaseJob(c); job.retryAt = S.time + 0.5; return false; }
    }
    return true;
  },

  label(job) {
    switch (job.kind) {
      case 'repair': return 'Repariert';
      case 'refill': return 'Füllt nach: ' + G.ITEMS[job.item].name;
      case 'move': return job.phase === 'deliver' ? 'Trägt Gerät' : 'Hebt Gerät auf';
      case 'remove': return 'Reißt ab';
      case 'cable': return 'Verlegt Kabel';
      case 'device': return 'Baut ' + G.DEVICES[job.dev].name;
      default: return 'Baut ' + G.TILE_INFO[job.tile].name;
    }
  },

  describe(job) {
    switch (job.kind) {
      case 'repair': return 'reparieren';
      case 'refill': return 'nachfüllen';
      case 'move': return 'versetzen';
      case 'remove': return 'abreißen';
      case 'cable': return 'Kabel';
      case 'device': return G.DEVICES[job.dev].name;
      default: return G.TILE_INFO[job.tile].name;
    }
  },
};
