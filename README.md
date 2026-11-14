# NotchPal

**The notch that's alive.** NotchPal turns your MacBook's notch into a Dynamic Island like the one on Apple's newest MacBook Pro: search and Apple Intelligence right in the notch, Live Activities for calls and recordings, music from any app, a camera mirror, live alerts, a pet and games built right in.

Free. Open source. No account, no tracking, no ads.

Made by **Mohammed Saif** · [LinkedIn](https://www.linkedin.com/in/saif-mohammed-939902335/) · [GitHub](https://github.com/MohammedSaif29)

**[⬇ Download NotchPal](https://github.com/MohammedSaif29/NotchPal/releases/latest)** · **[Website: notchpal.mohammedsaif.dev](https://notchpal.mohammedsaif.dev)**

![The island floating below the notch, with the music player, AirDrop and battery](docs/screenshots/floating-island.png)

---

## Download and install

**You need:** a Mac with Apple silicon (M1 or newer) and macOS 14 Sonoma or newer. NotchPal works on Macs without a notch too: it becomes a small pill under the menu bar.

1. Open the **[latest release](https://github.com/MohammedSaif29/NotchPal/releases/latest)** and, under **Assets**, click **NotchPal-x.y.z.zip** to download it.
2. Double-click the zip to unzip it, then drag **NotchPal** into your **Applications** folder.
3. Double-click NotchPal to open it. macOS will say it can't verify the app. Click **Done**, not Move to Trash.
   This happens because NotchPal is free and isn't signed with a paid Apple developer account yet. The code is all here for anyone to check.
4. Open **System Settings → Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to NotchPal. Confirm with your password or Touch ID. You only do this once.
5. That's it. A short tour in the notch shows you around. Click the notch (or swipe down on it with two fingers) to open the island, and press **⌥ Space** to search. NotchPal also puts a small capsule icon in the menu bar, with Settings, About and Quit.

**If macOS says NotchPal "is damaged", or music doesn't show up:** open **Terminal** and run this, then open NotchPal again:

```bash
xattr -dr com.apple.quarantine /Applications/NotchPal.app
```

It removes the "downloaded from the internet" flag from NotchPal only.

**Permissions** are only asked for when you first use a feature: Camera for the Mirror, Calendar for your events, and Accessibility for notification counts. Music, battery, volume and AirDrop need none.

**Start at login:** Settings → General → Open NotchPal at login.

**Update:** when a new version is out, NotchPal tells you in the notch. Click **Update** and it downloads, checks and installs it, then restarts by itself. Your settings stay. From 0.7.1 on, NotchPal only installs updates signed by its maker (see [Safe updates](#safe-updates)). You can also use the menu bar icon → Check for Updates. (Still on 0.4.0? Download the latest version once by hand; from 0.5.0 on, NotchPal updates itself.)

**Uninstall:** click the capsule icon in the menu bar → Quit NotchPal, then drag NotchPal from Applications to the Trash.

## What it does (v0.7)

**Like Apple's new Mac Dynamic Island, on every Mac**
- **A floating island**: click the notch, or swipe down on it with two fingers, and the island splits off and floats just below the notch like a droplet. Push up to send it back. Prefer it attached to the notch, or opening on hover? Both are in Settings → General.
- **Pointer black hole**: bring the pointer up under the notch and a drop of the notch stretches down to pull it in.
- **A tour in the notch**: new users get a short welcome tour, and after an update the notch shows what's new. See it again in Settings → General.
- **Search in the notch**: press **⌥ Space** (or click 🔍) and the notch drops open into a search bar, like Spotlight on Apple's island. Find apps, files and System Settings, do maths (`24*7`), run quick commands (`timer 10m`, `note buy milk`, `pause`, `next`), or search the web.
- **Apple Intelligence in the notch**: type a question and Apple Intelligence answers right inside the notch, privately on your Mac, with follow-up questions. Needs an Apple silicon Mac on macOS 26 or newer with Apple Intelligence turned on.
- **Siri in the notch**: a Siri button in search and the open island, and a rainbow glow around the notch while Siri listens. Or send your question to Claude or ChatGPT.
- **Live Activities**: a call in FaceTime, Zoom, Meet, Teams or WhatsApp, a Voice Memos recording or a screen recording shows in the notch with its timer, like Apple's pills. Open the island to jump back to the call or stop the screen recording.
- **Island mitosis**: with two things live, the second splits off the notch like a water droplet, and melts back in when it's done.
- **More pills**: switch to AirPods or another speaker and the notch says where your sound is playing now.
- **Glass from ultra clear to fully tinted**, like macOS 27, with text that stays readable over bright windows.

**In the closed notch**
- **Glow**: a soft light around the notch. At rest it's a faint, still ember in your accent colour. A new song pulses in the album's colours for a few seconds, then holds its main colour. A timer goes green, yellow, then red, the camera and microphone glow green or orange, and charging, low battery, meetings and messages flash it. Pick Halo, Neon, Aurora or Ripple, and choose what lights it in Settings → Glow. A still glow uses no battery.
- **Lights up when it starts**: two sparks trace your notch, meet in the middle, and the notch lights up. On a light wallpaper they draw in dark ink with coloured halos, so they always show.
- **Music from any app** with album art and a visualizer tinted to the cover. Swipe sideways on the island to change songs.
- **Battery, your way**: show it always, unplugged, when low, or while charging. Pick a clean style (a thin Ring, an iPhone-style Pill, the Classic battery, or just the Number) with iPhone colours (white, green while charging, yellow in Low Power Mode, red when low) or any colour you like. Six emoji packs are there too, if you want something playful.
- **Pal, the notch pet**: dances to music, munches electricity while charging, sweats when the battery is low, and naps late at night. Choose Lively, Calm or Still.
- **Easy on the eyes**: brightness sliders for the closed notch and the open island, a soft white Pal, and Reduce Motion support.
- **Updates itself**: when a new version is out, the notch tells you. One click downloads it, checks it and restarts NotchPal, like an app update on your phone.
- **Stays out of your way**: the closed island never blocks clicks on the menu bar items next to it, it hides while a movie or video plays full screen (point at the notch to bring it back; full-screen browsing and work apps keep it), and on Macs without a notch it stays hidden until you hover the top middle of the screen.
- **Privacy dots**: green while any app uses the camera, orange for the microphone, like iPhone.
- **Live alerts**: charging, low battery, AirPods, new song, meetings about to start (with a Join button), new messages, timer done.

**Widgets in the open island** (turn them on, off and reorder them in Settings, or right-click any icon in the island to hide or move it)
- **Music**: the same player for every app (Spotify, Apple Music, YouTube in your browser, VLC and more), with the app's icon on the album art, seek bar, play/pause, volume, screen brightness, speaker/AirPods picker, AirDrop and battery card. Choose which apps can show in the notch.
- **Calendar**: today's events with one-click Join for Zoom, Meet, Teams, FaceTime and Webex.
- **Mirror**: check yourself before a call, in a round or rectangle mirror right under the camera, with the camera's real proportions so your head is never cut off. Turn on Centre Stage, play Reactions (hearts, balloons, confetti…), switch cameras (like your iPhone), open Desk View, and see Portrait, Studio Light and Background at a glance, with macOS's Video Effects panel one click away. The camera is only on while the tab is open, and nothing is recorded.
- **Apps**: your favourite apps, one click away.
- **Notifications**: unread counts from Messages, WhatsApp, Mail, Slack and any other Dock app.
- **Notes**: a scratchpad that saves itself.
- **Timer** and **Games** (Runner, Flappy, Snake, Pong, each with Easy/Normal/Hard). Pick which games show up.

**Settings**
- Size: open width and length, corner roundness, closed wing width and height.
- Look: Black, Liquid Glass, Frosted or Clear, with a glass slider from ultra clear to fully tinted, readable text, tint colour, shiny edge, glass when closed, shadow and accent colour.
- Motion: Snappy, Smooth, Gentle, Liquid or Bouncy, and content that appears with a Blur, Fade, Slide or Pop.

## Pictures

Search in the notch (⌥ Space), with maths, Apple Intelligence, Siri, Claude and ChatGPT:

![Search in the notch, working out 24*7](docs/screenshots/search.png)

The tour that shows new users around, and shows what's new after an update:

![A tour card in the notch about the ⌥ Space shortcut](docs/screenshots/tour.png)

Or keep the island attached to the notch, the way it used to open (Settings → General):

![The open island attached to the notch, with the music player, AirDrop and battery](docs/screenshots/music.png)

The closed notch while music plays:

![The closed notch with album art and a visualizer](docs/screenshots/closed-notch.png)

Battery styles, with iPhone colours:

![The Ring, Pill, Classic and Number battery styles](docs/screenshots/battery-styles.png)

Games, timers and your favourite apps:

![The Games tab with Runner, Flappy, Snake and Pong](docs/screenshots/games.png)
![The Timer tab with quick timers](docs/screenshots/timer.png)
![The Apps tab with favourite apps](docs/screenshots/apps.png)

These were made with NotchPal's own **Save Pictures of My Island…** (menu bar icon, or Settings → About). Use it to share your setup!

## Safe updates

Only download NotchPal from **[notchpal.mohammedsaif.dev](https://notchpal.mohammedsaif.dev)** or **[github.com/MohammedSaif29/NotchPal](https://github.com/MohammedSaif29/NotchPal/releases/latest)**. Copies from anywhere else aren't official.

Every official release is signed with a key that lives inside the security chip (Secure Enclave) of the maker's Mac. That key can't be copied off the chip, and each signature needs his Touch ID. NotchPal checks that signature before installing any update and refuses anything else, so even someone who broke into the GitHub account couldn't push a fake update to you. Each release lists its signature next to the download (`NotchPal-x.y.z.zip.sig`); you don't need to do anything with it.

If NotchPal ever says it couldn't confirm an update came from its maker, it leaves your copy untouched. Click **Download** to get the new version from the official page instead.

## Privacy, and how it works

NotchPal collects nothing. The only time it goes online by itself is to ask GitHub, once a day, whether there's a new version. That request contains nothing about you or your Mac, and you can switch it off in Settings → About. The links in About (LinkedIn, GitHub, Report a Problem) only open your browser when you click them.

- **Music**: since macOS 15.4 only Apple's own programs may read what's playing, so NotchPal runs a tiny helper inside `/usr/bin/perl` (an Apple program) to read the system's Now Playing info. If Apple blocks that, it falls back to asking Spotify and Apple Music directly.
- **Notifications**: macOS doesn't let apps read other apps' notifications. With the Accessibility permission, NotchPal reads only the unread counts on Dock icons, never message text.
- **Calendar** and **Mirror** only ask for permission when you first use them. The camera is off unless the Mirror is open, and nothing is ever recorded.
- **Privacy dots** only check whether the camera or microphone is in use. They never see or hear anything.
- **Battery, volume and speakers** use public macOS APIs and need no permissions.

## Help and support

- **Found a bug or have an idea?** [Open an issue](https://github.com/MohammedSaif29/NotchPal/issues/new/choose). In the app: menu bar icon → Report a Problem.
- **Want to reach me?** Message me on [LinkedIn](https://www.linkedin.com/in/saif-mohammed-939902335/).

## Build it yourself

You need macOS 14 or newer and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/MohammedSaif29/NotchPal.git
cd NotchPal
bash Scripts/build-app.sh --run
```

That builds NotchPal, installs it to `~/Applications/NotchPal.app`, and makes a release zip in `dist/`.

For development, `bash Scripts/dev-watch.sh` rebuilds and relaunches the app every time the `.rebuild` file changes, and writes the output to `build.log`.

Official releases are signed with `Scripts/release-key.sh`. You don't need it to build or run NotchPal yourself.

Want to help? See [CONTRIBUTING.md](CONTRIBUTING.md).

## Roadmap

- [ ] Download tracker (TeraBox, Chrome, Safari…)
- [ ] `notch push` command so any script or app can show a live activity
- [ ] Clipboard history
- [ ] Live cricket scores
- [ ] Notch-to-notch multiplayer Pong
- [ ] Signed and notarized releases, so installing takes one click
- [ ] Windows version

## Licence and name

Copyright © 2026 Mohammed Saif.

NotchPal is free software under the **GNU General Public License v3** ([LICENSE](LICENSE)). In plain words: anyone may use NotchPal for free, read its code, and change it. Anyone who shares a copy or a changed version must keep the copyright notice, credit the original, and share their version's code under the same GPLv3 licence. Nobody can turn it into a closed, paid app.

The name **NotchPal** and its icon belong to Mohammed Saif and aren't covered by the code licence. Copies and changed versions must use a different name and icon, and must not present themselves as the official NotchPal. See [TRADEMARKS.md](TRADEMARKS.md). The official NotchPal is only published at **github.com/MohammedSaif29/NotchPal**.
