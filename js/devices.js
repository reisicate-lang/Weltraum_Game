// ============================================================
// devices.js – Geräte (Generator, Betten, Sauerstoff, ...)
// ============================================================

G.Devices = {
  create(type, x, y) {
    const def = G.DEVICES[type];
    const dev = { type, x, y, claimedBy: null, powered: false, net: -1, cond: 100, broken: false };
    if (def.stock !== undefined) dev.stock = def.stock;
    if (def.capacity !== undefined) dev.charge = def.capacity * 0.5;
    if (type === 'locker') dev.suit = { o2: 100, battery: 100 };
    if (type === 'pump') { dev.store = 1000; dev.request = null; }
    if (def.storage) dev.inv = G.Items.newInv(Infinity, def.storage);
    return dev;
  },

  needsPower(dev) { return (G.DEVICES[dev.type].power || 0) < 0; },

  // Kann ein Charakter das Gerät gerade benutzen?
  usable(dev) {
    if (dev.broken) return false;
    if (dev.stock !== undefined && dev.stock <= 0) return false;
    if (this.needsPower(dev) && !dev.powered) return false;
    return true;
  },

  // Geräte arbeiten lassen (dt in Spielminuten)
  update(dt) {
    const world = G.state.world, A = G.AIR, D = G.DAMAGE;
    for (const [i, dev] of world.devices) {
      const def = G.DEVICES[dev.type];
      // Verschleiß bei laufenden Geräten
      const running = (this.needsPower(dev) && dev.powered) || dev.producing;
      if (def.wears && running && !dev.broken) {
        dev.cond -= D.WEAR_PER_DAY * dt / 1440;
        if (dev.cond <= 0) {
          dev.cond = 0; dev.broken = true;
          G.UI.toast(def.name + ' ist kaputt gegangen!', 'bad');
          G.Damage.requestRepair(dev.x, dev.y);
        }
      }
      if (dev.broken) continue;

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
        case 'locker':
          // Gelagerten Anzug auffüllen
          if (dev.powered && dev.suit) {
            dev.suit.o2 = Math.min(100, dev.suit.o2 + G.SUIT.REFILL * dt);
            dev.suit.battery = Math.min(100, dev.suit.battery + G.SUIT.REFILL * dt);
          }
          break;
      }
    }
  },

  // Kurzer Statustext für die Anzeige
  status(dev) {
    const def = G.DEVICES[dev.type];
    const parts = [def.name];
    if (dev.broken) parts.push('KAPUTT');
    else if (dev.cond < 100) parts.push('Zustand ' + Math.round(dev.cond) + ' %');
    if (this.needsPower(dev) && !dev.broken) parts.push(dev.powered ? 'läuft' : 'kein Strom');
    if (dev.type === 'generator') parts.push(dev.net < 0 ? 'nicht am Kabel' : dev.producing ? 'liefert 6 kW' : 'liefert nichts');
    if (dev.type === 'solar') parts.push(dev.producing ? 'liefert 1,5 kW' : 'muss draußen im Vakuum stehen');
    if (def.capacity) parts.push(dev.charge.toFixed(1) + ' / ' + def.capacity + ' kWh' + (dev.net < 0 && dev.type === 'battery' ? ', nicht am Kabel' : ''));
    if (dev.stock !== undefined) parts.push('Vorrat: ' + Math.floor(dev.stock) + ' ' + def.unit);
    if (dev.type === 'locker') parts.push(dev.suit ? `Anzug: O₂ ${Math.round(dev.suit.o2)} %, Akku ${Math.round(dev.suit.battery)} %` : 'leer (Anzug ist unterwegs)');
    if (dev.inv) parts.push(`${Math.round(G.Items.volume(dev.inv))} / ${G.DEVICES[dev.type].storage} L belegt`);
    if (dev.type === 'pump') {
      const lock = G.Airlock.lockOfPump(dev);
      parts.push(lock ? `Schleuse ${Math.round(G.Airlock.pressure(lock))} kPa` : 'steht in keinem kleinen geschlossenen Raum');
      parts.push('Speicher ' + Math.round(dev.store) + ' kPa');
    }
    return parts.join(' · ');
  },
};
