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
