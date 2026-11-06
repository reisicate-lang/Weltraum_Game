// ============================================================
// pathfinding.js – Wegfindung
// Berechnet, wie ein Charakter von A nach B läuft, ohne durch
// Wände zu gehen. Diagonal laufen ist erlaubt, aber nicht
// "um die Ecke" durch zwei Wände hindurch.
// ============================================================

G.Path = {
  // Die 8 Nachbar-Richtungen mit ihren Kosten
  DIRS: [
    [1, 0, 1], [-1, 0, 1], [0, 1, 1], [0, -1, 1],
    [1, 1, Math.SQRT2], [1, -1, Math.SQRT2], [-1, 1, Math.SQRT2], [-1, -1, Math.SQRT2],
  ],

  // Berechnet von einem Startpunkt aus die Entfernung zu ALLEN
  // erreichbaren Kacheln (Dijkstra-Algorithmus).
  // dist[i] = Entfernung, prev[i] = vorherige Kachel auf dem Weg
  fromPoint(sx, sy) {
    const world = G.state.world;
    const n = world.w * world.h;
    const dist = new Float32Array(n).fill(Infinity);
    const prev = new Int32Array(n).fill(-1);
    const heap = new G.MinHeap();
    const start = world.idx(sx, sy);
    dist[start] = 0;
    heap.push(start, 0);

    while (heap.size) {
      const { item: cur, prio } = heap.pop();
      if (prio > dist[cur]) continue;
      const cx = cur % world.w, cy = (cur / world.w) | 0;
      for (const [dx, dy, cost] of this.DIRS) {
        const nx = cx + dx, ny = cy + dy;
        if (!world.walkable(nx, ny)) continue;
        // Keine Abkürzung diagonal an Wandecken vorbei
        if (dx && dy && (!world.walkable(cx + dx, cy) || !world.walkable(cx, cy + dy))) continue;
        const ni = world.idx(nx, ny);
        const nd = dist[cur] + cost;
        if (nd < dist[ni]) {
          dist[ni] = nd;
          prev[ni] = cur;
          heap.push(ni, nd);
        }
      }
    }
    return { dist, prev };
  },

  // Macht aus der prev-Liste einen Weg (ohne die Startkachel)
  buildPath(prev, targetIdx) {
    const world = G.state.world;
    const path = [];
    let cur = targetIdx;
    while (cur !== -1 && prev[cur] !== -1) {
      path.push({ x: cur % world.w, y: (cur / world.w) | 0 });
      cur = prev[cur];
    }
    return path.reverse();
  },

  // Weg von (sx,sy) nach (tx,ty). Gibt null zurück, wenn es keinen Weg gibt.
  find(sx, sy, tx, ty) {
    const world = G.state.world;
    if (!world.walkable(tx, ty)) return null;
    if (sx === tx && sy === ty) return [];
    const { dist, prev } = this.fromPoint(sx, sy);
    const ti = world.idx(tx, ty);
    if (dist[ti] === Infinity) return null;
    return this.buildPath(prev, ti);
  },
};

// Eine kleine Prioritäts-Warteschlange (holt immer das kleinste Element zuerst)
G.MinHeap = class MinHeap {
  constructor() { this.items = []; this.prios = []; }
  get size() { return this.items.length; }
  push(item, prio) {
    const a = this.items, p = this.prios;
    a.push(item); p.push(prio);
    let i = a.length - 1;
    while (i > 0) {
      const parent = (i - 1) >> 1;
      if (p[parent] <= p[i]) break;
      [a[i], a[parent]] = [a[parent], a[i]];
      [p[i], p[parent]] = [p[parent], p[i]];
      i = parent;
    }
  }
  pop() {
    const a = this.items, p = this.prios;
    const top = { item: a[0], prio: p[0] };
    const lastItem = a.pop(), lastPrio = p.pop();
    if (a.length) {
      a[0] = lastItem; p[0] = lastPrio;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1, r = l + 1;
        let m = i;
        if (l < a.length && p[l] < p[m]) m = l;
        if (r < a.length && p[r] < p[m]) m = r;
        if (m === i) break;
        [a[i], a[m]] = [a[m], a[i]];
        [p[i], p[m]] = [p[m], p[i]];
        i = m;
      }
    }
    return top;
  }
};
