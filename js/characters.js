// ============================================================
// characters.js – Die Charaktere (Crew)
// Ein Charakter läuft entweder zu einem Ziel, das du anklickst,
// oder er sucht sich selbst Baupläne und arbeitet sie ab.
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
      facing: 0,  // Blickrichtung in Bogenmaß
      path: [],   // Liste der nächsten Kacheln
      order: null, // Laufbefehl vom Spieler {x, y}
      job: null,  // aktueller Bauplan
      task: 'Wartet',
      searchCooldown: 0,
    };
  },

  tileX(c) { return Math.floor(c.x); },
  tileY(c) { return Math.floor(c.y); },

  // Spieler gibt einen Laufbefehl
  orderMove(c, tx, ty) {
    const path = G.Path.find(this.tileX(c), this.tileY(c), tx, ty);
    if (!path) return false;
    this.releaseJob(c);
    c.order = { x: tx, y: ty };
    c.path = path;
    return true;
  },

  releaseJob(c) {
    if (c.job) c.job.claimedBy = null;
    c.job = null;
    c.path = [];
  },

  // Läuft den Weg ab. Gibt false zurück, wenn der Weg blockiert ist.
  followPath(c, dt) {
    const world = G.state.world;
    let move = G.WALK_SPEED * dt;
    while (move > 0 && c.path.length) {
      const next = c.path[0];
      if (!world.walkable(next.x, next.y)) return false;
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

  // Wird jeden Simulationsschritt aufgerufen (dt in Spielminuten)
  update(c, dt) {
    const S = G.state;

    // 1) Laufbefehl vom Spieler hat Vorrang
    if (c.order) {
      if (!c.path.length) {
        c.order = null;
      } else {
        c.task = 'Läuft';
        if (!this.followPath(c, dt)) {
          // Weg blockiert: neu planen
          const p = G.Path.find(this.tileX(c), this.tileY(c), c.order.x, c.order.y);
          if (p) c.path = p; else { c.order = null; c.path = []; }
        }
        return;
      }
    }

    // 2) Bauplan abarbeiten
    if (c.job) {
      // Wurde der Plan gelöscht?
      if (S.jobs.get(G.Jobs.key(c.job.x, c.job.y)) !== c.job) {
        this.releaseJob(c);
      } else if (c.path.length) {
        c.task = 'Geht zu: ' + G.Jobs.label(c.job);
        if (!this.followPath(c, dt)) this.releaseJob(c);
        return;
      } else {
        const near = Math.abs(this.tileX(c) - c.job.x) <= 1 && Math.abs(this.tileY(c) - c.job.y) <= 1
          && !(this.tileX(c) === c.job.x && this.tileY(c) === c.job.y);
        if (near) {
          c.facing = Math.atan2(c.job.y + 0.5 - c.y, c.job.x + 0.5 - c.x);
          c.task = G.Jobs.label(c.job);
          c.job.progress += dt;
          if (c.job.progress >= c.job.need) {
            const done = c.job;
            c.job = null;
            G.Jobs.complete(done);
          }
          return;
        }
        this.releaseJob(c);
      }
    }

    // 3) Nichts zu tun: nach Bauplänen suchen
    c.task = S.jobs.size ? 'Kann keinen Bauplan erreichen' : 'Wartet';
    c.searchCooldown -= dt;
    if (c.searchCooldown <= 0) {
      c.searchCooldown = 3;
      if (G.Jobs.assign(c)) c.task = 'Geht zu: ' + G.Jobs.label(c.job);
    }
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

  // Der Charakter an einer Bildschirmposition (in Kacheln)
  at(wx, wy) {
    return G.state.chars.find(c => Math.hypot(c.x - wx, c.y - wy) < 0.5) || null;
  },
};
