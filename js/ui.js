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
    };

    // Geräte-Menü aus der Liste in config.js füllen
    this.el.devMenu.innerHTML = Object.entries(G.DEVICES).map(([type, d]) => `
      <button type="button" data-tool="dev:${type}">
        <span class="dm-name">${d.name}</span>
        <span class="dm-desc">${d.desc}</span>
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
    this.el.hint.textContent = G.TOOLS[tool].hint;
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
      if (job) parts.push('Plan: ' + G.Jobs.describe(job));
      const air = G.Atmo.describe(i);
      if (air) parts.push(air);
      el.hoverInfo.textContent = parts.join(' · ') + `  [${h.x}, ${h.y}]`;
    } else {
      el.hoverInfo.textContent = '';
    }
  },
};
