// ============================================================
// items.js – Gegenstände und Inventare
// Alle Gegenstände sind hier als Daten beschrieben. Neue Sorten
// kann man einfach unten in G.ITEMS ergänzen.
//   weight = kg pro Stück, volume = Liter pro Stück, value = Preis in Credits (neu)
// ============================================================

G.ITEMS = {
  scrap:    { name: 'Schrott',            weight: 3,   volume: 3,  value: 4,   desc: 'Verbogenes Metall. Taugt zum Einschmelzen.' },
  plate:    { name: 'Stahlplatte',        weight: 8,   volume: 4,  value: 18,  desc: 'Für Böden, Wände und Gehäuse.' },
  copper:   { name: 'Kupferkabel',        weight: 1.5, volume: 1,  value: 12,  desc: 'Für Stromleitungen.' },
  circuit:  { name: 'Platine',            weight: 0.4, volume: 0.5, value: 45, desc: 'Steuerelektronik für Türen und Geräte.' },
  motor:    { name: 'Elektromotor',       weight: 6,   volume: 4,  value: 90,  desc: 'Für Pumpen, Lüfter und Generatoren.' },
  cell:     { name: 'Akkuzelle',          weight: 2,   volume: 1,  value: 60,  desc: 'Speichert Strom. Für Batterien und Ladestationen.' },
  pipe:     { name: 'Rohrstück',          weight: 2,   volume: 2,  value: 10,  desc: 'Für Luft- und Wasserleitungen.' },
  glass:    { name: 'Panzerglas',         weight: 5,   volume: 3,  value: 30,  desc: 'Für Solarpanels und Fenster.' },
  filter:   { name: 'Filterkartusche',    weight: 1,   volume: 1.5, value: 35, desc: 'Für CO₂-Filter und Wasseraufbereitung.' },
  fabric:   { name: 'Stoff',              weight: 1,   volume: 2,  value: 8,   desc: 'Für Betten und Anzüge.' },
  datachip: { name: 'Datenchip',          weight: 0.05, volume: 0.1, value: 150, desc: 'Gespeicherte Daten. Manche zahlen viel dafür.' },
  ration:   { name: 'Essensration',       weight: 0.5, volume: 0.6, value: 6,  desc: 'Füllt den Vorratsschrank um 1 Ration auf.', refill: { food: 1 } },
  watercan: { name: 'Wasserkanister',     weight: 10,  volume: 10, value: 8,   desc: 'Füllt einen Wasserspender oder ein Waschbecken um 10 L auf.', refill: { water: 10, sink: 10 } },
  fuelcan:  { name: 'Brennstoffkanister', weight: 12,  volume: 10, value: 40,  desc: 'Füllt den Generator um 40 Brennstoff auf.', refill: { generator: 40 } },
  aircan:   { name: 'Druckluftflasche',   weight: 15,  volume: 12, value: 50,  desc: 'Füllt einen Lufttank um 800 kPa auf.', refill: { airtank: 800 } },
};

G.Items = {
  // Ein Stapel: { type, qty, cond }   cond = Zustand in Prozent
  make(type, qty = 1, cond = 100) { return { type, qty, cond }; },

  newInv(maxWeight = Infinity, maxVolume = Infinity) { return { items: [], maxWeight, maxVolume }; },

  weight(inv) { return inv.items.reduce((s, it) => s + G.ITEMS[it.type].weight * it.qty, 0); },
  volume(inv) { return inv.items.reduce((s, it) => s + G.ITEMS[it.type].volume * it.qty, 0); },
  // Marktwert: neuer Preis, abhängig vom Zustand
  value(it) { return Math.round(G.ITEMS[it.type].value * it.qty * (0.25 + 0.75 * it.cond / 100)); },
  count(inv, type) { return inv.items.reduce((s, it) => s + (it.type === type ? it.qty : 0), 0); },

  // Wie viele Stück passen noch hinein?
  room(inv, type) {
    const d = G.ITEMS[type];
    const w = (inv.maxWeight - this.weight(inv)) / d.weight;
    const v = (inv.maxVolume - this.volume(inv)) / d.volume;
    return Math.max(0, Math.floor(Math.min(w, v) + 1e-9));
  },

  // Legt einen Stapel hinein. Gibt zurück, wie viel hineingepasst hat.
  add(inv, stack) {
    const qty = Math.min(stack.qty, this.room(inv, stack.type));
    if (qty <= 0) return 0;
    // Gleiche Sorte mit ähnlichem Zustand zusammenlegen
    const same = inv.items.find(it => it.type === stack.type && Math.abs(it.cond - stack.cond) < 15);
    if (same) {
      same.cond = (same.cond * same.qty + stack.cond * qty) / (same.qty + qty);
      same.qty += qty;
    } else {
      inv.items.push({ type: stack.type, qty, cond: stack.cond });
    }
    return qty;
  },

  // Nimmt bis zu qty Stück einer Sorte heraus (bester Zustand zuerst)
  take(inv, type, qty) {
    const out = [];
    const stacks = inv.items.filter(it => it.type === type).sort((a, b) => b.cond - a.cond);
    for (const it of stacks) {
      if (qty <= 0) break;
      const n = Math.min(qty, it.qty);
      it.qty -= n; qty -= n;
      out.push({ type, qty: n, cond: it.cond });
    }
    inv.items = inv.items.filter(it => it.qty > 0);
    return out;
  },

  // Bewegt Gegenstände von einem Inventar ins andere. Gibt die bewegte Menge zurück.
  move(from, to, type, qty) {
    const n = Math.min(qty, this.count(from, type), this.room(to, type));
    if (n <= 0) return 0;
    for (const st of this.take(from, type, n)) this.add(to, st);
    return n;
  },

  // Fehlende Materialien: { type: menge }
  missing(cost, inv) {
    const out = {};
    for (const [type, qty] of Object.entries(cost || {})) {
      const have = this.count(inv, type);
      if (have < qty) out[type] = qty - have;
    }
    return out;
  },

  // ---------- Gegenstände in der Welt ----------

  // Alle Lager in der Welt: Kisten und Haufen auf dem Boden
  sources() {
    const world = G.state.world, out = [];
    for (const dev of world.devices.values()) if (dev.inv) out.push({ x: dev.x, y: dev.y, inv: dev.inv, dev });
    for (const [i, inv] of world.piles) out.push({ x: i % world.w, y: (i / world.w) | 0, inv, pile: true });
    return out;
  },

  // Wie viele Stück gibt es irgendwo in der Welt (ohne getragene)?
  available(type) {
    return this.sources().reduce((s, src) => s + this.count(src.inv, type), 0);
  },

  // Gegenstände auf den Boden legen (bildet einen Haufen)
  drop(x, y, stack) {
    const world = G.state.world;
    const i = world.idx(x, y);
    let pile = world.piles.get(i);
    if (!pile) { pile = this.newInv(); world.piles.set(i, pile); }
    this.add(pile, stack);
  },

  // Leere Haufen entfernen
  cleanPiles() {
    const world = G.state.world;
    for (const [i, inv] of world.piles) if (!inv.items.length) world.piles.delete(i);
  },

  label(it) {
    const d = G.ITEMS[it.type];
    return d.name + (it.qty > 1 ? ' ×' + it.qty : '');
  },
};
