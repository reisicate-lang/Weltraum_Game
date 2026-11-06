// ============================================================
// nav.js – Raumfahrt: Schiffsphysik im Erde-Mond-System
// Das Schiff ist ein Punkt im Raum mit Position, Geschwindigkeit
// und Ausrichtung. Erde und Mond ziehen es an (Schwerkraft).
// Triebwerke beschleunigen in Blickrichtung (Trägheit: ohne
// Gegenschub fliegt das Schiff einfach weiter).
// Einheiten: km, km/s, Sekunden.
// ============================================================

G.Nav = {
  create() {
    const loc = this.loc('tycho');
    const p = this.locState(loc, 0);
    return { x: p.x, y: p.y, vx: p.vx, vy: p.vy, angle: 0, docked: 'tycho', travel: null, autodock: null,
      thrust: 0, turn: 0, warned: false, crashed: false };
  },

  loc(id) { return G.LOCATIONS.find(l => l.id === id) || null; },

  // Position und Geschwindigkeit eines Ortes zur Spielzeit (Sekunden)
  locState(loc, secs) {
    if (loc.body) {
      const b = G.SPACE[loc.body];
      const w = Math.sqrt(b.gm / loc.radius ** 3); // Winkelgeschwindigkeit der Kreisbahn
      const a = loc.phase + w * secs;
      return {
        x: b.x + Math.cos(a) * loc.radius, y: b.y + Math.sin(a) * loc.radius,
        vx: -Math.sin(a) * loc.radius * w, vy: Math.cos(a) * loc.radius * w,
      };
    }
    return { x: loc.x, y: loc.y, vx: 0, vy: 0 };
  },

  secs() { return G.state.time * 60; },

  // Schwerkraft von Erde und Mond an einem Punkt (km/s²)
  gravity(x, y) {
    let ax = 0, ay = 0;
    for (const b of [G.SPACE.EARTH, G.SPACE.MOON]) {
      const dx = b.x - x, dy = b.y - y;
      const r2 = dx * dx + dy * dy, r = Math.sqrt(r2);
      const a = b.gm / r2;
      ax += a * dx / r; ay += a * dy / r;
    }
    return { ax, ay };
  },

  // ---------- Schiff: Masse, Triebwerke, Treibstoff ----------
  shipDevices(type) {
    const world = G.state.world;
    return [...world.devices.values()].filter(d => d.type === type && world.zone[world.idx(d.x, d.y)] !== 1);
  },

  // Masse in Tonnen: Rumpf, Geräte, Ladung
  mass() {
    const world = G.state.world;
    let m = 0;
    for (let i = 0; i < world.tiles.length; i++) if (world.tiles[i] && world.zone[i] !== 1) m += 0.2;
    for (const d of world.devices.values()) {
      if (world.zone[world.idx(d.x, d.y)] === 1) continue;
      m += 0.5;
      if (d.inv) m += G.Items.weight(d.inv) / 1000;
    }
    return m;
  },

  fuel() { return this.shipDevices('fueltank').reduce((s, d) => s + (d.broken ? 0 : d.stock), 0); },

  useFuel(amount) {
    for (const t of this.shipDevices('fueltank')) {
      if (amount <= 0) break;
      if (t.broken) continue;
      const n = Math.min(t.stock, amount);
      t.stock -= n; amount -= n;
    }
  },

  // Schub in kN, den die funktionierenden Triebwerke gerade liefern könnten
  maxThrust() {
    return this.shipDevices('thruster').filter(t => t.powered && !t.broken).length * G.DEVICES.thruster.thrust;
  },

  helmOk() { return this.shipDevices('helm').some(h => h.powered && !h.broken); },
  autodockOk() { return this.shipDevices('autodock').some(h => h.powered && !h.broken); },

  // Pilot-Können verbessert Treibstoffverbrauch (siehe Fähigkeiten)
  fuelFactor() { return G.Skills ? G.Skills.pilotFuelFactor() : 1; },

  // ---------- Simulation ----------
  update(dt) {
    const n = G.state.nav;
    if (!n || n.crashed) return;
    const secs = dt * 60, T = this.secs();

    if (n.docked) {
      const p = this.locState(this.loc(n.docked), T);
      Object.assign(n, { x: p.x, y: p.y, vx: p.vx, vy: p.vy });
      return;
    }

    if (n.travel) {
      const tr = n.travel;
      const f = Math.min(1, (T - tr.t0) / (tr.t1 - tr.t0));
      const to = this.locState(this.loc(tr.to), T);
      n.x = tr.x0 + (to.x - tr.x0) * f; n.y = tr.y0 + (to.y - tr.y0) * f;
      n.angle = Math.atan2(to.y - tr.y0, to.x - tr.x0);
      if (f >= 1) { n.travel = null; this.dock(tr.to, true); G.UI.toast('Angekommen: ' + this.loc(tr.to).name); }
      return;
    }

    if (n.autodock) {
      const ad = n.autodock;
      const to = this.locState(this.loc(ad.to), T);
      const f = Math.min(1, (T - ad.t0) / (ad.t1 - ad.t0));
      n.x += (to.x - n.x) * f; n.y += (to.y - n.y) * f;
      n.vx += (to.vx - n.vx) * f; n.vy += (to.vy - n.vy) * f;
      if (f >= 1) { n.autodock = null; this.dock(ad.to, true); }
      return;
    }

    const g = this.gravity(n.x, n.y);
    let ax = g.ax, ay = g.ay;
    // "Angleichen": Triebwerke bremsen die Geschwindigkeit relativ zum Ziel ab
    if (n.match) {
      const r = this.relTo(n.match);
      const dvx = r.p.vx - n.vx, dvy = r.p.vy - n.vy, dv = Math.hypot(dvx, dvy);
      const amax = this.maxThrust() / this.mass() / 1000;
      if (dv < 0.0005 || amax <= 0 || !this.helmOk()) { n.match = null; }
      else {
        const a = Math.min(amax, dv / secs);
        const fuelNeed = this.shipDevices('thruster').filter(t => t.powered && !t.broken).length * G.SPACE.BURN * (a / amax) * dt * this.fuelFactor();
        if (this.fuel() >= fuelNeed) {
          this.useFuel(fuelNeed);
          n.vx += dvx / dv * a * secs; n.vy += dvy / dv * a * secs;
          n.angle = Math.atan2(dvy, dvx);
        } else n.match = null;
      }
    }
    if (n.thrust !== 0 && this.helmOk()) {
      const thrust = this.maxThrust();
      const fuelNeed = this.shipDevices('thruster').filter(t => t.powered && !t.broken).length
        * G.SPACE.BURN * Math.abs(n.thrust) * dt * this.fuelFactor();
      if (thrust > 0 && this.fuel() >= fuelNeed) {
        this.useFuel(fuelNeed);
        const a = thrust / this.mass() / 1000 * n.thrust; // kN / t = m/s², /1000 = km/s²
        ax += Math.cos(n.angle) * a; ay += Math.sin(n.angle) * a;
        if (G.Skills) for (const c of G.state.chars) if (c.atHelm) G.Skills.train(c, 'pilot', secs / 60 * 0.5);
      } else if (!n.noFuelWarned) {
        n.noFuelWarned = true;
        G.UI.toast(thrust > 0 ? 'Kein Treibstoff!' : 'Keine Triebwerke mit Strom!', 'bad');
      }
    } else n.noFuelWarned = false;
    // Halb-implizites Euler-Verfahren: stabil für Umlaufbahnen
    n.vx += ax * secs; n.vy += ay * secs;
    n.x += n.vx * secs; n.y += n.vy * secs;

    this.checkHazards();
  },

  checkHazards() {
    const n = G.state.nav, S = G.SPACE, T = this.secs();
    const altE = Math.hypot(n.x - S.EARTH.x, n.y - S.EARTH.y) - S.EARTH.r;
    const altM = Math.hypot(n.x - S.MOON.x, n.y - S.MOON.y) - S.MOON.r;
    if (altE < S.WARN_ALT && !n.warned) { n.warned = true; G.UI.toast('Warnung: Die Schwerkraft der Erde zieht das Schiff an! Gegenschub geben.', 'bad'); }
    if (altE > S.WARN_ALT * 1.5) n.warned = false;
    if (altE < S.CRASH_ALT || altM < S.MOON_CRASH_ALT) {
      n.crashed = true;
      G.setSpeed(0);
      G.UI.gameOver(altE < S.CRASH_ALT
        ? 'Die Erde hat dein Schiff nicht mehr losgelassen. Beim Eintritt in die Atmosphäre ist es verglüht.'
        : 'Dein Schiff ist auf der Mondoberfläche zerschellt.', 'Abgestürzt');
      return;
    }
    // Zusammenstoß mit einer Station
    for (const loc of G.LOCATIONS) {
      if (loc.kind !== 'station') continue;
      const p = this.locState(loc, T);
      const d = Math.hypot(p.x - n.x, p.y - n.y);
      const rv = Math.hypot(p.vx - n.vx, p.vy - n.vy);
      if (d < 0.05 && rv > S.COLLIDE_SPEED) {
        const hits = Math.min(6, Math.ceil(rv / S.COLLIDE_SPEED));
        for (let k = 0; k < hits; k++) G.Damage.strike(true);
        n.vx = p.vx; n.vy = p.vy;
        G.UI.toast('Zusammenstoß mit ' + loc.name + '! Die Hülle ist beschädigt.', 'bad');
      }
    }
  },

  // ---------- Andocken, Abdocken, Reisen ----------
  // Entfernung und Geschwindigkeitsunterschied zu einem Ort
  relTo(id) {
    const n = G.state.nav, p = this.locState(this.loc(id), this.secs());
    return { dist: Math.hypot(p.x - n.x, p.y - n.y), speed: Math.hypot(p.vx - n.vx, p.vy - n.vy), p };
  },

  nearest() {
    let best = null;
    for (const loc of G.LOCATIONS) {
      const r = this.relTo(loc.id);
      if (!best || r.dist < best.dist) best = { loc, ...r };
    }
    return best;
  },

  canDock(id) {
    const r = this.relTo(id);
    return r.dist < G.SPACE.DOCK_DIST && r.speed < G.SPACE.DOCK_SPEED;
  },

  dock(id, force) {
    const n = G.state.nav;
    if (!force && !this.canDock(id)) return false;
    n.docked = id; n.thrust = 0; n.turn = 0;
    G.Fleet.arrive(this.loc(id));
    if (G.Skills) for (const c of G.state.chars) if (c.atHelm) G.Skills.train(c, 'pilot', force ? 0.3 : 3);
    G.UI.toast('Angedockt: ' + this.loc(id).name);
    return true;
  },

  undock() {
    const n = G.state.nav;
    if (!n.docked) return true;
    if (!this.helmOk()) { G.UI.toast('Das Steuerpult braucht Strom.', 'bad'); return false; }
    if (!G.Wreck.clearable()) { G.UI.toast('Erst alle Crewmitglieder vom Wrack holen.'); return false; }
    const loc = this.loc(n.docked);
    G.Fleet.leave(loc);
    n.docked = null;
    // Leicht wegdriften
    n.vx += Math.cos(n.angle + Math.PI) * 0.003; n.vy += Math.sin(n.angle + Math.PI) * 0.003;
    G.UI.toast('Abgedockt von ' + loc.name + '.');
    return true;
  },

  startAutodock() {
    const n = G.state.nav;
    if (!this.autodockOk()) return G.UI.toast('Kein funktionierendes Auto-Dock-Modul an Bord.', 'bad');
    const near = this.nearest();
    if (near.dist > G.SPACE.AUTODOCK_DIST || near.speed > G.SPACE.AUTODOCK_SPEED) {
      return G.UI.toast(`Zu weit weg oder zu schnell (höchstens ${G.SPACE.AUTODOCK_DIST} km und ${G.SPACE.AUTODOCK_SPEED * 1000} m/s).`);
    }
    const fuel = (5 + near.speed * 60) * this.fuelFactor();
    if (this.fuel() < fuel) return G.UI.toast('Nicht genug Treibstoff zum Andocken.', 'bad');
    this.useFuel(fuel);
    n.autodock = { to: near.loc.id, t0: this.secs(), t1: this.secs() + 300 + near.dist * 5 };
    G.UI.toast('Auto-Dock läuft: ' + near.loc.name);
  },

  travelInfo(id) {
    const n = G.state.nav, r = this.relTo(id);
    return { dist: r.dist, fuel: r.dist * G.SPACE.TRAVEL_FUEL * this.fuelFactor(), secs: r.dist / G.SPACE.TRAVEL_SPEED + 600 };
  },

  travel(id) {
    const n = G.state.nav;
    if (!this.helmOk()) return G.UI.toast('Das Steuerpult braucht Strom.', 'bad');
    if (n.docked === id) return;
    const info = this.travelInfo(id);
    if (this.maxThrust() <= 0) return G.UI.toast('Keine Triebwerke mit Strom.', 'bad');
    if (this.fuel() < info.fuel) return G.UI.toast(`Zu wenig Treibstoff (${Math.ceil(info.fuel)} nötig).`, 'bad');
    if (!this.undock()) return;
    this.useFuel(info.fuel);
    n.travel = { to: id, t0: this.secs(), t1: this.secs() + info.secs, x0: n.x, y0: n.y };
    G.UI.toast(`Schnellreise nach ${this.loc(id).name}: ${(info.secs / 3600).toFixed(1)} Stunden.`);
  },

  status() {
    const n = G.state.nav;
    if (n.docked) return 'Angedockt: ' + this.loc(n.docked).name;
    if (n.travel) return 'Unterwegs nach ' + this.loc(n.travel.to).name;
    if (n.autodock) return 'Dockt an: ' + this.loc(n.autodock.to).name;
    return 'Im freien Flug';
  },
};
