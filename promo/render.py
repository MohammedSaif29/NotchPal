"""Records the NotchPal promo film (promo/film.html) to an MP4, one exact frame at a time.

    python3 -m http.server 8766          # from the NotchPal folder, in another terminal
    python3 promo/render.py out.mp4

Needs Python Playwright with Chromium, and ffmpeg.
"""
import asyncio
import os
import subprocess
import sys
import tempfile

from playwright.async_api import async_playwright

FPS = 30
URL = "http://localhost:8766/promo/film.html"
# Cut points where nothing is moving between scenes, so each scene is its own file.
SCENES = [(0, 3.6), (3.6, 6.2), (6.2, 10.6), (10.6, 15.4), (15.4, 19.4), (19.4, 24.0)]
ENCODE = ["-c:v", "libx264", "-crf", "18", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-r", str(FPS)]


async def record(page, start, end, path):
    temporary = path + ".part.mp4"
    ffmpeg = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", str(FPS), "-i", "-", *ENCODE, temporary],
        stdin=subprocess.PIPE,
    )
    frames = round((end - start) * FPS)
    for index in range(frames):
        await page.evaluate(f"render({start + index / FPS})")
        ffmpeg.stdin.write(await page.screenshot(type="jpeg", quality=92))
    ffmpeg.stdin.close()
    if ffmpeg.wait() != 0:
        raise SystemExit(f"ffmpeg failed on the scene starting at {start}s")
    os.replace(temporary, path)


async def main(output):
    work = tempfile.mkdtemp(prefix="notchpal-film-")
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch()
        page = await browser.new_page(viewport={"width": 1080, "height": 1080})
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        await page.goto(URL)
        await page.evaluate("document.fonts.ready")
        files = []
        for number, (start, end) in enumerate(SCENES):
            path = os.path.join(work, f"scene{number}.mp4")
            await record(page, start, end, path)
            files.append(path)
            print(f"scene {number + 1} of {len(SCENES)} done", flush=True)
        await browser.close()
        if errors:
            raise SystemExit("The film page had errors: " + "; ".join(errors))
    listing = os.path.join(work, "scenes.txt")
    with open(listing, "w") as handle:
        handle.writelines(f"file '{path}'\n" for path in files)
    temporary = output + ".part.mp4"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", listing,
                    "-c", "copy", "-movflags", "+faststart", temporary], check=True)
    os.replace(temporary, output)
    print("saved", output)


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "notchpal-demo.mp4"))
