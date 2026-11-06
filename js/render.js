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
    this.drawJobs();
    this.drawPaths();
    for (const c of S.chars) this.drawChar(c, s);
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
    } else if (t === T.DOOR) {
      // Tür: Ausrichtung je nachdem, wo die Wände sind
      const horizontal = world.wallLike(x - 1, y) || world.wallLike(x + 1, y);
      ctx.fillStyle = C.doorDark;
      if (horizontal) ctx.fillRect(x, y + 0.3, 1, 0.4); else ctx.fillRect(x + 0.3, y, 0.4, 1);
      ctx.fillStyle = C.door;
      if (horizontal) {
        ctx.fillRect(x + 0.04, y + 0.36, 0.44, 0.28);
        ctx.fillRect(x + 0.52, y + 0.36, 0.44, 0.28);
      } else {
        ctx.fillRect(x + 0.36, y + 0.04, 0.28, 0.44);
        ctx.fillRect(x + 0.36, y + 0.52, 0.28, 0.44);
      }
    }
  },

  drawJobs() {
    const ctx = this.ctx, C = this.COLORS;
    const pulse = 0.55 + 0.25 * Math.sin(performance.now() / 300);
    for (const job of G.state.jobs.values()) {
      const { x, y } = job;
      if (job.kind === 'remove') {
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
        ctx.strokeStyle = C.plan;
        ctx.lineWidth = 0.05;
        ctx.setLineDash([0.15, 0.1]);
        ctx.strokeRect(x + 0.08, y + 0.08, 0.84, 0.84);
        ctx.setLineDash([]);
        // Symbol für das, was gebaut wird
        ctx.globalAlpha = 0.8;
        ctx.fillStyle = C.plan;
        if (job.tile === G.T.WALL) ctx.fillRect(x + 0.3, y + 0.3, 0.4, 0.4);
        if (job.tile === G.T.DOOR) ctx.fillRect(x + 0.42, y + 0.2, 0.16, 0.6);
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
    const working = c.job && !c.path.length;
    const bob = working ? Math.sin(performance.now() / 90) * 0.03 : 0;
    // Schatten
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.beginPath();
    ctx.ellipse(c.x + 0.04, c.y + 0.08, 0.3, 0.24, 0, 0, Math.PI * 2);
    ctx.fill();
    // Körper
    ctx.fillStyle = c.color;
    ctx.beginPath();
    ctx.arc(c.x, c.y + bob, 0.28, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,0.5)';
    ctx.lineWidth = 0.04;
    ctx.stroke();
    // Visier zeigt die Blickrichtung
    ctx.fillStyle = '#bfe9ff';
    ctx.beginPath();
    ctx.arc(c.x + Math.cos(c.facing) * 0.14, c.y + bob + Math.sin(c.facing) * 0.14, 0.11, 0, Math.PI * 2);
    ctx.fill();
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
      ctx.fillText(c.name, sx + 1, sy - 0.5 * s + 1);
      ctx.fillStyle = '#e8eef6';
      ctx.fillText(c.name, sx, sy - 0.5 * s);
      ctx.restore();
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
    for (const t of tiles) {
      const ok = G.Jobs.canPlace(tool, t.x, t.y);
      ctx.fillStyle = ok ? (tool === 'remove' || tool === 'cancel' ? 'rgba(229,84,75,0.35)' : 'rgba(89,199,230,0.35)') : 'rgba(255,255,255,0.06)';
      ctx.fillRect(t.x, t.y, 1, 1);
    }
  },
};
