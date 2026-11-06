// ============================================================
// input.js – Maus, Touch und Tastatur
// ============================================================

G.Input = {
  hover: null,      // Kachel unter dem Mauszeiger
  dragStart: null,  // Start-Kachel beim Ziehen im Baumodus
  pan: null,        // Daten fürs Verschieben der Ansicht
  keys: new Set(),

  init(canvas) {
    this.canvas = canvas;
    canvas.addEventListener('pointerdown', e => this.onDown(e));
    canvas.addEventListener('pointermove', e => this.onMove(e));
    canvas.addEventListener('pointerup', e => this.onUp(e));
    canvas.addEventListener('pointercancel', () => { this.pan = null; this.dragStart = null; });
    canvas.addEventListener('pointerleave', () => { if (!this.pan && !this.dragStart) this.hover = null; });
    canvas.addEventListener('wheel', e => this.onWheel(e), { passive: false });
    canvas.addEventListener('contextmenu', e => e.preventDefault());
    window.addEventListener('keydown', e => this.onKey(e));
    window.addEventListener('keyup', e => { this.keys.delete(e.key.toLowerCase()); if (e.key === 'Control' || e.key === 'Meta') this.ctrl = false; });
    window.addEventListener('blur', () => this.keys.clear());
  },

  tileAt(e) {
    const rect = this.canvas.getBoundingClientRect();
    const w = G.Render.screenToWorld(e.clientX - rect.left, e.clientY - rect.top);
    return { x: Math.floor(w.x), y: Math.floor(w.y), wx: w.x, wy: w.y };
  },

  onDown(e) {
    this.canvas.setPointerCapture(e.pointerId);
    G.UI.showDevMenu(false);
    const tool = G.state.tool;
    this.hover = this.tileAt(e);
    // Mittlere/rechte Maustaste oder Auswahl-Werkzeug: Ansicht verschieben möglich
    if (e.button === 1 || e.button === 2 || tool === 'select') {
      this.pan = { sx: e.clientX, sy: e.clientY, cx: G.state.camera.x, cy: G.state.camera.y, moved: false, button: e.button };
      return;
    }
    if (e.button === 0) this.dragStart = { x: this.hover.x, y: this.hover.y };
  },

  onMove(e) {
    this.hover = this.tileAt(e);
    if (this.pan) {
      const dx = e.clientX - this.pan.sx, dy = e.clientY - this.pan.sy;
      if (Math.hypot(dx, dy) > 6) this.pan.moved = true;
      if (this.pan.moved) {
        const s = G.TILE * G.state.camera.zoom;
        G.state.camera.x = this.pan.cx - dx / s;
        G.state.camera.y = this.pan.cy - dy / s;
        G.clampCamera();
      }
    }
  },

  onUp(e) {
    const S = G.state;
    if (this.pan) {
      const p = this.pan;
      this.pan = null;
      if (p.moved) return;
      if (p.button === 2) { this.rightClick(this.tileAt(e)); return; }
      if (p.button === 0 && S.tool === 'select') this.click(this.tileAt(e));
      return;
    }
    if (this.dragStart && S.tool === 'move') {
      const a = this.dragStart, b = this.tileAt(e);
      this.dragStart = null;
      if (a.x !== b.x || a.y !== b.y) G.Jobs.placeMove(a.x, a.y, b.x, b.y);
      else G.UI.toast('Halte die Maustaste gedrückt und ziehe vom Gerät zum Zielfeld.');
      return;
    }
    if (this.dragStart) {
      const tiles = this.dragTiles();
      this.dragStart = null;
      let count = 0;
      for (const t of tiles) if (G.Jobs.place(S.tool, t.x, t.y)) count++;
      if (!count && tiles.length === 1) G.UI.toast(this.whyNot(S.tool, tiles[0]));
    }
  },

  // Rechtsklick: Aufgaben abbrechen
  //  - auf einen Bauplan: Plan löschen
  //  - auf einen Charakter: er hört auf mit dem, was er gerade tut
  //  - sonst im Baumodus: zurück zur Auswahl
  rightClick(t) {
    const S = G.state;
    if (S.world.inBounds(t.x, t.y)) {
      const k = S.world.idx(t.x, t.y);
      const c = G.Chars.at(t.wx, t.wy);
      if (c) {
        if (c.job) { const j = c.job; G.Chars.releaseJob(c); G.Jobs.cancel(j); }
        G.Chars.releaseJob(c);
        G.Chars.stopActivity(c);
        c.order = null;
        G.UI.toast(c.name + ': Aufgabe abgebrochen.');
        return;
      }
      // Auch das Ziel eines "Versetzen"-Auftrags zählt
      let job = S.jobs.get(k);
      if (!job) job = [...S.jobs.values()].find(j => j.kind === 'move' && j.tx === t.x && j.ty === t.y);
      if (job) {
        G.Jobs.cancel(job);
        G.UI.toast('Bauplan abgebrochen.');
        return;
      }
    }
    if (S.tool !== 'select') G.UI.setTool('select');
  },

  // Klick mit dem Auswahl-Werkzeug
  click(t) {
    const S = G.state;
    const c = G.Chars.at(t.wx, t.wy);
    if (c) { S.selectedId = c.id; return; }
    // Kiste oder Haufen: Inhalt anzeigen
    if (S.world.inBounds(t.x, t.y)) {
      const i = S.world.idx(t.x, t.y);
      const dev = S.world.devices.get(i);
      if ((dev && dev.inv) || S.world.piles.has(i)) { G.UI.openSource(t.x, t.y); return; }
    }
    const sel = S.chars.find(ch => ch.id === S.selectedId) || S.chars[0];
    if (!sel) return;
    if (!S.world.walkable(t.x, t.y)) { G.UI.toast('Dorthin kann niemand laufen.'); return; }
    if (!G.Chars.orderMove(sel, t.x, t.y)) G.UI.toast(sel.name + ' findet keinen Weg dorthin.');
  },

  whyNot(tool, t) {
    const world = G.state.world;
    if (!world.inBounds(t.x, t.y)) return 'Das ist außerhalb der Karte.';
    if (tool === 'floor') return 'Boden kann nur im leeren Weltraum gebaut werden.';
    if (tool === 'wall') return 'Hier steht schon eine Wand oder Tür.';
    if (tool === 'door') return 'Hier ist schon eine Tür.';
    if (tool === 'remove') return 'Hier gibt es nichts zum Abreißen.';
    if (tool === 'cancel') return 'Hier ist kein Bauplan.';
    if (tool === 'repair') return 'Hier ist nichts beschädigt.';
    if (tool === 'cable') return world.get(t.x, t.y) === G.T.SPACE ? 'Kabel brauchen Boden oder Wand.' : 'Hier liegt schon ein Kabel.';
    if (tool.startsWith('dev:')) return 'Geräte brauchen einen freien Boden.';
    return '';
  },

  // Welche Kacheln sind beim Ziehen markiert?
  dragTiles() {
    const a = this.dragStart, b = this.hover;
    if (!a || !b) return null;
    const tool = G.state.tool;
    if (tool === 'door' || tool === 'repair' || tool === 'move') return [{ x: b.x, y: b.y }];
    const x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x);
    const y0 = Math.min(a.y, b.y), y1 = Math.max(a.y, b.y);
    const out = [];
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        // Wand: nur der Rand des Rechtecks (oder eine Linie)
        if (tool === 'wall' && x !== x0 && x !== x1 && y !== y0 && y !== y1) continue;
        out.push({ x, y });
      }
    }
    return out;
  },

  onWheel(e) {
    e.preventDefault();
    const rect = this.canvas.getBoundingClientRect();
    const sx = e.clientX - rect.left, sy = e.clientY - rect.top;
    const before = G.Render.screenToWorld(sx, sy);
    G.zoomBy(e.deltaY < 0 ? 1.12 : 1 / 1.12);
    // Zoomen zum Mauszeiger hin
    const after = G.Render.screenToWorld(sx, sy);
    G.state.camera.x += before.x - after.x;
    G.state.camera.y += before.y - after.y;
    G.clampCamera();
  },

  onKey(e) {
    if (e.target.closest && e.target.closest('input, textarea')) return;
    const k = e.key.toLowerCase();
    this.ctrl = e.ctrlKey || e.metaKey;
    if (!this.ctrl) this.keys.add(k);
    if (e.ctrlKey || e.metaKey) {
      if (k === 's') { e.preventDefault(); G.Save.save(); }
      return;
    }
    switch (k) {
      case ' ': e.preventDefault(); G.togglePause(); break;
      case '1': G.setSpeed(1); break;
      case '2': G.setSpeed(2); break;
      case '3': G.setSpeed(3); break;
      case 'escape': G.UI.setTool('select'); G.UI.showHelp(false); G.UI.showDevMenu(false); G.UI.closeSource(); break;
      case 'k': G.UI.setTool('cable'); break;
      case 'v': G.UI.setTool('move'); break;
      case 'r': G.UI.setTool('repair'); break;
      case '4': G.setSpeed(4); break;
      case 'g': G.UI.showDevMenu(); break;
      case 'l': G.UI.setView(G.state.view === 'air' ? 'normal' : 'air'); break;
      case 'p': G.UI.setView(G.state.view === 'power' ? 'normal' : 'power'); break;
      case 'b': G.UI.setTool('floor'); break;
      case 'm': G.UI.setTool('wall'); break;
      case 't': G.UI.setTool('door'); break;
      case 'x': G.UI.setTool('remove'); break;
      case 'c': G.UI.setTool('cancel'); break;
      case 'h': G.UI.showHelp(); break;
      case 'e': G.UI.interact(); break;
      case 'i': G.UI.toggleInv(); break;
      case '+': case '=': G.zoomBy(1.15); break;
      case '-': G.zoomBy(1 / 1.15); break;
    }
  },

  // Wird jedes Bild aufgerufen (echte Zeit, realDt in Sekunden)
  update(realDt) {
    const k = this.keys, cam = G.state.camera;
    // Ansicht mit den Pfeiltasten bewegen (auch in der Pause)
    const speed = 14 / cam.zoom * realDt;
    if (k.has('arrowleft')) cam.x -= speed;
    if (k.has('arrowright')) cam.x += speed;
    if (k.has('arrowup')) cam.y -= speed;
    if (k.has('arrowdown')) cam.y += speed;

    // Deine Figur mit WASD steuern (läuft immer in echter Geschwindigkeit, nicht in der Pause)
    const p = G.player();
    if (p && G.state.speedIndex > 0 && !this.ctrl) {
      let dx = 0, dy = 0;
      if (k.has('a')) dx -= 1;
      if (k.has('d')) dx += 1;
      if (k.has('w')) dy -= 1;
      if (k.has('s')) dy += 1;
      if (dx || dy) {
        const sprint = k.has('shift') ? G.SPRINT : 1;
        G.Chars.manualMove(p, dx, dy, G.WALK_SPEED / 60 * realDt * sprint);
        // Kamera folgt weich
        cam.x += (p.x - cam.x) * Math.min(1, realDt * 4);
        cam.y += (p.y - cam.y) * Math.min(1, realDt * 4);
      }
    }
    G.clampCamera();
  },
};
