# NotchPal website

The site for NotchPal: one page with a working demo of the island, plus a privacy page. It's plain HTML, CSS and JavaScript with no build step, no cookies and no tracking.

- `index.html`, `privacy.html`: the pages.
- `styles.css`: the ink wash look (ivory, cool gray, charcoal, and the black of the notch).
- `notch.js`: the demo island at the top of the page.
- `site.js`: points the Download button at the latest GitHub release.
- `_headers`: security headers for Cloudflare Pages.

To look at it on your Mac: `python3 -m http.server --directory website 8000`, then open http://localhost:8000.

The typeface is Archivo, under the SIL Open Font License (`fonts/OFL.txt`).
