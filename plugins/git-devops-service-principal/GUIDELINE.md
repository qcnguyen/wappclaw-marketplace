# Azure DevOps git, as a service principal

This plugin is a **credential handler for Azure DevOps, and nothing else**. It runs
ordinary `git` commands with an Azure DevOps access token already in place, so
anything you would type at a terminal works unchanged:

```bash
git clone https://dev.azure.com/<org>/<project>/_git/<repo>
git fetch origin
git push origin my-branch
```

There is **no plugin-specific command, flag or syntax to learn**. If you know how
to do it with git, that is the command to send. Nothing is rewritten on the way
through.

Send git through this plugin whenever the repository is in Azure DevOps. The same
command in a plain shell has no credential and will fail — or hang waiting for a
username — because the credential exists only inside this plugin.

**Whose account this is.** A service principal, not a person. It sees only what it
has been granted, and a project or repository it lacks access to is *absent*
rather than forbidden — so "not found" often means "not permitted for this
principal", which you cannot fix. An administrator grants access in the Azure
DevOps organisation settings.

## Repository URLs

An organisation has a modern host and a legacy one, and **both work**, for the same
repositories:

```
https://dev.azure.com/<org>/<project>/_git/<repo>
https://<org>.visualstudio.com/<project>/_git/<repo>
```

Repositories cloned years ago still carry the legacy URL in their config, so you
will see both. Don't rewrite one into the other — there is no need, and a remote
URL you change is a change to the user's repository.

**A project name with a space is percent-encoded in a git URL**:
`https://dev.azure.com/<org>/My%20Project/_git/<repo>`. This is the commonest
reason a hand-built URL 404s.

**This plugin cannot list what repositories exist** — that is not a git question,
and nothing here answers it. Get the URL from one of:

- what the user told you;
- an existing checkout: `git -C <path> remote -v`, or the workspace's
  `repositories/manifest.yaml`, which records the URL of everything checked out;
- the Azure DevOps web UI, if a human is available to look.

Then confirm it before committing to a long clone — this costs a second and tells
you whether both the URL and the permissions are right:

```bash
git ls-remote --heads https://dev.azure.com/<org>/<project>/_git/<repo>
```

## Cloning

```bash
git clone https://dev.azure.com/<org>/<project>/_git/<repo>
git clone --branch develop --single-branch https://dev.azure.com/<org>/<project>/_git/<repo>
```

**Where files land is yours to decide, and you must decide it.** This plugin has
no default checkout location. Give an absolute path — the folder your task or
conversation has been told to write in:

```bash
cd /abs/path/to/work && git clone https://dev.azure.com/<org>/<project>/_git/<repo>
git -C /abs/path/to/repo fetch origin        # or address the repo directly
```

`git -C /abs/path <subcommand>` does the same thing for a command that acts on an
existing clone, and is the tidier form when you are not creating one.

A command that writes to a *relative* path, without a working directory having been
set, runs in a throwaway directory instead — and the output tells you where its
files ended up. Nothing is deleted, but nothing else will look there either, so
treat that message as a mistake to correct rather than a location to keep using.

**These repositories are large.** A full clone of a long-lived product repository
can exceed the command timeout (15 minutes). Prefer, in order:

```bash
# You need the current files only — by far the cheapest
git clone --depth 1 --single-branch https://dev.azure.com/<org>/<project>/_git/<repo>

# You need history, but not every historical version of every file
git clone --filter=blob:none https://dev.azure.com/<org>/<project>/_git/<repo>

# You only want to know what refs exist — no clone at all
git ls-remote --heads https://dev.azure.com/<org>/<project>/_git/<repo>
```

In a shallow clone `git log` stops at the depth you asked for, and `git diff`
against an older ref and `git merge-base` can both fail for want of history.
Deepen when you actually need it: `git fetch --deepen 50`, or
`git fetch --unshallow`.

## Working in a clone

Ordinary git, with nothing special about it:

```bash
cd /abs/path/to/repo && git fetch origin
cd /abs/path/to/repo && git checkout -b feature/x origin/develop
cd /abs/path/to/repo && git log --oneline -20
cd /abs/path/to/repo && git diff origin/develop...HEAD --stat
cd /abs/path/to/repo && git grep -n "ConnectionString" -- '*.cs'
cd /abs/path/to/repo && git show <sha> --stat
cd /abs/path/to/repo && git log -1 --format='%H %an %ad %s' -- path/to/file
```

Clone once and search locally with `git grep` / `git log`; that is far faster than
fetching files one at a time.

## Committing and pushing

```bash
cd /abs/path/to/repo && git add -A && git commit -m "Fix the thing"
cd /abs/path/to/repo && git push origin feature/x
```

Two things here are not like a personal account:

- **The author and the push are separate.** The commit is authored as the identity
  configured for this plugin (or, failing that, the server's own git identity);
  the push is authorised as the service principal. Both must be in place, and
  neither implies the other. **Don't set `user.name`/`user.email` yourself** — an
  administrator configures them for the plugin, and a value you set would either be
  overridden or would write into the user's repository. A commit failing with
  *"Author identity unknown"* or *"unable to auto-detect email address"* means the
  plugin has no commit identity configured: say so and stop, because setting one is
  an administrator's job, not yours.
- **Pushing needs `Contribute`, which read access does not include.** A push
  rejected with `TF401027` or `403` is a permission somebody has to grant, not
  something to retry or work around.

**Branch policies routinely forbid pushing to `main`/`master` directly.** Push a
branch instead and tell the user it needs a pull request; opening one is not
something this plugin does.

## Rules

- **Never put a credential in a URL.** No `https://user:token@dev.azure.com/...`,
  and never `git remote set-url` with a token in it. The credential is already
  applied to every request; a URL carrying one is both redundant and a secret
  written into `.git/config`, where it stays on disk and travels with the clone.
- **Don't add `-c http.extraHeader` or a credential helper of your own**, and
  don't print the environment or git's full config — the token is in there, and
  this plugin's output is shown to a user and kept in a transcript.
- **Don't `git config --global` anything.** That is the machine's configuration,
  shared with everything else running on it.
- **`--help` is authoritative.** `git help clone`, `git push --help`. The installed
  git's own help always matches the installed git; a table in a document
  eventually does not.

## Traps

| | |
|---|---|
| **Percent-encoding** | A project or repo name containing a space must be `%20` in the URL. |
| **Both hosts are live** | `dev.azure.com/<org>` and `<org>.visualstudio.com` serve the same repositories; existing clones may use either. |
| **Git LFS** | A repository storing binaries in LFS clones its pointer files first; contents need `git lfs pull` and a `git-lfs` binary. Small text files reading `version https://git-lfs...` are pointers, not the real thing. |
| **Shallow clones** | `git log`, `git diff` against an older ref and `git merge-base` all behave differently in one. Deepen before concluding history is missing. |
| **Missing branches** | After `--single-branch`, other branches are not present. `git fetch origin <branch>` first, then check it out. |

## What a failure means

- **`fatal: Authentication failed` / `403` on every repository** — the credential
  itself. Most often the service principal's client secret has **expired**;
  secrets are time-limited and this is the commonest outage. A human
  re-authenticates the plugin from the admin app. Report it and stop.
- **`repository not found` / `404` on one repository** — no access to that
  project, or a wrong URL (check the percent-encoding). Confirm with
  `git ls-remote` against the URL you believe is right.
- **`TF401019`** — the repository is disabled, or does not exist under that name.
- **`TF401027` / `403` on push only** — read access without `Contribute`.
- **A rejection mentioning a policy** — branch policy. Push a branch and say a
  pull request is needed.
- **A hang** — shouldn't happen; prompts are disabled so git fails with a message
  instead. A command that times out is a genuinely large transfer: retry shallow.

In every credential case above: **you cannot fix it.** Say plainly what failed and
what an administrator needs to do.
