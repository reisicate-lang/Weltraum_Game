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
    };

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
    if (dev && dev.inv) return { x: o.x, y: o.y, inv: dev.inv, dev, name: G.DEVICES[dev.type].name };
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
