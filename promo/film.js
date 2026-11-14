// NotchPal promo film. render(t) draws the exact frame at t seconds, so promo/render.py can
// record the film frame by frame. 1080 × 1080, about 24 seconds.
"use strict";

const $ = (id) => document.getElementById(id);
const island = $("island"), notch = $("notch"), card = $("island-card"), bubble = $("bubble");
const ink = $("island-ink"), inkNotch = $("ink-notch"), inkCard = $("ink-card"), inkDrop = $("ink-drop"), inkBubble = $("ink-bubble");
const intro = $("island-intro"), glow = $("glow"), cursor = $("cursor");
const input = $("search-input"), results = $("results"), answer = $("answer"), callTime = $("call-time");
const lead = notch.querySelector(".notch-lead"), trail = notch.querySelector(".notch-trail");

const NW = 200, NH = 34, GAP = 10, REACH = 46, FRAME = 1080;
const DURATION = 24;

const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, p) => a + (b - a) * p;
const span = (t, a, b) => clamp((t - a) / (b - a));
const smooth = (p) => { p = clamp(p); return p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2; };
const out = (p) => 1 - Math.pow(1 - clamp(p), 3);
// Settles with a small overshoot, like the app's spring.
const spring = (p) => { p = clamp(p); return p >= 1 ? 1 : 1 - Math.exp(-6 * p) * Math.cos(8.5 * p); };

// A caption fades and rises in, then fades out.
function caption(el, t, a, b) {
  const shown = Math.min(out(span(t, a, a + 0.4)), 1 - smooth(span(t, b - 0.3, b)));
  el.style.opacity = shown;
  el.style.transform = `translateY(${(1 - out(span(t, a, a + 0.4))) * 24}px)`;
}

function setRows(rows, selected = 0) {
  const key = JSON.stringify(rows) + selected;
  if (results.dataset.key === key) return;
  results.dataset.key = key;
  results.replaceChildren(...rows.map(([glyph, title, detail], index) => {
    const item = document.createElement("li");
    item.setAttribute("aria-selected", String(index === selected));
    const g = document.createElement("span"); g.className = "glyph"; g.textContent = glyph;
    const s = document.createElement("strong"); s.textContent = title;
    const d = document.createElement("small"); d.textContent = detail;
    item.append(g, s, d);
    return item;
  }));
}

const QUESTION = "Plan a 20-minute study break";
const ANSWER = "Stretch for five minutes, drink some water, take a short walk, then rest your eyes until the timer ends.";

function render(t) {
  // ----- What the island shows -----
  const searching = t >= 10.95 && t < 15.9;
  island.dataset.state = t >= 7.6 && t < 15.9 ? (searching ? "search" : "home") : "closed";
  island.dataset.live = t >= 16.05 && t < 19.9 ? "call" : "music";
  $("clock").textContent = "4:20 PM";

  // Song progress and the visualiser move with time.
  card.querySelector(".progress b").style.width = `${clamp(0.46 + (t - 7.6) * 0.012, 0.46, 0.6) * 100}%`;
  document.querySelectorAll(".wave i").forEach((bar, index) => {
    const phase = [0, 2.1, 4.2, 1.2][index % 4];
    bar.style.transform = `scaleY(${0.35 + 0.65 * (0.5 + 0.5 * Math.sin(t * 5.7 + phase))})`;
  });
  callTime.textContent = `0:${String(42 + Math.max(0, Math.floor(t - 16.05))).padStart(2, "0")}`;

  // Search: first a sum, then a question for Apple Intelligence.
  if (searching) {
    if (t < 13.0) {
      const typed = "24*7".slice(0, Math.floor(span(t, 11.35, 11.95) * 4 + 0.001));
      input.value = typed;
      setRows(typed === "24*7"
        ? [["±", "= 168", "Press Return to copy"], ["✦", "Ask Apple Intelligence", "24*7"], ["↗", "Search the web for “24*7”", "Google"]]
        : typed
          ? [["✦", "Ask Apple Intelligence", typed], ["↗", `Search the web for “${typed}”`, "Google"]]
          : [["±", "Try 24*7", "Maths as you type"], ["⏱", "Try timer 10m", "Quick commands"], ["✦", "Try a question", "Ask Apple Intelligence"]]);
      answer.textContent = "";
    } else {
      const typed = QUESTION.slice(0, Math.floor(span(t, 13.05, 13.9) * QUESTION.length + 0.001));
      input.value = typed;
      setRows(typed ? [["✦", "Ask Apple Intelligence", typed], ["↗", `Search the web for “${typed}”`, "Google"]] : [], 0);
      answer.textContent = t >= 14.15 ? ANSWER.slice(0, Math.floor(span(t, 14.15, 14.95) * ANSWER.length + 0.001)) : "";
    }
  }

  // The island is drawn 1.8× so it reads on a phone, and the camera moves in on the notch for the Live Activity.
  const SCALE = lerp(1.8, 2.6, smooth(span(t, 15.95, 16.5)) * (1 - smooth(span(t, 19.35, 19.9))));
  island.style.transform = `scale(${SCALE})`;

  // ----- How far the island has floated out -----
  let open = 0;
  if (t < 10.75) open = spring(span(t, 7.65, 8.75));
  else if (t < 11.25) open = 1 - 0.14 * Math.sin(Math.PI * span(t, 10.75, 11.25)); // a small squash as it turns into search
  else if (t < 15.35) open = 1;
  else open = 1 - smooth(span(t, 15.35, 15.95));

  // The call's music splitting off like a droplet, then melting back.
  const split = t < 19.4 ? spring(span(t, 16.6, 17.35)) : 1 - smooth(span(t, 19.4, 19.95));

  // ----- The pointer -----
  const path = [
    [6.3, 960, 980], [7.45, 548, 74], [7.85, 548, 74], [8.6, 1066, 150],
  ];
  let px = null, py = null, cursorOpacity = 0, press = 1;
  if (t >= path[0][0] && t <= path[3][0]) {
    let i = 0;
    while (i < path.length - 2 && t > path[i + 1][0]) i++;
    const [ta, xa, ya] = path[i], [tb, xb, yb] = path[i + 1];
    const p = smooth(span(t, ta, tb));
    px = lerp(xa, xb, p); py = lerp(ya, yb, p);
    cursorOpacity = Math.min(span(t, 6.3, 6.5), 1 - span(t, 8.3, 8.6));
    if (t > 7.5 && t < 7.75) press = 1 - 0.18 * Math.sin(Math.PI * span(t, 7.5, 7.75));
  }
  cursor.style.opacity = cursorOpacity;
  if (px !== null) cursor.style.transform = `translate(${px - 6}px, ${py - 4}px) scale(${press})`;

  // The black hole: the notch reaches toward the pointer before the click.
  let drop = null;
  if (px !== null && t < 7.62) {
    const x = (px - FRAME / 2) / SCALE, y = py / SCALE;
    const below = y - NH;
    if (below > -2 && below < REACH && Math.abs(x) < NW / 2 + 30) {
      const pull = 1 - Math.max(0, below) / REACH;
      drop = { x: clamp(x, -NW / 2 + 10, NW / 2 - 10), y: NH + Math.max(0, below) * 0.55, r: 4 + 9 * pull };
    }
  }

  // ----- Draw the island -----
  const cardW = card.offsetWidth, cardH = card.offsetHeight;
  const width = Math.max(cardW, NW + 160) + 80, height = NH + GAP + cardH + 80, c = width / 2;
  for (const svg of [ink, intro]) {
    svg.setAttribute("width", width); svg.setAttribute("height", height);
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
  }
  inkNotch.setAttribute("x", c - NW / 2); inkNotch.setAttribute("y", -12);
  inkNotch.setAttribute("width", NW); inkNotch.setAttribute("height", NH + 12);

  const top = lerp(NH - 18, NH + GAP, open);
  // The spring may overshoot a little, but never so far that the island leaves the frame.
  const scaleX = 0.2 + 0.8 * Math.min(open, 1.03), scaleY = 0.1 + 0.9 * Math.min(open, 1.05);
  card.style.transform = `translateY(${top}px) scale(${scaleX}, ${scaleY})`;
  card.style.opacity = Math.min(1, clamp(open) * 1.8);
  card.style.visibility = open < 0.01 ? "hidden" : "visible";
  const joining = open > 0.02 && open < 0.97;
  if (joining) {
    const w = cardW * scaleX, h = cardH * scaleY;
    inkCard.setAttribute("x", c - w / 2); inkCard.setAttribute("y", top);
    inkCard.setAttribute("width", w); inkCard.setAttribute("height", h); inkCard.setAttribute("rx", Math.min(26, h / 2));
  } else {
    inkCard.setAttribute("width", 0); inkCard.setAttribute("height", 0);
  }

  const splitting = split > 0.02 && split < 0.97;
  const edge = c + NW / 2;
  if (splitting) {
    inkBubble.setAttribute("cx", edge - 12 + split * (20 + NH / 2));
    inkBubble.setAttribute("cy", NH / 2);
    inkBubble.setAttribute("r", 6 + (NH / 2 - 6) * split);
  } else inkBubble.setAttribute("r", 0);
  bubble.style.opacity = Math.max(0, (split - 0.6) / 0.4);
  bubble.style.transform = `translateX(${(split - 1) * 16}px) scale(${0.6 + 0.4 * clamp(split)})`;

  if (drop) { inkDrop.setAttribute("cx", c + drop.x); inkDrop.setAttribute("cy", drop.y); inkDrop.setAttribute("r", drop.r); }
  else inkDrop.setAttribute("r", 0);
  ink.style.display = joining || splitting || drop ? "block" : "none";

  // Apple Intelligence's rainbow glow around the island while it thinks and answers.
  const glowing = Math.min(out(span(t, 13.95, 14.25)), 1 - smooth(span(t, 15.0, 15.4)));
  glow.style.opacity = glowing * 0.9;
  glow.style.width = `${cardW + 28}px`; glow.style.height = `${cardH + 28}px`;
  glow.style.marginLeft = `${-(cardW + 28) / 2}px`;
  glow.style.top = `${NH + GAP - 14}px`;
  glow.style.setProperty("--spin", `${t * 140}deg`);

  // ----- Opening: two lines trace the notch and meet, then it fills in -----
  const halfW = NW / 2 + 4, bottom = NH + 4;
  const side = (dir) => `M ${c + dir * halfW} 0 V ${bottom - 11} Q ${c + dir * halfW} ${bottom} ${c + dir * (halfW - 11)} ${bottom} H ${c}`;
  $("intro-left").setAttribute("d", side(-1)); $("intro-right").setAttribute("d", side(1));
  for (const id of ["intro-left", "intro-right"]) {
    const line = $(id);
    line.setAttribute("pathLength", 1);
    line.style.strokeDashoffset = String(1 - smooth(span(t, 0.25, 1.35)));
    line.style.opacity = String(1 - span(t, 1.5, 1.9));
  }
  notch.style.opacity = smooth(span(t, 1.25, 1.6));
  const content = t < 15.95 || t > 16.15 ? 1 : 0;
  const contentFade = Math.min(smooth(span(t, 3.6, 4.1)), t > 15.85 && t < 16.25 ? Math.abs(t - 16.05) / 0.2 : 1, content || 0.0001);
  lead.style.opacity = trail.style.opacity = String(contentFade);

  // ----- Words -----
  caption($("cap-hook-1"), t, 0.35, 2.0);
  caption($("cap-hook-2"), t, 2.1, 3.55);
  caption($("cap-float"), t, 6.35, 10.55);
  caption($("cap-search"), t, 10.65, 15.3);
  caption($("cap-live"), t, 15.55, 19.3);
  const title = Math.min(out(span(t, 3.65, 4.15)), 1 - smooth(span(t, 5.85, 6.2)));
  $("brand-title").style.opacity = title;
  $("brand-title").style.transform = `translateY(${(1 - out(span(t, 3.65, 4.15))) * 28}px)`;
  const end = out(span(t, 19.85, 20.45));
  $("brand-end").style.opacity = end;
  $("brand-end").style.transform = `translateY(${(1 - end) * 28}px)`;
}

window.render = render;
window.DURATION = DURATION;
render(0);
