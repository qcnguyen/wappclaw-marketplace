# hyperframes plugin

Gives the Wappclaw agent [HyperFrames](https://github.com/heygen-com/hyperframes): videos written as
HTML (HTML, CSS, media and a seekable GSAP/Lottie/Three.js timeline) and rendered deterministically to
MP4 with headless Chrome and FFmpeg. The agent scaffolds a project, writes the scenes, checks and
snapshots them, pulls blocks from the ~450-item catalog, finds or makes media, and renders.

This file is for administrators. The agent reads [GUIDELINE.md](GUIDELINE.md).

## Installing

1. Admin app → **Plugins → Import plugin → Choose folder**, and pick this `hyperframes/` folder.
2. Press **Install**. It runs unattended (also under the migration wizard) and takes a few minutes:

   | Needs | Uses, in order |
   |---|---|
   | Node.js 22+ | the server's `node` if it is 22+, else the official Node 22 tarball (checksum-verified) into `state/node` |
   | `hyperframes` CLI | `npm i -g hyperframes@<CLI version>` into the first writable npm prefix, else `state/npm-global` |
   | FFmpeg + FFprobe | already installed, else the distro package (root or password-less `sudo` only), else a static build into `state/ffmpeg` |
   | Chrome | `hyperframes browser ensure` (the pinned build, into the plugin's home), then its shared libraries via the distro (root or password-less `sudo` only) |
   | Skill references | the skills inside the npm package, plus `hyperframes-registry` from the matching GitHub tag, linked into `state/skills` |

   It ends with `hyperframes doctor`. Docker, Kokoro, MusicGen and whisper show as missing on most
   servers; they are optional. **Chrome missing libraries** is the one to act on: without root the
   install prints which `.so` files are missing — install them (Debian/Ubuntu: `libnss3 libatk1.0-0
   libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 libgbm1
   libpango-1.0-0 libcairo2 libasound2`) and press Reinstall. Until then lint and cloud renders work,
   local check/snapshot/render do not.

3. Press **Reinstall** to upgrade. The **CLI version** setting pins a version (`latest` by default);
   pin one when renders must stay reproducible.

## Signing in (optional)

Local authoring and rendering need no account. A HeyGen sign-in unlocks cloud rendering, the music
catalog, image/icon search, HeyGen voices, avatars and generated media — charged to that account's
plan or credits. Choose the **HeyGen sign-in mode**, then press **Authenticate**:

- **Local only** (default) — no HeyGen account. The plugin always shows as authenticated, since there
  is nothing to sign in to; Authenticate only clears a stored HeyGen session.
- **Device code** — Authenticate prints a HeyGen URL and code; approve it in a browser with the
  account the server should act as.
- **API key** — paste a HeyGen API key into the secret; Authenticate only verifies it. Billed to the
  key's API credits.

The agent cannot sign in or out, and the login is the plugin's own (it lives under `state/home`), so a
`hyperframes` run from a plain shell on the server is a different, signed-out CLI.

## Using it

Ask for a video in chat, for example:

- "Make a 10-second product intro for Acme with a fade-in title over our logo and subtle music."
- "Turn https://example.com into a 20-second vertical promo."
- "Render the project from earlier as the final MP4."

The agent proposes storylines for longer films, shows snapshot PNGs or a draft render for approval,
and then renders. Projects and renders are files on the server; the agent reports their paths. There
is no browser preview or desktop app here — open the project in the HyperFrames desktop app or
`npx hyperframes preview` on a workstation if you want to edit it by hand.

| Setting | Default | Purpose |
|---|---|---|
| CLI version | `latest` | npm version Install puts in place |
| HeyGen sign-in mode | `local` | `local`, `device` or `apiKey` |
| Usage telemetry | `on` | `off` sets `HYPERFRAMES_NO_TELEMETRY=1` |
| HeyGen API key (secret) | — | only in `apiKey` mode |
