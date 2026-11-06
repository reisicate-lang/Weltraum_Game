// ============================================================
// devices.js – Geräte (Generator, Betten, Sauerstoff, ...)
// ============================================================

G.Devices = {
  create(type, x, y) {
    const def = G.DEVICES[type];
    const dev = { type, x, y, claimedBy: null, powered: false, net: -1 };
    if (def.stock !== undefined) dev.stock = def.stock;
    if (def.capacity !== undefined) dev.charge = def.capacity * 0.5;
    return dev;
  },

  needsPower(dev) { return (G.DEVICES[dev.type].power || 0) < 0; },

  // Kann ein Charakter das Gerät gerade benutzen?
  usable(dev) {
    if (dev.stock !== undefined && dev.stock <= 0) return false;
    if (this.needsPower(dev) && !dev.powered) return false;
    return true;
  },

  // Geräte arbeiten lassen (dt in Spielminuten)
  update(dt) {
    const world = G.state.world, A = G.AIR;
    for (const [i, dev] of world.devices) {
      switch (dev.type) {
        case 'o2gen':
          if (dev.powered && world.o2[i] < A.O2) world.o2[i] = Math.min(A.O2, world.o2[i] + A.O2GEN_RATE * dt);
          break;
        case 'scrubber':
          if (dev.powered && world.co2[i] > A.CO2) world.co2[i] = Math.max(A.CO2, world.co2[i] - A.SCRUB_RATE * dt);
          break;
        case 'airtank':
          if (dev.stock > 0 && world.pressure(i) < A.TANK_TARGET) {
            const add = Math.min(dev.stock, A.TANK_RATE * dt);
            world.o2[i] += add * 0.21;
            world.n2[i] += add * 0.79;
            dev.stock -= add;
          }
          break;
      }
    }
  },

  // Kurzer Statustext für die Anzeige
  status(dev) {
    const def = G.DEVICES[dev.type];
    const parts = [def.name];
    if (this.needsPower(dev)) parts.push(dev.powered ? 'läuft' : 'kein Strom');
    if (dev.type === 'generator') parts.push(dev.net >= 0 ? 'liefert 6 kW' : 'nicht am Kabel');
    if (dev.type === 'battery') parts.push(dev.charge.toFixed(1) + ' / ' + def.capacity + ' kWh' + (dev.net < 0 ? ', nicht am Kabel' : ''));
    if (dev.stock !== undefined) parts.push('Vorrat: ' + Math.floor(dev.stock) + ' ' + def.unit);
    return parts.join(' · ');
  },
};
