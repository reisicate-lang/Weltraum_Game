// ============================================================
// power.js – Stromnetz
// Kabel, die sich berühren (oben/unten/links/rechts), bilden ein
// Netz. Alle Geräte, die auf einem Kabel stehen, hängen daran.
// ============================================================

G.Power = {
  dirty: true,     // muss das Netz neu berechnet werden?
  nets: [],        // Infos pro Netz
  netOf: null,     // Netz-Nummer pro Kachel (-1 = keins)

  rebuild() {
    const world = G.state.world;
    const n = world.w * world.h;
    this.netOf = new Int32Array(n).fill(-1);
    this.nets = [];
    for (let start = 0; start < n; start++) {
      if (!world.cables[start] || this.netOf[start] !== -1) continue;
      const id = this.nets.length;
      this.nets.push({ id, production: 0, demand: 0, charge: 0, capacity: 0, ok: true });
      const stack = [start];
      this.netOf[start] = id;
      while (stack.length) {
        const i = stack.pop();
        const x = i % world.w, y = (i / world.w) | 0;
        for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
          const nx = x + dx, ny = y + dy;
          if (!world.inBounds(nx, ny)) continue;
          const ni = world.idx(nx, ny);
          if (world.cables[ni] && this.netOf[ni] === -1) { this.netOf[ni] = id; stack.push(ni); }
        }
      }
    }
    for (const [i, dev] of world.devices) dev.net = this.netOf[i];
    this.dirty = false;
  },

  update(dt) {
    if (this.dirty) this.rebuild();
    const world = G.state.world;
    for (const net of this.nets) { net.production = 0; net.demand = 0; net.charge = 0; net.capacity = 0; net.batteries = []; net.consumers = []; }

    for (const dev of world.devices.values()) {
      const def = G.DEVICES[dev.type];
      if (dev.net < 0) { dev.powered = false; continue; }
      const net = this.nets[dev.net];
      if (def.power > 0) net.production += def.power;
      if (def.power < 0) { net.demand += -def.power; net.consumers.push(dev); }
      if (dev.type === 'battery') { net.batteries.push(dev); net.charge += dev.charge; net.capacity += def.capacity; }
    }

    for (const net of this.nets) {
      const balance = net.production - net.demand;      // kW
      const energy = Math.abs(balance) * dt / 60;        // kWh in diesem Schritt
      if (balance >= 0) {
        net.ok = true;
        // Überschuss in die Batterien
        let left = energy;
        for (const b of net.batteries) {
          const cap = G.DEVICES.battery.capacity;
          const add = Math.min(left, cap - b.charge);
          b.charge += add; left -= add;
        }
      } else if (net.charge >= energy) {
        net.ok = true;
        // Fehlenden Strom aus den Batterien nehmen
        for (const b of net.batteries) b.charge -= energy * (b.charge / net.charge);
      } else {
        net.ok = false; // Nicht genug Strom: alles aus
      }
      for (const c of net.consumers) c.powered = net.ok;
    }
  },
};
