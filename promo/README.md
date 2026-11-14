# NotchPal promo film

A 24-second, 1080 × 1080 motion graphic for social media, drawn with the website's own island.
Every frame comes from `render(t)` in `film.js`, so it records the same way every time.

```bash
python3 -m http.server 8766          # from the NotchPal folder
python3 promo/render.py notchpal-demo.mp4
```

Needs Python Playwright with Chromium, and ffmpeg.
