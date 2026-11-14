// A small working copy of NotchPal's island for the website: click the notch and the island
// splits off and floats below it, the pointer gets pulled in, and a second Live Activity
// splits off like a droplet. Nothing here talks to the network.
(() => {
  "use strict";

  const island = document.getElementById("island");
  if (!island) return;
  const notch = document.getElementById("notch");
  const card = document.getElementById("island-card");
  const bubble = document.getElementById("bubble");
  const ink = document.getElementById("island-ink");
  const inkNotch = document.getElementById("ink-notch");
  const inkCard = document.getElementById("ink-card");
  const inkDrop = document.getElementById("ink-drop");
  const inkBubble = document.getElementById("ink-bubble");
  const intro = document.getElementById("island-intro");
  const input = document.getElementById("search-input");
  const results = document.getElementById("results");
  const answer = document.getElementById("answer");
  const callTime = document.getElementById("call-time");
  const clock = document.getElementById("clock");
  const play = document.getElementById("play");

  const calm = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const GAP = 10;
  const REACH = 46;

  let size = { notchW: 200, notchH: 34, cardW: 560, cardH: 200, width: 700 };
  let open = 0;        // 0 tucked inside the notch, 1 floating
  let split = 0;       // the second activity's droplet
  let drop = null;     // the pointer's pull: {x, y, r}
  let neck = null;     // the stretchy join, set in drawCard

  // ----- Geometry -----

  function measure() {
    const style = getComputedStyle(document.documentElement);
    size.notchW = parseFloat(style.getPropertyValue("--notch-w")) || 200;
    size.notchH = parseFloat(style.getPropertyValue("--notch-h")) || 34;
    size.cardW = card.offsetWidth;
    size.cardH = card.offsetHeight;
    size.width = Math.max(size.cardW, size.notchW + 160) + 80;
    const height = size.notchH + GAP + size.cardH + 60;
    for (const svg of [ink, intro]) {
      svg.setAttribute("width", size.width);
      svg.setAttribute("height", height);
      svg.setAttribute("viewBox", `0 0 ${size.width} ${height}`);
    }
    const c = size.width / 2;
    set(inkNotch, { x: c - size.notchW / 2, y: -12, width: size.notchW, height: size.notchH + 12 });
    drawIntro(c);
    draw();
  }

  function set(node, attributes) {
    for (const key in attributes) node.setAttribute(key, attributes[key]);
  }

  // Two lines trace the notch from its top corners and meet in the middle, like NotchPal's launch.
  function drawIntro(c) {
    const half = size.notchW / 2 + 4;
    const bottom = size.notchH + 4;
    const side = (dir) => `M ${c + dir * half} 0 V ${bottom - 11} Q ${c + dir * half} ${bottom} ${c + dir * (half - 11)} ${bottom} H ${c}`;
    for (const [id, dir] of [["intro-left", -1], ["intro-right", 1]]) {
      set(document.getElementById(id), { d: side(dir), pathLength: 1 });
    }
  }

  // ----- Drawing -----

  function draw() {
    const c = size.width / 2;
    const p = Math.max(0, open);
    const clamped = Math.min(1, p);
    const startTop = size.notchH - 18;
    const finalTop = size.notchH + GAP;
    const top = startTop + (finalTop - startTop) * p;
    const scaleX = 0.2 + 0.8 * p;
    const scaleY = 0.1 + 0.9 * p;

    card.style.transform = `translateY(${top}px) scale(${scaleX}, ${scaleY})`;
    card.style.opacity = Math.min(1, clamped * 1.8);
    card.style.visibility = p < 0.01 ? "hidden" : "visible";

    const joining = clamped > 0.02 && clamped < 0.97;
    if (joining) {
      const width = size.cardW * scaleX;
      const height = size.cardH * scaleY;
      set(inkCard, { x: c - width / 2, y: top, width, height, rx: Math.min(26, height / 2) });
      neck = Math.min(size.notchW * 0.55, Math.max(40, width * 0.6));
    } else {
      set(inkCard, { width: 0, height: 0 });
    }

    const q = Math.min(1, Math.max(0, split));
    const splitting = q > 0.02 && q < 0.97;
    const edge = c + size.notchW / 2;
    set(inkBubble, splitting
      ? { cx: edge - 12 + q * (20 + size.notchH / 2), cy: size.notchH / 2, r: 6 + (size.notchH / 2 - 6) * q }
      : { r: 0 });
    bubble.style.opacity = Math.max(0, (q - 0.6) / 0.4);
    bubble.style.transform = `translateX(${(q - 1) * 16}px) scale(${0.6 + 0.4 * q})`;

    set(inkDrop, drop ? { cx: c + drop.x, cy: drop.y, r: drop.r } : { r: 0 });
    ink.style.display = joining || splitting || drop ? "block" : "none";
  }

  // A spring, so the island overshoots a touch and settles, like the app.
  function spring(read, write) {
    let velocity = 0, target = read(), frame = 0, last = 0;
    function step(now) {
      const dt = Math.min(0.032, (now - last) / 1000 || 0.016);
      last = now;
      const value = read();
      velocity += (190 * (target - value) - 21 * velocity) * dt;
      const next = value + velocity * dt;
      if (Math.abs(target - next) < 0.001 && Math.abs(velocity) < 0.01) {
        write(target); frame = 0; draw(); return;
      }
      write(next); draw();
      frame = requestAnimationFrame(step);
    }
    return (to) => {
      target = to;
      if (calm) { write(to); draw(); return; }
      if (!frame) { last = performance.now(); frame = requestAnimationFrame(step); }
    };
  }
  const moveOpen = spring(() => open, (v) => { open = v; });
  const moveSplit = spring(() => split, (v) => { split = v; });

  // ----- Opening and closing -----

  function show(state) {
    const was = island.dataset.state;
    if (state === was) return;
    island.dataset.state = state;
    const isOpen = state !== "closed";
    notch.setAttribute("aria-expanded", String(isOpen));
    card.inert = !isOpen;
    drop = null;
    if (isOpen) {
      setLive("music");
      if (state === "search") renderResults();
      size.cardH = card.offsetHeight;
      moveOpen(1);
      if (state === "search") input.focus({ preventScroll: true });
    } else {
      moveOpen(0);
      if (card.contains(document.activeElement)) notch.focus({ preventScroll: true });
    }
  }

  notch.addEventListener("click", () => show(island.dataset.state === "closed" ? "home" : "closed"));
  document.getElementById("open-search").addEventListener("click", () => show("search"));
  document.getElementById("ask-orb").addEventListener("click", () => {
    show("search");
    input.value = "What can NotchPal do?";
    renderResults();
  });
  play.addEventListener("click", () => {
    const paused = island.classList.toggle("is-paused");
    play.setAttribute("aria-label", paused ? "Play" : "Pause");
  });

  document.addEventListener("pointerdown", (event) => {
    if (island.dataset.state !== "closed" && !island.contains(event.target)) show("closed");
  });
  document.addEventListener("keydown", (event) => {
    if (event.altKey && event.code === "Space") {
      event.preventDefault();
      show(island.dataset.state === "search" ? "closed" : "search");
    } else if (event.key === "Escape" && island.dataset.state !== "closed") {
      show("closed");
    }
  });

  // ----- The pointer's black hole -----

  if (!calm) {
    window.addEventListener("pointermove", (event) => {
      if (event.pointerType !== "mouse" || island.dataset.state !== "closed") return;
      const x = event.clientX - window.innerWidth / 2;
      const below = event.clientY - size.notchH;
      const half = size.notchW / 2;
      const near = below > -2 && below < REACH && Math.abs(x) < half + 30;
      if (!near && !drop) return;
      if (near) {
        const pull = 1 - Math.max(0, below) / REACH;
        drop = { x: Math.max(-half + 10, Math.min(half - 10, x)), y: size.notchH + Math.max(0, below) * 0.55, r: 4 + 9 * pull };
      } else {
        drop = null;
      }
      draw();
    }, { passive: true });
  }

  // ----- Live Activities: music, then a call with the music split off -----

  let callStarted = 0;
  function setLive(kind) {
    if (island.dataset.live === kind) return;
    island.dataset.live = kind;
    if (kind === "call") callStarted = Date.now();
    moveSplit(kind === "call" ? 1 : 0);
  }
  function tick() {
    const now = new Date();
    clock.textContent = now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
    if (island.dataset.live === "call") {
      const seconds = Math.floor((Date.now() - callStarted) / 1000);
      callTime.textContent = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
    }
  }
  setInterval(tick, 1000);
  tick();
  if (!calm) {
    setInterval(() => {
      if (island.dataset.state !== "closed" || document.hidden) return;
      setLive(island.dataset.live === "music" ? "call" : "music");
    }, 7000);
  }

  // ----- Search -----

  const apps = ["Safari", "Music", "Notes", "Calendar", "Mail", "Messages", "Photos", "Maps", "Finder", "FaceTime", "System Settings", "Terminal"];
  let rows = [];
  let selected = 0;

  // A small, safe calculator: numbers, + - * / and brackets. It never runs the text as code.
  function calculate(text) {
    if (!/^[\d\s+\-*/().×÷]+$/.test(text) || !/\d/.test(text) || !/[+\-*/×÷]/.test(text)) return null;
    const source = text.replace(/×/g, "*").replace(/÷/g, "/").replace(/\s+/g, "");
    let at = 0;
    const peek = () => source[at];
    function number() {
      if (peek() === "(") { at++; const value = sum(); if (peek() !== ")") throw 0; at++; return value; }
      if (peek() === "-") { at++; return -number(); }
      const match = /^\d+(\.\d+)?|^\.\d+/.exec(source.slice(at));
      if (!match) throw 0;
      at += match[0].length;
      return parseFloat(match[0]);
    }
    function product() {
      let value = number();
      while (peek() === "*" || peek() === "/") { const op = source[at++]; const right = number(); value = op === "*" ? value * right : value / right; }
      return value;
    }
    function sum() {
      let value = product();
      while (peek() === "+" || peek() === "-") { const op = source[at++]; const right = product(); value = op === "+" ? value + right : value - right; }
      return value;
    }
    try {
      const value = sum();
      if (at !== source.length || !isFinite(value)) return null;
      return String(Math.round(value * 1e9) / 1e9);
    } catch { return null; }
  }

  function findRows(text) {
    const query = text.trim();
    if (!query) {
      return [
        { glyph: "±", title: "Try 24*7", detail: "Maths as you type", fill: "24*7" },
        { glyph: "⏱", title: "Try timer 10m", detail: "Quick commands", fill: "timer 10m" },
        { glyph: "✦", title: "Try a question", detail: "Ask Apple Intelligence", fill: "What can NotchPal do?" },
      ];
    }
    const found = [];
    const result = calculate(query);
    if (result !== null) found.push({ glyph: "±", title: `= ${result}`, detail: "Press Return to copy", say: `In NotchPal, Return copies ${result}.` });
    const timer = /^timer\s+(\d+)\s*(m|min|minutes?)?$/i.exec(query);
    if (timer) found.push({ glyph: "⏱", title: `Start a ${timer[1]} minute timer`, detail: "Timer", say: `In NotchPal, this starts a ${timer[1]} minute timer in the notch.` });
    const note = /^note\s+(.+)$/i.exec(query);
    if (note) found.push({ glyph: "✎", title: `Add “${note[1]}” to Notes`, detail: "Notes", say: "In NotchPal, this adds a line to your notes." });
    for (const app of apps) {
      if (found.length < 4 && app.toLowerCase().startsWith(query.toLowerCase())) {
        found.push({ glyph: app[0], title: app, detail: "App", say: `In NotchPal, this opens ${app}.` });
      }
    }
    found.push({ glyph: "✦", title: "Ask Apple Intelligence", detail: query, say: "This page is only a demo. In NotchPal, Apple Intelligence answers right here, privately on your Mac." });
    found.push({ glyph: "↗", title: `Search the web for “${query}”`, detail: "Google", say: "In NotchPal, this opens your browser with the results." });
    return found.slice(0, 5);
  }

  function renderResults() {
    rows = findRows(input.value);
    selected = 0;
    answer.textContent = "";
    results.replaceChildren(...rows.map((row, index) => {
      const item = document.createElement("li");
      item.setAttribute("aria-selected", String(index === selected));
      const glyph = document.createElement("span");
      glyph.className = "glyph";
      glyph.textContent = row.glyph;
      const title = document.createElement("strong");
      title.textContent = row.title;
      const detail = document.createElement("small");
      detail.textContent = row.detail;
      item.append(glyph, title, detail);
      item.addEventListener("click", () => { selected = index; run(); });
      return item;
    }));
    resize();
  }

  function mark() {
    [...results.children].forEach((item, index) => item.setAttribute("aria-selected", String(index === selected)));
  }

  function run() {
    const row = rows[selected];
    if (!row) return;
    if (row.fill) { input.value = row.fill; renderResults(); input.focus({ preventScroll: true }); return; }
    mark();
    answer.textContent = row.say;
    resize();
  }

  function resize() {
    size.cardH = card.offsetHeight;
    draw();
  }

  input.addEventListener("input", renderResults);
  input.addEventListener("keydown", (event) => {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      selected = (selected + (event.key === "ArrowDown" ? 1 : rows.length - 1)) % rows.length;
      mark();
    } else if (event.key === "Enter") {
      event.preventDefault();
      run();
    }
  });

  window.addEventListener("resize", measure);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(measure);
  measure();
})();
