// ============================================================
// main.js – Startet das Spiel und hält die Spielschleife am Laufen
// ============================================================

G.state = {
  world: null,
  jobs: new Map(),
  chars: [],
  time: 0,          // vergangene Spielminuten seit Spielbeginn
  speedIndex: 1,    // Index in G.SPEEDS (0 = Pause)
  lastSpeedIndex: 1,
  camera: { x: 0, y: 0, zoom: 1.4 },
  tool: 'select',
  selectedId: null,
};

G.newGame = function () {
  const world = new G.World(G.WORLD_W, G.WORLD_H);
  const start = G.createStartShip(world);
  G.Chars.nextId = 1;
  const mira = G.Chars.create('Mira Okafor', start.x, start.y, '#f2a33a');
  G.state.world = world;
  G.state.jobs = new Map();
  G.state.chars = [mira];
  G.state.time = 0;
  G.state.selectedId = mira.id;
  G.state.camera = { x: world.w / 2, y: world.h / 2, zoom: 1.4 };
};

G.setSpeed = function (i) {
  G.state.speedIndex = i;
  if (i > 0) G.state.lastSpeedIndex = i;
};

G.togglePause = function () {
  G.setSpeed(G.state.speedIndex === 0 ? G.state.lastSpeedIndex : 0);
};

G.zoomBy = function (f) {
  const cam = G.state.camera;
  cam.zoom = Math.min(3, Math.max(0.35, cam.zoom * f));
};

G.clampCamera = function () {
  const cam = G.state.camera, w = G.state.world;
  cam.x = Math.min(w.w, Math.max(0, cam.x));
  cam.y = Math.min(w.h, Math.max(0, cam.y));
};

// Ein Simulationsschritt (dt in Spielminuten)
G.step = function (dt) {
  G.state.time += dt;
  for (const c of G.state.chars) G.Chars.update(c, dt);
};

G.start = function () {
  const canvas = document.getElementById('game');
  G.Render.init(canvas);
  G.Input.init(canvas);
  if (!G.Save.load(true)) G.newGame();
  G.UI.init();

  // Erster Besuch: Hilfe zeigen
  let seen = false;
  try { seen = localStorage.getItem('weltraum_game_help_seen') === '1'; } catch (err) { /* egal */ }
  G.UI.showHelp(!seen);
  try { localStorage.setItem('weltraum_game_help_seen', '1'); } catch (err) { /* egal */ }

  // Automatisch speichern, jede Minute (echte Zeit)
  setInterval(() => G.Save.save(true), 60000);

  const STEP = 1 / 3; // Spielminuten pro Simulationsschritt
  let last = performance.now(), acc = 0;
  function frame(now) {
    const realDt = Math.min(0.1, (now - last) / 1000);
    last = now;
    G.Input.update(realDt);
    acc += realDt * G.SPEEDS[G.state.speedIndex] * G.MINUTES_PER_SECOND;
    let n = 0;
    while (acc >= STEP && n < 200) { G.step(STEP); acc -= STEP; n++; }
    if (n === 200) acc = 0;
    G.Render.draw();
    G.UI.update();
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
};

window.addEventListener('DOMContentLoaded', G.start);
