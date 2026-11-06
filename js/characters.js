// ============================================================
// characters.js – Die Charaktere (Crew)
// Reihenfolge, was ein Charakter tut:
//   1. Laufbefehl vom Spieler
//   2. Laufende Tätigkeit (essen, schlafen, vor schlechter Luft fliehen ...)
//   3. Bedürfnisse erfüllen, wenn sie zu niedrig sind
//   4. Baupläne abarbeiten
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
      needs: { food: 85, water: 80, sleep: 75, hygiene: 80, air: 100 },
      health: 100,
      unconscious: false,
      task: 'Wartet',
      searchCooldown: 0,
      warned: {},      // welche Warnungen schon angezeigt wurden
    };
  },

  tileX(c) { return Math.floor(c.x); },
  tileY(c) { return Math.floor(c.y); },
  tileIdx(c) { return G.state.world.idx(this.tileX(c), this.tileY(c)); },

  // Spieler gibt einen Laufbefehl
  orderMove(c, tx, ty) {
    if (c.unconscious) return false;
    const path = G.Path.find(this.tileX(c), this.tileY(c), tx, ty);
    if (!path) return false;
    this.releaseJob(c);
    this.stopActivity(c);
    c.order = { x: tx, y: ty };
    c.path = path;
    return true;
  },

  releaseJob(c) {
    if (c.job) c.job.claimedBy = null;
    c.job = null;
    c.path = [];
  },

  stopActivity(c) {
    if (c.activity && c.activity.dev) c.activity.dev.claimedBy = null;
    c.activity = null;
    c.path = [];
  },

  // Läuft den Weg ab. Gibt false zurück, wenn der Weg blockiert ist.
  followPath(c, dt) {
    const world = G.state.world;
    let move = G.WALK_SPEED * dt;
    while (move > 0 && c.path.length) {
      const next = c.path[0];
      if (!world.walkable(next.x, next.y)) return false;
      // Türen öffnen sich, wenn jemand durchgeht
      const ni = world.idx(next.x, next.y), ci = this.tileIdx(c);
      if (world.tiles[ni] === G.T.DOOR) world.doorOpenUntil[ni] = G.state.time + 0.05; // 3 Sekunden
      if (world.tiles[ci] === G.T.DOOR) world.doorOpenUntil[ci] = G.state.time + 0.05;
      const tx = next.x + 0.5, ty = next.y + 0.5;
      const dx = tx - c.x, dy = ty - c.y;
      const d = Math.hypot(dx, dy);
      if (d > 0.0001) c.facing = Math.atan2(dy, dx);
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

  // ---------------- Körper: Atmen, Bedürfnisse, Gesundheit ----------------
  updateBody(c, dt) {
    const world = G.state.world, A = G.AIR, N = G.NEEDS, n = c.needs;
    const i = this.tileIdx(c);
    const sleeping = c.activity && c.activity.need === 'sleep' && !c.path.length;

    // Atmen: O2 wird zu CO2
    let o2 = 0;
    if (world.holdsAir(i)) {
      const used = Math.min(world.o2[i], A.BREATH_O2 * dt);
      world.o2[i] -= used;
      world.co2[i] += used;
      o2 = world.o2[i];
    }
    if (o2 < A.O2_LOW) n.air -= (A.O2_LOW - o2) / A.O2_LOW * 40 * dt; // im Vakuum: nach gut 1 Minute wird's knapp
    else n.air += 30 * dt;

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
    if (world.holdsAir(i) && world.co2[i] > A.CO2_BAD) damage += 3;
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
    this.warn(c, 'co2', world.holdsAir(i) && world.co2[i] > A.CO2_BAD, 'Zu viel CO₂ in der Luft. Ein CO₂-Filter hilft.');
    this.warn(c, 'health', c.health < 30, c.name + ' geht es sehr schlecht.', c.health > 50);
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

    // 1) Laufbefehl vom Spieler
    if (c.order) {
      if (!c.path.length) {
        c.order = null;
      } else {
        c.task = 'Läuft';
        if (!this.followPath(c, dt)) {
          const p = G.Path.find(this.tileX(c), this.tileY(c), c.order.x, c.order.y);
          if (p) c.path = p; else { c.order = null; c.path = []; }
        }
        return;
      }
    }

    // 2) Schlechte Luft: Luft anhalten und dann weg hier! (unterbricht alles andere)
    const i = this.tileIdx(c);
    c.fleeCooldown = (c.fleeCooldown || 0) - dt;
    if (S.world.o2[i] < G.AIR.O2_LOW && c.needs.air < 50 && !(c.activity && c.activity.flee) && c.fleeCooldown <= 0) {
      c.fleeCooldown = 0.05;
      this.stopActivity(c);
      if (this.startFlee(c)) return;
    }

    // 3) Laufende Tätigkeit
    if (c.activity) { this.doActivity(c, dt); return; }

    // Regelmäßig prüfen, ob ein Bedürfnis dran ist
    c.searchCooldown -= dt;
    const check = c.searchCooldown <= 0;
    if (check) {
      c.searchCooldown = 0.05; // alle 3 Sekunden
      if (this.startNeed(c)) return;
    }

    // 4) Bauplan abarbeiten
    if (c.job) {
      if (S.jobs.get(G.Jobs.key(c.job.x, c.job.y)) !== c.job) {
        this.releaseJob(c);
      } else if (c.path.length) {
        c.task = 'Geht zu: ' + G.Jobs.label(c.job);
        if (!this.followPath(c, dt)) this.releaseJob(c);
        return;
      } else if (this.isNextTo(c, c.job.x, c.job.y)) {
        c.facing = Math.atan2(c.job.y + 0.5 - c.y, c.job.x + 0.5 - c.x);
        c.task = G.Jobs.label(c.job);
        c.job.progress += dt;
        if (c.job.progress >= c.job.need) {
          const done = c.job;
          c.job = null;
          G.Jobs.complete(done);
        }
        return;
      } else {
        this.releaseJob(c);
      }
    }

    // Nichts zu tun: nach Bauplänen suchen
    c.task = S.jobs.size ? 'Kann keinen Bauplan erreichen' : 'Wartet';
    if (check && G.Jobs.assign(c)) c.task = 'Geht zu: ' + G.Jobs.label(c.job);
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
      c.activity = { need, dev: res.target, timer: 0 };
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
      c.task = 'Sucht Luft zum Atmen';
      if (!c.path.length || !this.followPath(c, dt)) this.stopActivity(c);
      return;
    }

    const def = G.NEEDS[a.need];
    const dev = a.dev;
    // Gibt es das Gerät noch?
    if (world.devices.get(world.idx(dev.x, dev.y)) !== dev) { this.stopActivity(c); return; }
    if (c.path.length) {
      c.task = 'Geht zu: ' + G.DEVICES[dev.type].name;
      if (!this.followPath(c, dt)) this.stopActivity(c);
      return;
    }
    if (!this.isNextTo(c, dev.x, dev.y) || !G.Devices.usable(dev)) { this.stopActivity(c); return; }

    c.facing = Math.atan2(dev.y + 0.5 - c.y, dev.x + 0.5 - c.x);
    c.task = def.verb;
    a.timer += dt;

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
