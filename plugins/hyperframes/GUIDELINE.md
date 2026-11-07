# HyperFrames (`hyperframes` CLI)

This plugin gives you **HyperFrames**: a video is written as an HTML project (HTML, CSS, media and a seekable animation timeline) and the CLI renders it to MP4 by seeking a paused timeline frame by frame in headless Chrome and encoding with FFmpeg — the same input always gives the same video. The CLI, Node.js 22+, FFmpeg and the pinned Chrome are installed for you.

Every command starts with `hyperframes`. Run `hyperframes --help` or `hyperframes <command> --help` for the options of the installed version — the help is authoritative where it differs from this document. Most commands take `--json`; a failure prints `✗ …` and a `Fix:` line, and exits non-zero.

The upstream docs write every command as `npx hyperframes …`. Here that means exactly the same command; write it as `hyperframes …`.

Use HyperFrames for any request to make, edit, animate or render a video, motion graphic, captions, an animated chart or a title card — unless the person asks for another framework.

---

## 1. The full references

This guideline is self-contained for everyday work. HyperFrames' own skills — the detailed references, matched to the installed CLI version — are on disk in **`$HYPERFRAMES_SKILLS_DIR`**. Read them with `cat`:

```bash
cat "$HYPERFRAMES_SKILLS_DIR/hyperframes/references/motion.md"
ls  "$HYPERFRAMES_SKILLS_DIR/hyperframes/references" "$HYPERFRAMES_SKILLS_DIR/hyperframes/references/types"
```

| Skill folder | What it covers |
|---|---|
| `hyperframes/` | The render contract, the work loop, and per-genre guides (`references/types/*.md`), story, spec, motion, look, sound, captions, overlays, review |
| `hyperframes-cli/` | Every CLI command by job, preview/render, lint/check/snapshot, cloud, Lambda, Cloud Run |
| `media-use/` | Getting or making media: music, sound effects, images, icons, logos, voiceover, avatars, transcripts, cutouts, colour grades |
| `hyperframes-registry/` | The ~450-item catalog of blocks and components (only present if install could fetch it; §8 covers the essentials) |

Rules for reading them here:

- Where a reference says `<SKILL_DIR>`, use `$HYPERFRAMES_SKILLS_DIR/<that skill>`, e.g. `node "$HYPERFRAMES_SKILLS_DIR/media-use/scripts/dither.mjs" …`.
- A reference saying `/hyperframes-cli`, `/media-use` and so on means "read that skill folder".
- **Ignore** `hyperframes/references/plugin-installation.md`, `skill-lifecycle.md`, and any instruction to run `hyperframes skills …`, `npx skills add …` or `hyperframes upgrade` on the CLI itself. The plugin owns the CLI version (an administrator changes it with Reinstall) and those commands are refused.
- **Ignore** everything about "the HyperFrames desktop app", Studio, Framey, `hyperframes open` and `catch-up`: there is no desktop on this server and the person cannot open one from here.
- `hyperframes docs <topic>` prints the product docs (`compositions`, `data-attributes`, `troubleshooting`, …).

---

## 2. Where work happens

- A command runs in a scratch directory for this turn unless you `cd` somewhere. **Create each project under a path you keep** (`hyperframes init my-video`) and note its absolute path (`pwd`): the next turn starts in a different directory, so later commands begin with `cd /abs/path/my-video && hyperframes …`.
- Files the person should get (the rendered `.mp4`, snapshot PNGs) are files on this server. Say where each is, by absolute path.
- There is no browser for the person here. `hyperframes preview` starts a local web server on this machine; only use it when the person says they can reach this host, and never leave one running in the background. The way to show work in progress is **snapshots** (PNGs of frames) and a **draft render**.

---

## 3. A project

```
my-video/
  index.html            # the root composition: variables, scene hosts, media, audio
  compositions/         # one scene per file, each inside <template>
  assets/               # media and fonts (paths are written assets/..., no leading /)
  hyperframes.json      # project config (install paths for catalog items, …)
  .hyperframes/         # history, snapshots, caches — never delete it
```

Start one with `hyperframes init <dir>` (a blank 1920×1080 scaffold; `--resolution portrait|square|landscape-4k|…`, `--video clip.mp4`, `--audio track.mp3`, `--example <name>` only when asked). A website as the subject: `hyperframes capture <url> -o <dir> --json`.

`init` writes a single-file `index.html`; split it into scenes as the film grows. The root with one scene mounted (GSAP is loaded once, here, for every scene):

```html
<!doctype html>
<html lang="en" data-composition-variables='[{"id":"headline","type":"string","label":"Headline","default":"Launch day"}]'>
  <head>
    <meta charset="UTF-8" />
    <script src="https://cdn.jsdelivr.net/npm/gsap@3.15.0/dist/gsap.min.js"></script>
    <style>
      html, body { margin: 0; width: 1920px; height: 1080px; overflow: hidden; background: #0b0b10; }
    </style>
  </head>
  <body>
    <div id="root" data-composition-id="main" data-start="0" data-duration="4"
         data-width="1920" data-height="1080">
      <div id="intro" data-composition-id="intro" data-composition-src="compositions/intro.html"
           data-start="0" data-duration="4" data-track-index="1" data-track-kind="graphics"
           data-width="1920" data-height="1080"></div>
    </div>
    <script>
      window.__timelines["main"] = gsap.timeline({ paused: true });
    </script>
  </body>
</html>
```

A scene, `compositions/intro.html` — styles, markup and script all inside `<template>`:

```html
<template>
  <style>
    #root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }
    #intro-title { font: 900 120px Inter; color: #fff; }
  </style>
  <div id="root" data-composition-id="intro" data-width="1920" data-height="1080">
    <h1 id="intro-title" class="clip" data-start="0.4" data-duration="3.4" data-var-text="headline">Launch day</h1>
  </div>
  <script>
    const tl = gsap.timeline({ paused: true });
    tl.fromTo("#intro-title", { opacity: 0, y: 40 }, { opacity: 1, y: 0, duration: 0.6, ease: "power4.out" }, 0.4);
    window.__timelines["intro"] = tl;
  </script>
</template>
```

The host's `id`, its `data-composition-id`, the scene's root `data-composition-id` and the `__timelines` key are the **same** (`intro`). A mismatch makes every render wait 45 s per scene and then show static frames.

Music and voice are `<audio id="…" class="clip" data-start="0" data-duration="…" data-volume="0.5" src="assets/….mp3">` elements on the root, next to the scene hosts; the file must exist in `assets/`.

---

## 4. The render contract

`hyperframes check --json` reports most violations with a `Fix:` line. Break one of these and the render is wrong, not just ugly.

1. Every timed element has `class="clip"`, `data-start` and `data-duration` (seconds) and shows over `[start, start + duration)` — an end state that lands exactly on the end is never rendered, so land it just before. `data-track-index` is only an editor lane; paint order is `z-index`.
2. The video's length is the root's `data-duration`: anything later is cut, an early end holds the last frame. No command changes it — raise it yourself before adding something past the end.
3. Each composition builds **one paused timeline** and registers it after its tweens: `window.__timelines["<data-composition-id>"] = tl`. Never `tl.play()`, never `add()` a scene's timeline to the root's.
4. **Determinism**: no `Date.now()`, unseeded `Math.random()`, network fetches, timers, or `repeat: -1`. Everything visible is a function of timeline time.
5. Never tween `display`, `visibility` or `autoAlpha` on a `.clip` — animate a child.
6. No CSS `transform` on an element GSAP transforms; animate transforms, not `left`/`top`/`width`/`height`.
7. Never `play()`, `pause()` or seek media. A `<video>` keeps its sound with `data-has-audio="true"`, otherwise it is `muted`. Music and voice are separate `<audio>` elements.
8. Every `<audio>` has an `id`, or it is left out of the mix. No `crossorigin` on media. Time a `<video>` or its wrapper, never both.
9. Only bundled fonts resolve by name (Inter, Montserrat, Outfit, Nunito, Oswald, League Gothic, Archivo Black, Space Mono, IBM Plex Mono, JetBrains Mono, EB Garamond, Playfair Display, Source Code Pro, Noto Sans JP, Roboto, Open Sans, Lato, Poppins). Any other family needs `@font-face` to a file in `assets/fonts/`.
10. Asset paths are `assets/...` with no leading `/`, in scene files too.
11. Grades, grain, blur and vignettes on footage go through `hyperframes media-treatment`, never CSS filters.
12. A scene file puts everything inside `<template>` and styles its root as `#root` sized with `inset: 0`. Use `fromTo`, not `from`, inside a scene (scenes are re-seeked). Intended overflow/overlap: `data-layout-allow-overflow`, `data-layout-allow-overlap`.

Keep ids unique across the assembled page — prefix them with the scene id (`#intro-title`).

### Keep it editable

- One scene per file, short readable ids; the root holds only scene hosts, media and audio.
- Timed elements are written in the HTML (not created by script), each with a stable `id`.
- Copy, brand colours and swappable media are variables (`data-var-text`, `data-var-src`, `var(--id)`), so batch renders and later edits need no code changes.
- `data-track-kind="graphics"` on scene and overlay hosts, `captions` on the single host holding every caption group.
- Content inside the 90% action-safe box; captions and key text inside 80% title-safe.

---

## 5. How to work

**Build what was asked.** No voiceover, captions or new aspect ratio unless the request or source calls for them. A new video is 1920×1080 at 30 fps. A film over ~15 s that tells something gets music and sound on its visible actions unless the person asked for silence. A question or a loose idea gets an answer or a proposal, not an edit. Show real things from their source (the product's screens, the brand's logo); draw only what has none.

**A new film over ~15 s:** read its genre guide (§10) and `hyperframes/references/story.md`; propose three storylines in words and let the person pick, unless they asked for the file straight away. Then write `SPEC.md` (`hyperframes/references/spec.md`): every adjective as a number, the shots by frame.

**Before hand-building a named effect** (transition, lower third, caption style, chart, glitch, grain…): search the catalog (§8).

**An existing project:** `hyperframes timeline --json` first — it lists every clip with absolute times, owning file and `#id`. Read it rather than opening every file.

**The loop, every time:**

1. Write, then `hyperframes lint` after the first pass and after structural changes.
2. `hyperframes check --json` — the gate (lint, runtime, layout, contrast). Fix every error, weigh every warning. While a lint error remains, layout and contrast audits don't run ("0 samples" means nothing was checked). Contrast failures carry a `suggestedColor`.
3. `hyperframes snapshot` and **look at the PNGs** (under `.hyperframes/artifacts/snapshots/`) — that is how you see the video. With scenes, snapshot a midpoint of each (`--at 2,6,10`, `--range 0,4`, `--composition intro`). Tiny unstyled content or a missing hero means a scene didn't mount (check the id rule in §3).
4. Show the person: the snapshots, or a draft render (`--quality draft`). Passing checks alone is not a reason to do the final render — wait for approval unless they asked for the file or for no stops.
5. Final render (§6). Confirm the file is non-empty and `ffprobe -v error -show_entries format=duration -of csv=p=0 out.mp4` matches the root `data-duration`; snapshot or extract a few frames to look at.

**Project history** — every write is kept and can be undone: `hyperframes history begin --who agent --label "<plan>"` at the start of a turn, `hyperframes history --since mine --who agent` to see what changed since, `hyperframes history undo --who agent` when a change made it worse (never hand-edit back), `hyperframes history end` at the end.

---

## 6. Rendering

| Need | Command |
|---|---|
| Iterating | `hyperframes render --quality draft -o draft.mp4` |
| Normal | `hyperframes render --quality looks -o out.mp4` |
| Final delivery | `hyperframes render --quality delivery -o final.mp4` |
| Many variants from variables | `hyperframes render --batch rows.json -o "renders/{name}.mp4"` |
| HeyGen's cloud (needs sign-in, §9) | `hyperframes cloud render --fps <data-fps> --quality high -o out.mp4` |
| Inspect what a cloud upload would send | `hyperframes cloud render . --dry-run --json` |

- A 30 s film renders in a minute or two locally: run it in the foreground. A command here is cut off after **15 minutes**; only a render longer than that is detached, in its own process group, and polled from later commands:

  ```bash
  bash -c 'set -m; HYPERFRAMES_RENDER_DETACHED=1 hyperframes render --quality delivery -o final.mp4 < /dev/null > render.log 2>&1 &'
  grep -E 'Render (complete|failed)' render.log    # repeat until it reports; never wait with pgrep -f
  ```
- Final renders go to the cloud only when `hyperframes auth status` shows a paid HyperFrames plan; on Free, or with no sign-in, render locally. If a cloud render is refused or fails, render locally and say why.
- Cloud upload limit is 200 MB; trim with `.hyperframesignore` after the dry run (`hyperframes-cli/references/cloud.md`) — never ignore `index.html`, mounted scenes, fonts or used media.
- Don't send `hyperframes feedback` unless the person asks you to.

---

## 7. Commands by job

| Job | Commands |
|---|---|
| Start | `init <dir>`, `capture <url>` |
| Read a project | `info`, `compositions`, `timeline --json`, `docs <topic>` |
| Check | `lint` while writing; `check --json` as the gate |
| Look | `snapshot` (`--at t,…`, `--range S,E`, `--composition id`, `--zoom`), `keyframes`, `compare`, `audio` |
| Edit the timeline | `timeline move|trim|split|set|duplicate|delete <#ref> …`, `timeline apply plan.json`, `timeline undo receipt.json`, `timeline ids` |
| Reuse | `catalog`, `add` (§8) |
| Media and sound | `media-use resolve`, `media-use generate`, `media-treatment`, `grade-compare`, `remove-background`, `tts`, `transcribe`, `beats`, `normalize-audio` (§9) |
| Ship | `render`, `cloud render`, `publish`, `lambda`, `cloudrun` |
| Upkeep | `doctor`, `browser`, `usage`, `clean` |

Don't run `validate`, `inspect`, `layout` (deprecated aliases of `check`) or `events` (internal telemetry).

**Timeline edits** keep the project in the editor's own shape — prefer them to hand-editing times:

- `hyperframes timeline move|trim|split|set|duplicate|delete <#id> … --plan --json` previews one edit; run it again without `--plan` to apply. `--start`, `--end`, `--duration` set one edge or the length.
- An edit is refused when the clip would overlap a neighbour (`--overwrite`, or move the neighbour first) or end past its composition (raise the root's `data-duration` first).
- Several edits: a JSON file like `[{"verb": "move", "ref": "#outro", "time": "9"}]`, then `hyperframes timeline apply plan.json --json`. Save the printed `receipt`; `hyperframes timeline undo receipt.json` reverts it.

---

## 8. The catalog (blocks and components)

About 450 ready-made items installed as editable source: transitions, overlays and lower thirds, title cards and kinetic type, social/chat/UI cards, code diffs, charts, maps, 3D and shader backgrounds, caption styles, camera moves, textures. Starting from one is faster and usually better than writing the effect yourself.

```bash
hyperframes catalog --query "<what the beat should do, in English>" --json
hyperframes add <name> --json        # prints the written files and the mount snippet
```

- Query **in English** even when the video isn't; narrow with `--type block|component` and `--tag <tag>`. `add` needs the network.
- **Block** (a scene with its own timeline): installs to `compositions/<name>.html`. Mount it with `data-composition-src`, a `data-composition-id` equal to the block's own id, `data-start` and `data-duration` — start from the snippet `add` prints. Set its variables for one mount with `data-variable-values` (or `add <name> --vars '{"title":"…"}'`), and point its colour/font variables at the brand's.
- **Component** (a snippet): installs to `compositions/components/<name>.html`; copy its markup, `<style>` and script into your scene and follow its comment block.
- Take the largest unit that fits, then edit it. Keep installed ids prefixed as they are.
- Beat-synced blocks take hit times from `hyperframes beats --json` (beat times minus the mount's `data-start`).
- Nothing fits: say so before hand-building it.

---

## 9. Media, and the HeyGen account

Media always lands as a local file in the project's `assets/`; renders never fetch. One verb finds or makes it:

```bash
hyperframes media-use resolve --type <bgm|sfx|image|icon|logo|voice|video> --intent "<what you need>" --project <dir>
```

It prints `resolved <id> → <path> (…)`. List reusable assets first with `--candidates`. Details: `media-use/SKILL.md` and `media-use/references/resolve.md`.

| Need | Without an account | With the HeyGen sign-in |
|---|---|---|
| Music | — | HeyGen catalog (10k+ tracks); generated tracks use credits |
| Sound effects | Openverse (credit CC BY sounds) and 21 bundled offline | same |
| Images, icons | — | HeyGen asset search (75k+); generated images use credits |
| Logos | theSVG, GitHub avatar, favicon — never redraw a logo | same |
| Voiceover | `hyperframes tts` (Kokoro, on device, if installed) | HeyGen voices |
| Presenter / avatar video | — | `media-use generate` (credits) |
| Transcripts | `hyperframes transcribe` | same |
| Cutouts | `hyperframes remove-background` | same |
| Grades, LUTs, looks | `hyperframes media-treatment` | same |

- Footage that looks dark, flat or dull, should feel retro, or needs a face hidden: inspect it, then follow `media-use/references/media-treatments.md` and persist with `hyperframes media-treatment` — never a CSS filter.
- When you build or review a piece, scan once for concrete gaps (on-screen text with no voice, emoji standing in for icons, placeholder images, 10 s+ with no music) and offer the fixes in one ask. Never add them silently.
- Never quote prices, estimates or what a run used. If the person sets a credit limit, pass what is left as `--max-credits` on every `generate`.
- Recipes that need the separate `heygen` CLI are not available here; say so rather than installing it.

### Whose account, and what failure means

- Signing in is **optional**. Everything local — authoring, check, snapshot, render, catalog, local media tools — works with no account.
- HeyGen features run as **the account (or API key) an administrator configured** for this plugin (admin app → Plugins → hyperframes → Authenticate) — not necessarily the person you are talking to — and are charged to its plan or credits. `hyperframes auth status` shows which account, plan and billing apply; exit 1 means not signed in.
- **You cannot sign in or out**: `hyperframes auth login` and `auth logout` are refused. If a request needs HeyGen and nobody is signed in, say in one line that an administrator can sign the plugin in to unlock it, and offer the local alternative where one exists.
- `hyperframes usage --json` at the start of a new video reports the plan's remaining usage (say "unknown" when it is).

| Output | Meaning | What to do |
|---|---|---|
| `auth status` exit 1 / "not signed in" | No HeyGen credential | Local work is fine; HeyGen features need an administrator to Authenticate |
| A refused call naming a `billing` command | Out of plan or credits | Tell the person why; don't retry |
| Chrome missing or won't start | Install incomplete | `hyperframes doctor --json` (always exits 0 — read `.ok` per check) and report it; an administrator can Reinstall |
| `0 samples` from `check` | A lint error stopped the audits | Fix lint first |
| A scene renders blank or static | Host/scene/timeline id mismatch | Make the three ids equal (§3) |
| `capture` fails or writes `BLOCKED.md` | The site blocked capture | Take nothing from its partial files; retry into a new `-o` folder |
| A heavy page isn't ready in time | Timeout | Raise `--timeout` on `check` or `snapshot` |
| Disk tight | Caches | `hyperframes clean --dry-run`, then `clean`; never delete `.hyperframes` |

---

## 10. What to read for the request

All paths under `$HYPERFRAMES_SKILLS_DIR/hyperframes/references/`:

| The request | Read |
|---|---|
| Launch, promo, feature | `types/launch.md` |
| Explainer, tutorial | `types/explainer.md` |
| Music video | `types/music.md` |
| Chart, numbers | `types/data.md` |
| Vertical or social clip | `types/vertical.md` |
| 3D, simulation, generative | `types/3d.md` |
| Character, mascot, story short | `types/character.md` |
| A real place or map; a website, PR or script; kinetic type | `film.md` |
| Captions; cards over a talking head | `captions.md`; `overlays.md` |
| Motion: eases, titles, cuts, punch-ins, speed, holds | `motion.md` |
| Colour, type, the look | `look.md` |
| Music and sound design | `sound.md` |
| Reviewing a finished film | `review.md` (ends in `REVIEW.md`) |
| Scenes, attributes, media, lint; GSAP, Lottie, Three.js, canvas | `format.md`; `runtimes.md` |

For a command, the matching file in `$HYPERFRAMES_SKILLS_DIR/hyperframes-cli/references/` (`preview-render.md`, `lint-validate-inspect.md`, `cloud.md`, `compare-and-batch.md`, `init-and-scaffold.md`, …).
