// ============================================================
// render.js – Alles zeichnen (Sterne, Schiff, Baupläne, Crew)
// ============================================================

G.Render = {
  COLORS: {
    space: '#05070c',
    floor: '#2a3442',
    floorAlt: '#273140',
    floorLine: '#1d2531',
    wall: '#8792a3',
    wallTop: '#a7b1c0',
    wallEdge: '#4b5566',
    door: '#c98a2c',
    doorDark: '#6b4a1a',
    plan: '#59c7e6',
    remove: '#e5544b',
    hover: 'rgba(255,255,255,0.18)',
  },

  init(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    // Zufällige Sterne für den Hintergrund
    this.stars = [];
    let seed = 12345;
    const rand = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
    for (let i = 0; i < 420; i++) {
      this.stars.push({ x: rand() * 2000, y: rand() * 2000, r: rand() * 1.3 + 0.3, a: rand() * 0.7 + 0.3, depth: rand() * 0.25 + 0.05 });
    }
    this.resize();
    window.addEventListener('resize', () => this.resize());
  },

  resize() {
    const dpr = window.devicePixelRatio || 1;
    const rect = this.canvas.getBoundingClientRect();
    this.canvas.width = Math.round(rect.width * dpr);
    this.canvas.height = Math.round(rect.height * dpr);
    this.dpr = dpr;
    this.viewW = rect.width;
    this.viewH = rect.height;
  },

  // Umrechnung Bildschirm <-> Welt (Welt in Kacheln)
  screenToWorld(sx, sy) {
    const cam = G.state.camera, s = G.TILE * cam.zoom;
    return { x: (sx - this.viewW / 2) / s + cam.x, y: (sy - this.viewH / 2) / s + cam.y };
  },

  draw() {
    const ctx = this.ctx, S = G.state, cam = S.camera;
    const s = G.TILE * cam.zoom;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.fillStyle = this.COLORS.space;
    ctx.fillRect(0, 0, this.viewW, this.viewH);
    this.drawStars();

    // Ab hier: Weltkoordinaten (1 Einheit = 1 Kachel)
    ctx.setTransform(this.dpr * s, 0, 0, this.dpr * s,
      this.dpr * (this.viewW / 2 - cam.x * s), this.dpr * (this.viewH / 2 - cam.y * s));

    // Nur sichtbare Kacheln zeichnen
    const tl = this.screenToWorld(0, 0), br = this.screenToWorld(this.viewW, this.viewH);
    const x0 = Math.max(0, Math.floor(tl.x)), y0 = Math.max(0, Math.floor(tl.y));
    const x1 = Math.min(S.world.w - 1, Math.ceil(br.x)), y1 = Math.min(S.world.h - 1, Math.ceil(br.y));

    this.drawWorldBorder();
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) this.drawTile(x, y, s);
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) this.drawCable(x, y);
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
      const dev = S.world.device(x, y);
      if (dev) this.drawDevice(dev, x, y);
    }
    for (const [i, pile] of S.world.piles) this.drawPile(i % S.world.w, (i / S.world.w) | 0, pile);
    if (S.view === 'air') this.drawAirOverlay(x0, y0, x1, y1);
    this.drawJobs();
    this.drawPaths();
    for (const c of S.chars) this.drawChar(c, s);
    this.drawEffects();
    this.drawCursor();
  },

  drawStars() {
    const ctx = this.ctx, cam = G.state.camera;
    for (const st of this.stars) {
      const px = ((st.x - cam.x * G.TILE * st.depth) % 2000 + 2000) % 2000;
      const py = ((st.y - cam.y * G.TILE * st.depth) % 2000 + 2000) % 2000;
      if (px > this.viewW || py > this.viewH) continue;
      ctx.globalAlpha = st.a;
      ctx.fillStyle = '#cfd8ff';
      ctx.fillRect(px, py, st.r, st.r);
    }
    ctx.globalAlpha = 1;
  },

  drawWorldBorder() {
    const ctx = this.ctx, w = G.state.world;
    ctx.strokeStyle = 'rgba(89,199,230,0.12)';
    ctx.lineWidth = 0.05;
    ctx.setLineDash([0.3, 0.3]);
    ctx.strokeRect(0, 0, w.w, w.h);
    ctx.setLineDash([]);
  },

  drawTile(x, y) {
    const ctx = this.ctx, T = G.T, C = this.COLORS, world = G.state.world;
    const t = world.get(x, y);
    if (t === T.SPACE) return;

    // Unter Wänden und Türen liegt immer Boden
    ctx.fillStyle = (x + y) % 2 ? C.floor : C.floorAlt;
    ctx.fillRect(x, y, 1, 1);
    ctx.strokeStyle = C.floorLine;
    ctx.lineWidth = 0.04;
    ctx.strokeRect(x + 0.02, y + 0.02, 0.96, 0.96);
    // Schleusenboden: Warnstreifen
    if (t === T.FLOOR && G.Airlock.isLockTile(world.idx(x, y))) {
      ctx.save();
      ctx.beginPath(); ctx.rect(x, y, 1, 1); ctx.clip();
      ctx.strokeStyle = 'rgba(242,163,58,0.22)';
      ctx.lineWidth = 0.12;
      for (let k = -1; k < 2; k += 0.35) { ctx.beginPath(); ctx.moveTo(x + k, y + 1); ctx.lineTo(x + k + 1, y); ctx.stroke(); }
      ctx.restore();
    }

    if (t === T.WALL) {
      ctx.fillStyle = C.wall;
      ctx.fillRect(x, y, 1, 1);
      ctx.fillStyle = C.wallTop;
      ctx.fillRect(x + 0.12, y + 0.12, 0.76, 0.76);
      // Angrenzende Wände verbinden, sonst dunkle Kante -> Wände wirken wie ein Stück
      const e = 0.12;
      const sides = [
        [0, -1, x + e, y, 1 - 2 * e, e, x, y, 1, 0.1],
        [0, 1, x + e, y + 1 - e, 1 - 2 * e, e, x, y + 0.9, 1, 0.1],
        [-1, 0, x, y + e, e, 1 - 2 * e, x, y, 0.1, 1],
        [1, 0, x + 1 - e, y + e, e, 1 - 2 * e, x + 0.9, y, 0.1, 1],
      ];
      for (const [dx, dy, ax, ay, aw, ah, bx, by, bw, bh] of sides) {
        if (world.wallLike(x + dx, y + dy)) {
          ctx.fillStyle = C.wallTop;
          ctx.fillRect(ax, ay, aw, ah);
        } else {
          ctx.fillStyle = C.wallEdge;
          ctx.fillRect(bx, by, bw, bh);
        }
      }
      this.drawCracks(x, y, world.cond[world.idx(x, y)]);
    } else if (t === T.DOOR) {
      // Tür: Ausrichtung je nachdem, wo die Wände sind
      const horizontal = world.wallLike(x - 1, y) || world.wallLike(x + 1, y);
      ctx.fillStyle = C.doorDark;
      if (horizontal) ctx.fillRect(x, y + 0.3, 1, 0.4); else ctx.fillRect(x + 0.3, y, 0.4, 1);
      // Offene Tür: die beiden Hälften gleiten auseinander
      const gap = world.doorOpen(world.idx(x, y)) ? 0.3 : 0;
      ctx.fillStyle = C.door;
      if (horizontal) {
        ctx.fillRect(x + 0.04, y + 0.36, 0.44 - gap, 0.28);
        ctx.fillRect(x + 0.52 + gap, y + 0.36, 0.44 - gap, 0.28);
      } else {
        ctx.fillRect(x + 0.36, y + 0.04, 0.28, 0.44 - gap);
        ctx.fillRect(x + 0.36, y + 0.52 + gap, 0.28, 0.44 - gap);
      }
      // Schleusentür: blaue Markierung
      if (G.Airlock.doorLock.has(world.idx(x, y))) {
        ctx.fillStyle = '#59c7e6';
        if (horizontal) { ctx.fillRect(x + 0.02, y + 0.3, 0.08, 0.4); ctx.fillRect(x + 0.9, y + 0.3, 0.08, 0.4); }
        else { ctx.fillRect(x + 0.3, y + 0.02, 0.4, 0.08); ctx.fillRect(x + 0.3, y + 0.9, 0.4, 0.08); }
      }
      this.drawCracks(x, y, world.cond[world.idx(x, y)]);
    }
  },

  drawJobs() {
    const ctx = this.ctx, C = this.COLORS;
    const pulse = 0.55 + 0.25 * Math.sin(performance.now() / 300);
    for (const job of G.state.jobs.values()) {
      const { x, y } = job;
      if (job.kind === 'move') {
        // Pfeil von der Quelle zum Ziel
        ctx.strokeStyle = C.plan; ctx.globalAlpha = pulse; ctx.lineWidth = 0.06; ctx.setLineDash([0.15, 0.1]);
        ctx.beginPath(); ctx.moveTo(x + 0.5, y + 0.5); ctx.lineTo(job.tx + 0.5, job.ty + 0.5); ctx.stroke();
        ctx.setLineDash([]);
        ctx.strokeRect(job.tx + 0.1, job.ty + 0.1, 0.8, 0.8);
        ctx.globalAlpha = 1;
        continue;
      }
      if (job.kind === 'refill') {
        ctx.globalAlpha = pulse;
        ctx.strokeStyle = '#6fcf8e'; ctx.lineWidth = 0.06;
        ctx.beginPath(); ctx.moveTo(x + 0.5, y + 0.15); ctx.lineTo(x + 0.5, y + 0.45); ctx.moveTo(x + 0.35, y + 0.3); ctx.lineTo(x + 0.65, y + 0.3); ctx.stroke();
      } else if (job.kind === 'repair') {
        ctx.globalAlpha = pulse;
        ctx.strokeStyle = '#f2a33a'; ctx.lineWidth = 0.07;
        ctx.beginPath(); ctx.moveTo(x + 0.25, y + 0.75); ctx.lineTo(x + 0.7, y + 0.3); ctx.stroke();
        ctx.beginPath(); ctx.arc(x + 0.72, y + 0.28, 0.12, 0, Math.PI * 2); ctx.stroke();
      } else if (job.kind === 'remove') {
        ctx.strokeStyle = C.remove;
        ctx.globalAlpha = pulse;
        ctx.lineWidth = 0.08;
        ctx.beginPath();
        ctx.moveTo(x + 0.2, y + 0.2); ctx.lineTo(x + 0.8, y + 0.8);
        ctx.moveTo(x + 0.8, y + 0.2); ctx.lineTo(x + 0.2, y + 0.8);
        ctx.stroke();
      } else {
        ctx.globalAlpha = 0.18;
        ctx.fillStyle = C.plan;
        ctx.fillRect(x + 0.05, y + 0.05, 0.9, 0.9);
        ctx.globalAlpha = pulse;
        ctx.strokeStyle = job.missing ? C.remove : C.plan;
        ctx.lineWidth = 0.05;
        ctx.setLineDash([0.15, 0.1]);
        ctx.strokeRect(x + 0.08, y + 0.08, 0.84, 0.84);
        ctx.setLineDash([]);
        // Symbol für das, was gebaut wird
        ctx.globalAlpha = 0.8;
        ctx.fillStyle = C.plan;
        if (job.tile === G.T.WALL) ctx.fillRect(x + 0.3, y + 0.3, 0.4, 0.4);
        if (job.tile === G.T.DOOR) ctx.fillRect(x + 0.42, y + 0.2, 0.16, 0.6);
        if (job.kind === 'cable') ctx.fillRect(x + 0.1, y + 0.45, 0.8, 0.1);
        if (job.kind === 'device') {
          ctx.globalAlpha = 0.45;
          this.drawDevice({ type: job.dev, powered: true, stock: 1, charge: 0 }, x, y, true);
        }
      }
      // Fortschrittsbalken
      if (job.progress > 0) {
        ctx.globalAlpha = 1;
        ctx.fillStyle = 'rgba(0,0,0,0.6)';
        ctx.fillRect(x + 0.1, y + 0.82, 0.8, 0.1);
        ctx.fillStyle = job.kind === 'remove' ? C.remove : '#f2a33a';
        ctx.fillRect(x + 0.1, y + 0.82, 0.8 * Math.min(1, job.progress / job.need), 0.1);
      }
      ctx.globalAlpha = 1;
    }
  },

  drawPaths() {
    const ctx = this.ctx;
    for (const c of G.state.chars) {
      if (!c.path.length) continue;
      ctx.strokeStyle = c.order ? 'rgba(242,163,58,0.7)' : 'rgba(89,199,230,0.45)';
      ctx.lineWidth = 0.05;
      ctx.setLineDash([0.12, 0.12]);
      ctx.beginPath();
      ctx.moveTo(c.x, c.y);
      for (const p of c.path) ctx.lineTo(p.x + 0.5, p.y + 0.5);
      ctx.stroke();
      ctx.setLineDash([]);
      if (c.order) {
        const last = c.path[c.path.length - 1];
        ctx.strokeStyle = 'rgba(242,163,58,0.9)';
        ctx.beginPath();
        ctx.arc(last.x + 0.5, last.y + 0.5, 0.25, 0, Math.PI * 2);
        ctx.stroke();
      }
    }
  },

  drawChar(c, s) {
    const ctx = this.ctx;
    const sleeping = c.activity && c.activity.need === 'sleep' && !c.path.length;
    if (c.unconscious || sleeping) { this.drawLying(c, s, sleeping); return; }
    const working = c.job && !c.path.length;
    const bob = working ? Math.sin(performance.now() / 90) * 0.03 : 0;
    // Schatten
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.beginPath();
    ctx.ellipse(c.x + 0.04, c.y + 0.08, 0.3, 0.24, 0, 0, Math.PI * 2);
    ctx.fill();
    // Körper (im Raumanzug weiß mit farbigem Ring)
    ctx.fillStyle = c.suit ? '#e6e9ee' : c.color;
    ctx.beginPath();
    ctx.arc(c.x, c.y + bob, c.suit ? 0.31 : 0.28, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = c.suit ? c.color : 'rgba(0,0,0,0.5)';
    ctx.lineWidth = c.suit ? 0.07 : 0.04;
    ctx.stroke();
    if (c.suit) {
      // Rucksack mit Lebenserhaltung
      ctx.fillStyle = '#8a95a6';
      const bx = c.x - Math.cos(c.facing) * 0.2, by = c.y + bob - Math.sin(c.facing) * 0.2;
      ctx.beginPath(); ctx.arc(bx, by, 0.13, 0, Math.PI * 2); ctx.fill();
    }
    // Visier zeigt die Blickrichtung
    ctx.fillStyle = c.suit ? '#f2c14e' : '#bfe9ff';
    ctx.beginPath();
    ctx.arc(c.x + Math.cos(c.facing) * 0.14, c.y + bob + Math.sin(c.facing) * 0.14, c.suit ? 0.14 : 0.11, 0, Math.PI * 2);
    ctx.fill();
    // Getragenes Gerät
    if (c.carrying) {
      ctx.save();
      ctx.translate(c.x - 0.3, c.y - 0.75);
      ctx.scale(0.6, 0.6);
      this.drawDevice(c.carrying, 0, 0, true);
      ctx.restore();
    }
    // Funken beim Arbeiten
    if (working && Math.random() < 0.6) {
      const jx = c.job.x + 0.5, jy = c.job.y + 0.5;
      ctx.fillStyle = Math.random() < 0.5 ? '#ffd27a' : '#ffffff';
      for (let i = 0; i < 3; i++) {
        ctx.fillRect(jx + (Math.random() - 0.5) * 0.5, jy + (Math.random() - 0.5) * 0.5, 0.05, 0.05);
      }
    }
    // Ausgewählt: Ring
    if (G.state.selectedId === c.id) {
      ctx.strokeStyle = '#f2a33a';
      ctx.lineWidth = 0.05;
      ctx.beginPath();
      ctx.arc(c.x, c.y, 0.42, 0, Math.PI * 2);
      ctx.stroke();
    }
    // Name
    if (s > 20) {
      ctx.save();
      ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
      const cam = G.state.camera;
      const sx = (c.x - cam.x) * s + this.viewW / 2, sy = (c.y - cam.y) * s + this.viewH / 2;
      ctx.font = '600 11px "Chakra Petch", system-ui, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = 'rgba(0,0,0,0.6)';
      const label = c.isPlayer ? '▸ ' + c.name : c.name;
      ctx.fillText(label, sx + 1, sy - 0.5 * s + 1);
      ctx.fillStyle = c.isPlayer ? '#f2c14e' : '#e8eef6';
      ctx.fillText(label, sx, sy - 0.5 * s);
      ctx.restore();
    }
  },

  drawLying(c, s, sleeping) {
    const ctx = this.ctx;
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.beginPath(); ctx.ellipse(c.x + 0.04, c.y + 0.06, 0.36, 0.2, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = sleeping ? c.color : '#7a6a5a';
    ctx.beginPath(); ctx.ellipse(c.x, c.y, 0.34, 0.18, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#bfe9ff';
    ctx.beginPath(); ctx.arc(c.x - 0.22, c.y, 0.1, 0, Math.PI * 2); ctx.fill();
    ctx.save();
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    const cam = G.state.camera;
    const sx = (c.x - cam.x) * s + this.viewW / 2, sy = (c.y - cam.y) * s + this.viewH / 2;
    ctx.font = '700 12px "Chakra Petch", system-ui, sans-serif';
    ctx.textAlign = 'center';
    const t = performance.now() / 600;
    if (sleeping) { ctx.fillStyle = '#bfe9ff'; ctx.fillText('z Z', sx + 0.3 * s, sy - 0.35 * s - (t % 1) * 6); }
    else { ctx.fillStyle = '#e5544b'; ctx.fillText('!', sx, sy - 0.4 * s); }
    ctx.restore();
  },

  // Kabel: dünne Leitung, die sich mit Nachbar-Kabeln verbindet
  drawCable(x, y) {
    const world = G.state.world;
    const i = world.idx(x, y);
    if (!world.cables[i]) return;
    const ctx = this.ctx;
    const powerView = G.state.view === 'power';
    let color = 'rgba(214,160,60,0.55)';
    if (powerView) {
      const net = G.Power.netOf ? G.Power.nets[G.Power.netOf[i]] : null;
      color = net && net.ok && (net.production > 0 || net.charge > 0) ? '#ffd23f' : '#e5544b';
    }
    ctx.strokeStyle = color;
    ctx.lineWidth = powerView ? 0.12 : 0.07;
    ctx.lineCap = 'round';
    ctx.beginPath();
    let any = false;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      if (world.inBounds(x + dx, y + dy) && world.cables[world.idx(x + dx, y + dy)]) {
        ctx.moveTo(x + 0.5, y + 0.5);
        ctx.lineTo(x + 0.5 + dx * 0.5, y + 0.5 + dy * 0.5);
        any = true;
      }
    }
    if (!any) { ctx.moveTo(x + 0.3, y + 0.5); ctx.lineTo(x + 0.7, y + 0.5); }
    ctx.stroke();
    ctx.lineCap = 'butt';
  },

  // Geräte als einfache Symbole
  drawDevice(dev, x, y, ghost) {
    const ctx = this.ctx;
    const cx = x + 0.5, cy = y + 0.5;
    const box = (fill, inset = 0.1) => {
      ctx.fillStyle = fill;
      ctx.fillRect(x + inset, y + inset, 1 - 2 * inset, 1 - 2 * inset);
      ctx.strokeStyle = 'rgba(0,0,0,0.5)';
      ctx.lineWidth = 0.04;
      ctx.strokeRect(x + inset, y + inset, 1 - 2 * inset, 1 - 2 * inset);
    };
    const circle = (r, fill, ox = 0, oy = 0) => {
      ctx.fillStyle = fill;
      ctx.beginPath(); ctx.arc(cx + ox, cy + oy, r, 0, Math.PI * 2); ctx.fill();
    };
    const t = performance.now() / 1000;
    switch (dev.type) {
      case 'generator': {
        box('#4a4f5a');
        const on = dev.net >= 0 || ghost;
        circle(0.22, on ? '#ffb347' : '#5a4630');
        if (on && !ghost) circle(0.12 + Math.sin(t * 4) * 0.03, '#fff1c7');
        break;
      }
      case 'battery': {
        box('#3c4a44');
        const f = dev.charge / G.DEVICES.battery.capacity;
        ctx.fillStyle = '#1b231f';
        ctx.fillRect(x + 0.3, y + 0.2, 0.4, 0.6);
        ctx.fillStyle = f > 0.25 ? '#6fcf8e' : '#e5544b';
        ctx.fillRect(x + 0.3, y + 0.8 - 0.6 * f, 0.4, 0.6 * f);
        ctx.fillStyle = '#6a7a72';
        ctx.fillRect(x + 0.4, y + 0.13, 0.2, 0.07);
        break;
      }
      case 'o2gen':
        box('#2f4a5e');
        circle(0.26, '#59c7e6');
        circle(0.13, '#e4f7ff');
        if (dev.powered && !ghost) for (let k = 0; k < 3; k++) {
          const p = (t * 0.7 + k / 3) % 1;
          ctx.globalAlpha = (ghost ? 0.45 : 1) * (1 - p);
          circle(0.05, '#bfefff', Math.sin(k * 2.1) * 0.2, -0.1 - p * 0.35);
        }
        ctx.globalAlpha = ghost ? 0.45 : 1;
        break;
      case 'scrubber': {
        box('#3d4a3a');
        ctx.save();
        ctx.translate(cx, cy);
        ctx.rotate(dev.powered && !ghost ? t * 6 : 0);
        ctx.fillStyle = '#9fb39a';
        for (let k = 0; k < 4; k++) { ctx.rotate(Math.PI / 2); ctx.fillRect(-0.04, 0, 0.08, 0.3); }
        ctx.restore();
        circle(0.07, '#2a3328');
        break;
      }
      case 'airtank':
        circle(0.4, '#5d6b7d');
        circle(0.32, '#8796aa');
        ctx.fillStyle = '#2a3442';
        ctx.fillRect(x + 0.2, y + 0.45, 0.6, 0.1);
        ctx.fillStyle = '#59c7e6';
        ctx.fillRect(x + 0.2, y + 0.45, 0.6 * Math.max(0, (dev.stock || 0) / G.DEVICES.airtank.stock), 0.1);
        break;
      case 'bed':
        box('#3a4560', 0.06);
        ctx.fillStyle = '#d9dfeb';
        ctx.fillRect(x + 0.14, y + 0.12, 0.72, 0.22);
        ctx.fillStyle = '#5873a8';
        ctx.fillRect(x + 0.1, y + 0.4, 0.8, 0.5);
        break;
      case 'food':
        box('#6b5a44');
        ctx.strokeStyle = '#3d3326'; ctx.lineWidth = 0.04;
        ctx.beginPath(); ctx.moveTo(cx, y + 0.12); ctx.lineTo(cx, y + 0.88); ctx.stroke();
        ctx.fillStyle = '#e8c27a';
        ctx.fillRect(cx - 0.12, cy - 0.05, 0.06, 0.1); ctx.fillRect(cx + 0.06, cy - 0.05, 0.06, 0.1);
        break;
      case 'water':
        box('#3c556b');
        ctx.fillStyle = '#7fd3f5';
        ctx.fillRect(x + 0.28, y + 0.18, 0.44, 0.4 * Math.max(0.1, (dev.stock || 0) / G.DEVICES.water.stock) + 0.04);
        ctx.fillStyle = '#d0dbe6';
        ctx.fillRect(x + 0.42, y + 0.68, 0.16, 0.12);
        break;
      case 'crate': {
        box('#5a4a32', 0.08);
        ctx.strokeStyle = '#3a2f1f'; ctx.lineWidth = 0.05;
        ctx.strokeRect(x + 0.18, y + 0.18, 0.64, 0.64);
        ctx.beginPath(); ctx.moveTo(x + 0.18, y + 0.18); ctx.lineTo(x + 0.82, y + 0.82); ctx.stroke();
        // Füllstand
        const f = dev.inv ? Math.min(1, G.Items.volume(dev.inv) / dev.inv.maxVolume) : 0;
        ctx.fillStyle = '#f2a33a'; ctx.fillRect(x + 0.12, y + 0.86, 0.76 * f, 0.05);
        break;
      }
      case 'solar':
        ctx.fillStyle = '#1d2f5a';
        ctx.fillRect(x + 0.05, y + 0.05, 0.9, 0.9);
        ctx.strokeStyle = '#4f6fb5'; ctx.lineWidth = 0.03;
        for (let k = 1; k < 3; k++) {
          ctx.beginPath(); ctx.moveTo(x + 0.05 + k * 0.3, y + 0.05); ctx.lineTo(x + 0.05 + k * 0.3, y + 0.95); ctx.stroke();
          ctx.beginPath(); ctx.moveTo(x + 0.05, y + 0.05 + k * 0.3); ctx.lineTo(x + 0.95, y + 0.05 + k * 0.3); ctx.stroke();
        }
        if (dev.producing) { ctx.fillStyle = 'rgba(160,200,255,0.25)'; ctx.fillRect(x + 0.05, y + 0.05, 0.45, 0.45); }
        break;
      case 'locker':
        box('#46505e', 0.06);
        ctx.fillStyle = '#2b323c';
        ctx.fillRect(x + 0.16, y + 0.14, 0.68, 0.72);
        if (dev.suit) {
          ctx.fillStyle = '#e6e9ee';
          ctx.beginPath(); ctx.arc(cx, y + 0.34, 0.13, 0, Math.PI * 2); ctx.fill();
          ctx.fillRect(cx - 0.17, y + 0.46, 0.34, 0.34);
          ctx.fillStyle = '#f2c14e';
          ctx.beginPath(); ctx.arc(cx, y + 0.34, 0.07, 0, Math.PI * 2); ctx.fill();
        }
        break;
      case 'charger': {
        box('#4b4636', 0.16);
        const f = (dev.charge || 0) / G.DEVICES.charger.capacity;
        ctx.fillStyle = '#1e1c15'; ctx.fillRect(x + 0.26, y + 0.56, 0.48, 0.14);
        ctx.fillStyle = f > 0.25 ? '#ffd23f' : '#e5544b'; ctx.fillRect(x + 0.26, y + 0.56, 0.48 * f, 0.14);
        ctx.fillStyle = '#ffd23f';
        ctx.beginPath(); ctx.moveTo(cx + 0.04, y + 0.2); ctx.lineTo(cx - 0.1, y + 0.4); ctx.lineTo(cx, y + 0.4); ctx.lineTo(cx - 0.04, y + 0.52); ctx.lineTo(cx + 0.1, y + 0.32); ctx.lineTo(cx, y + 0.32); ctx.closePath(); ctx.fill();
        // Griff zum Tragen
        ctx.strokeStyle = '#8a8470'; ctx.lineWidth = 0.05;
        ctx.beginPath(); ctx.moveTo(x + 0.35, y + 0.16); ctx.lineTo(x + 0.35, y + 0.08); ctx.lineTo(x + 0.65, y + 0.08); ctx.lineTo(x + 0.65, y + 0.16); ctx.stroke();
        break;
      }
      case 'pump': {
        box('#3b4652');
        ctx.save(); ctx.translate(cx, cy);
        const lock = !ghost && G.Airlock.lockOfPump(dev);
        const active = lock && lock.requestUntil >= G.state.time && dev.powered;
        ctx.rotate(active ? t * 10 : 0);
        ctx.strokeStyle = '#59c7e6'; ctx.lineWidth = 0.06;
        ctx.beginPath(); ctx.arc(0, 0, 0.24, 0.3, Math.PI * 1.7); ctx.stroke();
        ctx.restore();
        circle(0.08, '#59c7e6');
        break;
      }
      case 'sink':
        box('#57636f');
        ctx.fillStyle = '#c9d6e2';
        ctx.beginPath(); ctx.ellipse(cx, cy + 0.06, 0.28, 0.2, 0, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = '#8fa3b5';
        ctx.fillRect(cx - 0.04, y + 0.14, 0.08, 0.16);
        break;
    }
    if (ghost) return;
    // Abnutzung und Schäden sichtbar machen
    if (dev.cond < 60) {
      ctx.fillStyle = 'rgba(30,20,10,' + (0.45 * (1 - dev.cond / 60)) + ')';
      ctx.fillRect(x + 0.1, y + 0.1, 0.8, 0.8);
      this.drawCracks(x, y, dev.cond);
    }
    if (dev.broken) {
      if (Math.random() < 0.3) {
        ctx.fillStyle = Math.random() < 0.5 ? '#ffd27a' : '#ffffff';
        ctx.fillRect(x + 0.2 + Math.random() * 0.6, y + 0.2 + Math.random() * 0.6, 0.06, 0.06);
      }
      ctx.strokeStyle = '#e5544b'; ctx.lineWidth = 0.06;
      ctx.beginPath(); ctx.moveTo(x + 0.25, y + 0.25); ctx.lineTo(x + 0.75, y + 0.75); ctx.moveTo(x + 0.75, y + 0.25); ctx.lineTo(x + 0.25, y + 0.75); ctx.stroke();
    }
    // Rote Lampe: Gerät hat keinen Strom bzw. Vorrat ist leer
    const problem = (G.Devices.needsPower(dev) && !dev.powered) || (dev.stock !== undefined && dev.stock <= 0)
      || (dev.type === 'generator' && dev.net < 0) || (dev.type === 'solar' && !dev.producing) || dev.broken;
    if (problem && Math.sin(t * 6) > -0.3) {
      ctx.fillStyle = '#e5544b';
      ctx.beginPath(); ctx.arc(x + 0.82, y + 0.18, 0.09, 0, Math.PI * 2); ctx.fill();
    }
  },

  // Herumliegende Gegenstände: kleine Kisten und Teile
  drawPile(x, y, pile) {
    const ctx = this.ctx;
    const n = Math.min(4, pile.items.length);
    const colors = { scrap: '#7d6f62', plate: '#9aa3ad', copper: '#c27a3f', circuit: '#3f8f5a', motor: '#5a6270', cell: '#c9b23a',
      pipe: '#8c97a3', glass: '#8fc3d6', filter: '#d9d2c0', fabric: '#8a6b9e', datachip: '#59c7e6', ration: '#d6a35b',
      watercan: '#4f8fcf', fuelcan: '#cf4f4f', aircan: '#dcdcdc' };
    const spots = [[0.3, 0.32], [0.62, 0.38], [0.38, 0.66], [0.66, 0.68]];
    for (let k = 0; k < n; k++) {
      const it = pile.items[k];
      const [ox, oy] = spots[k];
      ctx.fillStyle = 'rgba(0,0,0,0.35)';
      ctx.fillRect(x + ox - 0.1, y + oy - 0.06, 0.24, 0.2);
      ctx.fillStyle = colors[it.type] || '#aaa';
      ctx.fillRect(x + ox - 0.12, y + oy - 0.1, 0.24, 0.2);
    }
  },

  // Risse: je schlechter der Zustand, desto mehr. Immer gleich pro Feld (kein Flackern).
  drawCracks(x, y, cond) {
    if (cond >= 85) return;
    const ctx = this.ctx;
    let seed = (x * 73856093) ^ (y * 19349663);
    const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
    const count = cond < 30 ? 4 : cond < 60 ? 2 : 1;
    ctx.strokeStyle = cond < 30 ? 'rgba(20,10,5,0.85)' : 'rgba(20,10,5,0.6)';
    ctx.lineWidth = cond < 30 ? 0.05 : 0.035;
    for (let k = 0; k < count; k++) {
      let px = x + 0.2 + rnd() * 0.6, py = y + 0.2 + rnd() * 0.6;
      ctx.beginPath(); ctx.moveTo(px, py);
      for (let s = 0; s < 3; s++) {
        px = Math.min(x + 0.95, Math.max(x + 0.05, px + (rnd() - 0.5) * 0.4));
        py = Math.min(y + 0.95, Math.max(y + 0.05, py + (rnd() - 0.5) * 0.4));
        ctx.lineTo(px, py);
      }
      ctx.stroke();
    }
  },

  // Einschlag-Blitze von Mikrometeoriten
  drawEffects() {
    const ctx = this.ctx, now = performance.now();
    G.Damage.effects = G.Damage.effects.filter(e => now - e.start < 1500);
    for (const e of G.Damage.effects) {
      const p = (now - e.start) / 1500;
      ctx.globalAlpha = 1 - p;
      ctx.fillStyle = '#fff3c4';
      ctx.beginPath(); ctx.arc(e.x + 0.5, e.y + 0.5, 0.2 + p * 1.6, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = '#ffb347'; ctx.lineWidth = 0.08;
      ctx.beginPath(); ctx.arc(e.x + 0.5, e.y + 0.5, 0.4 + p * 2.5, 0, Math.PI * 2); ctx.stroke();
    }
    ctx.globalAlpha = 1;
  },

  // Luft-Ansicht: grün = gut, gelb = knapp, rot = keine Luft
  drawAirOverlay(x0, y0, x1, y1) {
    const ctx = this.ctx, world = G.state.world, A = G.AIR;
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const i = world.idx(x, y);
        if (!world.holdsAir(i)) continue;
        const o2 = world.o2[i];
        let col;
        if (o2 >= A.O2_OK && world.co2[i] <= A.CO2_BAD) col = 'rgba(111,207,142,0.38)';
        else if (o2 >= A.O2_LOW) col = 'rgba(242,200,58,0.45)';
        else col = 'rgba(229,84,75,' + (0.25 + 0.35 * (1 - o2 / A.O2_LOW)) + ')';
        ctx.fillStyle = col;
        ctx.fillRect(x, y, 1, 1);
      }
    }
  },

  // Vorschau unter dem Mauszeiger bzw. beim Ziehen
  drawCursor() {
    const ctx = this.ctx, inp = G.Input, S = G.state;
    if (!inp.hover) return;
    const tool = S.tool;
    const tiles = (inp.dragStart && inp.dragTiles()) || [inp.hover];
    if (tool === 'select') {
      if (!S.world.inBounds(inp.hover.x, inp.hover.y)) return;
      ctx.fillStyle = this.COLORS.hover;
      ctx.fillRect(inp.hover.x, inp.hover.y, 1, 1);
      return;
    }
    if (tool === 'move') {
      const a = inp.dragStart;
      if (a) {
        ctx.strokeStyle = 'rgba(89,199,230,0.8)'; ctx.lineWidth = 0.06; ctx.setLineDash([0.15, 0.1]);
        ctx.beginPath(); ctx.moveTo(a.x + 0.5, a.y + 0.5); ctx.lineTo(inp.hover.x + 0.5, inp.hover.y + 0.5); ctx.stroke();
        ctx.setLineDash([]);
        const okT = S.world.get(inp.hover.x, inp.hover.y) === G.T.FLOOR && !S.world.device(inp.hover.x, inp.hover.y);
        ctx.fillStyle = okT ? 'rgba(89,199,230,0.35)' : 'rgba(229,84,75,0.35)';
        ctx.fillRect(inp.hover.x, inp.hover.y, 1, 1);
      } else {
        ctx.fillStyle = G.Jobs.canPlace('move', inp.hover.x, inp.hover.y) ? 'rgba(89,199,230,0.35)' : 'rgba(255,255,255,0.06)';
        ctx.fillRect(inp.hover.x, inp.hover.y, 1, 1);
      }
      return;
    }
    for (const t of tiles) {
      const ok = G.Jobs.canPlace(tool, t.x, t.y);
      ctx.fillStyle = ok ? (tool === 'remove' || tool === 'cancel' ? 'rgba(229,84,75,0.35)' : 'rgba(89,199,230,0.35)') : 'rgba(255,255,255,0.06)';
      ctx.fillRect(t.x, t.y, 1, 1);
    }
  },
};
