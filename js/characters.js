// ============================================================
// characters.js – Die Charaktere (Crew)
// Reihenfolge, was ein Charakter tut:
//   1. Laufbefehl vom Spieler
//   2. Bei schlechter Luft (ohne Anzug): Luft anhalten, dann fliehen
//   3. Laufende Tätigkeit (essen, schlafen, Anzug an/aus, laden ...)
//   4. Anzug fast leer? Zurück und aufladen
//   5. Bedürfnisse erfüllen, wenn sie zu niedrig sind
//   6. Baupläne abarbeiten
// ============================================================

G.Chars = {
  nextId: 1,

  create(name, x, y, color) {
    return {
      id: this.nextId++,
      name,
      color,
      x: x + 0.5, // Position in Kacheln (Mitte der Kachel = +0.5)
      y: y + 0.5,
      facing: 0,
      path: [],
      order: null,     // Laufbefehl vom Spieler {x, y}
      job: null,       // aktueller Bauplan
      activity: null,  // aktuelle Tätigkeit
      suit: null,      // getragener Raumanzug { o2, battery }
      carrying: null,  // getragenes Gerät
      inv: G.Items.newInv(G.CARRY.weight, G.CARRY.volume), // Gepäck
      fetch: null,     // holt gerade Material { src }
      transfer: null,  // geplanter Austausch mit einer Kiste { src, dir, type, qty }
      isPlayer: false, // die Figur, die du mit WASD steuerst
      manualUntil: 0,  // bis wann die Figur gerade von Hand gesteuert wird
      needs: { food: 85, water: 80, sleep: 75, hygiene: 80, air: 100 },
      health: 100,
      unconscious: false,
      waiting: false,  // wartet gerade an einer Schleuse
      task: 'Wartet',
      searchCooldown: 0,
      warned: {},
    };
  },

  tileX(c) { return Math.floor(c.x); },
  tileY(c) { return Math.floor(c.y); },
  tileIdx(c) { return G.state.world.idx(this.tileX(c), this.tileY(c)); },

  // Kann man hier ohne Anzug atmen?
  safeAir(i) {
    const world = G.state.world;
    return world.holdsAir(i) && world.o2[i] >= G.AIR.O2_LOW;
  },

  // Trägt der Charakter einen funktionierenden Anzug?
  suitOk(c) { return !!(c.suit && c.suit.o2 > 0 && c.suit.battery > 0); },

  // Spieler gibt einen Laufbefehl
  orderMove(c, tx, ty) {
    if (c.unconscious) return false;
    const path = G.Path.find(this.tileX(c), this.tileY(c), tx, ty);
    if (!path) return false;
    this.releaseJob(c);
    this.stopActivity(c);
    c.order = { x: tx, y: ty };
    c.path = path;
    c.transfer = null;
    return true;
  },

  // ---------------- Gegenstände ----------------

  // Steht der Charakter nah genug an einem Lager (Kiste oder Haufen)?
  canReach(c, src) {
    return Math.abs(this.tileX(c) - src.x) <= 1 && Math.abs(this.tileY(c) - src.y) <= 1;
  },

  // Geht zum nächsten Lager mit fehlendem Material für den aktuellen Auftrag
  startFetch(c) {
    const miss = G.Items.missing(G.Jobs.cost(c.job), c.inv);
    const types = Object.keys(miss);
    if (!types.length) return false;
    const srcs = G.Items.sources().filter(s => types.some(t => G.Items.count(s.inv, t) > 0));
    // Haufen kann man auch betreten, darum zählt dort auch das Feld selbst
    const res = G.Path.nearestAdjacent(c, srcs);
    if (!res.target) return false;
    c.fetch = { src: res.target };
    c.path = res.path;
    return true;
  },

  doFetch(c, dt) {
    const src = c.fetch.src;
    if (c.path.length) {
      c.task = c.waiting ? 'Wartet auf Schleuse' : 'Holt Material';
      if (!this.followPath(c, dt)) this.releaseJob(c);
      return;
    }
    if (!this.canReach(c, src)) { this.releaseJob(c); return; }
    c.task = 'Nimmt Material';
    for (const [type, qty] of Object.entries(G.Items.missing(G.Jobs.cost(c.job), c.inv))) {
      G.Items.move(src.inv, c.inv, type, qty);
    }
    G.Items.cleanPiles();
    c.fetch = null;
    // Fehlt noch etwas? Nächstes Lager. Sonst zur Baustelle.
    if (Object.keys(G.Items.missing(G.Jobs.cost(c.job), c.inv)).length) {
      if (!this.startFetch(c)) {
        G.UI.toast(c.name + ': Nicht genug Material (oder zu schwer zum Tragen).', 'bad');
        c.job.retryAt = G.state.time + 1;
        this.releaseJob(c);
      }
      return;
    }
    const tgt = G.Jobs.target(c.job);
    const res = G.Path.nearestAdjacent(c, [tgt]);
    if (!res.target) { this.releaseJob(c); return; }
    c.path = res.path;
  },

  // Gegenstände mit einer Kiste oder einem Haufen austauschen (vom Spieler angeordnet)
  // dir: 'take' = herausnehmen, 'put' = hineinlegen
  startTransfer(c, src, dir, type, qty) {
    if (c.unconscious) return false;
    if (this.canReach(c, src)) return this.doTransfer(c, { src, dir, type, qty });
    const res = G.Path.nearestAdjacent(c, [src]);
    if (!res.target) { G.UI.toast(c.name + ' kommt dort nicht hin.'); return false; }
    this.releaseJob(c); this.stopActivity(c);
    c.order = null;
    c.transfer = { src, dir, type, qty };
    c.path = res.path;
    return true;
  },

  doTransfer(c, t) {
    const from = t.dir === 'take' ? t.src.inv : c.inv;
    const to = t.dir === 'take' ? c.inv : t.src.inv;
    const n = G.Items.move(from, to, t.type, t.qty);
    G.Items.cleanPiles();
    c.transfer = null;
    if (n < t.qty) G.UI.toast(t.dir === 'take' ? c.name + ' kann nicht mehr tragen.' : 'Da passt nichts mehr hinein.');
    return n > 0;
  },

  // Etwas aus dem Gepäck auf den Boden legen
  dropItem(c, type, qty) {
    const spot = G.state.world.get(this.tileX(c), this.tileY(c)) === G.T.FLOOR ? { x: this.tileX(c), y: this.tileY(c) } : G.Jobs.dropSpot(this.tileX(c), this.tileY(c));
    for (const st of G.Items.take(c.inv, type, qty)) G.Items.drop(spot.x, spot.y, st);
  },

  // ---------------- Direkte Steuerung (WASD) ----------------
  // dx, dy = Richtung, dist = Strecke in Kacheln
  manualMove(c, dx, dy, dist) {
    if (c.unconscious) return;
    const world = G.state.world;
    if (c.order || c.job || c.activity || c.transfer) {
      this.releaseJob(c); this.stopActivity(c); c.order = null; c.transfer = null;
    }
    c.manualUntil = performance.now() + 8000;
    c.path = [];
    const len = Math.hypot(dx, dy);
    if (!len) return;
    dx /= len; dy /= len;
    this.turnTo(c, Math.atan2(dy, dx), 1);
    const r = 0.27;
    // Kann der Körper (Kreis) an dieser Stelle stehen? Türen öffnen sich dabei.
    const fits = (px, py) => {
      for (const [ox, oy] of [[-r, -r], [r, -r], [-r, r], [r, r]]) {
        const tx = Math.floor(px + ox), ty = Math.floor(py + oy);
        if (!world.walkable(tx, ty)) return false;
        const ti = world.idx(tx, ty);
        if (world.tiles[ti] === G.T.DOOR && ti !== this.tileIdx(c)) {
          if (!G.Airlock.canPass(ti)) { c.waiting = true; return false; }
          world.doorOpenUntil[ti] = G.state.time + 0.05;
        }
      }
      return true;
    };
    c.waiting = false;
    // Achsen getrennt prüfen: so gleitet man an Wänden entlang
    if (fits(c.x + dx * dist, c.y)) c.x += dx * dist;
    if (fits(c.x, c.y + dy * dist)) c.y += dy * dist;
    const ci = this.tileIdx(c);
    if (world.tiles[ci] === G.T.DOOR) world.doorOpenUntil[ci] = G.state.time + 0.05;
  },

  isManual(c) { return c.isPlayer && performance.now() < c.manualUntil; },

  releaseJob(c) {
    if (c.carrying) this.dropCarried(c);
    c.fetch = null;
    // Unterbrochenes Einsammeln: die Sachen bleiben im Gepäck
    if (c.job && c.job.kind === 'haul' && c.job.phase === 'deliver') G.state.jobs.delete(G.state.world.idx(c.job.x, c.job.y));
    if (c.job) c.job.claimedBy = null;
    c.job = null;
    c.path = [];
  },

  stopActivity(c) {
    if (c.activity && c.activity.dev) c.activity.dev.claimedBy = null;
    c.activity = null;
    c.path = [];
  },

  // Getragenes Gerät in der Nähe abstellen (z. B. wenn die Arbeit unterbrochen wird)
  dropCarried(c) {
    const dev = c.carrying, world = G.state.world;
    if (!dev) return;
    c.carrying = null;
    if (c.job && c.job.kind === 'move') {
      G.state.jobs.delete(world.idx(c.job.x, c.job.y));
      c.job = null;
    }
    const cx = this.tileX(c), cy = this.tileY(c);
    let spot = null;
    for (let r = 1; r < 6 && !spot; r++) {
      for (let dy = -r; dy <= r && !spot; dy++) {
        for (let dx = -r; dx <= r && !spot; dx++) {
          const x = cx + dx, y = cy + dy;
          if (world.get(x, y) === G.T.FLOOR && !world.device(x, y) && !G.state.jobs.has(world.idx(x, y))) spot = { x, y };
        }
      }
    }
    if (!spot) spot = { x: cx, y: cy };
    dev.x = spot.x; dev.y = spot.y;
    world.devices.set(world.idx(spot.x, spot.y), dev);
    G.Jobs.changed();
  },

  // ---------------- Bewegung ----------------

  // Freie Sicht zwischen zwei Punkten? (für glattere Wege)
  canSee(ax, ay, bx, by) {
    const world = G.state.world;
    const dx = bx - ax, dy = by - ay;
    const len = Math.hypot(dx, dy);
    if (len < 0.01) return true;
    const nx = -dy / len * 0.3, ny = dx / len * 0.3; // Körperbreite
    const steps = Math.ceil(len / 0.15);
    for (let s = 1; s <= steps; s++) {
      const px = ax + dx * s / steps, py = ay + dy * s / steps;
      for (const k of [-1, 0, 1]) {
        const tx = Math.floor(px + nx * k), ty = Math.floor(py + ny * k);
        if (!world.walkable(tx, ty) || world.tiles[world.idx(tx, ty)] === G.T.DOOR) return false;
      }
    }
    return true;
  },

  // Blickrichtung weich drehen
  turnTo(c, angle, dt) {
    let d = angle - c.facing;
    while (d > Math.PI) d -= Math.PI * 2;
    while (d < -Math.PI) d += Math.PI * 2;
    const max = 720 * dt; // so schnell dreht sich der Kopf (Bogenmaß pro Minute)
    c.facing += Math.max(-max, Math.min(max, d));
  },

  // Läuft den Weg ab. Gibt false zurück, wenn der Weg blockiert ist.
  followPath(c, dt) {
    const world = G.state.world;
    let move = G.WALK_SPEED * dt;
    c.waiting = false;
    while (move > 0 && c.path.length) {
      // Wegpunkte überspringen, wenn man direkt hinsehen kann (keine Zickzack-Wege)
      while (c.path.length > 1 && world.tiles[world.idx(c.path[0].x, c.path[0].y)] !== G.T.DOOR
        && this.canSee(c.x, c.y, c.path[1].x + 0.5, c.path[1].y + 0.5)) c.path.shift();

      const next = c.path[0];
      if (!world.walkable(next.x, next.y)) return false;
      const ni = world.idx(next.x, next.y), ci = this.tileIdx(c);
      // Türen: Schleusen erst durchlassen, wenn der Druck passt
      if (world.tiles[ni] === G.T.DOOR && ni !== ci) {
        if (!G.Airlock.canPass(ni)) { c.waiting = true; return true; }
        world.doorOpenUntil[ni] = G.state.time + 0.05;
      }
      if (world.tiles[ci] === G.T.DOOR) world.doorOpenUntil[ci] = G.state.time + 0.05;

      const tx = next.x + 0.5, ty = next.y + 0.5;
      const dx = tx - c.x, dy = ty - c.y;
      const d = Math.hypot(dx, dy);
      if (d > 0.0001) this.turnTo(c, Math.atan2(dy, dx), dt);
      if (d <= move) {
        c.x = tx; c.y = ty;
        move -= d;
        c.path.shift();
      } else {
        c.x += (dx / d) * move;
        c.y += (dy / d) * move;
        move = 0;
      }
    }
    return true;
  },

  isNextTo(c, x, y) {
    const cx = this.tileX(c), cy = this.tileY(c);
    return Math.abs(cx - x) <= 1 && Math.abs(cy - y) <= 1 && !(cx === x && cy === y);
  },

  face(c, x, y, dt) { this.turnTo(c, Math.atan2(y + 0.5 - c.y, x + 0.5 - c.x), dt); },

  // ---------------- Körper: Atmen, Bedürfnisse, Gesundheit ----------------
  updateBody(c, dt) {
    const world = G.state.world, A = G.AIR, N = G.NEEDS, n = c.needs;
    const i = this.tileIdx(c);
    const sleeping = c.activity && c.activity.need === 'sleep' && !c.path.length;

    // Raumanzug versorgt mit Luft, solange Sauerstoff und Akku reichen
    const suitOk = this.suitOk(c);
    if (c.suit) {
      c.suit.battery = Math.max(0, c.suit.battery - G.SUIT.BATTERY_USE * dt);
      if (suitOk) c.suit.o2 = Math.max(0, c.suit.o2 - G.SUIT.O2_USE * dt);
    }

    if (suitOk) {
      n.air += 30 * dt;
    } else {
      // Atmen aus der Raumluft: O2 wird zu CO2
      let o2 = 0;
      if (world.holdsAir(i)) {
        const used = Math.min(world.o2[i], A.BREATH_O2 * dt);
        world.o2[i] -= used;
        world.co2[i] += used;
        o2 = world.o2[i];
      }
      if (o2 < A.O2_LOW) n.air -= (A.O2_LOW - o2) / A.O2_LOW * 40 * dt; // im Vakuum: nach gut 1 Minute wird's knapp
      else n.air += 30 * dt;
    }

    // Bedürfnisse sinken mit der Zeit (im Schlaf langsamer)
    const h = dt / 60;
    const slow = sleeping ? 0.5 : 1;
    n.food -= N.food.decay * h * slow;
    n.water -= N.water.decay * h * slow;
    n.hygiene -= N.hygiene.decay * h * slow;
    if (!sleeping) n.sleep -= N.sleep.decay * h;
    for (const k in n) n[k] = Math.max(0, Math.min(100, n[k]));

    // Gesundheit
    let damage = 0;
    if (n.food <= 0) damage += 2;
    if (n.water <= 0) damage += 4;
    if (n.air < 25) damage += 600; // Sauerstoffmangel ist schnell gefährlich
    if (!suitOk && world.holdsAir(i) && world.co2[i] > A.CO2_BAD) damage += 3;
    if (damage) c.health -= damage * h;
    else c.health += 1.5 * h;
    c.health = Math.max(0, Math.min(100, c.health));

    // Bewusstlos?
    if (!c.unconscious && (c.health <= 0 || n.air < 10)) {
      c.unconscious = true;
      this.releaseJob(c); this.stopActivity(c); c.order = null;
      G.UI.toast(c.name + ' ist bewusstlos!', 'bad');
    } else if (c.unconscious && c.health >= 10 && n.air >= 40) {
      c.unconscious = false;
      G.UI.toast(c.name + ' ist wieder bei Bewusstsein.');
    }

    // Warnungen (nur einmal, bis es wieder besser ist)
    this.warn(c, 'air', n.air < 40, c.name + ' bekommt kaum Luft!', n.air > 95);
    this.warn(c, 'co2', !suitOk && world.holdsAir(i) && world.co2[i] > A.CO2_BAD, 'Zu viel CO₂ in der Luft. Ein CO₂-Filter hilft.');
    this.warn(c, 'health', c.health < 30, c.name + ' geht es sehr schlecht.', c.health > 50);
    if (c.suit) this.warn(c, 'suit', Math.min(c.suit.o2, c.suit.battery) < G.SUIT.RETURN_AT,
      'Der Raumanzug von ' + c.name + ' wird knapp.', Math.min(c.suit.o2, c.suit.battery) > 60);
  },

  // Zeigt eine Warnung einmal an. Erst wenn "clear" zutrifft, kann sie wiederkommen.
  warn(c, key, condition, text, clear) {
    if (condition && !c.warned[key]) { c.warned[key] = true; G.UI.toast(text, 'bad'); }
    if (clear === undefined ? !condition : clear) c.warned[key] = false;
  },

  // ---------------- Verhalten ----------------
  update(c, dt) {
    const S = G.state;
    this.updateBody(c, dt);
    if (c.unconscious) { c.task = 'Bewusstlos'; return; }

    // Von Hand gesteuert: keine eigenen Entscheidungen
    if (this.isManual(c)) { c.task = c.waiting ? 'Wartet auf Schleuse' : 'Wird von dir gesteuert'; return; }

    // Austausch mit einer Kiste (vom Spieler angeordnet)
    if (c.transfer) {
      if (c.path.length) {
        c.task = c.waiting ? 'Wartet auf Schleuse' : 'Geht zur Kiste';
        if (!this.followPath(c, dt)) { c.transfer = null; c.path = []; }
        return;
      }
      if (this.canReach(c, c.transfer.src)) this.doTransfer(c, c.transfer);
      c.transfer = null;
    }

    // 1) Laufbefehl vom Spieler
    if (c.order) {
      if (!c.path.length) {
        c.order = null;
      } else {
        c.task = c.waiting ? 'Wartet auf Schleuse' : 'Läuft';
        if (!this.followPath(c, dt)) {
          const p = G.Path.find(this.tileX(c), this.tileY(c), c.order.x, c.order.y);
          if (p) c.path = p; else { c.order = null; c.path = []; }
        }
        return;
      }
    }

    // 2) Schlechte Luft ohne Anzug: Luft anhalten und dann weg hier!
    const i = this.tileIdx(c);
    c.fleeCooldown = (c.fleeCooldown || 0) - dt;
    if (!this.suitOk(c) && !this.safeAir(i) && c.needs.air < 50 && !(c.activity && c.activity.flee) && c.fleeCooldown <= 0) {
      c.fleeCooldown = 0.05;
      this.releaseJob(c);
      this.stopActivity(c);
      if (this.startFlee(c)) return;
    }

    // 3) Laufende Tätigkeit
    if (c.activity) { this.doActivity(c, dt); return; }

    // Regelmäßig prüfen (alle 3 Sekunden), was zu tun ist
    c.searchCooldown -= dt;
    const check = c.searchCooldown <= 0;
    if (check) {
      c.searchCooldown = 0.05;
      // 4) Anzug fast leer: aufladen oder ausziehen
      if (c.suit && Math.min(c.suit.o2, c.suit.battery) < G.SUIT.RETURN_AT && !c.carrying) {
        this.releaseJob(c);
        if (c.suit.o2 >= G.SUIT.RETURN_AT && this.startDevice(c, 'recharge', d => d.type === 'charger' && d.charge > 0.05)) return;
        if (this.startDevice(c, 'suitOff', d => d.type === 'locker' && !d.suit && !d.broken)) return;
      }
      // Geräte in der Nähe untersuchen (Wrack)
      G.Wreck.reveal(c);
      // 5) Bedürfnisse
      if (!c.carrying && this.startNeed(c)) return;
    }

    // 6) Bauplan abarbeiten
    if (c.job) {
      const tgt = G.Jobs.target(c.job);
      if (S.jobs.get(G.Jobs.key(c.job.x, c.job.y)) !== c.job) {
        this.releaseJob(c);
      } else if (c.fetch) {
        this.doFetch(c, dt);
        return;
      } else if (c.path.length) {
        c.task = c.waiting ? 'Wartet auf Schleuse' : 'Geht zu: ' + G.Jobs.label(c.job);
        if (!this.followPath(c, dt)) this.releaseJob(c);
        return;
      } else if (this.isNextTo(c, tgt.x, tgt.y)) {
        // Material verbauen
        if (!c.job.paid) {
          const cost = G.Jobs.cost(c.job);
          if (Object.keys(G.Items.missing(cost, c.inv)).length) {
            if (!this.startFetch(c)) { c.job.retryAt = S.time + 0.5; this.releaseJob(c); }
            return;
          }
          for (const [type, qty] of Object.entries(cost || {})) G.Items.take(c.inv, type, qty);
          c.job.paid = true;
        }
        this.face(c, tgt.x, tgt.y, dt);
        c.task = G.Jobs.label(c.job);
        c.job.progress += dt;
        if (c.job.progress >= c.job.need) this.finishJob(c);
        return;
      } else {
        this.releaseJob(c);
      }
    }

    // Nichts zu tun: nach Bauplänen suchen
    c.task = S.jobs.size ? 'Kann keinen Bauplan erreichen' : 'Wartet';
    if (!check) return;
    const r = G.Jobs.assign(c);
    if (r === true) { c.task = 'Geht zu: ' + G.Jobs.label(c.job); return; }
    if (r === 'suit') return;
    // Nichts mehr zu tun: zurück ins Schiff und Anzug ablegen
    if (c.suit) this.startDevice(c, 'suitOff', d => d.type === 'locker' && !d.suit && !d.broken);
  },

  finishJob(c) {
    const job = c.job;
    if (job.kind === 'haul') {
      if (job.phase === 'pickup') { if (!G.Jobs.haulPickUp(c, job)) c.job = null; return; }
      c.job = null;
      G.Jobs.haulDeliver(c, job);
      return;
    }
    if (job.kind === 'move' && job.phase === 'pickup') {
      if (!G.Jobs.pickUp(c, job)) { c.job = null; return; }
      const res = G.Path.nearestAdjacent(c, [{ x: job.tx, y: job.ty }]);
      if (!res.target) { G.UI.toast(c.name + ' kommt nicht zum Ziel und stellt das Gerät ab.'); this.dropCarried(c); return; }
      c.path = res.path;
      return;
    }
    c.job = null;
    if (job.kind === 'move') G.Jobs.deliver(c, job);
    else G.Jobs.complete(job, c);
  },

  // Zu einem passenden Gerät gehen (z. B. Anzugschrank). Gibt true zurück, wenn es losgeht.
  startDevice(c, kind, filter) {
    const devs = [...G.state.world.devices.values()].filter(d => filter(d) && (!d.claimedBy || d.claimedBy === c.id));
    const res = G.Path.nearestAdjacent(c, devs);
    if (!res.target) return false;
    this.stopActivity(c);
    res.target.claimedBy = c.id;
    c.activity = { kind, dev: res.target, timer: 0 };
    c.path = res.path;
    return true;
  },

  startSuitUp(c) {
    if (c.suit) return false;
    if (c.job) this.releaseJob(c);
    return this.startDevice(c, 'suitUp', d => d.type === 'locker' && d.suit && !d.broken);
  },

  // Sucht ein Gerät für das dringendste Bedürfnis
  startNeed(c) {
    const world = G.state.world;
    const order = Object.keys(G.NEEDS)
      .filter(k => G.NEEDS[k].at !== undefined && c.needs[k] < G.NEEDS[k].at)
      .sort((a, b) => c.needs[a] - c.needs[b]);
    for (const need of order) {
      const devs = [...world.devices.values()].filter(d =>
        G.DEVICES[d.type].need === need && G.Devices.usable(d) && (!d.claimedBy || d.claimedBy === c.id));
      const res = G.Path.nearestAdjacent(c, devs);
      if (!res.target) {
        this.warn(c, 'no-' + need, c.needs[need] < G.NEEDS[need].at - 15,
          c.name + ': ' + G.NEEDS[need].name + ', aber kein ' + this.deviceNameFor(need) + ' erreichbar.');
        continue;
      }
      this.releaseJob(c);
      res.target.claimedBy = c.id;
      c.activity = { kind: 'need', need, dev: res.target, timer: 0 };
      c.path = res.path;
      return true;
    }
    return false;
  },

  deviceNameFor(need) {
    const entry = Object.values(G.DEVICES).find(d => d.need === need);
    return entry ? entry.name : 'Gerät';
  },

  doActivity(c, dt) {
    const a = c.activity, world = G.state.world;

    if (a.flee) {
      c.task = c.waiting ? 'Wartet auf Schleuse' : 'Sucht Luft zum Atmen';
      if (!c.path.length || !this.followPath(c, dt)) this.stopActivity(c);
      return;
    }

    const dev = a.dev;
    // Gibt es das Gerät noch?
    if (world.devices.get(world.idx(dev.x, dev.y)) !== dev) { this.stopActivity(c); return; }
    const names = { suitUp: 'Raumanzug holen', suitOff: 'Raumanzug ablegen', recharge: 'Anzug laden' };
    if (c.path.length) {
      c.task = c.waiting ? 'Wartet auf Schleuse' : 'Geht zu: ' + (names[a.kind] || G.DEVICES[dev.type].name);
      if (!this.followPath(c, dt)) this.stopActivity(c);
      return;
    }
    if (!this.isNextTo(c, dev.x, dev.y)) { this.stopActivity(c); return; }
    this.face(c, dev.x, dev.y, dt);
    a.timer += dt;

    switch (a.kind) {
      case 'suitUp':
        c.task = 'Zieht Raumanzug an';
        if (!dev.suit) { this.stopActivity(c); return; }
        if (a.timer >= 0.5) { c.suit = dev.suit; dev.suit = null; this.stopActivity(c); c.searchCooldown = 0; }
        return;
      case 'suitOff':
        c.task = 'Zieht Raumanzug aus';
        if (dev.suit || !c.suit) { this.stopActivity(c); return; }
        if (a.timer >= 0.5) { dev.suit = c.suit; c.suit = null; this.stopActivity(c); }
        return;
      case 'recharge': {
        c.task = 'Lädt Anzug';
        if (!c.suit) { this.stopActivity(c); return; }
        const add = Math.min(G.SUIT.CHARGE * dt, 100 - c.suit.battery);
        const kwh = add / 100 * G.SUIT.KWH_PER_100;
        if (dev.charge < kwh) { this.stopActivity(c); return; }
        dev.charge -= kwh;
        c.suit.battery += add;
        if (c.suit.battery >= 99.9) this.stopActivity(c);
        return;
      }
    }

    // Bedürfnis erfüllen
    const def = G.NEEDS[a.need];
    if (!G.Devices.usable(dev)) { this.stopActivity(c); return; }
    c.task = def.verb;
    if (a.need === 'sleep') {
      c.needs.sleep = Math.min(100, c.needs.sleep + def.gain / 60 * dt);
      if (c.needs.sleep >= 100) this.stopActivity(c);
      return;
    }
    if (a.timer >= def.useTime) {
      c.needs[a.need] = Math.min(100, c.needs[a.need] + def.gain);
      if (dev.stock !== undefined) {
        const use = { food: 1, water: 0.5, hygiene: 2 }[a.need] || 1;
        dev.stock = Math.max(0, dev.stock - use);
      }
      this.stopActivity(c);
    }
  },

  // Zur nächsten Stelle mit genug Sauerstoff laufen
  startFlee(c) {
    const world = G.state.world;
    const { dist, prev } = G.Path.fromPoint(this.tileX(c), this.tileY(c));
    let best = -1, bestD = Infinity;
    for (let i = 0; i < dist.length; i++) {
      if (dist[i] < bestD && dist[i] > 0 && world.o2[i] >= G.AIR.O2_OK && world.walkable(i % world.w, (i / world.w) | 0)) {
        bestD = dist[i]; best = i;
      }
    }
    if (best < 0) { c.task = 'Keine Atemluft erreichbar!'; return false; }
    this.releaseJob(c);
    c.activity = { flee: true };
    c.path = G.Path.buildPath(prev, best);
    return true;
  },

  // Falls ein Charakter in einer Wand steckt: zur nächsten freien Kachel
  pushOutIfStuck(c) {
    const world = G.state.world;
    const cx = this.tileX(c), cy = this.tileY(c);
    if (world.walkable(cx, cy)) return;
    for (let r = 1; r < 20; r++) {
      for (let dy = -r; dy <= r; dy++) {
        for (let dx = -r; dx <= r; dx++) {
          if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
          if (world.walkable(cx + dx, cy + dy)) {
            c.x = cx + dx + 0.5; c.y = cy + dy + 0.5;
            c.path = [];
            return;
          }
        }
      }
    }
  },

  at(wx, wy) {
    return G.state.chars.find(c => Math.hypot(c.x - wx, c.y - wy) < 0.5) || null;
  },
};
