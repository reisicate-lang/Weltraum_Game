// ============================================================
// navui.js – Navigationskarte (Taste N am Steuerpult)
// Zeigt Erde, Mond, Stationen, dein Schiff und die voraus-
// berechnete Flugbahn. Steuerung: W Schub, S Gegenschub,
// A/D drehen, F andocken, Mausrad zoomen.
// ============================================================

G.NavUI = {
  open: false,
  zoom: 0.005,     // Pixel pro km
  follow: true,
  center: { x: 30000, y: 0 },

  init() {
    this.el = document.getElementById('nav');
    this.canvas = document.getElementById('navmap');
    this.ctx = this.canvas.getContext('2d');
    this.side = document.getElementById('nav-side');
    this.side.addEventListener('click', e => this.onButton(e));
    this.canvas.addEventListener('wheel', e => {
      e.preventDefault();
      this.zoom = Math.min(4000, Math.max(0.002, this.zoom * (e.deltaY < 0 ? 1.25 : 0.8)));
    }, { passive: false });
    let drag = null;
    this.canvas.addEventListener('pointerdown', e => { drag = { x: e.clientX, y: e.clientY, cx: this.center.x, cy: this.center.y }; });
    this.canvas.addEventListener('pointermove', e => {
      if (!drag) return;
      const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
      if (Math.hypot(dx, dy) > 5) { this.follow = false; this.center.x = drag.cx - dx / this.zoom; this.center.y = drag.cy - dy / this.zoom; }
    });
    window.addEventListener('pointerup', () => { drag = null; });
    this.lastSide = '';
  },

  toggle(show) {
    const hasHelm = G.Nav.shipDevices('helm').length > 0;
    if (show === undefined) show = !this.open;
    if (show && !hasHelm) return G.UI.toast('Dein Schiff hat kein Steuerpult.');
    this.open = show;
    this.el.hidden = !show;
    const n = G.state.nav;
    if (!show && n) { n.thrust = 0; n.turn = 0; n.match = null; }
    if (show) { this.follow = true; this.resize(); this.lastSide = ''; }
  },

  resize() {
    const r = this.canvas.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
    this.canvas.width = r.width * dpr; this.canvas.height = r.height * dpr;
    this.dpr = dpr; this.w = r.width; this.h = r.height;
  },

  // Tasten, solange die Karte offen ist (echte Zeit)
  control(keys, realDt) {
    const n = G.state.nav;
    if (!n || n.docked || n.travel || n.autodock || G.state.speedIndex === 0) { if (n) n.thrust = 0; return; }
    const turn = (keys.has('d') ? 1 : 0) - (keys.has('a') ? 1 : 0);
    n.angle += turn * G.SPACE.ROT_SPEED * realDt;
    n.thrust = keys.has('w') ? 1 : keys.has('s') ? -0.5 : 0;
  },

  onButton(e) {
    const b = e.target.closest('[data-act]');
    if (!b) return;
    const d = b.dataset, N = G.Nav;
    switch (d.act) {
      case 'close': this.toggle(false); break;
      case 'undock': N.undock(); break;
      case 'dock': if (!N.dock(d.id)) G.UI.toast('Noch zu weit weg oder zu schnell.'); break;
      case 'autodock': N.startAutodock(); break;
      case 'travel': N.travel(d.id); break;
      case 'match': G.state.nav.match = d.id; break;
      case 'aim': {
        const r = N.relTo(d.id), n = G.state.nav;
        n.angle = Math.atan2(r.p.y - n.y, r.p.x - n.x);
        break;
      }
      case 'follow': this.follow = true; break;
      case 'zoomship': this.follow = true; this.zoom = 40; break;
      case 'zoomall': this.follow = false; this.center = { x: 30000, y: -5000 }; this.zoom = Math.min(this.w, this.h) / 150000; break;
    }
    this.lastSide = '';
  },

  toScreen(x, y) { return { x: (x - this.center.x) * this.zoom + this.w / 2, y: (y - this.center.y) * this.zoom + this.h / 2 }; },

  draw() {
    if (!this.open) return;
    const ctx = this.ctx, n = G.state.nav, S = G.SPACE, N = G.Nav, T = N.secs();
    if (this.follow) { this.center.x = n.x; this.center.y = n.y; }
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.fillStyle = '#04060b'; ctx.fillRect(0, 0, this.w, this.h);

    // Himmelskörper
    for (const b of [S.EARTH, S.MOON]) {
      const p = this.toScreen(b.x, b.y);
      ctx.fillStyle = b.color;
      ctx.beginPath(); ctx.arc(p.x, p.y, Math.max(4, b.r * this.zoom), 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = '#c8d2e0'; ctx.font = '600 12px "Chakra Petch", sans-serif'; ctx.textAlign = 'center';
      ctx.fillText(b.name, p.x, p.y - Math.max(4, b.r * this.zoom) - 6);
    }
    // Gefahrenzonen der Erde
    const e = this.toScreen(S.EARTH.x, S.EARTH.y);
    ctx.strokeStyle = 'rgba(229,84,75,0.7)'; ctx.setLineDash([6, 6]); ctx.lineWidth = 1;
    ctx.beginPath(); ctx.arc(e.x, e.y, (S.EARTH.r + S.WARN_ALT) * this.zoom, 0, Math.PI * 2); ctx.stroke();
    ctx.setLineDash([]);

    // Orte und ihre Bahnen
    for (const loc of G.LOCATIONS) {
      if (loc.body) {
        const b = this.toScreen(G.SPACE[loc.body].x, G.SPACE[loc.body].y);
        ctx.strokeStyle = 'rgba(89,199,230,0.15)';
        ctx.beginPath(); ctx.arc(b.x, b.y, loc.radius * this.zoom, 0, Math.PI * 2); ctx.stroke();
      }
      const ls = N.locState(loc, T), p = this.toScreen(ls.x, ls.y);
      const size = Math.max(5, 0.08 * this.zoom);
      ctx.fillStyle = loc.kind === 'debris' ? '#a0866a' : loc.black ? '#b06ad0' : '#59c7e6';
      if (loc.kind === 'debris') for (let k = 0; k < 6; k++) ctx.fillRect(p.x + Math.sin(k * 2.3) * 8, p.y + Math.cos(k * 1.7) * 8, 3, 3);
      else ctx.fillRect(p.x - size / 2, p.y - size / 2, size, size);
      ctx.fillStyle = '#dde5ef'; ctx.font = '500 11px "IBM Plex Sans", sans-serif'; ctx.textAlign = 'left';
      ctx.fillText(loc.name, p.x + size / 2 + 6, p.y + 4);
    }

    // Vorausberechnete Flugbahn (nur Schwerkraft, ohne Schub)
    if (!n.docked && !n.travel) {
      let x = n.x, y = n.y, vx = n.vx, vy = n.vy;
      ctx.strokeStyle = 'rgba(242,163,58,0.6)'; ctx.lineWidth = 1.2;
      ctx.beginPath();
      let p = this.toScreen(x, y); ctx.moveTo(p.x, p.y);
      const step = Math.max(2, Math.min(120, 30 / Math.max(0.01, this.zoom)));
      for (let k = 0; k < 600; k++) {
        const g = N.gravity(x, y);
        vx += g.ax * step; vy += g.ay * step; x += vx * step; y += vy * step;
        p = this.toScreen(x, y); ctx.lineTo(p.x, p.y);
        if (Math.hypot(x - S.EARTH.x, y - S.EARTH.y) < S.EARTH.r) break;
      }
      ctx.stroke();
    }
    if (n.travel) {
      const to = N.locState(N.loc(n.travel.to), T), a = this.toScreen(n.x, n.y), b = this.toScreen(to.x, to.y);
      ctx.strokeStyle = 'rgba(111,207,142,0.7)'; ctx.setLineDash([4, 4]);
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke(); ctx.setLineDash([]);
    }

    // Dein Schiff
    const s = this.toScreen(n.x, n.y);
    ctx.save(); ctx.translate(s.x, s.y); ctx.rotate(n.angle);
    ctx.fillStyle = '#f2a33a';
    ctx.beginPath(); ctx.moveTo(10, 0); ctx.lineTo(-7, -6); ctx.lineTo(-4, 0); ctx.lineTo(-7, 6); ctx.closePath(); ctx.fill();
    if (n.thrust > 0) { ctx.fillStyle = '#ffd27a'; ctx.beginPath(); ctx.moveTo(-5, -3); ctx.lineTo(-14 - Math.random() * 5, 0); ctx.lineTo(-5, 3); ctx.fill(); }
    ctx.restore();

    this.renderSide();
  },

  fmtDist(km) { return km < 1 ? Math.round(km * 1000) + ' m' : km < 100 ? km.toFixed(1) + ' km' : Math.round(km).toLocaleString('de-DE') + ' km'; },
  fmtSpeed(kms) { return kms < 1 ? Math.round(kms * 1000) + ' m/s' : kms.toFixed(2) + ' km/s'; },

  renderSide() {
    const n = G.state.nav, N = G.Nav, S = G.SPACE;
    const altE = Math.hypot(n.x - S.EARTH.x, n.y - S.EARTH.y) - S.EARTH.r;
    const mass = N.mass(), thrust = N.maxThrust();
    let h = `<div class="box-head"><span class="label">Navigation</span><button type="button" class="icon" data-act="close" aria-label="Schließen">✕</button></div>
      <div class="credits small">${N.status()}</div>
      <div class="kv"><span>Geschwindigkeit</span><b>${this.fmtSpeed(Math.hypot(n.vx, n.vy))}</b></div>
      <div class="kv"><span>Höhe über der Erde</span><b class="${altE < S.WARN_ALT ? 'bad' : ''}">${this.fmtDist(altE)}</b></div>
      <div class="kv"><span>Treibstoff</span><b>${Math.floor(N.fuel())}</b></div>
      <div class="kv"><span>Schub / Masse</span><b>${thrust} kN / ${mass.toFixed(1)} t</b></div>
      <div class="kv"><span>Beschleunigung</span><b>${(thrust / mass).toFixed(2)} m/s²</b></div>`;
    if (!N.helmOk()) h += '<div class="empty bad">Das Steuerpult hat keinen Strom.</div>';
    if (n.docked) h += `<div class="tabs"><button type="button" data-act="undock">Abdocken</button></div>`;
    else if (!n.travel && !n.autodock) h += `<div class="tabs"><button type="button" data-act="autodock" ${N.autodockOk() ? '' : 'disabled'}>Auto-Dock (nächster Ort)</button></div>`;
    h += '<div class="needs-sub">Ziele</div>';
    for (const loc of G.LOCATIONS) {
      const r = N.relTo(loc.id), info = N.travelInfo(loc.id);
      const here = n.docked === loc.id;
      h += `<div class="item"><span class="item-name">${loc.name}${here ? ' · hier' : ''}</span>
        <span class="item-meta">${this.fmtDist(r.dist)} · Δv ${this.fmtSpeed(r.speed)}</span>
        <span class="item-btns">${here || n.travel ? '' : `
          ${r.dist < 300 ? `<button type="button" data-act="match" data-id="${loc.id}" title="Geschwindigkeit an das Ziel angleichen">Angleichen</button>` : ''}
          <button type="button" data-act="aim" data-id="${loc.id}" title="Schiff auf das Ziel ausrichten">Ausrichten</button>
          ${N.canDock(loc.id) ? `<button type="button" data-act="dock" data-id="${loc.id}">Andocken</button>` : ''}
          <button type="button" data-act="travel" data-id="${loc.id}" title="${loc.desc}">Reisen · ${(info.secs / 3600).toFixed(1)} h · ${Math.ceil(info.fuel)} T</button>`}</span></div>`;
    }
    h += `<div class="tabs"><button type="button" data-act="zoomship">Schiff zeigen</button><button type="button" data-act="zoomall">Ganzes System</button></div>
      <div class="empty"><kbd>W</kbd> Schub · <kbd>S</kbd> Gegenschub · <kbd>A</kbd>/<kbd>D</kbd> drehen · <kbd>F</kbd> andocken · Mausrad zoomen.
      Zum Andocken: näher als ${Math.round(S.DOCK_DIST * 1000)} m und langsamer als ${Math.round(S.DOCK_SPEED * 1000)} m/s.</div>`;
    if (h !== this.lastSide) { this.side.innerHTML = h; this.lastSide = h; }
  },

  // Taste F: am nächsten Ort andocken
  tryDock() {
    const near = G.Nav.nearest();
    if (G.state.nav.docked) return;
    if (!G.Nav.dock(near.loc.id)) G.UI.toast(`${near.loc.name}: ${this.fmtDist(near.dist)} entfernt, Δv ${this.fmtSpeed(near.speed)}. Zu weit oder zu schnell.`);
  },
};
