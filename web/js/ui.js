// ============================================================
// ui.js – Menüs und Anzeigen über dem Spielfeld
// ============================================================

G.UI = {
  init() {
    this.el = {
      clock: document.getElementById('clock'),
      day: document.getElementById('day'),
      speeds: [...document.querySelectorAll('[data-speed]')],
      hint: document.getElementById('tool-hint'),
      crew: document.getElementById('crew'),
      needs: document.getElementById('needs'),
      hoverInfo: document.getElementById('hover-info'),
      jobCount: document.getElementById('job-count'),
      toasts: document.getElementById('toasts'),
      help: document.getElementById('help'),
      newGame: document.getElementById('btn-new'),
      devMenu: document.getElementById('dev-menu'),
      devButton: document.getElementById('btn-devices'),
      views: [...document.querySelectorAll('[data-view]')],
      power: document.getElementById('power-info'),
      inv: document.getElementById('inv'),
      box: document.getElementById('box'),
      panel: document.getElementById('panel'),
      money: document.getElementById('money'),
    };
    this.panelKind = null;
    this.tradeTab = 'sell';
    this.lastPanelHtml = '';
    this.el.panel.addEventListener('click', e => this.onPanelButton(e));
    document.getElementById('btn-restart').addEventListener('click', () => {
      document.getElementById('gameover').hidden = true;
      G.newGame();
      G.setSpeed(1);
    });

    // Geräte-Menü aus der Liste in config.js füllen
    this.el.devMenu.innerHTML = Object.entries(G.DEVICES).map(([type, d]) => `
      <button type="button" data-tool="dev:${type}">
        <span class="dm-name">${d.name}</span>
        <span class="dm-desc">${d.desc}</span>
        <span class="dm-cost">${this.costText(d.cost)}</span>
      </button>`).join('');
    this.el.tools = [...document.querySelectorAll('[data-tool]')];

    this.el.speeds.forEach(b => b.addEventListener('click', () => G.setSpeed(Number(b.dataset.speed))));
    this.el.tools.forEach(b => b.addEventListener('click', () => { this.setTool(b.dataset.tool); this.showDevMenu(false); }));
    this.el.devButton.addEventListener('click', () => this.showDevMenu());
    this.el.views.forEach(b => b.addEventListener('click', () => this.setView(b.dataset.view)));
    document.getElementById('btn-save').addEventListener('click', () => G.Save.save());
    document.getElementById('btn-load').addEventListener('click', () => G.Save.load());
    document.getElementById('btn-help').addEventListener('click', () => this.showHelp());
    document.getElementById('help-close').addEventListener('click', () => this.showHelp(false));

    // "Neues Spiel" braucht einen zweiten Klick zur Sicherheit
    let armed = null;
    this.el.newGame.addEventListener('click', () => {
      if (armed) {
        clearTimeout(armed); armed = null;
        this.el.newGame.textContent = 'Neues Spiel';
        G.newGame();
        this.toast('Neues Spiel gestartet.');
      } else {
        this.el.newGame.textContent = 'Wirklich? Nochmal klicken';
        armed = setTimeout(() => { armed = null; this.el.newGame.textContent = 'Neues Spiel'; }, 3000);
      }
    });

    // Knöpfe im Gepäck und im Kisten-Fenster
    this.el.inv.addEventListener('click', e => this.onItemButton(e));
    this.el.box.addEventListener('click', e => this.onItemButton(e));
    this.lastInvHtml = '';
    this.lastBoxHtml = '';

    this.el.crew.addEventListener('click', e => {
      const card = e.target.closest('[data-char]');
      if (!card) return;
      const c = G.state.chars.find(ch => ch.id === Number(card.dataset.char));
      if (!c) return;
      G.state.selectedId = c.id;
      G.state.camera.x = c.x; G.state.camera.y = c.y;
    });

    this.setTool('select');
    this.setView(G.state.view || 'normal');
    this.lastCrewHtml = '';
    this.lastNeedsHtml = '';
  },

  setTool(tool) {
    G.state.tool = tool;
    G.Input.dragStart = null;
    this.el.tools.forEach(b => b.classList.toggle('active', b.dataset.tool === tool));
    this.el.devButton.classList.toggle('active', tool.startsWith('dev:'));
    this.el.devButton.querySelector('.t-name').textContent = tool.startsWith('dev:') ? G.TOOLS[tool].name : 'Geräte';
    const cost = tool.startsWith('dev:') ? G.DEVICES[tool.slice(4)].cost
      : { floor: G.TILE_INFO[1].cost, wall: G.TILE_INFO[2].cost, door: G.TILE_INFO[3].cost, cable: G.CABLE_COST }[tool];
    this.el.hint.textContent = G.TOOLS[tool].hint + (cost ? '  ' + this.costText(cost) : '');
    document.body.dataset.tool = tool;
    // Beim Kabel-Verlegen automatisch die Strom-Ansicht zeigen
    if (tool === 'cable') this.setView('power');
  },

  setView(view) {
    G.state.view = view;
    this.el.views.forEach(b => b.classList.toggle('active', b.dataset.view === view));
  },

  showDevMenu(show) {
    const m = this.el.devMenu;
    m.hidden = show === undefined ? !m.hidden : !show;
  },

  costText(cost) {
    if (!cost) return '';
    return 'Kosten: ' + Object.entries(cost).map(([t, q]) => q + '× ' + G.ITEMS[t].name).join(', ');
  },

  // ---------- Gepäck und Kisten ----------

  toggleInv() { document.body.classList.toggle('inv-hidden'); },

  // Taste E: nächste Kiste oder nächsten Haufen neben deiner Figur öffnen
  interact() {
    const p = G.player();
    if (!p) return;
    const srcs = G.Items.sources().filter(s => G.Chars.canReach(p, s));
    if (!srcs.length) { this.toast('Hier ist nichts zum Durchsuchen. Stell dich neben eine Kiste oder einen Haufen.'); return; }
    srcs.sort((a, b) => Math.hypot(a.x + 0.5 - p.x, a.y + 0.5 - p.y) - Math.hypot(b.x + 0.5 - p.x, b.y + 0.5 - p.y));
    this.openSource(srcs[0].x, srcs[0].y);
  },

  openSource(x, y) {
    G.state.openSource = { x, y };
    this.el.box.hidden = false;
    this.lastBoxHtml = '';
  },

  closeSource() {
    G.state.openSource = null;
    this.el.box.hidden = true;
  },

  // Das aktuell geöffnete Lager (Kiste oder Haufen) finden
  currentSource() {
    const o = G.state.openSource, world = G.state.world;
    if (!o) return null;
    const i = world.idx(o.x, o.y);
    const dev = world.devices.get(i);
    if (dev && dev.inv) return { x: o.x, y: o.y, inv: dev.inv, dev, name: dev.unknown ? 'Unbekannte Kiste' : G.DEVICES[dev.type].name, unknown: dev.unknown };
    const pile = world.piles.get(i);
    return { x: o.x, y: o.y, inv: pile || G.Items.newInv(), pile: true, name: 'Haufen auf dem Boden' };
  },

  selectedChar() {
    const S = G.state;
    return S.chars.find(c => c.id === S.selectedId) || G.player();
  },

  onItemButton(e) {
    const b = e.target.closest('[data-act]');
    if (!b) return;
    const c = this.selectedChar();
    const act = b.dataset.act, type = b.dataset.type, qty = Number(b.dataset.qty);
    if (act === 'close') { this.closeSource(); return; }
    if (!c) return;
    if (act === 'drop') { G.Chars.dropItem(c, type, qty); return; }
    const src = this.currentSource();
    if (!src) return;
    if (act === 'take' || act === 'put') G.Chars.startTransfer(c, src, act, type, qty);
    if (act === 'takeall') for (const it of [...src.inv.items]) G.Chars.startTransfer(c, src, 'take', it.type, it.qty);
  },

  itemRow(it, buttons) {
    const d = G.ITEMS[it.type];
    return `<div class="item" title="${d.desc}">
      <span class="item-name">${G.Items.label(it)}</span>
      <span class="item-meta">${Math.round(it.cond)} % · ${(d.weight * it.qty).toFixed(1)} kg · ${G.Items.value(it)} Cr</span>
      <span class="item-btns">${buttons}</span>
    </div>`;
  },

  renderInventories() {
    const c = this.selectedChar();
    // Gepäck des ausgewählten Charakters
    let html = '';
    if (c) {
      const w = G.Items.weight(c.inv), v = G.Items.volume(c.inv);
      html = `<div class="needs-sub">Gepäck · ${w.toFixed(1)}/${c.inv.maxWeight} kg · ${Math.round(v)}/${c.inv.maxVolume} L</div>`;
      html += c.inv.items.length
        ? c.inv.items.map(it => this.itemRow(it, `<button type="button" data-act="drop" data-type="${it.type}" data-qty="${it.qty}">Ablegen</button>`)).join('')
        : '<div class="empty">Leer. Mit <kbd>E</kbd> neben einer Kiste oder einem Haufen durchsuchen.</div>';
      if (c.carrying) html += `<div class="empty">Trägt: ${G.DEVICES[c.carrying.type].name}</div>`;
    }
    if (html !== this.lastInvHtml) { this.el.inv.innerHTML = html; this.lastInvHtml = html; }

    // Geöffnete Kiste / Haufen
    const src = this.currentSource();
    if (!src) return;
    const near = c && G.Chars.canReach(c, src);
    let b = `<div class="box-head"><span class="label">${src.name}</span><button type="button" class="icon" data-act="close" aria-label="Schließen">✕</button></div>`;
    if (src.unknown) {
      b += `<div class="empty">Inhalt unbekannt. Geh mit einer Figur nah heran, um sie zu öffnen.</div>`;
      if (b !== this.lastBoxHtml) { this.el.box.innerHTML = b; this.lastBoxHtml = b; }
      return;
    }
    if (!src.pile) b += `<div class="empty">${Math.round(G.Items.volume(src.inv))} / ${src.inv.maxVolume} L belegt</div>`;
    const total = src.inv.items.reduce((s, it) => s + G.Items.value(it), 0);
    b += src.inv.items.length
      ? src.inv.items.map(it => this.itemRow(it,
        (it.qty > 1 ? `<button type="button" data-act="take" data-type="${it.type}" data-qty="1">1</button>` : '')
        + `<button type="button" data-act="take" data-type="${it.type}" data-qty="${it.qty}">Nehmen</button>`)).join('')
        + `<div class="box-foot"><span>Wert: ${total} Cr</span><button type="button" data-act="takeall">Alles nehmen</button></div>`
      : '<div class="empty">Leer.</div>';
    if (c && !src.pile && c.inv.items.length) {
      b += `<div class="needs-sub">Aus dem Gepäck von ${c.name}</div>`;
      b += c.inv.items.map(it => this.itemRow(it, `<button type="button" data-act="put" data-type="${it.type}" data-qty="${it.qty}">Hineinlegen</button>`)).join('');
    }
    if (c && !near) b += `<div class="empty">${c.name} steht nicht daneben und läuft erst hin.</div>`;
    if (b !== this.lastBoxHtml) { this.el.box.innerHTML = b; this.lastBoxHtml = b; }
  },

  // ---------- Handelsterminal und Werkbank ----------

  openPanel(kind) {
    this.panelKind = kind;
    this.el.panel.hidden = false;
    this.lastPanelHtml = '';
    this.closeSource();
  },

  closePanel() {
    this.panelKind = null;
    if (this.el) this.el.panel.hidden = true;
  },

  gameOver(text, title) {
    if (text) document.getElementById('go-text').textContent = text;
    if (title) document.getElementById('go-title').textContent = title;
    document.getElementById('gameover').hidden = false;
  },

  fmt(n) { return Math.round(n).toLocaleString('de-DE'); },

  onPanelButton(e) {
    const b = e.target.closest('[data-act]');
    if (!b) return;
    const d = b.dataset, E = G.Econ;
    switch (d.act) {
      case 'close': this.closePanel(); break;
      case 'tab': this.tradeTab = d.tab; break;
      case 'sell': E.sell(d.type, Number(d.qty)); break;
      case 'sellall': E.sellAll(); break;
      case 'buy': E.buy(d.type, Number(d.qty)); break;
      case 'pay': E.payDebt(d.qty === 'all' ? Infinity : Number(d.qty)); break;
      case 'claim': E.buyClaim(); break;
      case 'scrap': E.scrapHull(); break;
      case 'craft': E.craftJob(d.id); break;
      case 'switch': G.Fleet.switchTo(Number(d.id)); break;
      case 'sellship': G.Fleet.sell(Number(d.id)); break;
      case 'buyship': G.Fleet.buy(d.id); break;
      case 'register': G.Fleet.registerWreck(); break;
      case 'put': {
        const c = this.selectedChar(), t = E.terminal();
        if (c && t) G.Chars.startTransfer(c, { x: t.x, y: t.y, inv: t.inv, dev: t }, 'put', d.type, Number(d.qty));
        break;
      }
    }
    this.lastPanelHtml = '';
  },

  renderPanel() {
    if (!this.panelKind) return;
    const E = G.Econ, e = E.state();
    let h = '';
    const head = (title) => `<div class="box-head"><span class="label">${title}</span><button type="button" class="icon" data-act="close" aria-label="Schließen">✕</button></div>`;

    if (this.panelKind === 'bench') {
      h += head('Werkbank');
      h += '<div class="empty">Aus Schrott und Resten Neues machen. Die Crew holt das Material selbst und legt das Ergebnis neben die Werkbank.</div>';
      for (const r of G.RECIPES) {
        const ok = Object.entries(r.in).every(([t, q]) => G.Items.available(t) + G.state.chars.reduce((s, c) => s + G.Items.count(c.inv, t), 0) >= q);
        const inTxt = Object.entries(r.in).map(([t, q]) => q + '× ' + G.ITEMS[t].name).join(' + ');
        h += `<div class="item"><span class="item-name">${r.name}</span>
          <span class="item-meta">${inTxt} → ${r.out[1]}× ${G.ITEMS[r.out[0]].name}</span>
          <span class="item-btns"><button type="button" data-act="craft" data-id="${r.id}" ${ok ? '' : 'disabled'}>Herstellen</button></span></div>`;
      }
    } else {
      const t = E.terminal();
      const st = E.station();
      h += head('Handelsterminal' + (st ? ' · ' + st.name : ''));
      if (!E.terminalOnline()) h += `<div class="empty bad">${st ? 'Kein Strom. Das Terminal ist offline.' : 'Keine Verbindung: Handel geht nur angedockt an einer Station.'}</div>`;
      if (st && st.black) h += '<div class="empty">Schwarzmarkt: Datenchips bringen hier das Doppelte.</div>';
      h += `<div class="tabs">${[['sell', 'Verkaufen'], ['buy', 'Kaufen'], ['bank', 'Konto'], ['salvage', 'Bergung'], ['ships', 'Schiffe']]
        .map(([k, n]) => `<button type="button" data-act="tab" data-tab="${k}" class="${this.tradeTab === k ? 'active' : ''}">${n}</button>`).join('')}</div>`;
      h += `<div class="credits">${this.fmt(e.credits)} Cr</div>`;

      if (this.tradeTab === 'sell') {
        const items = t ? t.inv.items : [];
        h += '<div class="empty">Was im Terminal liegt, kannst du verkaufen. Leg Sachen aus dem Gepäck hinein.</div>';
        h += items.length ? items.map(it => this.itemRow(it, `<button type="button" data-act="sell" data-type="${it.type}" data-qty="${it.qty}">${this.fmt(E.sellPrice(it))} Cr</button>`)).join('')
          + `<div class="box-foot"><span>Summe: ${this.fmt(items.reduce((s, it) => s + E.sellPrice(it), 0))} Cr</span><button type="button" data-act="sellall">Alles verkaufen</button></div>`
          : '<div class="empty">Das Terminal ist leer.</div>';
        const c = this.selectedChar();
        if (c && c.inv.items.length) {
          h += `<div class="needs-sub">Gepäck von ${c.name}</div>`;
          h += c.inv.items.map(it => this.itemRow(it, `<button type="button" data-act="put" data-type="${it.type}" data-qty="${it.qty}">Hineinlegen</button>`)).join('');
        }
      } else if (this.tradeTab === 'buy') {
        h += '<div class="empty">Gekauftes landet im Terminal. Preise ändern sich jeden Tag.</div>';
        for (const [type, d] of Object.entries(G.ITEMS)) {
          const f = e.prices[type];
          const trend = f > 1.1 ? '<span class="up">▲ teuer</span>' : f < 0.9 ? '<span class="down">▼ günstig</span>' : '';
          h += `<div class="item" title="${d.desc}"><span class="item-name">${d.name} ${trend}</span>
            <span class="item-meta">${d.weight} kg · Verkauf ~${this.fmt(E.marketPrice(type) * G.ECON.SELL_FACTOR)} Cr</span>
            <span class="item-btns"><button type="button" data-act="buy" data-type="${type}" data-qty="1">${this.fmt(E.buyPrice(type))} Cr</button><button type="button" data-act="buy" data-type="${type}" data-qty="5">×5</button></span></div>`;
        }
      } else if (this.tradeTab === 'bank') {
        const days = Math.max(0, (e.nextPayment - G.state.time) / 1440);
        h += `<div class="kv"><span>Restschuld</span><b>${this.fmt(e.debt)} Cr</b></div>
          <div class="kv"><span>Nächste Rate</span><b>${this.fmt(Math.min(G.ECON.PAYMENT, e.debt))} Cr in ${days.toFixed(1)} Tagen</b></div>
          <div class="kv"><span>Liegegebühr</span><b>${G.ECON.DOCK_FEE} Cr pro Tag</b></div>
          <div class="kv"><span>Verpasste Raten</span><b class="${e.strikes ? 'bad' : ''}">${e.strikes} von ${G.ECON.MAX_STRIKES}</b></div>
          <div class="tabs"><button type="button" data-act="pay" data-qty="500">500 Cr tilgen</button><button type="button" data-act="pay" data-qty="all">Alles tilgen</button></div>
          <div class="needs-sub">Kontoauszug</div>`;
        h += e.log.length ? e.log.map(l => `<div class="kv small"><span>${l.text}</span><b class="${l.amount < 0 ? 'bad' : 'good'}">${l.amount ? (l.amount > 0 ? '+' : '') + this.fmt(l.amount) : ''}</b></div>`).join('')
          : '<div class="empty">Noch keine Buchungen.</div>';
      } else if (this.tradeTab === 'ships') {
        const F = G.Fleet, f = F.st(), here = G.state.nav.docked, loc = here ? G.Nav.loc(here) : null;
        h += `<div class="kv"><span>Aktuelles Schiff</span><b>${f.currentName}</b></div>`;
        h += '<div class="needs-sub">Deine anderen Schiffe</div>';
        h += f.ships.length ? f.ships.map(s => `<div class="item"><span class="item-name">${s.name}</span>
          <span class="item-meta">liegt bei ${G.Nav.loc(s.location).name}</span>
          <span class="item-btns">${s.location === here ? `<button type="button" data-act="switch" data-id="${s.id}">An Bord gehen</button>` : ''}
          ${s.location === here && loc && loc.shipyard ? `<button type="button" data-act="sellship" data-id="${s.id}">Verkaufen</button>` : ''}</span></div>`).join('')
          : '<div class="empty">Keine weiteren Schiffe.</div>';
        if (G.state.wreckName && st) h += `<div class="tabs"><button type="button" data-act="register">Wrack „${G.state.wreckName}“ als Schiff anmelden (${G.ECON.REGISTER_FEE} Cr)</button></div>
          <div class="empty">Das Wrack wird dein Schiff. Du kannst es reparieren und damit fliegen, wenn Steuerpult, Triebwerk und Tank funktionieren.</div>`;
        if (loc && loc.shipyard) {
          h += '<div class="needs-sub">Werft</div>';
          h += G.SHIPYARD.map(t => `<div class="item"><span class="item-name">${t.name}</span><span class="item-meta">${t.desc}</span>
            <span class="item-btns"><button type="button" data-act="buyship" data-id="${t.id}">${this.fmt(t.price)} Cr</button></span></div>`).join('');
        } else h += '<div class="empty">Schiffe kaufen und verkaufen kannst du an der Werft am Kármán-Ring.</div>';
      } else {
        const has = G.state.wreckName;
        h += has ? `<div class="kv"><span>Wrack an der Leine</span><b>${G.state.wreckName}</b></div>
          <div class="kv"><span>Restwert beim Verschrotten</span><b>${this.fmt(G.Wreck.hullValue())} Cr</b></div>
          <div class="empty">Tipp: Was du vorher ausbaust und einzeln verkaufst, bringt viel mehr als das Verschrotten.</div>
          <div class="tabs"><button type="button" data-act="scrap">Wrack verschrotten</button></div>`
          : '<div class="empty">Kein Wrack an der Bergungsleine.</div>';
        h += `<div class="tabs"><button type="button" data-act="claim">Neues Bergungsrecht (${G.ECON.CLAIM_FEE} Cr)</button></div>`;
        if (has) h += '<div class="empty">Ein neues Bergungsrecht ersetzt das aktuelle Wrack.</div>';
      }
    }
    if (h !== this.lastPanelHtml) { this.el.panel.innerHTML = h; this.lastPanelHtml = h; }
  },

  showHelp(show) {
    const help = this.el.help;
    help.hidden = show === undefined ? !help.hidden : !show;
  },

  toast(text, kind) {
    if (!text || !this.el) return;
    const t = document.createElement('div');
    t.className = 'toast' + (kind ? ' ' + kind : '');
    t.textContent = text;
    this.el.toasts.appendChild(t);
    const life = kind === 'bad' ? 6000 : 3000;
    setTimeout(() => t.classList.add('out'), life - 400);
    setTimeout(() => t.remove(), life);
    while (this.el.toasts.children.length > 5) this.el.toasts.firstChild.remove();
  },

  bar(label, value, warnAt) {
    const v = Math.round(value);
    const cls = v < warnAt / 2 ? 'bad' : v < warnAt ? 'warn' : '';
    return `<div class="need ${cls}"><span>${label}</span><span class="need-bar"><i style="width:${v}%"></i></span><span class="need-val">${v}</span></div>`;
  },

  // Wird jedes Bild aufgerufen
  update() {
    const S = G.state, el = this.el, world = S.world;
    const secs = Math.floor((G.START_MINUTES + S.time) * 60);
    const day = Math.floor(secs / 86400) + 1;
    const pad = v => String(v).padStart(2, '0');
    el.day.textContent = 'Tag ' + day;
    el.clock.textContent = pad(Math.floor(secs / 3600) % 24) + ':' + pad(Math.floor(secs / 60) % 60) + ':' + pad(secs % 60);
    el.speeds.forEach(b => b.classList.toggle('active', Number(b.dataset.speed) === S.speedIndex));
    document.body.classList.toggle('paused', S.speedIndex === 0);

    // Crew-Liste
    const html = S.chars.map(c => `
      <button class="crew-card${c.id === S.selectedId ? ' selected' : ''}${c.unconscious ? ' down' : ''}" data-char="${c.id}" type="button">
        <span class="crew-dot" style="background:${c.color}"></span>
        <span class="crew-text"><span class="crew-name">${c.name}</span><span class="crew-task">${c.task}</span></span>
      </button>`).join('');
    if (html !== this.lastCrewHtml) { el.crew.innerHTML = html; this.lastCrewHtml = html; }

    // Bedürfnisse des ausgewählten Charakters
    const sel = S.chars.find(c => c.id === S.selectedId);
    let needsHtml = '';
    if (sel) {
      const N = G.NEEDS;
      needsHtml = this.bar('Gesundheit', sel.health, 50)
        + this.bar(N.air.name, sel.needs.air, 70)
        + this.bar(N.food.name, sel.needs.food, N.food.at)
        + this.bar(N.water.name, sel.needs.water, N.water.at)
        + this.bar(N.sleep.name, sel.needs.sleep, N.sleep.at)
        + this.bar(N.hygiene.name, sel.needs.hygiene, N.hygiene.at);
      if (sel.suit) {
        needsHtml += '<div class="needs-sub">Raumanzug</div>'
          + this.bar('Anzug O₂', sel.suit.o2, G.SUIT.RETURN_AT * 1.5)
          + this.bar('Anzug-Akku', sel.suit.battery, G.SUIT.RETURN_AT * 1.5);
      }
    }
    if (needsHtml !== this.lastNeedsHtml) { el.needs.innerHTML = needsHtml; this.lastNeedsHtml = needsHtml; }

    // Strom-Übersicht (größtes Netz mit Generator)
    const nets = G.Power.nets.filter(n => n.production > 0 || n.capacity > 0);
    if (nets.length) {
      const n = nets.reduce((a, b) => (b.production + b.capacity > a.production + a.capacity ? b : a));
      const bal = n.production - n.demand;
      el.power.innerHTML = `<span class="${n.ok ? '' : 'bad'}">⚡ ${n.production.toFixed(1)} kW erzeugt · ${n.demand.toFixed(1)} kW verbraucht</span>`
        + (n.capacity ? ` · Batterie ${n.charge.toFixed(1)}/${n.capacity} kWh` : '')
        + (bal < 0 && n.ok ? ' · <span class="warn">Batterie wird leer</span>' : '');
    } else {
      el.power.innerHTML = '<span class="bad">⚡ Kein Stromnetz</span>';
    }

    this.renderInventories();
    this.renderPanel();
    // Geld oben in der Leiste
    const e = S.econ;
    if (e) {
      const days = Math.max(0, (e.nextPayment - S.time) / 1440);
      const html = `<span class="cr">${this.fmt(e.credits)} Cr</span><span class="debt">Schulden ${this.fmt(e.debt)} · Rate in ${days.toFixed(1)} T</span>`;
      if (html !== this.lastMoney) { el.money.innerHTML = html; this.lastMoney = html; }
    }

    el.jobCount.textContent = S.jobs.size ? S.jobs.size + (S.jobs.size === 1 ? ' Bauplan offen' : ' Baupläne offen') : 'Keine Baupläne';

    // Info zur Kachel unter der Maus
    const h = G.Input.hover;
    if (h && world.inBounds(h.x, h.y)) {
      const i = world.idx(h.x, h.y);
      const parts = [];
      const dev = world.devices.get(i);
      parts.push(dev ? G.Devices.status(dev) : G.TILE_INFO[world.tiles[i]].name);
      if (world.cables[i]) parts.push('Kabel');
      const job = S.jobs.get(i);
      if (job) parts.push('Plan: ' + G.Jobs.describe(job) + (job.missing ? ' (Material fehlt)' : ''));
      const pile = world.piles.get(i);
      if (pile) parts.push('Haufen: ' + pile.items.map(it => G.Items.label(it)).join(', '));
      const air = G.Atmo.describe(i);
      if (air) parts.push(air);
      el.hoverInfo.textContent = parts.join(' · ') + `  [${h.x}, ${h.y}]`;
    } else {
      el.hoverInfo.textContent = '';
    }
  },
};
