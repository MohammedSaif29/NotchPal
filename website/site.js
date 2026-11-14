// Points the Download button at the newest NotchPal release and shows its version and
// fingerprint. If GitHub can't be reached, the button still opens the latest release page.
(() => {
  "use strict";
  const button = document.getElementById("download");
  const note = document.getElementById("download-note");
  const fingerprint = document.getElementById("fingerprint");
  if (!button) return;

  fetch("https://api.github.com/repos/MohammedSaif29/NotchPal/releases/latest", { headers: { Accept: "application/vnd.github+json" } })
    .then((response) => (response.ok ? response.json() : Promise.reject(new Error("GitHub didn't answer"))))
    .then((release) => {
      const zip = (release.assets || []).find((asset) => /^NotchPal-[\d.]+\.zip$/.test(asset.name));
      if (!zip || !/^https:\/\/github\.com\/MohammedSaif29\/NotchPal\//.test(zip.browser_download_url)) return;
      const version = String(release.tag_name || "").replace(/^v/, "");
      button.href = zip.browser_download_url;
      button.textContent = `Download NotchPal ${version}`;
      if (note) note.textContent = `Free. ${(zip.size / 1048576).toFixed(1)} MB, for macOS 14 Sonoma or later on Apple silicon.`;
      const digest = String(zip.digest || "");
      if (fingerprint && /^sha256:[0-9a-f]{64}$/.test(digest)) {
        fingerprint.textContent = "";
        const code = document.createElement("code");
        code.textContent = digest.slice(7);
        const command = document.createElement("code");
        command.textContent = `shasum -a 256 ${zip.name}`;
        fingerprint.append(`Want to check your download? The fingerprint of NotchPal ${version} is `, code, ". In Terminal, ", command, " should print the same.");
      }
    })
    .catch(() => {});
})();
