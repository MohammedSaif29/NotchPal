// Scroll motion for the home page:
//  - the big paragraph fills in with ink, word by word, as you read it
//  - screenshots open out of a notch shape as they scroll in, like the island does
//  - "A day with NotchPal": a line fills down the day and each stop's island opens in turn
// With "reduce motion" switched on (or without JavaScript), everything simply shows in its
// finished state: the CSS only animates when this script adds the "moving" class.
(() => {
  "use strict";
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  document.documentElement.classList.add("moving");

  const clamp = (value, low = 0, high = 1) => Math.min(high, Math.max(low, value));
  const easeOut = (t) => 1 - Math.pow(1 - t, 3);
  const jobs = [];

  // Words that fill in with ink
  document.querySelectorAll("[data-fill]").forEach((paragraph) => {
    const words = paragraph.textContent.trim().split(/\s+/);
    paragraph.textContent = "";
    paragraph.style.setProperty("--n", words.length);
    words.forEach((word, index) => {
      const span = document.createElement("span");
      span.className = "word";
      span.style.setProperty("--i", index);
      span.textContent = word;
      paragraph.append(span, index < words.length - 1 ? " " : "");
    });
    jobs.push((height) => {
      const box = paragraph.getBoundingClientRect();
      const progress = clamp((height * 0.85 - box.top) / (box.height + height * 0.2));
      paragraph.style.setProperty("--p", progress.toFixed(4));
    });
  });

  // Screenshots that open like the island
  document.querySelectorAll(".feature .screen").forEach((screen) => {
    jobs.push((height) => {
      const box = screen.getBoundingClientRect();
      const progress = easeOut(clamp((height * 0.98 - box.top) / (height * 0.55)));
      screen.style.setProperty("--open", progress.toFixed(4));
    });
  });

  // A day with NotchPal
  const track = document.querySelector(".day-track");
  if (track) {
    const items = [...track.querySelectorAll(".day-item")];
    const callClock = track.querySelector("[data-call-clock]");
    let now = -2;
    let callTimer = 0;

    const startCall = () => {
      let seconds = 0;
      const show = () => { callClock.textContent = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`; };
      show();
      callTimer = window.setInterval(() => { seconds += 1; show(); }, 1000);
    };
    const stopCall = () => { window.clearInterval(callTimer); callTimer = 0; };

    jobs.push((height) => {
      const box = track.getBoundingClientRect();
      const middle = height * 0.5;
      track.style.setProperty("--fill", `${clamp(middle - box.top, 0, box.height).toFixed(1)}px`);

      // A stop lights up once its time reaches the middle of the screen, and stays lit.
      let latest = -1;
      items.forEach((item, index) => {
        const time = item.querySelector(".day-time").getBoundingClientRect();
        const on = time.top + time.height / 2 <= middle + 1;
        item.classList.toggle("is-on", on);
        if (on) latest = index;
      });
      if (latest !== now) {
        now = latest;
        items.forEach((item, index) => item.classList.toggle("is-now", index === now));
        const call = items[now] && items[now].hasAttribute("data-call");
        if (callClock) { stopCall(); if (call) startCall(); }
      }
    });
  }

  let queued = false;
  const run = () => {
    queued = false;
    const height = window.innerHeight;
    jobs.forEach((job) => job(height));
  };
  const queue = () => {
    if (!queued) { queued = true; window.requestAnimationFrame(run); }
  };
  window.addEventListener("scroll", queue, { passive: true });
  window.addEventListener("resize", queue);
  run();
})();
