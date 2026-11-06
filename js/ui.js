// ============================================================
// ui.js – Menüs und Anzeigen über dem Spielfeld
// ============================================================

G.UI = {
  init() {
    this.el = {
      clock: document.getElementById('clock'),
      day: document.getElementById('day'),
      speeds: [...document.querySelectorAll('[data-speed]')],
      tools: [...document.querySelectorAll('[data-tool]')],
      hint: document.getElementById('tool-hint'),
      crew: document.getElementById('crew'),
      hoverInfo: document.getElementById('hover-info'),
      jobCount: document.getElementById('job-count'),
      toasts: document.getElementById('toasts'),
      help: document.getElementById('help'),
      newGame: document.getElementById('btn-new'),
    };

    this.el.speeds.forEach(b => b.addEventListener('click', () => G.setSpeed(Number(b.dataset.speed))));
    this.el.tools.forEach(b => b.addEventListener('click', () => this.setTool(b.dataset.tool)));
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
    this.lastCrewHtml = '';
  },

  setTool(tool) {
    G.state.tool = tool;
    G.Input.dragStart = null;
    this.el.tools.forEach(b => b.classList.toggle('active', b.dataset.tool === tool));
    this.el.hint.textContent = G.TOOLS[tool].hint;
    document.body.dataset.tool = tool;
  },

  showHelp(show) {
    const help = this.el.help;
    help.hidden = show === undefined ? !help.hidden : !show;
  },

  toast(text) {
    if (!text) return;
    const t = document.createElement('div');
    t.className = 'toast';
    t.textContent = text;
    this.el.toasts.appendChild(t);
    setTimeout(() => t.classList.add('out'), 2600);
    setTimeout(() => t.remove(), 3000);
    while (this.el.toasts.children.length > 4) this.el.toasts.firstChild.remove();
  },

  // Wird jedes Bild aufgerufen
  update() {
    const S = G.state, el = this.el;
    const total = G.START_MINUTES + Math.floor(S.time);
    const day = Math.floor(total / 1440) + 1;
    const mins = total % 1440;
    el.day.textContent = 'Tag ' + day;
    el.clock.textContent = String(Math.floor(mins / 60)).padStart(2, '0') + ':' + String(mins % 60).padStart(2, '0');
    el.speeds.forEach(b => b.classList.toggle('active', Number(b.dataset.speed) === S.speedIndex));
    document.body.classList.toggle('paused', S.speedIndex === 0);

    // Crew-Liste (nur neu zeichnen, wenn sich etwas geändert hat)
    const html = S.chars.map(c => `
      <button class="crew-card${c.id === S.selectedId ? ' selected' : ''}" data-char="${c.id}" type="button">
        <span class="crew-dot" style="background:${c.color}"></span>
        <span class="crew-text"><span class="crew-name">${c.name}</span><span class="crew-task">${c.task}</span></span>
      </button>`).join('');
    if (html !== this.lastCrewHtml) { el.crew.innerHTML = html; this.lastCrewHtml = html; }

    el.jobCount.textContent = S.jobs.size ? S.jobs.size + (S.jobs.size === 1 ? ' Bauplan offen' : ' Baupläne offen') : 'Keine Baupläne';

    const h = G.Input.hover;
    if (h && S.world.inBounds(h.x, h.y)) {
      const job = S.jobs.get(S.world.idx(h.x, h.y));
      let text = G.TILE_INFO[S.world.get(h.x, h.y)].name;
      if (job) text += ' · Plan: ' + (job.kind === 'remove' ? 'abreißen' : G.TILE_INFO[job.tile].name);
      el.hoverInfo.textContent = `${text}  [${h.x}, ${h.y}]`;
    } else {
      el.hoverInfo.textContent = '';
    }
  },
};
