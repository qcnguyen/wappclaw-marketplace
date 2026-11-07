# Writing a plugin

A **plugin** gives the agent a tool it does not otherwise have — a CLI, an API, a
system with a login. It bundles four things into one folder: how to *install* the
tool, how a human *signs it in*, a *guideline* that teaches the agent to use it,
and a *run* handler that executes commands against it.

Four plugins were built while writing this, in deliberately different shapes.
The two most instructive are reproduced in full in
[Appendix: the worked examples](#appendix-the-worked-examples); the other two are
described here because their lessons recur below:

- [`m365/`](#example-m365) — wraps a **CLI that holds its own login**. It installs a
  binary, signs in interactively with a device code, and its credential lives
  wherever that CLI decided to put it.
- [`jira/`](#example-jira) — a **credential handler for an HTTP API**, where the tool is
  just `curl`. Read it for how a secret reaches a command without being *in* it: a
  `.netrc` in the plugin's private home, so the agent writes plain `curl -n` and the
  token appears in no command line and no transcript. Also for a value that has to
  be told to the agent but is not a secret — the API base URL, discovered from the
  site rather than configured, and exported as `$JIRA_BASE`.
- `az` — a CLI with its **own** isolation mechanism (`AZURE_CONFIG_DIR`
  rather than `HOME`) and an **extension** that has to be installed into the
  plugin's own config dir, since extensions are per-config-dir. Its lesson is the
  fingerprint trick that keeps a CLI's stored login in step with the configured
  secret — and that lets a plugin log itself in on first use
  ([excerpt](#excerpt-the-az-fingerprint-trick)).
- `git-devops-service-principal` — a pure
  **credential handler** for a tool that is **already on the machine** (`git`): a
  service principal's id and secret arrive as settings, and each command gets a
  freshly minted access token. Nothing interactive, nothing written to disk, and
  **nothing added to the command's vocabulary** — the agent sends ordinary `git`.
  It is the example to follow when the tool exists and only the credential is
  missing, which is a large share of real cases.

Read whichever is closer to your case alongside this document; most of what
follows is a rule one of them demonstrates.

## When a plugin is the right answer

| You need… | Write… |
|---|---|
| To teach the agent a procedure with tools it already has | a **skill** |
| To give it files to read | a **reference item** |
| To give it source code | a **repository** |
| To install a tool, hold a credential, and run commands against it | a **plugin** |

The test is whether *installation* or *authentication* is part of the answer. A
skill can say "run `m365 spo site list`", but nothing makes `m365` exist or signs
it in — so the skill works on the machine where somebody once set that up by hand,
and nowhere else. That gap is what a plugin closes.

**If neither applies, the plugin will simply be ignored, and rightly.** A test
plugin wrapping `df`, `free` and `uptime` was built, installed and asked about; the
agent ran `df -h /` with Bash and never opened the plugin. It was correct to — the
tools were already on the machine and needed no credential, so the plugin added
nothing but a longer path to the same command. Wrap a tool the agent *cannot
otherwise reach*.

## The folder

```
my-plugin/
  plugin.json      # the manifest — the only required file
  GUIDELINE.md     # what the agent reads to learn the tool
  install.sh       # provisions the tool
  auth.sh          # interactive sign-in (optional)
  auth-status.sh   # "is it signed in?" probe (optional)
  run.sh           # executes one command
  lib.sh           # anything the scripts share (optional)
```

Import it from the admin app (**Plugins → Import plugin → Choose folder**). The
server copies it to `<workspace>/plugins/<slug>/` and adds a `state/` folder that
belongs to the plugin at runtime — see [State](#state).

The folder name comes from `name`, lowercased with everything outside
`[a-z0-9_-]` turned into a dash, capped at 64 characters. That slug is the plugin's
id: it is what the agent passes to `run-plugin`, so keep `name` short and typeable.

## `plugin.json`

```jsonc
{
  "name": "m365",                        // required; becomes the id
  "description": "…",                    // one line — the agent sees this in a table
  "version": "2.0.0",
  "keywords": ["sharepoint", "teams", "entra-users"], // capabilities, ≤ 64 chars in total
  "guideline": "GUIDELINE.md",           // default: GUIDELINE.md

  "install": {
    "runtime": "bash",                   // bash only, today
    "script": "install.sh",
    "timeoutMs": 900000                  // how long it may run; default 15 min
  },

  "auth": {                              // omit entirely if nothing to sign in
    "runtime": "bash",
    "script": "auth.sh",                 // presence = "Authenticate" is offered
    "statusScript": "auth-status.sh"     // exit 0 = signed in
  },

  "run": {                               // omit and the plugin can run nothing
    "runtime": "bash",
    "script": "run.sh",
    "timeoutMs": 300000                  // default 3 min
  },

  "settings": [                          // configuration — readable back
    { "key": "TENANT_ID", "label": "Tenant", "required": true, "default": "",
      "description": "Which tenant to talk to" },
    { "key": "AUTH_MODE", "label": "Sign-in mode", "default": "deviceCode",
      "options": [                       // a closed set: picked, not typed
        { "value": "deviceCode", "label": "Device code", "description": "As a person" },
        { "value": "certificate", "label": "Certificate", "description": "As the app" }
      ] }
  ],

  "secrets": [                           // credentials — write-only
    { "key": "API_TOKEN", "label": "API token", "required": true,
      "description": "From Settings → Developer" }
  ]
}
```

`settings` and `secrets` sit at the **root**, not under `auth`: `install` and
`run` read the same environment, so a tenant id needed to sign in is usually
needed to run a command too, and a default region is not about signing in at all.

Every field except `name` is optional, and each is independent — there is no
`mode` flag anywhere. **A capability exists because its script exists.** A plugin
with `auth.script` has an interactive login; one without it does not. Nothing
declares a fact a file already answers, so nothing can disagree with the folder.

Paths are relative to the plugin folder and cannot escape it.

### `keywords`

The capabilities the plugin covers, as a short index the agent keeps in
context. Every enabled plugin's keywords are written into `run-plugin`'s tool
description and the `get-plugin-instruction` skill, both of which the agent sees
on every turn — so a request that mentions `sharepoint` sends it to look into
the plugin that covers SharePoint instead of answering from memory or trying the
shell. The description says what the plugin *is*; keywords say what a user
might *ask for* that it can do.

- One word each: letters, digits and hyphens. Use a hyphen where you would put
  a space — `azure-devops`, not `azure devops`.
- **At most 64 characters in total** per plugin (the keywords' own lengths
  added up). They are in every turn's context for every plugin installed, so
  they must stay an index, not a second description. A manifest over the limit
  is refused on import.
- Name capabilities and products a user would say (`jira`, `sprint-board`,
  `entra-users`), not your plugin's internals.

## The four scripts

All of them run with:

| | |
|---|---|
| **cwd** | the plugin folder |
| **`PLUGIN_NAME`** | the slug |
| **`PLUGIN_DIR`** | absolute path of the plugin folder |
| **`PLUGIN_STATE_DIR`** | absolute path of `state/` — yours to write into |
| **`PLUGIN_HOME`** | a private `$HOME` you may adopt — see [whose credentials](#whose-credentials-are-they) |
| **`PLUGIN_CWD`** | the directory this command is running in, already applied — see [cwd](#cwd-is-handled-for-you) |
| **settings** | each declared setting under its own `key` (declared `default` if unset) |
| **secrets** | each declared secret under its own `key` |
| **stdout + stderr** | combined; this is the result |
| **exit code** | non-zero marks the call failed |

They are invoked as `bash -l <script>` — a **login** shell, so `/etc/profile` and
the server user's profile are sourced. That matters more than it sounds: see
[PATH](#the-path-problem).

### `install.sh`

Provisions the tool. Streamed to the admin page as it runs. A zero exit marks the
plugin installed; anything else leaves it uninstalled and the agent is told the
plugin exists but cannot run.

**Make it idempotent.** It is a Reinstall button as well as an Install button, and
people press it to upgrade.

**Install what is missing. Do not describe it.** This is the rule that all four
examples originally got wrong, in four different places: each one detected a
missing tool and exited non-zero with a shell command for the admin to run —
`curl … | sudo bash` for the Azure CLI, `sudo npm install -g` for the m365 CLI,
`apt-get install git` for git. That reads as conscientious and is, in the place
that matters most, useless: `install.sh` also runs under the **migration wizard**,
against a server nobody has logged into, where there is nobody to hand a command
to and no terminal to type it in. A step whose success condition is "a human reads
this, runs a command, comes back and presses the button again" is a step that has
failed.

So provision, in this order, stopping at the first that works:

1. **What is already there.** `command -v`, and a prefix a previous run of this
   script wrote to.
2. **The distro package, but only if you can get root without asking.** Already
   `uid 0`, or `sudo -n` — and `sudo -n` *only*. Plain `sudo` prompts for a
   password, and with nobody watching that does not fail, it **hangs** until the
   session's `timeoutMs` kills it, which is a far worse outcome than a clear
   refusal. A fresh image often has no package lists either, so be ready to
   `apt-get update` once, lazily, after the first install attempt fails.
3. **A copy the plugin owns.** `state/` is always writable, so this is the one that
   cannot fail for want of permission: a venv for a Python tool (`az`), an npm
   prefix for a Node one (`m365`). Record its `bin` in `state/env.sh` — see
   [The PATH problem](#the-path-problem) — and it is as usable as a system install
   while touching nothing outside the plugin.

Only when all three are impossible is a sentence for an administrator the right
answer, and it should say what was **tried**, not just what to type.

Raise `timeoutMs` if the install genuinely takes longer than 15 minutes; the
session is killed at that point. Provisioning your own copy makes this likely —
`pip install azure-cli` into a fresh venv builds a few wheels and the `az` example
allows twenty minutes for it.

### `auth.sh`

Runs under a **pty** (`script -q -e -f -c`) and is streamed live, with an input box
wired to its stdin. That is the whole reason it is a session and not a request: a
device-code login prints a code *immediately* and then blocks, and a command whose
output only appears at exit shows that code far too late to be useful.

So: **print what the human needs before you block**, and let the tool's own output
through rather than capturing it.

`auth` has no `timeoutMs` of its own, deliberately: what it waits for is a person,
and the session's 15-minute life is the right bound on that.

```bash
m365 login --authType deviceCode   # prints the URL and code, then polls
```

The session is killed after 15 minutes and keeps its last 512 KB of output.

### `auth-status.sh`

A probe. **Only its exit code is read** — 0 means signed in — so send output to
`/dev/null` and keep it fast. It is called while building a plugin listing, capped
at 20 seconds, and its answer is cached for 30 seconds.

**Do not assume your CLI's own exit code answers this question.** It usually does
not. `m365 status` exits **0 whether signed in or not** — logged out, it prints
the string `"Logged out"` and exits 0 — so a probe written as

```bash
m365 status --output json >/dev/null 2>&1   # WRONG: always exit 0
```

reports "signed in" for ever. That shipped, and the admin page cheerfully showed a
green *Signed in* chip on a plugin that was logged out. Check the **output** for
something only a real session produces:

```bash
out=$(m365 status --output json 2>/dev/null) || exit 1
case "$out" in
  *'"connectedAs"'*) exit 0 ;;   # that field exists only when connected
  *) exit 1 ;;
esac
```

Test it **both ways** before believing it — signed out as well as signed in. A
probe is the one script whose bug is invisible while it happens to be right.

**A second tool did the same thing, so treat it as the norm rather than the
exception.** `acli jira auth status` prints `✓ Authenticated` and exits 0 for a
credential the site refuses — it reports a file on disk, not a working session. Two
rules fall out of it:

- **A status subcommand answers "is a credential stored?", which is not the
  question.** Prefer the cheapest *real* call the tool offers, because only a
  request can tell you the token has not been revoked, expired, or was never the
  right kind. For an HTTP API that is one endpoint (`/myself`); for a CLI it is
  usually one list command.
- **Check the answer, not just the exit code.** `acli jira auth login` exits **0**
  when handed the literal string `not-a-real-token`, and `curl` exits **0** on a
  401 — the request succeeded, the answer was no. Read the HTTP status.

Omit it if there is no cheap way to ask. `authenticated` is then `undefined`, and
the admin page says "we cannot tell" rather than claiming "not signed in" — a
different and more honest statement.

### `run.sh`

The one the agent reaches. It gets the command in `PLUGIN_COMMAND` (and as JSON on
stdin), and **runs it as written**:

```bash
eval "$PLUGIN_COMMAND"
```

That verbatim contract is the design, not laziness. See below.

**Relax your own shell options before the `eval`.** `set -u` and `pipefail` are
right for the script; applied to the agent's command they misreport it. `pipefail`
is the sharp one, and it shipped as a bug: a command ending `| head -3` kills the
producer with SIGPIPE the moment `head` has what it asked for, so the pipeline
exits **141** and the platform marks a command that did exactly the right thing as
a failure. Piping a long listing into `head` or `jq` is the normal shape of a
command, so this is wrong more often than it is right.

```bash
set +u +o pipefail   # the command runs under default shell semantics
eval "$PLUGIN_COMMAND"
```

**cwd is handled for you — do not `cd` anywhere.** A `run.sh` needs no working
directory logic of any kind, and adding some is a mistake worth spelling out
because two versions of this plugin system's own example got it wrong.

The platform puts your process in the right directory before your script starts:
the one the caller named through `run-plugin`'s `cwd`, or — when the caller named
none — `<the turn's tmp>/<your plugin>`, the same scratch folder the agent has
already been told to use for intermediate files. If your command leaves anything
there, the platform appends that path to your output, so nothing gets lost.
`PLUGIN_CWD` tells you where you are, if you care.

Two things you might reach for, and shouldn't:

- **A setting for it.** Where output belongs is knowledge the *caller* has and you
  do not: its conversation's `tmp/`, its task run's folders, the checkout it is
  already working in. A configured location is one nobody asked for and nobody
  thinks to look in. This example shipped a `Default working directory` setting for
  exactly one release.
- **A scratch directory of your own.** It works, and it still leaves every other
  plugin author to rediscover the same trap — a command that writes to a relative
  path (`git clone <url>`, `tar xf`, a build) would otherwise land **inside your
  bundle**, which the API lists and the file viewer serves. That is the platform's
  job precisely because it is everyone's problem, and it now does it.

So the whole of it is:

```bash
eval "$PLUGIN_COMMAND"   # you are already in the right place
```

## The guideline is documentation for *your tool*

This is the part most easily done badly, so it gets its own section.

`GUIDELINE.md` is what the agent reads before using the plugin. **Write it as
documentation for the underlying tool** — the command vocabulary, the flags, the
traps — exactly as you would for a human colleague.

**Do not document `run-plugin` in it.** No `run-plugin({ plugin: …, command: … })`
examples, no tool-call syntax. The generated `get-plugin-instruction` skill already
teaches the agent that mechanism, once, for every plugin. Your guideline repeating
it is a copy that drifts.

✅ Write this:

```
m365 spo site list --output json
m365 entra user get --userName someone@contoso.com --output json
```

❌ Not this:

```
run-plugin({ plugin: "m365", action: "cli", args: { command: "spo site list" } })
```

**Include the command prefix** (`m365 …`, `gh …`, `kubectl …`). The command runs
verbatim, so what you write is literally what executes — and a prefix the agent has
to remember to add is a rule that will eventually be forgotten.

What a good guideline covers:

- **A command table** by area, with real examples.
- **How to get machine-readable output** (`--output json`, `--format json`, `-o
  yaml`) and when not to.
- **`--help`, and that it is authoritative.** Tell the agent to run it rather than
  guess a flag. The CLI's own help always matches the installed version; your table
  will not.
- **The traps.** For m365 that is `--webUrl` (the site) versus `--url` (the path),
  pagination caps, and throttling. Yours will have its own; they are the most
  valuable paragraphs in the document.
- **What failure means.** Especially: how to tell "nobody is signed in" from
  "signed in but not permitted", and that the agent cannot fix the first — a human
  signs the plugin in from the admin app.
- **Whose account this is.** Everything runs as the account an administrator signed
  in, so permissions are that account's and "not found" may mean "invisible to it".

### Why commands and not named actions

An earlier version had manifests declare named `actions[]`, each with an argument
schema, and the agent called `{ plugin, action, args }`. It works, and it is worse:

- The action list is a **second surface to keep in step** with the CLI underneath.
  It goes stale the moment that CLI gains a verb.
- It forces the guideline to teach *your* invented vocabulary instead of the tool's
  real one — so `--help` stops matching, and so does every StackOverflow answer and
  every page of the vendor's docs.
- It caps the plugin at whatever its author thought of. Asked something no action
  covered, the agent's only honest answer was "I can't", with the CLI sitting right
  there able to do it.

With a command, the plugin adds **environment, not translation**: the tool is
installed, on `PATH`, and signed in. Nothing is rewritten, so nothing has to be
debugged through.

**The same mistake has a subtler form: a helper you expose to the command.** The
Azure DevOps plugin briefly put a shell function (`azdo_api`) in front of the
agent, wrapping `curl` for the one question `git` cannot answer — "what
repositories exist?". Each call was still a real REST path, so it looked harmless.
It was not: it was a command that exists nowhere but that plugin's guideline, so
`--help` does not describe it, no vendor documentation matches it, and the
guideline had stopped being documentation for a real tool. It was removed, and the
capability it bought was given up deliberately. If your plugin needs a helper for
the agent to be useful, prefer stating the limitation in the guideline — it is
better for the agent to know a thing cannot be done here than to learn a verb only
you have ever used.

## The PATH problem

The commonest way a plugin breaks: `install.sh` puts a binary somewhere, and
`run.sh` cannot find it.

The server's environment is not your shell's. `npm config get prefix` is routinely
a root-owned `/usr/local` while the server runs as someone else, and a prefix whose
*top level* is writable may still hold root-owned packages that a reinstall cannot
replace — that fails halfway through, on a rename, having already made a mess.

The pattern in `m365/install.sh`:

1. Test the directory the installer **actually writes to** (`lib/node_modules`, and
   the scope directory inside it), not the top level.
2. Fall back through candidate prefixes until one is genuinely writable.
3. **Record the resulting `bin` directory in `state/env.sh`**, which every other
   script sources through `lib.sh`.

```bash
# install.sh
printf 'export PATH="%s:$PATH"\n' "$bin_dir" > "$PLUGIN_STATE_DIR/env.sh"

# lib.sh, sourced by run.sh / auth.sh / auth-status.sh
[ -f "$PLUGIN_STATE_DIR/env.sh" ] && . "$PLUGIN_STATE_DIR/env.sh"
```

That way the plugin uses the binary its own install produced, rather than depending
on how the server happened to be started.

Also: if the tool cannot be installed but a working one is already present, **say so
and succeed**. Failing an install over an upgrade nobody asked for helps no one.

**Put a prefix inside `state/` at the end of the candidate list.** It is always
writable, so "nowhere to install" stops being an outcome and the punt described in
[`install.sh`](#installsh) never has to happen. Prefer a shared prefix ahead of it —
one copy, one update, a warm cache — but do not depend on getting one.

One trap when you do fall back to your own prefix: **`HOME` is the plugin's**, so
`$HOME/.npm-global` is already inside the plugin and `~/.npmrc` is not the server
user's. The m365 example documented the opposite of this for as long as it existed
("deliberately does not source `lib.sh`, and therefore keeps the real `$HOME`") and
was simply wrong — the platform forces `HOME` for *every* script, `lib.sh` or no
`lib.sh`. The cost was invisible and exactly the one [Whose credentials are
they?](#whose-credentials-are-they) warns about: no `~/.npmrc`, so a private
registry would not have worked, and a cold cache on every install. Borrow the real
home per command, for the package manager only:

```bash
real_home="${PLUGIN_REAL_HOME:-$HOME}"
env HOME="$real_home" npm_config_cache="$real_home/.npm" \
    npm_config_userconfig="$real_home/.npmrc" \
    npm install -g --prefix "$prefix" <package>
```

## Settings and secrets

Two lists, and the split is **how they are stored, not what they are for**. Both
reach your scripts the same way: in the environment, under the `key` you declared.

| | `settings` | `secrets` |
| --- | --- | --- |
| Stored | plain JSON in `state/settings.json` | encrypted (AES-256-GCM) outside the plugin |
| Readable back | **yes** — the admin field shows the value | never; the API only says which keys are set |
| For | a tenant id, a client id, a region, a default URL | a token, a password, a client secret |
| `default` | applies until someone stores over it | n/a |
| `options` | a closed set of values — a dropdown, not a text box | n/a |

Put a value in `settings` unless it is a credential. An app registration's client
id in the secret store would work and be wrong twice over: it is public
information, and it would be invisible the moment it was saved — so nobody could
check which app the plugin was pointed at. That mistake is why `settings` exists.

Values are handed to your scripts in the environment, under the `key` you
declared:

```bash
curl -H "Authorization: Bearer $API_TOKEN" https://api.example.com/things
```

### A setting with a closed set of values

Give a setting `options` and it stops being a text box: the admin page offers
exactly those values, the server refuses any other, and your script can branch on
the value knowing it is one of the ones you wrote.

```json
{ "key": "AUTH_MODE", "label": "Sign-in mode", "default": "deviceCode",
  "options": [
    { "value": "deviceCode",  "label": "Device code (as a person)",
      "description": "A human completes the login; the server acts as that account." },
    { "value": "certificate", "label": "Certificate (as the application)",
      "description": "App-only. Nothing expires until the certificate does." }
  ] }
```

**This is how a plugin offers more than one way to authenticate.** A tool that can
sign in several ways — device code or certificate, a password or a token — gets
one mode setting, and `auth.sh` takes exactly that branch:

```bash
case "${AUTH_MODE:-deviceCode}" in
  deviceCode)  args=(login --authType deviceCode ...) ;;
  certificate) args=(login --authType certificate ...) ;;
  *) echo "Unknown sign-in mode." >&2; exit 2 ;;
esac
```

Three things make "several modes" stay comprehensible, and they are worth copying
from the m365 plugin, which does all of this:

- **One mode is in force at a time.** Sign the old connection out before making
  the new one. A tool that can hold two logins at once will otherwise leave a
  command's permissions depending on which one happens to be current.
- **The status probe checks the mode too**, not just that *something* is signed
  in. Changing the mode should read as signed out until someone authenticates
  again — because for the mode now configured, nobody has.
- **Each mode's fields say which mode they belong to — `showWhen`.** Give a
  setting or secret a `showWhen` and it appears only while the settings it names
  hold one of the listed values:

  ```json
  { "key": "CERT_PASSWORD", "label": "Certificate password", "required": true,
    "showWhen": { "AUTH_MODE": "certificate" } }
  ```

  A value can be one string or an array (`{ "AUTH_MODE": ["a", "b"] }`); several
  keys must all match. The admin page shows only the chosen mode's fields, and
  swaps them as soon as the mode is picked (before saving). A blueprint import, or
  a sync from a blueprint repository, asks only for the secrets that mode reads.
  `required` counts only while the field is shown, so a mode's own fields can be
  marked required. A field that depends on a hidden setting is hidden too.

  It is presentation, not storage: a hidden field keeps its value and your
  scripts still receive it, so keep branching on the mode in `auth.sh`. A
  `showWhen` naming an undeclared setting, or a value that setting's `options`
  do not offer, makes the manifest invalid. Servers older than this feature ignore
  `showWhen` and show every field, with `required` applying to all of them.

Rules you inherit and should not work around:

- **Never put a secret on a command line.** `ps` is world-readable. Use the
  environment, a file you write `0600`, or stdin.
- **Never echo one.** Session output is streamed to a browser and buffered.
- **Never write one into the plugin folder.** That folder is listed by the API and
  served by the file-viewer route. `state/` is the place, and even there prefer not
  to — the encrypted store already exists.

No route ever returns a secret's value; the API only reports which keys are set.

## Whose credentials are they?

The one that catches people out. If your plugin wraps a CLI, **the CLI decides
where its own token goes** — and it is usually the user's home directory, not your
plugin folder. `m365` writes `~/.cli-m365-msal.json`; `az`, `gh` and `kubectl` all
do the equivalent. So by default, signing your plugin in signs in **every process
on the box running as the server's user**: the agent's own shell tool, any skill
that shells out to that CLI, and every other plugin.

That may be exactly what you want — a workspace where one `m365` login serves a
plugin and three skills is a coherent setup. But it is worth knowing you have it,
because the plugin boundary that holds for `settings` and `secrets` does not hold
for a credential the plugin never sees.

**You get one whether you want it or not, and you do not write a line for it.**
`HOME` is `state/home/` for all four of your scripts, set by the platform. Anything
resolving `~` lands inside your plugin, so a wrapped CLI's login is genuinely the
plugin's.

It is forced rather than offered because your three runtime scripts have to agree:
a login written under one home and read under another can never be signed in, and a
plugin that got that right in `auth.sh` and wrong in `run.sh` would authenticate and
then report itself signed out with nothing to point at.

**`PLUGIN_REAL_HOME` is exported too**, and that is your escape hatch for the two
things the private home costs:

- **Your install starts with an empty cache.** A package manager re-downloads, and
  a registry credential in the real `~/.npmrc` is not read — which against a private
  registry is a failure nobody would guess. If your install needs the machine's
  cache, point at `PLUGIN_REAL_HOME` explicitly.
- **Anything your tool read from the real home is gone**: `~/.gitconfig`, `~/.ssh`,
  `~/.docker/config.json`. Work out which of it is **critical** and make that a
  **setting**; leave the rest behind.
  The Azure DevOps git plugin is the worked example, including the wrong turn: losing
  `~/.gitconfig` breaks `git commit` (no `user.email`) and also drops
  `http.postBuffer`, `core.excludesFile` and `core.checkstat`. It first pulled the
  entire machine config back with `include.path`, which recovered the identity and
  dragged in a dozen unrelated settings — plus the machine's credential helper — with
  it. The identity is now two plugin settings injected as `user.name`/`user.email`,
  and the tuning is simply not reproduced. **A setting is where a decision about your
  plugin belongs. A machine's tuning is not yours to inherit**, and reaching for
  `PLUGIN_REAL_HOME` to get it back is usually a sign the value should have been a
  setting.

Two caveats. It is **not a sandbox**: a tool resolving the home directory through
`getpwuid()` instead of `$HOME` still writes to the real one. And if the environment
sets `XDG_CONFIG_HOME`/`XDG_CACHE_HOME`, those keep pointing at the real home and a
tool honouring them will follow — set them yourself if that matters to your tool.

**Say so in your guideline if this changes what the agent can do.** A CLI the agent
can no longer drive through the plain shell is a fact worth stating.

## State

`state/` is yours: caches, downloads, config a CLI insists on writing, the
`env.sh` above, `settings.json`, and the `home/` the section above describes. It is **preserved across re-imports** — a new bundle is new code,
not a reset of what the plugin has learned and signed into — and deleted when the
plugin is removed. It is gitignored, and never shown in the plugin's file list.

One consequence to know while iterating: because a re-import writes files over
rather than clearing the folder, **a file you delete from your bundle stays on the
server**. Remove it by hand, or remove and re-import the plugin.

## Testing it

```bash
# List what is installed
curl -s localhost:8787/acp/agents/claude/plugins | jq '.plugins[] | {id, installed, authenticated}'

# Install, and watch it
SID=$(curl -s -X POST localhost:8787/acp/agents/claude/plugins/<id>/install | jq -r .sessionId)
curl -sN localhost:8787/acp/agents/claude/plugins/sessions/$SID/stream
```

Then in the admin app: install, authenticate, and read the guideline in the viewer
(that pane renders the same file the agent gets).

Finally, test the part that matters — **ask the agent something in a chat and watch
which tools it reaches for.** You want to see `get-plugin-instruction`, then a
`Read` of your guideline, then `run-plugin`. If it reaches for Bash instead, your
guideline has not made the plugin's job clear enough, or a competing skill is
telling it something else.

## A minimal plugin

```jsonc
// plugin.json
{
  "name": "gh",
  "description": "GitHub — issues, pull requests and repository metadata via the gh CLI.",
  "keywords": ["github", "issues", "pull-requests", "gh"],
  "install": { "runtime": "bash", "script": "install.sh" },
  "auth": { "runtime": "bash", "script": "auth.sh", "statusScript": "auth-status.sh" },
  "run": { "runtime": "bash", "script": "run.sh" }
}
```

```bash
# run.sh
set -uo pipefail
[ -f "$PLUGIN_STATE_DIR/env.sh" ] && . "$PLUGIN_STATE_DIR/env.sh"
command -v gh >/dev/null 2>&1 || { echo "gh is not installed." >&2; exit 1; }
eval "${PLUGIN_COMMAND:?no command given}"
```

```bash
# auth-status.sh
[ -f "$PLUGIN_STATE_DIR/env.sh" ] && . "$PLUGIN_STATE_DIR/env.sh"
# Safe here only because `gh auth status` really does exit non-zero when signed
# out. Check that for your own CLI rather than copying this shape — see above.
gh auth status >/dev/null 2>&1
```

Everything else is `GUIDELINE.md` — which, for a plugin like this, is mostly
"here are the `gh` commands worth knowing, and use `--json` when you mean to parse".

## Checklist

- [ ] `plugin.json` parses, and `name` slugs to the id you expect
- [ ] `install.sh` is idempotent and survives a read-only prefix
- [ ] `install.sh` records its `bin` directory in `state/env.sh`
- [ ] `install.sh` **installs** a missing tool rather than printing a command for
      the admin — it runs unattended under the migration wizard. `sudo -n` only,
      never plain `sudo`, and a prefix under `state/` as the fallback that cannot
      fail for want of permission
- [ ] `auth.sh` prints the code/URL before it blocks
- [ ] `auth-status.sh` is silent, fast, and exits 0 only when truly signed in —
      **verified signed out as well as signed in**, not just assumed from `$?`
- [ ] `keywords` name what a user would ask for (one word each, hyphens for
      spaces, 64 characters in total) — not the plugin's internals
- [ ] `run.sh` runs `$PLUGIN_COMMAND` verbatim
- [ ] `GUIDELINE.md` documents the **tool**, with command prefixes, and no
      `run-plugin` syntax
- [ ] No secret reaches a command line or the plugin folder
- [ ] An agent in a real chat picks the plugin over the shell

## Two things to keep in mind

**A plugin's scripts are arbitrary code, run as the server's user, with no
sandbox.** That is deliberate — a plugin's job is to run things — but it means
installing one is a trusted-admin action, and a plugin you did not write deserves
the same reading as any script you would `sudo`.

**`bash` is the only runtime implemented.** `pwsh`, `node` and `python` are accepted
by the manifest schema and refused at execution with a named error. Adding one is a
single entry in the `RUNTIMES` table in
`src/drivers/plugins.ts` in the server — the runtime is already carried
through everywhere else.

## Appendix: the worked examples
Two of the example plugins referenced throughout this document, every file
verbatim — each is a complete folder you can recreate and import as-is:

- **`m365`** — a CLI that holds its own login. Shows nearly every rule above:
  installing into a fallback prefix and recording it in `state/env.sh`, borrowing
  `PLUGIN_REAL_HOME` for npm, a status probe that reads output rather than `$?`,
  and several sign-in modes driven by one `options` setting with `showWhen`.
- **`jira`** — a credential handler for an HTTP API, where the tool is plain
  `curl`. Shows a secret reaching commands through a `0600` `.netrc` instead of a
  command line, and a probe that checks the HTTP status of a real call.

### Example: m365

#### `m365/plugin.json`

````json
{
  "name": "m365",
  "description": "Microsoft 365 — read and manage SharePoint, Teams, Entra ID and Outlook through the CLI for Microsoft 365.",
  "keywords": ["sharepoint", "teams", "entra", "outlook", "onedrive", "m365"],
  "version": "2.4.0",
  "guideline": "GUIDELINE.md",
  "install": {
    "runtime": "bash",
    "script": "install.sh",
    "timeoutMs": 900000
  },
  "auth": {
    "runtime": "bash",
    "script": "auth.sh",
    "statusScript": "auth-status.sh"
  },
  "run": {
    "runtime": "bash",
    "script": "run.sh",
    "timeoutMs": 300000
  },
  "settings": [
    {
      "key": "CLIMICROSOFT365_AUTHTYPE",
      "label": "Sign-in mode",
      "default": "deviceCode",
      "description": "How this plugin signs in. Exactly one mode is in force: Authenticate signs out first and then uses this one, and the plugin counts as signed in only while the stored connection matches what is set here — change it and the plugin reads as signed out until you authenticate again. Each mode needs different fields below; the ones the other mode uses are ignored.",
      "options": [
        {
          "value": "deviceCode",
          "label": "Device code (sign in as a person)",
          "description": "A human completes the login in a browser and the server acts as that account, with that account's permissions. Needs an app registration with 'Allow public client flows' enabled and delegated permissions. The sign-in expires with its refresh token, so it has to be repeated eventually."
        },
        {
          "value": "certificate",
          "label": "Certificate (sign in as the application)",
          "description": "App-only: no user is involved, so nothing expires until the certificate does and nobody has to be present. The app registration needs APPLICATION permissions with admin consent — delegated ones do nothing here — and commands that mean 'the signed-in user' (a personal mailbox, a OneDrive, 'me') have no account to resolve."
        }
      ]
    },
    {
      "key": "CLIMICROSOFT365_ENTRAAPPID",
      "label": "Entra app (client) ID",
      "required": true,
      "description": "The application (client) ID of the Entra app registration this server signs in with. Needed by both sign-in modes. CLI for Microsoft 365 v10+ has no shared default app, so sign-in cannot proceed without one. Create it once with `m365 setup` on a workstation, or in the Azure portal, and paste the id here."
    },
    {
      "key": "CLIMICROSOFT365_TENANT",
      "label": "Tenant",
      "default": "common",
      "description": "Tenant to authenticate against. `common` works only for a MULTI-tenant app registration signing in by device code; a single-tenant one needs your tenant's GUID here, or sign-in fails with AADSTS7000014 (\"device_code is not valid\") and never shows a code at all. Certificate sign-in is always tenant-specific and REFUSES `common` outright. If in doubt, use the GUID."
    }
  ],
  "secrets": [
    {
      "key": "CLIMICROSOFT365_CERTIFICATE_BASE64",
      "label": "Certificate, base64-encoded (certificate mode)",
      "description": "The .pfx or .pem holding the certificate and its private key, base64-encoded: `base64 -w0 cert.pfx`. The only way it is supplied, deliberately — a path to a file on the server would be a second channel saying the same thing, and it would need shell access on this box to be any use, which pasting does not. Write-only: encrypted at rest and never read back. Not marked required, because it is only needed in certificate mode; the sign-in says so plainly if it is missing."
    },
    {
      "key": "CLIMICROSOFT365_CERTIFICATE_PASSWORD",
      "label": "Certificate password (certificate mode)",
      "description": "The password protecting the private key, if it has one — a .pfx exported from Windows normally does. Leave empty for an unprotected key. It is never passed on a command line: the sign-in opens the certificate with it locally and hands the CLI an already-opened copy, which is why openssl is a requirement for a protected certificate."
    }
  ]
}
````

#### `m365/GUIDELINE.md`

````markdown
# m365 — Microsoft 365 via the CLI for Microsoft 365

This plugin gives you [`@pnp/cli-microsoft365`](https://pnp.github.io/cli-microsoft365/),
a command-line client for Microsoft 365, installed and signed in. Through it you
can read and manage SharePoint sites and files, Teams, Entra ID (Azure AD) users
and groups, Outlook mail and calendars, Planner and OneDrive.

Send `m365 …` commands, exactly as you would type them at a terminal. They run
verbatim.

**Only through `run-plugin`.** This plugin's sign-in lives in the plugin's own
folder, not in the server user's home directory — so `m365` run any other way (the
shell tool, a Bash command, a script) is a *signed-out* CLI and every call will
fail on authentication. There is no fallback and nothing to work around: if you
need this account, the command goes through `run-plugin`.

```
m365 status --output json
m365 spo site list --output json
m365 entra user get --userName someone@contoso.com --output json
```

## The command vocabulary

Every command is `m365 <service> <resource> <verb>`. The ones that come up most:

| Area | Examples |
| --- | --- |
| Account | `m365 status` |
| SharePoint | `m365 spo site list`, `m365 spo site get --url <site>`, `m365 spo list list --webUrl <site>`, `m365 spo listitem list --webUrl <site> --listTitle "Documents"`, `m365 spo file list --webUrl <site> --folderUrl "/sites/x/Shared Documents"`, `m365 spo search --queryText "..."` |
| Teams | `m365 teams team list`, `m365 teams channel list --teamName "..."`, `m365 teams message list --teamId <id> --channelId <id>` |
| Entra ID | `m365 entra user list`, `m365 entra user get --userName someone@contoso.com`, `m365 entra group list`, `m365 entra m365group list` |
| Outlook | `m365 outlook message list --folderName Inbox`, `m365 outlook mail send --to ... --subject ... --bodyContents ...` |
| OneDrive | `m365 onedrive list --userName someone@contoso.com` |
| Planner | `m365 planner plan list --ownerGroupName "..."`, `m365 planner task list --planTitle "..."` |

**`--help` works at every level and is the fastest way to settle an argument
name**: `m365 spo file get --help`. Run that rather than guessing a flag — a
wrong flag is an error, and the CLI's own help is authoritative and always
matches the installed version.

## Conventions worth following

- **Ask for `--output json`** on anything you intend to parse. Without it the CLI
  prints a human-readable table. Use `--output text` when you want a single
  scalar back.
- **Quote arguments containing spaces.** SharePoint paths contain them
  constantly:
  `m365 spo file get --webUrl "https://contoso.sharepoint.com/sites/marketing" --url "/sites/marketing/Shared Documents/Q3 plan.docx"`
- **Parse the output; do not re-run a command to check a value you already have.**

## Downloading a file

To read a document's *contents* you need the bytes on disk. `--asFile` with a
`--path` does that, and you choose where it lands — put it with the rest of your
work (a conversation's `artifacts/`, a task run's `tmp/`) if the user will want
it afterwards:

```
m365 spo file get --webUrl "https://contoso.sharepoint.com/sites/marketing" \
  --url "/sites/marketing/Shared Documents/Q3 plan.docx" \
  --asFile --path "/abs/path/to/Q3 plan.docx"
```

## Things that will otherwise trip you up

- **`--webUrl` is the *site*, `--url` is the *server-relative path*.** Mixing them
  up is the commonest failure by far.
- **List results are paginated.** Several commands cap at 100 items and take
  `--pageSize` / `--pageNumber`. If a count looks suspiciously round, it is a
  page, not the total.
- **Large tenants throttle.** A burst of calls can come back with HTTP 429. Space
  out retries rather than looping immediately, and prefer one broad query to many
  narrow ones.
- **Searching beats walking.** To find a document,
  `m365 spo search --queryText "..."` is far cheaper and far more likely to
  succeed than listing folders down a tree.
- **The account is the server's, not the user's.** Everything runs as whichever
  identity an administrator signed this plugin in as, so the permissions are that
  identity's. Something reported as "not found" may simply be invisible to it, and
  "unauthorized" usually means it lacks a tenant-admin role rather than that the
  command was wrong.
- **That identity may be an application rather than a person.** The plugin signs
  in one of two ways, and `m365 status --output json` names which in `authType`:
  `deviceCode` is a person's account; `certificate` is **app-only**, where no user
  exists at all. Under app-only, anything meaning "the signed-in user" has nothing
  to resolve — `m365 outlook message list` with no `--userName`, a personal
  OneDrive, any "me" endpoint — and those commands fail rather than returning your
  own data. Name the mailbox, site or user explicitly and they work. Permissions
  come from the app registration's *application* permissions, which are often
  broad where a person's would be narrow, or absent where a person's would be
  automatic.

## When authentication fails

First check you are not running `m365` outside `run-plugin` — that CLI is signed
out by design and is the commonest cause of an auth error here.

You cannot sign this plugin in. Sign-in happens in the admin app (Plugins → m365 →
Authenticate) — either a device-code flow a human completes in a browser, or a
certificate the administrator configured. Run `m365 status --output json` to tell
"nobody is signed in" apart from "signed in, but not permitted"; the same output's
`authType` tells you which identity you have, which is usually the next question.
If nobody is signed in, **say so and stop** — do not try to work around it with
`az login`, a raw Graph call, or a shell command.
````

#### `m365/install.sh`

````bash
#!/usr/bin/env bash
# Provision the CLI for Microsoft 365. Idempotent: re-running updates it.
#
# Deliberately does NOT source lib.sh: lib.sh redirects HOME into the plugin so
# the CLI's *tokens* stay there, and npm has no business in that. Tokens are
# scoped, installs are not.
#
# **Not sourcing it is not enough, though.** The server forces `HOME` to the
# plugin's private home for every script it runs, lib.sh or no lib.sh, so this
# script does not get the server user's home by default — it has to ask for it,
# which is what `PLUGIN_REAL_HOME` is for and what `npm_env` below does. Without
# that, npm reads no `~/.npmrc` (so a private registry is invisible) and keeps its
# cache inside the plugin, where every install starts cold. Measured before the
# fix: 321 MB of package tree under the plugin's own home and no shared cache.
#
# It also installs what it needs rather than describing it. This runs under the
# migration wizard against servers nobody has logged into, so a step that ends in
# "run this as an administrator and press the button again" is a step that has
# failed — see `system_install`, and the plugin-owned prefix in the candidate list
# below, which is why "nowhere to install" is no longer an outcome.
set -uo pipefail

# Whether `apt-get update` has already been paid for in this run: a fresh image
# often has no package lists, and refreshing them is slow enough to be worth
# doing once, lazily, and only when an install has actually failed without it.
apt_refreshed=0

# Install a system package, but only when that can happen without a human: as
# root already, or with password-free sudo. `sudo -n` fails instead of prompting,
# which is what makes this safe to call unattended — there is no terminal here for
# anyone to type a password into, so a prompt would just hang until the session's
# timeout. Returns non-zero when the package could not be installed, for any
# reason; the caller decides whether that is fatal.
system_install() {
  local pkg="$1" bin="${2:-$1}" sudo_cmd
  if [ "$(id -u)" -eq 0 ]; then
    sudo_cmd=""
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo_cmd="sudo -n"
  else
    return 1
  fi

  if command -v apt-get >/dev/null 2>&1; then
    if ! DEBIAN_FRONTEND=noninteractive $sudo_cmd apt-get install -y -qq "$pkg" >/dev/null 2>&1; then
      [ "$apt_refreshed" -eq 1 ] && return 1
      apt_refreshed=1
      $sudo_cmd apt-get update -qq >/dev/null 2>&1
      DEBIAN_FRONTEND=noninteractive $sudo_cmd apt-get install -y -qq "$pkg" >/dev/null 2>&1 || return 1
    fi
  elif command -v dnf >/dev/null 2>&1; then
    $sudo_cmd dnf install -y -q "$pkg" >/dev/null 2>&1 || return 1
  elif command -v yum >/dev/null 2>&1; then
    $sudo_cmd yum install -y -q "$pkg" >/dev/null 2>&1 || return 1
  elif command -v apk >/dev/null 2>&1; then
    $sudo_cmd apk add --quiet "$pkg" >/dev/null 2>&1 || return 1
  else
    return 1
  fi

  hash -r 2>/dev/null || true
  command -v "$bin" >/dev/null 2>&1
}

# Run npm the way the server's own user would: its cache and its `.npmrc` from the
# real home, so a private registry works and a second install is warm. Only the
# *install* borrows the real home — the prefix search and everything the CLI does
# at run time stay where they were.
real_home="${PLUGIN_REAL_HOME:-$HOME}"
npm_env() {
  env HOME="$real_home" \
      npm_config_cache="$real_home/.npm" \
      npm_config_userconfig="$real_home/.npmrc" \
      "$@"
}

record_path() {
  # The install prefix's bin directory may not be on the *server process's* PATH.
  # Record it so this plugin's actions find the binary the install produced,
  # rather than depending on how the server happened to be started (lib.sh).
  [ -n "${PLUGIN_STATE_DIR:-}" ] || return 0
  mkdir -p "$PLUGIN_STATE_DIR"
  printf 'export PATH="%s:$PATH"\n' "$1" > "$PLUGIN_STATE_DIR/env.sh"
  echo "Recorded $1 in \$PLUGIN_STATE_DIR/env.sh for this plugin's actions."
}

working_m365() {
  command -v m365 >/dev/null 2>&1 && m365 --version >/dev/null 2>&1
}

# npm's configured global prefix is often root-owned (/usr/local), and this
# script runs as the *server's* user. So find a prefix we can actually write
# into — and test the directory npm really writes to (`lib/node_modules`, and
# the `@pnp` scope inside it if it already exists), not just the top level. A
# prefix whose top level is ours but whose packages were installed with sudo
# looks writable and then fails halfway through a rename.
usable_prefix() {
  local candidate="$1"
  [ -n "$candidate" ] || return 1
  mkdir -p "$candidate/lib/node_modules" 2>/dev/null || return 1
  [ -w "$candidate/lib/node_modules" ] || return 1
  [ ! -d "$candidate/lib/node_modules/@pnp" ] || [ -w "$candidate/lib/node_modules/@pnp" ] || return 1
  return 0
}

if working_m365; then
  echo "CLI for Microsoft 365 is already available at $(command -v m365)"
  m365 --version
  echo
  echo "Checking for an update..."
  echo
fi

# npm itself. Missing on a server whose node came as a single binary, and there is
# no root-free way to conjure it, so this is the one thing here that can still end
# in a sentence for an administrator — but only after trying.
if ! command -v npm >/dev/null 2>&1; then
  echo "npm is not on this server — installing it..."
  system_install npm >/dev/null 2>&1 || system_install nodejs npm >/dev/null 2>&1 || true
  echo
fi

# openssl, for the certificate sign-in mode. `auth.sh` opens a password-protected
# certificate here rather than handing the password to the CLI on a command line
# (process arguments are world-readable), and openssl is what opens it. Best
# effort and never fatal: device-code sign-in does not need it, nor does a
# certificate whose private key has no password.
if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is not on this server — installing it (the certificate sign-in mode uses it)..."
  if ! system_install openssl >/dev/null 2>&1; then
    echo "  Could not install openssl automatically. Nothing else here needs it:"
    echo "  device-code sign-in is unaffected, and so is a certificate with no password."
  fi
  echo
fi

prefix=""
# `$PLUGIN_STATE_DIR/npm-global` is last and is the reason this loop cannot come
# up empty: it is inside the plugin's own folder, so it is always writable, and a
# CLI installed there is this plugin's the way the az plugin's CLI is its own. The
# earlier candidates are preferred only because a shared prefix is shared — one
# copy, one update, and npm's cache already warm.
for candidate in \
  "$(npm_env npm config get prefix 2>/dev/null)" \
  /usr/local/share/npm-global \
  "$HOME/.npm-global" \
  "${PLUGIN_STATE_DIR:-}${PLUGIN_STATE_DIR:+/npm-global}"; do
  if usable_prefix "$candidate"; then
    prefix="$candidate"
    break
  fi
done

if [ -z "$prefix" ]; then
  # With a plugin-owned prefix in the list this is now nearly unreachable — it
  # means even `state/` could not be written to, or npm is absent. If a working
  # CLI is already here, that is a complete answer — the plugin can run — so say
  # what happened and succeed rather than failing over an update nobody asked for.
  if working_m365; then
    echo "No usable npm prefix, so the CLI could not be updated." >&2
    echo "The existing installation at $(command -v m365) works and will be used." >&2
    record_path "$(dirname "$(command -v m365)")"
    exit 0
  fi
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm is not on this server and could not be installed automatically." >&2
    echo "This plugin's CLI is an npm package, so npm is a hard requirement." >&2
    echo "Installing it needs root, which this server does not have (no root, and no" >&2
    echo "password-free sudo). An administrator has to run one of:" >&2
    echo "    apt-get install npm / dnf install npm" >&2
    echo "then run this install again." >&2
    exit 1
  fi
  echo "No writable npm prefix at all — not even inside this plugin's own folder." >&2
  echo "Check the permissions on ${PLUGIN_STATE_DIR:-the state directory}:" >&2
  echo "the server's user has to be able to write there, and it is where this plugin" >&2
  echo "keeps everything else it owns." >&2
  exit 1
fi

echo "Installing @pnp/cli-microsoft365 into $prefix (this takes a minute or two)..."
if ! npm_env npm install -g --prefix "$prefix" @pnp/cli-microsoft365; then
  if working_m365; then
    echo >&2
    echo "The install failed, but an existing CLI at $(command -v m365) works and will be used." >&2
    record_path "$(dirname "$(command -v m365)")"
    exit 0
  fi
  echo "The install failed and no working CLI is present." >&2
  exit 1
fi

bin_dir="$prefix/bin"
export PATH="$bin_dir:$PATH"

echo
if ! working_m365; then
  echo "Installed into $bin_dir, but m365 is not runnable from there." >&2
  exit 1
fi

echo "Installed: $(command -v m365)"
m365 --version
record_path "$bin_dir"

echo
echo "Next: authenticate the plugin, in the sign-in mode it is set to."
echo "  deviceCode  (the default) prints a code a person signs in with."
echo "  certificate signs in as the application, using a certificate you configure."
````

#### `m365/auth.sh`

````bash
#!/usr/bin/env bash
# Sign this plugin in. Runs under a pty, so a device code is printed and streamed
# to the admin page the instant the CLI emits it.
#
# **Two modes, and exactly one of them is in force.** `CLIMICROSOFT365_AUTHTYPE`
# picks it:
#
#   deviceCode   a person signs in and the server acts as that account
#   certificate  the app signs in as itself (app-only), nobody present
#
# One at a time is the whole design, not a limitation working around something.
# The CLI *can* hold several connections at once and switch between them, and
# that is precisely what would make this plugin unexplainable: a command's
# permissions would depend on which connection happened to be current, and the
# admin page's "authenticated" light would be answering about a connection nobody
# chose. So this script signs the old connection out before making a new one, and
# auth-status.sh reports the plugin signed in only while the stored connection's
# type matches the mode set here. Change the mode and the plugin reads as signed
# out until you authenticate again — which is the truth, for the mode you asked
# for.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
require_m365 || exit 1

mode="${CLIMICROSOFT365_AUTHTYPE:-deviceCode}"
case "$mode" in
  deviceCode | certificate) ;;
  *)
    echo "Unknown sign-in mode \"$mode\"." >&2
    echo "Set Plugins -> m365 -> Sign-in mode to 'deviceCode' or 'certificate'." >&2
    exit 2
    ;;
esac

# CLI for Microsoft 365 v10 removed its shared app registration, so every login
# needs an app (client) id — both modes. Without one the CLI *prompts* for it, and
# a prompt in a browser terminal is a bad way to supply a GUID, so refuse with the
# fix instead. `CLIMICROSOFT365_ENTRAAPPID` comes from the plugin's settings.
if [ -z "${CLIMICROSOFT365_ENTRAAPPID:-}" ]; then
  echo "No Entra app (client) ID is configured for this plugin." >&2
  echo >&2
  echo "Set it in the admin app: Plugins -> m365 -> Entra app (client) ID, then" >&2
  echo "run Authenticate again. It is the application (client) ID of the Entra app" >&2
  echo "registration this server signs in with." >&2
  exit 2
fi

# Never block on a prompt. Every value this login needs is passed explicitly
# below, so a prompt here can only mean something is misconfigured — and a
# session waiting on a question nobody can see is worse than a clear failure.
export CLIMICROSOFT365_PROMPT=false

# Where an opened certificate is written, when there is one. Inside the plugin's
# state folder (never listed by the API, never served by the file viewer) and
# removed however this script ends — the CLI copies the certificate into its own
# connection store at login, so nothing here needs to outlive the sign-in.
cert_workdir=""
cleanup() { [ -n "$cert_workdir" ] && rm -rf "$cert_workdir"; }
# INT and TERM as well as EXIT: a session the admin closes is killed, and an EXIT
# trap alone does not run for a signal that was never trapped — which would leave
# an opened private key behind. (SIGKILL cannot be caught at all, which is what
# the sweep in prepare_certificate is for.)
trap cleanup EXIT INT TERM

# Path handed to `--certificateFile`, produced by prepare_certificate.
cert_path=""

# Turn the configured certificate into one readable file holding the certificate
# and an *unencrypted* private key, and set `cert_path` to it.
#
# **The password is never an argument.** `/proc/<pid>/cmdline` is world-readable,
# so `--password "$secret"` publishes the secret to every account on the box. The
# CLI has no other way to take it — so instead of passing it on, this opens the
# certificate here (openssl reads the password from the *environment*, naming the
# variable rather than its value) and hands the CLI a copy that needs no password.
# That is also why openssl is a hard requirement for a protected certificate and
# not one otherwise.
#
# **One channel for the certificate, on purpose.** A "path to a file on the
# server" setting was written and then removed: it said exactly what the base64
# secret says, needed a guard for the two disagreeing, and only helped someone who
# already had shell access on this box — who can just run `base64 -w0` there.
prepare_certificate() {
  local source_path src

  if [ -z "${CLIMICROSOFT365_CERTIFICATE_BASE64:-}" ]; then
    echo "Certificate sign-in is selected, but no certificate is configured." >&2
    echo >&2
    echo "In the admin app, under Plugins -> m365 -> Certificate, base64-encoded, paste" >&2
    echo "the certificate AND its private key (a .pfx, or a .pem holding both):" >&2
    echo "    base64 -w0 cert.pfx" >&2
    echo >&2
    echo "Then add its password, if it has one, and run Authenticate again. The same" >&2
    echo "certificate's PUBLIC half must be uploaded to the app registration under" >&2
    echo "Certificates & secrets -> Certificates, or Entra will not know it." >&2
    return 2
  fi

  # 0077 so every file below is readable only by this user, including the
  # decrypted key. Set before the first write, not after.
  umask 077
  # Sweep anything an earlier run could not clean up after itself — a SIGKILL, a
  # server restart mid-login. Old opened keys are exactly what should not linger.
  rm -rf "${PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}}"/m365-cert.* 2>/dev/null || true
  cert_workdir=$(mktemp -d "${PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}}/m365-cert.XXXXXX") || {
    echo "Could not create a working directory for the certificate." >&2
    return 1
  }

  # `tr -d` first: a pasted base64 blob routinely arrives with newlines, and some
  # `base64` builds refuse them.
  if ! printf '%s' "$CLIMICROSOFT365_CERTIFICATE_BASE64" | tr -d '[:space:]' |
    base64 -d >"$cert_workdir/supplied" 2>/dev/null; then
    echo "The base64 certificate could not be decoded." >&2
    echo "It has to be the base64 of the certificate FILE — \`base64 -w0 cert.pfx\` —" >&2
    echo "not a thumbprint, not the PEM text on its own, and not a password." >&2
    return 2
  fi
  if [ ! -s "$cert_workdir/supplied" ]; then
    echo "The base64 certificate decoded to nothing." >&2
    return 2
  fi
  source_path="$cert_workdir/supplied"

  # No password: hand the file over as it is. A .pfx with no password and a .pem
  # with an unencrypted key are both things the CLI opens by itself.
  if [ -z "${CLIMICROSOFT365_CERTIFICATE_PASSWORD:-}" ]; then
    cert_path="$source_path"
    return 0
  fi

  if ! command -v openssl >/dev/null 2>&1; then
    echo "This certificate has a password, and openssl is not on this server." >&2
    echo >&2
    echo "The password is deliberately never passed to the CLI on a command line —" >&2
    echo "process arguments are readable by every account on the box — so openssl is" >&2
    echo "what opens the certificate here instead. Either install it (apt-get install" >&2
    echo "openssl / dnf install openssl, then run the plugin's Install again), or" >&2
    echo "supply a certificate whose private key is not password-protected and clear" >&2
    echo "the password field." >&2
    return 1
  fi

  src="$source_path"
  local out="$cert_workdir/opened.pem" err="$cert_workdir/openssl.err"

  if head -c 64 "$src" 2>/dev/null | grep -q -- '-----BEGIN'; then
    # PEM with an encrypted key: decrypt the key, keep the certificate as it is,
    # and concatenate the two — which is the shape the CLI expects anyway.
    if ! openssl pkey -in "$src" -passin env:CLIMICROSOFT365_CERTIFICATE_PASSWORD \
      -out "$cert_workdir/key.pem" 2>"$err"; then
      echo "The private key in the PEM could not be opened with the configured password." >&2
      sed 's/^/  openssl: /' "$err" >&2
      return 2
    fi
    if ! openssl x509 -in "$src" -out "$cert_workdir/cert.pem" 2>"$err"; then
      echo "No certificate found in the PEM — it looks like a key on its own." >&2
      echo "The file has to hold the certificate AND its private key." >&2
      sed 's/^/  openssl: /' "$err" >&2
      return 2
    fi
    cat "$cert_workdir/key.pem" "$cert_workdir/cert.pem" >"$out"
  else
    # PKCS#12 (.pfx/.p12). `-legacy` on the retry because a .pfx exported from an
    # older Windows uses RC2, which OpenSSL 3 will not touch without it — a very
    # common file meeting a very common openssl, so it is worth the second try
    # rather than a failure the admin has to decode.
    if ! openssl pkcs12 -in "$src" -out "$out" -nodes \
      -passin env:CLIMICROSOFT365_CERTIFICATE_PASSWORD 2>"$err"; then
      if ! openssl pkcs12 -legacy -in "$src" -out "$out" -nodes \
        -passin env:CLIMICROSOFT365_CERTIFICATE_PASSWORD 2>"$err"; then
        echo "The certificate could not be opened with the configured password." >&2
        echo "Either the password is wrong, or the file is not a .pfx/.p12." >&2
        sed 's/^/  openssl: /' "$err" >&2
        return 2
      fi
    fi
  fi

  if [ ! -s "$out" ]; then
    echo "The certificate opened but produced nothing usable." >&2
    return 1
  fi
  cert_path="$out"
  return 0
}

echo "Signing in to Microsoft 365."
echo "Mode:            $mode"
echo "App (client) ID: $CLIMICROSOFT365_ENTRAAPPID"
[ -n "${CLIMICROSOFT365_TENANT:-}" ] && echo "Tenant:          $CLIMICROSOFT365_TENANT"
echo

args=(login --authType "$mode" --appId "$CLIMICROSOFT365_ENTRAAPPID")
[ -n "${CLIMICROSOFT365_TENANT:-}" ] && args+=(--tenant "$CLIMICROSOFT365_TENANT")

if [ "$mode" = certificate ]; then
  # Client credentials are issued by one tenant, for one tenant. `common` and
  # `organizations` are routing hints for a user sign-in and mean nothing without
  # a user — the token endpoint rejects them, with an error that does not say so.
  case "${CLIMICROSOFT365_TENANT:-}" in
    "" | common | organizations)
      echo "Certificate sign-in needs a real tenant, and Tenant is '${CLIMICROSOFT365_TENANT:-unset}'." >&2
      echo >&2
      echo "App-only sign-in has no user to route, so 'common' and 'organizations' are" >&2
      echo "not answers here. Put the directory (tenant) GUID in Plugins -> m365 ->" >&2
      echo "Tenant — it is on the app registration's overview blade — and run" >&2
      echo "Authenticate again." >&2
      exit 2
      ;;
  esac

  prepare_certificate || exit $?
  # No `--thumbprint`: the CLI computes it from the certificate itself, and a
  # certificate whose real thumbprint is not the one Entra has on record is a
  # broken registration rather than something a setting should paper over.
  args+=(--certificateFile "$cert_path")
  echo "Certificate opened. Signing in as the application — nothing to do here, this"
  echo "takes a few seconds."
else
  echo "Open the URL below, enter the code, and sign in with the account this server should use."
fi
echo

# Clear any existing connection first. Two reasons, and both bite: a stale one
# makes the CLI try a silent token refresh before it offers a device code, and a
# refresh token that is no longer valid fails the whole login with `invalid_grant`
# — no code, no explanation. And this is where one mode replaces another, so the
# connection the previous mode left behind has to go with it. Signing in is
# exactly the moment it is safe to drop the old one.
m365 logout >/dev/null 2>&1 || true

m365 "${args[@]}"
code=$?

echo
if [ "$code" -eq 0 ]; then
  echo "Signed in as:"
  m365 status --output text || true
  if [ "$mode" = certificate ]; then
    echo
    echo "This is an APP-ONLY sign-in: commands run as the application, with the"
    echo "application permissions granted to it — not as any person. If a command now"
    echo "fails with 'Insufficient privileges' or returns nothing where a user would"
    echo "see something, check the app registration's API permissions: it needs"
    echo "APPLICATION permissions (with admin consent), and delegated ones do nothing"
    echo "in this mode."
  fi
elif [ "$mode" = certificate ]; then
  echo "Sign-in did not complete (exit $code)." >&2
  echo >&2
  echo "What the common failures mean, read off the AADSTS code above:" >&2
  echo "  AADSTS700027 / 'Client assertion contains an invalid signature'" >&2
  echo "      Entra does not know this certificate for this app. The PUBLIC half has" >&2
  echo "      to be uploaded to the app registration (Certificates & secrets ->" >&2
  echo "      Certificates), and it must be the same certificate configured here." >&2
  echo "  AADSTS700016 / invalid_client" >&2
  echo "      The app (client) ID is wrong, or no such app exists in this tenant." >&2
  echo "  AADSTS90002 / 'Tenant not found'" >&2
  echo "      The Tenant setting is not a tenant this app lives in. Use the GUID." >&2
  echo "  AADSTS7000222 / 'The provided client secret keys are expired'" >&2
  echo "      The certificate has expired. Issue a new one, upload it to the app" >&2
  echo "      registration, and replace it here." >&2
else
  echo "Sign-in did not complete (exit $code)." >&2
  echo >&2
  echo "What the common failures mean, read off the AADSTS code above:" >&2
  echo "  AADSTS7000014  (invalid_grant, \"device_code is not valid\")" >&2
  echo "      Almost always the wrong Tenant. A single-tenant app registration" >&2
  echo "      cannot authenticate through 'common' — put your tenant's GUID in the" >&2
  echo "      plugin's Tenant setting and try again. This one shows no code at all," >&2
  echo "      which is how you tell it apart from a code that went unused." >&2
  echo "  AADSTS700016 / invalid_client" >&2
  echo "      The app (client) ID is wrong, or no such app exists in this tenant." >&2
  echo "  AADSTS7000218" >&2
  echo "      The app registration is not a public client. Turn on 'Allow public" >&2
  echo "      client flows', which is what device-code sign-in requires." >&2
  echo "  AADSTS70016 / expired_token" >&2
  echo "      The code was not entered in time. Run Authenticate again." >&2
fi
exit "$code"
````

#### `m365/auth-status.sh`

````bash
#!/usr/bin/env bash
# The probe behind `Plugin.authenticated`. Exit 0 means signed in, in the mode
# this plugin is configured for.
#
# **Do not trust `m365 status`'s exit code**: it is 0 whether signed in or not
# (`m365 status --output json` prints the bare string `"Logged out"` and exits 0).
# A probe that returned `$?` therefore reported "signed in" always, which is
# exactly what the admin page showed while the plugin was logged out. So the
# *output* is what decides: `connectedAs` appears only in a real connection.
#
# **And the connection has to be the configured one.** The CLI can hold several
# connections at once, so a certificate plugin can be sitting on a device-code
# connection left over from before the mode was changed — signed in, as the wrong
# identity, with the wrong permissions. `authType` in the same output says which,
# and a mismatch reads as not signed in: the sign-in this plugin is configured to
# have has not happened yet. Authenticating takes exactly that mode, so the light
# turns green for the right reason.
#
# Quiet on purpose — nothing reads this script's output, only its exit code.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"

export CLIMICROSOFT365_PROMPT=false
command -v m365 >/dev/null 2>&1 || exit 1

out=$(m365 status --output json 2>/dev/null) || exit 1
case "$out" in
  *'"connectedAs"'*) ;;
  *) exit 1 ;;
esac

# `{"connectionName": "x", "authType": "deviceCode", ...}` -> `deviceCode`, with
# no jq: strip spaces and quotes, split on commas, take the field. An older CLI
# that does not report `authType` yields nothing here, and an empty answer is not
# evidence of a mismatch — `connectedAs` already said signed in, so leave it.
active=$(printf '%s' "$out" | tr -d ' \t"' | tr ',' '\n' | sed -n 's/^authType:\(.*\)$/\1/p' | head -1)
[ -n "$active" ] || exit 0

want="${CLIMICROSOFT365_AUTHTYPE:-deviceCode}"
[ "$active" = "$want" ] || exit 1
exit 0
````

#### `m365/run.sh`

````bash
#!/usr/bin/env bash
# Run one m365 command. The command arrives in the environment (PLUGIN_COMMAND)
# and on stdin as JSON — never on this script's command line, so nothing a
# caller sends is visible in `ps`.
#
# It is executed **as written**. That is the contract the guideline is built on:
# what the agent sends is what runs, so the guideline can document the real CLI
# rather than a translation nobody can debug through. All this script adds is
# what the plugin exists for — the binary on PATH, and the account signed in.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
require_m365 || exit 1

# Nothing is watching a command run by the agent, so a CLI prompt would hang it
# until the timeout. Fail on a missing required option instead.
export CLIMICROSOFT365_PROMPT=false

command_text="${PLUGIN_COMMAND:-}"
if [ -z "$command_text" ]; then
  echo "No command given. See GUIDELINE.md for the m365 command vocabulary." >&2
  exit 2
fi

# `eval` because a command is a command: SharePoint paths contain spaces
# constantly, and word-splitting them would break every one of them.
eval "$command_text"
````

#### `m365/lib.sh`

````bash
# Shared preamble for every m365 script. Sourced, never executed.
#
# Why it exists: `npm install -g` may have landed the CLI in a prefix that is not
# on the *server process's* PATH (see install.sh). The install records the bin
# directory here, so a command finds the binary the install actually produced
# rather than depending on how the server happened to be started.
if [ -n "${PLUGIN_STATE_DIR:-}" ] && [ -f "$PLUGIN_STATE_DIR/env.sh" ]; then
  # shellcheck disable=SC1091
  . "$PLUGIN_STATE_DIR/env.sh"
fi

# **This plugin's sign-in is its own, not the machine's — and the platform sees to
# that, not this file.** `HOME` already points at `state/home/` for every script.
#
# CLI for Microsoft 365 keeps its tokens at `os.homedir()/.cli-m365-*.json`, and
# Node's `os.homedir()` honours $HOME — so pointing HOME at the plugin's private
# home puts the MSAL cache and the connection files inside
# `plugins/m365/state/home/` instead of the server user's home directory.
#
# What that buys: signing this plugin in no longer signs in every process on the
# box that runs `m365`. What it costs, and it is a real cost: a skill or a shell
# command that invokes `m365` directly now sees a signed-out CLI. Everything that
# needs this account must go through `run-plugin`, which is what the guideline
# tells the agent.
#
# Sourced by auth.sh, auth-status.sh and run.sh — the three that touch tokens, and
# they MUST agree: a login written to one home and read from another can never be
# signed in. install.sh deliberately does NOT source this file, so `npm` keeps the
# real home and its cache and .npmrc with it.

require_m365() {
  command -v m365 >/dev/null 2>&1 && return 0
  echo "The m365 CLI is not available. Install the plugin from the admin app first." >&2
  return 1
}
````

### Example: jira

#### `jira/plugin.json`

````json
{
  "name": "jira",
  "description": "Jira Cloud — read, search, create, comment on and transition issues through the Jira REST API v3 with curl.",
  "keywords": ["jira", "issues", "tickets", "bugs", "jql", "atlassian"],
  "version": "2.1.0",
  "guideline": "GUIDELINE.md",
  "install": {
    "runtime": "bash",
    "script": "install.sh",
    "timeoutMs": 300000
  },
  "auth": {
    "runtime": "bash",
    "script": "auth.sh",
    "statusScript": "auth-status.sh"
  },
  "run": {
    "runtime": "bash",
    "script": "run.sh",
    "timeoutMs": 180000
  },
  "settings": [
    {
      "key": "JIRA_SITE",
      "label": "Jira site",
      "required": true,
      "description": "The Atlassian site host, without a scheme — e.g. `mycompany.atlassian.net`. The site's cloud id is looked up from it automatically, so there is nothing else to configure."
    },
    {
      "key": "JIRA_EMAIL",
      "label": "Account email",
      "required": true,
      "description": "Email of the Atlassian account the API token belongs to. Jira's Basic auth is `email:token`, and everything the agent does happens as this account — its permissions are the plugin's permissions."
    }
  ],
  "secrets": [
    {
      "key": "JIRA_API_TOKEN",
      "label": "API token",
      "required": true,
      "description": "An Atlassian API token from id.atlassian.com/manage-profile/security/api-tokens. Either kind works here: this plugin calls Jira through the api.atlassian.com gateway, which accepts scoped and unscoped (classic) tokens alike. Tokens can carry an expiry date — if calls start failing with 401, check that first."
    }
  ]
}
````

#### `jira/GUIDELINE.md`

````markdown
# Jira Cloud, through its REST API

This plugin runs **curl** already authenticated to a Jira site. Two things are set
up for you and nothing else is:

- **`curl -n`** picks up the credential on its own (it is in a `.netrc` this plugin
  owns). Never put a token, a header or a `-u` flag in a command — there is nothing
  to supply.
- **`$JIRA_BASE`** is the API root for this site
  (`https://api.atlassian.com/ex/jira/<cloudId>`). It cannot be guessed, so build
  every URL from it.

```bash
curl -sn "$JIRA_BASE/rest/api/3/myself" | jq -r .displayName
```

`$JIRA_SITE_URL` is the site's own address, for links you show a person:
`$JIRA_SITE_URL/browse/KEY-123`.

**Whose account this is.** One Atlassian account. Its permissions are the plugin's
permissions, and Jira *hides* what an account cannot see rather than forbidding it —
so a project it lacks access to reports as "does not exist".

## Ask for what you need, and nothing else

A Jira issue is a very large JSON document — a hundred-odd fields, most of them
empty custom fields. Always narrow it, twice over:

```bash
# `fields` narrows what Jira sends; jq narrows what you read
curl -sn "$JIRA_BASE/rest/api/3/issue/KEY-123?fields=summary,status,assignee,description" \
  | jq '{key, summary: .fields.summary, status: .fields.status.name, assignee: .fields.assignee.displayName}'
```

`fields=*all` exists and is almost never what you want.

## Reading

| Task | Call |
|---|---|
| Who am I | `curl -sn "$JIRA_BASE/rest/api/3/myself"` |
| One issue | `curl -sn "$JIRA_BASE/rest/api/3/issue/KEY-123?fields=summary,status,description"` |
| Its comments | `curl -sn "$JIRA_BASE/rest/api/3/issue/KEY-123/comment"` |
| Allowed transitions | `curl -sn "$JIRA_BASE/rest/api/3/issue/KEY-123/transitions"` |
| Search | see below — the endpoint has changed |
| Projects | `curl -sn "$JIRA_BASE/rest/api/3/project/search?maxResults=50"` |
| One project | `curl -sn "$JIRA_BASE/rest/api/3/project/KEY"` |
| Field ids (for custom fields) | `curl -sn "$JIRA_BASE/rest/api/3/field"` |
| What a project needs to create | `curl -sn "$JIRA_BASE/rest/api/3/issue/createmeta?projectKeys=KEY"` |
| Find a user's accountId | `curl -sn "$JIRA_BASE/rest/api/3/user/search?query=someone@example.com"` |

## Searching — `/search/jql`, not `/search`

**`GET /rest/api/3/search` has been removed and answers HTTP 410.** Use
`/rest/api/3/search/jql`:

```bash
curl -sn --get "$JIRA_BASE/rest/api/3/search/jql" \
  --data-urlencode 'jql=project = DD AND status != Done ORDER BY created DESC' \
  --data-urlencode 'fields=key,summary,status,assignee' \
  --data-urlencode 'maxResults=20' \
  | jq -r '.issues[] | "\(.key)  [\(.fields.status.name)]  \(.fields.summary)"'
```

`--get --data-urlencode` is the reliable way to send JQL: it URL-encodes the spaces,
`=` and quotes for you, and hand-encoding a query is a guaranteed source of 400s.

Three things about this endpoint specifically:

- **JQL must be bounded.** An open query is refused with *"Unbounded JQL queries are
  not allowed here. Please add a search restriction to your query."* — so
  `ORDER BY created DESC` on its own fails. Restrict it: `project = X`,
  `assignee = currentUser()`, `updated >= -7d`.
- **Paging is `nextPageToken`, not `startAt`.** The response carries
  `nextPageToken` and `isLast`; there is no `total`. Pass the token back as
  `nextPageToken=…` for the next page, and stop when `isLast` is true. Do not
  expect a result count — if you need one, use JQL you can bound and count what
  you receive.
- **Nothing tells you a page was the last one except `isLast`.** A page of exactly
  `maxResults` issues is not evidence either way.

## Writing

Reads are safe; **writes change somebody's tracker.** Do exactly what was asked,
and echo back the key of anything you create or change.

```bash
# Comment (v2 takes plain text — see the ADF note below)
curl -sn -X POST "$JIRA_BASE/rest/api/2/issue/KEY-123/comment" \
  -H 'Content-Type: application/json' \
  --data '{"body":"Deployed to staging."}'

# Edit fields
curl -sn -X PUT "$JIRA_BASE/rest/api/2/issue/KEY-123" \
  -H 'Content-Type: application/json' \
  --data '{"fields":{"summary":"New summary"}}'

# Transition — the id comes from the transitions endpoint, names are not accepted
curl -sn -X POST "$JIRA_BASE/rest/api/3/issue/KEY-123/transitions" \
  -H 'Content-Type: application/json' \
  --data '{"transition":{"id":"31"}}'

# Create
curl -sn -X POST "$JIRA_BASE/rest/api/2/issue" \
  -H 'Content-Type: application/json' \
  --data '{"fields":{"project":{"key":"DD"},"issuetype":{"name":"Task"},"summary":"...","description":"..."}}'
```

Build a JSON body with `jq -n` rather than by hand when any value comes from user
text — a stray quote or newline otherwise produces an invalid body:

```bash
body=$(jq -n --arg t "$TEXT" '{body: $t}')
curl -sn -X POST "$JIRA_BASE/rest/api/2/issue/KEY-123/comment" \
  -H 'Content-Type: application/json' --data "$body"
```

**A successful write returns `201` (create) or `204` (update/transition) with an
empty body.** Add `-w '\n%{http_code}\n'` if you want to see it, and do not treat
an empty response as a failure.

## v3 or v2 — and this is the one that saves the most trouble

Both are available on this site. They differ in how rich-text fields
(`description`, comment `body`) are represented:

- **v3 uses ADF**, Atlassian Document Format: a nested JSON document
  (`{"type":"doc","version":1,"content":[…]}`). Reading it means walking the tree;
  writing it means constructing one.
- **v2 uses plain strings** for the same fields. Verified on this site: the same
  issue's description comes back as an ADF object from `/rest/api/3/` and as a
  plain string from `/rest/api/2/`.

So: **use v2 for anything involving description or comment text**, in both
directions, unless specific formatting was asked for. Use v3 for everything else
(it is the current API and `/search/jql` lives there). Mixing them per call is
normal and fine.

## What is not available here

**The Agile API (`/rest/agile/1.0/…`) is out of scope for this credential** —
boards, sprints and backlogs answer `401 {"code":401,"message":"Unauthorized; scope
does not match"}`, and no amount of retrying changes that. Say so rather than
working around it. What you *can* still do: an issue's sprint is a custom field on
the issue itself, so `fields=customfield_XXXXX` (find the id via
`/rest/api/3/field`) reads sprint membership, and JQL understands `sprint in
openSprints()`.

## What a failure means

- **`401`** — the credential. The token has expired, been revoked, or does not match
  the email. A human re-authenticates the plugin from the admin app; you cannot.
  Report it and stop. (A `401` mentioning *"scope does not match"* is different: that
  is an endpoint this token cannot reach, above.)
- **`403`** — authenticated but not permitted. A real permission, not a retry.
- **`404` on an issue key you believe in** — usually the account cannot see that
  project. Check with `/rest/api/3/project/search`; if it is not listed, it is
  permissions, not a typo.
- **`400` on a search** — unbounded JQL, or a JQL syntax error. The response body
  says which; read it.
- **`410`** — you called `/rest/api/3/search`. Use `/search/jql`.
- **`429`** — rate limited. Back off and retry once, more slowly; do not hammer.

`curl` exits **0** for all of these: the request succeeded, the answer was no. Read
the body, or ask for the status with `-w '\n%{http_code}\n'`; do not judge a call by
curl's exit code alone.
````

#### `jira/install.sh`

````bash
#!/usr/bin/env bash
# Check what this plugin needs, install what is missing, and resolve the site's
# cloud id.
#
# There is nothing much to download: the tool is curl. So this script's job is
# mostly the other half of an install — proving the environment can do what the
# plugin promises, while a human is watching, rather than at the moment the agent
# first tries. Deliberately does not source lib.sh: it needs no credential.
#
# What it will *not* do is hand a shell command to whoever is watching. This runs
# under the migration wizard on servers nobody has touched yet, so a missing
# package is installed here if that is possible at all — see `system_install`.
set -uo pipefail

# Whether `apt-get update` has already been paid for in this run: a fresh image
# often has no package lists, and refreshing them is slow enough to be worth
# doing once, lazily, and only when an install has actually failed without it.
apt_refreshed=0

# Install a system package, but only when that can happen without a human: as
# root already, or with password-free sudo. `sudo -n` fails instead of prompting,
# which is what makes this safe to call unattended — there is no terminal here for
# anyone to type a password into, so a prompt would just hang until the session's
# timeout. Returns non-zero when the package could not be installed, for any
# reason; the caller decides whether that is fatal.
system_install() {
  local pkg="$1" bin="${2:-$1}" sudo_cmd
  if [ "$(id -u)" -eq 0 ]; then
    sudo_cmd=""
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo_cmd="sudo -n"
  else
    return 1
  fi

  if command -v apt-get >/dev/null 2>&1; then
    if ! DEBIAN_FRONTEND=noninteractive $sudo_cmd apt-get install -y -qq "$pkg" >/dev/null 2>&1; then
      [ "$apt_refreshed" -eq 1 ] && return 1
      apt_refreshed=1
      $sudo_cmd apt-get update -qq >/dev/null 2>&1
      DEBIAN_FRONTEND=noninteractive $sudo_cmd apt-get install -y -qq "$pkg" >/dev/null 2>&1 || return 1
    fi
  elif command -v dnf >/dev/null 2>&1; then
    $sudo_cmd dnf install -y -q "$pkg" >/dev/null 2>&1 || return 1
  elif command -v yum >/dev/null 2>&1; then
    $sudo_cmd yum install -y -q "$pkg" >/dev/null 2>&1 || return 1
  elif command -v apk >/dev/null 2>&1; then
    $sudo_cmd apk add --quiet "$pkg" >/dev/null 2>&1 || return 1
  else
    return 1
  fi

  hash -r 2>/dev/null || true
  command -v "$bin" >/dev/null 2>&1
}

fail=0
echo "Checking what this plugin needs."
echo

if ! command -v curl >/dev/null 2>&1; then
  echo "  curl: not found — installing it..."
  system_install curl >/dev/null 2>&1 || true
fi
if command -v curl >/dev/null 2>&1; then
  echo "  curl: $(curl --version | head -1 | awk '{print $2}')  ($(command -v curl))"
else
  echo "  curl: NOT FOUND, and it could not be installed automatically." >&2
  echo "        This plugin cannot call Jira without it. Installing curl needs root," >&2
  echo "        which this server does not have (no root, no password-free sudo)." >&2
  fail=1
fi

# jq is optional but close to essential in practice, so it is installed rather
# than recommended: without it a whole issue's JSON goes through the agent's
# context to answer a question about one field.
if ! command -v jq >/dev/null 2>&1; then
  echo "  jq:   not found — installing it (Jira's responses are large JSON documents)..."
  system_install jq >/dev/null 2>&1 || true
fi
if command -v jq >/dev/null 2>&1; then
  echo "  jq:   $(jq --version)  (for reading JSON responses)"
else
  echo "  jq:   not found, and it could not be installed automatically — this plugin"
  echo "        still works, but less well: Jira's responses are large JSON documents,"
  echo "        and reading them without jq means pulling whole issues through the"
  echo "        agent's context. Installing jq needs root, which this server does not"
  echo "        have. A fallback parser is used until then."
fi

echo

# --- the cloud id ------------------------------------------------------------
#
# Every call goes through api.atlassian.com/ex/jira/<cloudId>, and the site tells
# us its own cloud id without authentication. Resolving it here means an admin
# never has to find it, and a failure is diagnosed now rather than as a confusing
# 404 later.
host="${JIRA_SITE:-}"
host="${host#http://}"; host="${host#https://}"; host="${host%%/*}"

if [ -z "$host" ]; then
  echo "No Jira site configured yet, so its cloud id could not be looked up."
  echo "  Set 'Jira site' (e.g. mycompany.atlassian.net) in the admin app, then run"
  echo "  Install again — or just press Authenticate, which resolves it too."
else
  echo "Looking up the cloud id for $host ..."
  if info=$(curl -sS --max-time 20 "https://$host/_edge/tenant_info" 2>&1); then
    id=$(printf '%s' "$info" | sed -n 's/.*"cloudId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    if [ -n "$id" ]; then
      echo "  cloudId: $id"
      echo "  API base: https://api.atlassian.com/ex/jira/$id"
      if [ -n "${PLUGIN_STATE_DIR:-}" ]; then
        mkdir -p "$PLUGIN_STATE_DIR"
        printf 'JIRA_CACHED_SITE=%s\nJIRA_CLOUD_ID=%s\n' "$host" "$id" \
          > "$PLUGIN_STATE_DIR/site.env"
        echo "  Cached in \$PLUGIN_STATE_DIR/site.env (re-resolved if the site setting changes)."
      fi
    else
      echo "  https://$host/_edge/tenant_info gave no cloudId." >&2
      echo "  The site should be a bare host — no scheme, no path." >&2
      fail=1
    fi
  else
    echo "  Could not reach https://$host" >&2
    printf '  %s\n' "$(printf '%s' "$info" | head -2)" >&2
    echo "  If this server restricts outbound traffic, atlassian.net and" >&2
    echo "  api.atlassian.com both need to be reachable." >&2
    fail=1
  fi
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "Install incomplete — fix the items above and run it again." >&2
  exit 1
fi

echo "Ready."
echo
echo "Next: set the Jira site, the account email and the API token in the admin app,"
echo "then press Authenticate. Nothing interactive — it takes a second."
````

#### `jira/auth.sh`

````bash
#!/usr/bin/env bash
# Store the credential, and prove it works.
#
# Nothing here waits for a human — Basic auth with an API token needs no round
# trip to a browser — but it is still a streamed session, and the second half is
# why: storing a token proves nothing, so "signed in" has to be established by
# making a real request while somebody is watching the output.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
require_curl || exit 1
jira_check_config || exit 2

host=$(jira_host)
echo "Signing in to Jira."
echo "  site:  $host"
echo "  email: $JIRA_EMAIL"
echo

echo "1. Looking up the site's cloud id..."
jira_resolve_base || exit 1
echo "   cloudId:  $JIRA_CLOUD_ID"
echo "   API base: $JIRA_BASE"
echo

echo "2. Storing the credential..."
if ! jira_write_netrc; then
  echo "   Could not write the credential file in the plugin's private home." >&2
  echo "   Check the permissions on the plugin's state folder." >&2
  exit 1
fi
echo "   Written to the plugin's own home, mode 0600. It is never passed on a"
echo "   command line, so it cannot appear in \`ps\` or in a transcript."
echo

echo "3. Checking it against Jira..."
body=$(curl -sS -n --max-time 25 -w '\n%{http_code}' \
  -H 'Accept: application/json' "$JIRA_BASE/rest/api/3/myself" 2>&1) || {
  echo "   Could not reach $JIRA_BASE" >&2
  printf '   %s\n' "$(printf '%s' "$body" | head -2)" >&2
  exit 1
}
code=$(printf '%s' "$body" | tail -1)
body=$(printf '%s' "$body" | sed '$d')

case "$code" in
  200)
    if command -v jq >/dev/null 2>&1; then
      echo "   Jira says this is: $(printf '%s' "$body" | jq -r '"\(.displayName) <\(.emailAddress // "no email visible")>"')"
      echo "   accountId: $(printf '%s' "$body" | jq -r '.accountId')"
    else
      echo "   Jira accepted it (HTTP 200)."
    fi
    echo
    echo "Signed in. The agent can now call the Jira REST API with plain curl:"
    echo "   curl -sn \"\$JIRA_BASE/rest/api/3/issue/KEY-123\" | jq ."
    echo
    echo "This account's permissions are the plugin's permissions. Jira hides what an"
    echo "account cannot see rather than forbidding it, so a project this one lacks"
    echo "access to reports as 'does not exist'."
    exit 0
    ;;
  401)
    echo "   Jira refused the credential (HTTP 401)." >&2
    echo >&2
    echo "   In order of likelihood:" >&2
    echo "     1. The API token has expired or been revoked. Atlassian tokens can carry" >&2
    echo "        an expiry date. Create a new one and store it here:" >&2
    echo "        https://id.atlassian.com/manage-profile/security/api-tokens" >&2
    echo "     2. The email does not match the token's account. Basic auth here is" >&2
    echo "        email:token, so both have to belong together." >&2
    echo "     3. The token was pasted with a leading or trailing space." >&2
    ;;
  403)
    echo "   Authenticated, but forbidden (HTTP 403)." >&2
    echo "   The credential is good and the account is not permitted. Check that it has" >&2
    echo "   a Jira application licence, not just an Atlassian account." >&2
    ;;
  404)
    echo "   HTTP 404 from $JIRA_BASE" >&2
    echo "   The cloud id resolved but the gateway does not recognise it. Check the" >&2
    echo "   'Jira site' setting names the right site." >&2
    ;;
  *)
    echo "   Unexpected response (HTTP ${code:-none})." >&2
    printf '   %s\n' "$(printf '%s' "$body" | head -c 300)" >&2
    ;;
esac
exit 1
````

#### `jira/auth-status.sh`

````bash
#!/usr/bin/env bash
# The probe behind `Plugin.authenticated`. Exit 0 means usable. Silent by design.
#
# It really calls Jira, rather than checking that a token is *present*. An API
# token can be revoked or expire, and a probe that only looked for a stored value
# would show a green chip through the whole outage. `/myself` is the cheapest
# authenticated endpoint there is, well inside the platform's 20s budget, and the
# answer is cached for 30s.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"

command -v curl >/dev/null 2>&1 || exit 1
[ -n "${JIRA_SITE:-}" ]      || exit 1
[ -n "${JIRA_EMAIL:-}" ]     || exit 1
[ -n "${JIRA_API_TOKEN:-}" ] || exit 1

# Write the netrc first: the probe must test the credential that is *stored now*,
# not whatever the last Authenticate happened to leave on disk.
jira_write_netrc >/dev/null 2>&1 || exit 1
jira_usable >/dev/null 2>&1
````

#### `jira/run.sh`

````bash
#!/usr/bin/env bash
# Run one command with Jira credentials in place.
#
# The command arrives in the environment (PLUGIN_COMMAND) and on stdin as JSON —
# never on this script's command line — and is executed **as written**. That
# verbatim contract is what lets the guideline document the real REST API rather
# than a translation nobody can debug through.
#
# What this adds is only environment, which is the whole reason the plugin exists
# rather than the agent curling Jira itself:
#   - the credential, in a `.netrc` curl finds on its own, so `curl -n` is
#     authenticated and no token appears in the command or its output
#   - `$JIRA_BASE`, the gateway URL for this site, which is not guessable
#
# Nothing here decides where the command runs: the platform has already put this
# process in the directory the caller asked for, or in the turn's own scratch
# folder when it named none.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
require_curl || exit 1

command_text="${PLUGIN_COMMAND:-}"
if [ -z "$command_text" ]; then
  echo "No command given. See GUIDELINE.md for the Jira REST API vocabulary." >&2
  exit 2
fi

jira_check_config || exit 2
jira_resolve_base || exit 1

# Rewritten per command, so a token rotated in the admin app takes effect on the
# next call rather than at the next Authenticate.
jira_write_netrc || {
  echo "Could not write the credential file for this command." >&2
  exit 1
}

export JIRA_BASE JIRA_CLOUD_ID
export JIRA_SITE_URL="https://$(jira_host)"

# **Drop the raw token before running anything.** The command reaches Jira through
# the netrc, so it has no need of the token itself — and a command that dumps its
# own environment then leaks nothing.
unset JIRA_API_TOKEN

# Run the command under default shell semantics, not this script's: `pipefail`
# would turn `… | head -5` into exit 141 (SIGPIPE) and report a command that did
# exactly what was asked as a failure.
set +u +o pipefail

# `eval` because a command is a command: a JQL query and a JSON body are full of
# spaces and quotes, and word-splitting them would break every one of them.
eval "$command_text"
````

#### `jira/lib.sh`

````bash
# Shared preamble for every script in this plugin. Sourced, never executed.
#
# The tool here is **curl**, which every box already has, so what this plugin adds
# is only the credential and the base URL. There is no CLI to install and no
# vocabulary to learn: the agent writes ordinary curl commands against Jira's
# documented REST API.

# ---------------------------------------------------------------------------
# The private home, which is where the credential lives
# ---------------------------------------------------------------------------

# **The private `HOME` is load-bearing here rather than tidiness**, and the platform
# has already set it. The credential is handed to curl through a `.netrc`, and curl looks
# for that in `$HOME` — so the private home is what keeps it inside
# `plugins/jira/state/home/` instead of the server user's home directory, where it
# would authenticate every process on the box.
#
# auth.sh, auth-status.sh and run.sh must all agree on this: a `.netrc` written to
# one home and read from another can never be signed in. install.sh does not
# source this file.

JIRA_NETRC="$HOME/.netrc"
JIRA_CACHE="${PLUGIN_STATE_DIR:-$HOME}/site.env"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Report every missing value at once, naming the admin field.
jira_check_config() {
  local missing=""
  [ -n "${JIRA_SITE:-}" ]      || missing="$missing  - Jira site (JIRA_SITE)\n"
  [ -n "${JIRA_EMAIL:-}" ]     || missing="$missing  - Account email (JIRA_EMAIL)\n"
  [ -n "${JIRA_API_TOKEN:-}" ] || missing="$missing  - API token (JIRA_API_TOKEN)\n"
  [ -z "$missing" ] && return 0
  {
    echo "This plugin is not configured yet. Missing:"
    printf "$missing"
    echo
    echo "Set them in the admin app: Plugins -> $PLUGIN_NAME -> Settings."
    echo "The site and email are readable settings; the API token is write-only."
  } >&2
  return 1
}

# Strip anything but the host, so a site pasted as a URL still works.
jira_host() {
  local h="${JIRA_SITE:-}"
  h="${h#http://}"
  h="${h#https://}"
  printf '%s' "${h%%/*}"
}

# ---------------------------------------------------------------------------
# The credential
# ---------------------------------------------------------------------------

# Hand the token to curl through a `.netrc`, so the agent's command can be plain
# `curl -n` with **no credential in it at all**.
#
# The alternative was to export the token as an environment variable and document
# `curl -H "Authorization: Basic $TOKEN"`. That is worse in two ways that matter
# more than the one way it is better. It puts the token in curl's **argv**, and
# `/proc/<pid>/cmdline` is world-readable — every account on the box could read it
# while a command runs. And it names the token in the guideline, so the model knows
# it by name and can print it into a transcript.
#
# What it costs: the token is written to disk here, in plaintext, at 0600, inside
# the plugin's `state/`. That folder is not listed by the API but *is* readable by
# path through the plugin file route, so an administrator can read it back — and
# any process running as this user can. That is the same exposure a wrapped CLI's
# own token store has (the m365 plugin's MSAL cache, acli's config files), so it is
# not a new class of risk; it is the ordinary one for a plugin that holds a login.
# Rewritten on every command, so rotating the secret in the admin app takes effect
# on the next call rather than at the next Authenticate.
jira_write_netrc() {
  local host tmp
  host=$(jira_host)
  [ -n "$host" ] || return 1
  tmp="$JIRA_NETRC.$$"
  # Written to a temp file and moved, and created 0600 *before* anything is in it:
  # a create-then-chmod leaves a window where the token is world-readable.
  ( umask 077; : > "$tmp" ) || return 1
  {
    echo "# Written by the '$PLUGIN_NAME' plugin. Do not edit."
    # api.atlassian.com is the gateway every call goes through; the site host is
    # here too so a direct call to it works with an unscoped token.
    printf 'machine api.atlassian.com login %s password %s\n' "$JIRA_EMAIL" "$JIRA_API_TOKEN"
    printf 'machine %s login %s password %s\n' "$host" "$JIRA_EMAIL" "$JIRA_API_TOKEN"
  } >> "$tmp" || return 1
  mv -f "$tmp" "$JIRA_NETRC" || return 1
  chmod 600 "$JIRA_NETRC" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# The base URL
# ---------------------------------------------------------------------------

# Every call goes through `api.atlassian.com/ex/jira/<cloudId>`, which needs the
# site's cloud id — and that is **discovered, not configured**: `/_edge/tenant_info`
# on the site answers it without authentication. One less thing for an admin to
# find, and it cannot go stale against the site setting.
#
# Cached in `state/`, keyed by the site it was resolved for, so editing the site
# setting re-resolves rather than silently pointing at the old tenant. Without the
# cache every command would pay an extra round trip — the same objection that
# applies to minting a credential per call.
jira_resolve_base() {
  local host cached_site cached_id info
  host=$(jira_host)
  [ -n "$host" ] || return 1

  if [ -f "$JIRA_CACHE" ]; then
    # shellcheck disable=SC1090
    . "$JIRA_CACHE"
    cached_site="${JIRA_CACHED_SITE:-}"
    cached_id="${JIRA_CLOUD_ID:-}"
    if [ "$cached_site" = "$host" ] && [ -n "$cached_id" ]; then
      export JIRA_CLOUD_ID="$cached_id"
      export JIRA_BASE="https://api.atlassian.com/ex/jira/$cached_id"
      return 0
    fi
  fi

  info=$(curl -sS --max-time 20 "https://$host/_edge/tenant_info" 2>&1) || {
    echo "Could not reach https://$host to look up its cloud id." >&2
    echo "$info" >&2
    return 1
  }
  local id
  id=$(printf '%s' "$info" | sed -n 's/.*"cloudId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  if [ -z "$id" ]; then
    echo "https://$host/_edge/tenant_info did not return a cloudId." >&2
    echo "Check the 'Jira site' setting: it should be a bare host such as" >&2
    echo "mycompany.atlassian.net — no scheme, no path." >&2
    return 1
  fi
  if [ -n "${PLUGIN_STATE_DIR:-}" ]; then
    mkdir -p "$PLUGIN_STATE_DIR" 2>/dev/null || true
    printf 'JIRA_CACHED_SITE=%s\nJIRA_CLOUD_ID=%s\n' "$host" "$id" > "$JIRA_CACHE" 2>/dev/null || true
  fi
  export JIRA_CLOUD_ID="$id"
  export JIRA_BASE="https://api.atlassian.com/ex/jira/$id"
}

require_curl() {
  command -v curl >/dev/null 2>&1 && return 0
  echo "curl is not available on this server, so this plugin cannot call Jira." >&2
  return 1
}

# **Is the credential usable?** One real, cheap call.
#
# `/myself` is the smallest authenticated endpoint Jira has: no arguments to get
# wrong, and it fails exactly as everything else does. Checking the HTTP status
# rather than curl's exit code, because curl exits 0 on a 401 — the request
# succeeded, the answer was "no".
jira_usable() {
  jira_resolve_base >/dev/null 2>&1 || return 1
  local code
  code=$(curl -sS -n --max-time 15 -o /dev/null -w '%{http_code}' \
    -H 'Accept: application/json' "$JIRA_BASE/rest/api/3/myself" 2>/dev/null) || return 1
  [ "$code" = "200" ]
}
````

### Excerpt: the `az` fingerprint trick

The one piece of the `az` plugin worth copying on its own: from its `lib.sh`. `az_ensure_login` runs
before every command in `run.sh`, so a rotated secret takes effect without anyone
pressing Authenticate, and a plugin with its settings filled in logs itself in on
first use.

````bash
# **Keeping the stored login in step with the configured secret.**
#
# `az` keeps its own credential store inside the config dir, so once logged in it
# answers from that and never consults this plugin's settings again. Measured: with
# a deliberately wrong secret stored in the admin app, the probe still reported
# *signed in* — truthfully, because az's stored login did still work. The failure
# that hides behind it is the bad one: an administrator rotates the secret, does not
# press Authenticate, the old secret is later revoked, and the plugin breaks while
# the correct credential sits in the store unused.
#
# So the secret's **fingerprint** is recorded at login and compared before every
# command. A SHA-256 of a high-entropy secret is not a secret — it cannot be
# reversed and it is not a credential for anything — so it is safe to keep beside
# the config. Cost when nothing changed: one hash. When it has changed: one login,
# which is exactly when a login is wanted.
az_fingerprint() {
  printf '%s' "${AZ_CLIENT_SECRET:-}" | sha256sum | cut -d' ' -f1
}

az_fingerprint_file() {
  printf '%s' "${PLUGIN_STATE_DIR:-$HOME}/.secret-fingerprint"
}

# Log in as the service principal. The secret reaches az through a file (see
# az_secret_file), never argv.
az_login() {
  local secret_file rc
  secret_file=$(az_secret_file) || return 1
  az login --service-principal \
    --username "$AZ_CLIENT_ID" \
    --password "@$secret_file" \
    --tenant "$AZ_TENANT_ID" \
    --only-show-errors -o none
  rc=$?
  rm -f "$secret_file"
  [ "$rc" -eq 0 ] || return "$rc"
  az_fingerprint > "$(az_fingerprint_file)" 2>/dev/null || true
  [ -n "${AZ_SUBSCRIPTION:-}" ] && az account set --subscription "$AZ_SUBSCRIPTION" --only-show-errors >/dev/null 2>&1
  return 0
}

# Make sure the stored login exists and was made with the secret that is configured
# *now*. Two cheap local checks, and a login only when one of them fails:
#
#   - **no stored login at all** (`az account show` reads local config, no network):
#     the config dir is empty, was wiped, or nobody ever pressed Authenticate. The
#     plugin logs itself in, which makes Authenticate a *verification* button rather
#     than a prerequisite — an admin who fills in the settings and runs a command
#     gets a working plugin.
#   - **the fingerprint differs**: the secret was rotated in the admin app. The new
#     one takes effect on the next command instead of waiting for someone to
#     remember to re-authenticate. This is the case that matters, because the old
#     credential usually keeps working for a while and then stops — and the moment
#     it stops, this recovers by itself.
#
# A failed login deliberately leaves the existing one alone (az does not clear it),
# so a wrong secret stored over a working login degrades to "still working, with the
# previous credential" rather than to a broken plugin.
az_ensure_login() {
  local recorded current
  current=$(az_fingerprint)
  recorded=$(cat "$(az_fingerprint_file)" 2>/dev/null || true)
  if [ "$recorded" = "$current" ] && az account show -o none >/dev/null 2>&1; then
    return 0
  fi
  az_login >/dev/null 2>&1
}
````
