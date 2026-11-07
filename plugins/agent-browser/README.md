# agent-browser plugin

Gives the Wappclaw agent [agent-browser](https://github.com/vercel-labs/agent-browser): a fast native CLI
that drives a headless Chrome over CDP. The agent opens pages, reads them as accessibility-tree snapshots
with short element refs (`@e3`), clicks, fills and submits forms, extracts data, takes screenshots, PDFs
and recordings, and tests web apps.

This file is for administrators. The agent reads [GUIDELINE.md](GUIDELINE.md).

## Installing

1. Admin app → **Plugins → Import plugin → Choose folder**, and pick this `agent-browser/` folder.
2. Press **Install**. It runs unattended (also under the migration wizard), needs no Node.js, and takes
   under a minute on a good connection:

   | Needs | Uses, in order |
   |---|---|
   | `agent-browser` | the npm tarball for **CLI version**, fetched from registry.npmjs.org with curl and checked against its published SHA-1, unpacked into `state/agent-browser` (only this platform's native binary is kept) and linked into `state/bin` |
   | Chrome | `agent-browser install` — the Chrome for Testing build that CLI version pins (~400 MB), into the plugin's home; older builds are removed |
   | Chrome's shared libraries | already present, else the distro packages (root or password-less `sudo` only) |
   | Chrome sandbox | with **Chrome sandbox** = Auto, Chrome is launched once with its sandbox and, only if that fails, once with `--no-sandbox`; the result is remembered until the next Reinstall |

   It ends with `agent-browser doctor`. The cloud providers, `AI_GATEWAY_API_KEY` and the encryption
   key show as "not set" — they are optional and not used here. The install **fails** if Chrome cannot
   start: without root it prints which `.so` files are missing — install them (Debian/Ubuntu: `libnss3
   libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2
   libgbm1 libpango-1.0-0 libcairo2 libasound2`) and press Reinstall.

3. Press **Reinstall** to upgrade, or after the host changes (it re-checks the sandbox). Upgrading from
   inside a chat (`agent-browser upgrade`, `agent-browser install`) is refused.

There is no sign-in: agent-browser has no account.

## What the agent's browser can reach

The browser runs on this server, as the server's user, with this server's network access — including
internal hosts. Use **Allowed domains** to confine it (`example.com,*.example.com`); navigation and page
traffic elsewhere is then blocked, and saved-state restore, Chrome profiles and CDP attach are refused.

Logins the agent saves (the auth vault, `--restore` session state) live in the plugin's
`state/home/.agent-browser` and are **shared by every conversation on this server**. The vault is
encrypted with a key generated there on first use. Removing the plugin deletes them.

Its daemons use their own socket namespace (`$XDG_RUNTIME_DIR/agent-browser/namespaces/agent-browser`),
so they never collide with an `agent-browser` someone runs from a plain shell — which is, equally, a
different install with no access to the plugin's sessions or vault.

| Setting | Default | Purpose |
|---|---|---|
| CLI version | `latest` | npm version Install puts in place (each pins its own Chrome) |
| Chrome sandbox | `auto` | `auto` decides at install; `on` never passes `--no-sandbox`; `off` always does |
| Allowed domains | empty (any) | comma-separated patterns the browser may reach |
| Mark page content | `on` | wraps page text in nonce-bearing boundary markers (`AGENT_BROWSER_CONTENT_BOUNDARIES`) |

## Using it

Ask in chat, for example:

- "Open https://example.com/pricing and screenshot the plans table."
- "Log into our staging app as the test user and check that the invoice page loads."
- "Go through the signup flow on https://example.com and report anything broken."

The agent reports screenshots and other files by their path on the server.
