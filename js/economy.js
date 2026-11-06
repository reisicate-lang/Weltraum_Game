// ============================================================
// economy.js – Geld, Markt und Schulden
// Du bist an der Station "Tycho-Schrottplatz" im Mondorbit angedockt.
// Über das Handelsterminal kaufst und verkaufst du. Die Preise
// schwanken jeden Tag und fallen, wenn du viel von einer Sorte verkaufst.
// Alle 7 Tage ist eine Kreditrate fällig.
// ============================================================

G.Econ = {
  create() {
    const E = G.ECON;
    const prices = {}, supply = {};
    for (const type of Object.keys(G.ITEMS)) { prices[type] = 0.85 + Math.random() * 0.3; supply[type] = 0; }
    return {
      credits: E.START_CREDITS,
      debt: E.START_DEBT,
      nextPayment: E.PAYMENT_DAYS * 1440,  // Spielzeit (Minuten), wann die nächste Rate fällig ist
      strikes: 0,
      prices,       // Preisfaktor pro Sorte (1 = normal)
      supply,       // wie viel du zuletzt verkauft hast (drückt den Preis)
      nextDay: 1440,
      log: [],      // Kontoauszug
      over: false,  // Schiff gepfändet?
    };
  },

  state() { return G.state.econ; },

  // Aktueller Marktpreis für 1 Stück in neuem Zustand
  marketPrice(type) {
    const e = this.state();
    const glut = 1 / (1 + e.supply[type] / 20); // viel verkauft = Preis sinkt
    const st = this.station();
    let local = st ? st.market : 1;
    // Schwarzmarkt: Datenchips bringen dort das Doppelte
    if (st && st.black && type === 'datachip') local *= 2;
    return G.ITEMS[type].value * e.prices[type] * glut * local;
  },
  buyPrice(type) { return Math.ceil(this.marketPrice(type) * G.ECON.BUY_MARKUP); },
  sellPrice(it) { return Math.floor(this.marketPrice(it.type) * G.ECON.SELL_FACTOR * (0.2 + 0.8 * it.cond / 100) * it.qty); },

  book(text, amount) {
    const e = this.state();
    e.log.unshift({ t: G.state.time, text, amount });
    e.log.length = Math.min(e.log.length, 30);
  },

  terminal() {
    return [...G.state.world.devices.values()].find(d => d.type === 'terminal') || null;
  },

  // Handel geht nur, wenn du an einer Station angedockt bist
  station() {
    const n = G.state.nav;
    const loc = n && n.docked ? G.Nav.loc(n.docked) : null;
    return loc && loc.kind === 'station' ? loc : null;
  },

  terminalOnline() {
    const t = this.terminal();
    return !!(t && t.powered && !t.broken && this.station());
  },

  // ---------- Handel ----------
  sell(type, qty) {
    const t = this.terminal();
    if (!t || !this.terminalOnline()) return G.UI.toast('Das Handelsterminal ist offline (kein Strom oder keine Station).', 'bad');
    let total = 0, sold = 0;
    for (const st of G.Items.take(t.inv, type, qty)) {
      total += this.sellPrice(st); sold += st.qty;
    }
    if (!sold) return;
    const e = this.state();
    e.credits += total;
    e.supply[type] += sold;
    this.book('Verkauf: ' + G.ITEMS[type].name + ' ×' + sold, total);
  },

  sellAll() {
    const t = this.terminal();
    if (!t) return;
    for (const type of [...new Set(t.inv.items.map(i => i.type))]) this.sell(type, Infinity);
  },

  buy(type, qty) {
    const t = this.terminal();
    if (!t || !this.terminalOnline()) return G.UI.toast('Das Handelsterminal ist offline (kein Strom oder keine Station).', 'bad');
    const e = this.state();
    const price = this.buyPrice(type);
    const n = Math.min(qty, Math.floor(e.credits / price), G.Items.room(t.inv, type));
    if (n <= 0) return G.UI.toast(e.credits < price ? 'Nicht genug Credits.' : 'Im Terminal ist kein Platz mehr.');
    e.credits -= n * price;
    e.supply[type] -= n * 0.5; // Kaufen hebt die Nachfrage ein wenig
    G.Items.add(t.inv, G.Items.make(type, n, 100));
    this.book('Kauf: ' + G.ITEMS[type].name + ' ×' + n, -n * price);
  },

  // Extra-Zahlung auf den Kredit
  payDebt(amount) {
    const e = this.state();
    const n = Math.min(amount, e.credits, e.debt);
    if (n <= 0) return;
    e.credits -= n; e.debt -= n;
    this.book('Sondertilgung', -n);
    if (e.debt <= 0) G.UI.toast('Der Kredit ist abbezahlt! Das Schiff gehört jetzt dir.');
  },

  // ---------- Bergungsrechte ----------
  buyClaim() {
    const e = this.state();
    if (!this.terminalOnline()) return G.UI.toast('Bergungsrechte gibt es nur an einer Station.', 'bad');
    if (e.credits < G.ECON.CLAIM_FEE) return G.UI.toast('Nicht genug Credits für ein Bergungsrecht.');
    if (!G.Wreck.clearable()) return G.UI.toast('Erst alle Crewmitglieder vom Wrack holen.');
    e.credits -= G.ECON.CLAIM_FEE;
    this.book('Bergungsrecht für neues Wrack', -G.ECON.CLAIM_FEE);
    G.Wreck.clear();
    G.Wreck.generate();
    G.UI.toast('Ein neues Wrack wurde an die Bergungsleine geschleppt.');
  },

  scrapHull() {
    if (!this.terminalOnline()) return G.UI.toast('Verschrotten geht nur an einer Station.', 'bad');
    if (!G.Wreck.clearable()) return G.UI.toast('Erst alle Crewmitglieder vom Wrack holen.');
    const value = G.Wreck.hullValue();
    this.state().credits += value;
    this.book('Wrack verschrottet', value);
    G.Wreck.clear();
    G.UI.toast('Das Wrack wurde verschrottet. Kauf ein neues Bergungsrecht, um weiterzumachen.');
  },

  // ---------- Zeit: Preise, Gebühren, Raten ----------
  update() {
    const e = this.state(), E = G.ECON, S = G.state;
    if (e.over) return;
    // Neuer Tag: Preise schwanken, Überangebot baut sich ab, Liegegebühr
    while (S.time >= e.nextDay) {
      e.nextDay += 1440;
      for (const type of Object.keys(e.prices)) {
        e.prices[type] = Math.min(1.6, Math.max(0.5, e.prices[type] * (1 + (Math.random() * 2 - 1) * E.DRIFT)));
        e.supply[type] *= 0.7;
      }
      if (this.station()) {
        if (e.credits >= E.DOCK_FEE) { e.credits -= E.DOCK_FEE; this.book('Liegegebühr ' + this.station().name, -E.DOCK_FEE); }
        else { e.debt += E.DOCK_FEE; this.book('Liegegebühr: kein Geld, ' + E.DOCK_FEE + ' Cr auf die Schulden', 0); }
      }
    }
    // Kreditrate
    if (e.debt > 0 && S.time >= e.nextPayment) {
      e.nextPayment += E.PAYMENT_DAYS * 1440;
      const rate = Math.min(E.PAYMENT, e.debt);
      if (e.credits >= rate) {
        e.credits -= rate; e.debt -= rate;
        this.book('Kreditrate', -rate);
        G.UI.toast('Kreditrate bezahlt: ' + rate + ' Cr.');
      } else {
        e.strikes++;
        const fee = Math.round(e.debt * E.LATE_FEE);
        e.debt += fee;
        this.book('Rate verpasst: ' + fee + ' Cr Strafzins auf die Schulden', 0);
        if (e.strikes >= E.MAX_STRIKES) {
          e.over = true;
          G.setSpeed(0);
          G.UI.gameOver();
        } else {
          G.UI.toast(`Rate verpasst! ${fee} Cr Strafzins. Noch ${E.MAX_STRIKES - e.strikes} verpasste Rate(n) bis zur Pfändung.`, 'bad');
        }
      }
    }
  },

  // ---------- Werkbank ----------
  craftJob(recipeId) {
    const S = G.state;
    const bench = [...S.world.devices.values()].find(d => d.type === 'workbench');
    if (!bench) return G.UI.toast('Du brauchst eine Werkbank.');
    const key = S.world.idx(bench.x, bench.y);
    if (S.jobs.has(key)) return G.UI.toast('An der Werkbank wird schon gearbeitet.');
    const r = G.RECIPES.find(x => x.id === recipeId);
    for (const [type, qty] of Object.entries(r.in)) {
      if (G.Items.available(type) + S.chars.reduce((s, c) => s + G.Items.count(c.inv, type), 0) < qty) {
        return G.UI.toast('Nicht genug ' + G.ITEMS[type].name + ' im Lager.');
      }
    }
    S.jobs.set(key, { kind: 'craft', recipe: r.id, x: bench.x, y: bench.y, need: r.time, progress: 0, claimedBy: null, retryAt: 0 });
    G.UI.toast('Auftrag an der Werkbank: ' + r.name);
  },
};
