# Azure and Azure DevOps, through the `az` CLI

This plugin runs `az` already signed in as a **service principal**, with the
**azure-devops** extension installed. Ordinary commands work as written:

```bash
az group list -o table
az repos list --project MyProject -o table
```

There is no plugin-specific syntax. If you know how to do it with `az`, that is
the command to send.

**Whose account this is.** A service principal, not a person — so there is no
interactive consent, no MFA, and **no roles except the ones it was granted**. Azure
returns an empty list rather than an error for resources it cannot see, so an empty
result may mean "no access" rather than "nothing there". Say which you think it is.

## Output: `-o table` for a person, `-o json` for you

```bash
az group list -o table                                   # to show someone
az group list --query "[].{name:name, location:location}" -o json   # to parse
az vm list --query "[?powerState=='VM running'].name" -o tsv        # one column
```

`--query` is **JMESPath**, applied server-side-ish by the CLI before output, and it
is the difference between reading a screenful and reading a megabyte. Prefer it over
piping everything through `jq`. `-o tsv` is right when you want a bare value to use
in the next command.

## Azure resources

| Task | Command |
|---|---|
| Subscriptions visible | `az account list -o table` |
| Current subscription | `az account show -o table` |
| Resource groups | `az group list -o table` |
| Everything in a group | `az resource list --resource-group RG -o table` |
| One resource | `az resource show --ids <id> -o json` |
| VMs | `az vm list -d -o table` |
| Web apps | `az webapp list -o table` |
| Storage accounts | `az storage account list -o table` |
| AKS clusters | `az aks list -o table` |
| Key vault secret *names* | `az keyvault secret list --vault-name V --query "[].name" -o tsv` |
| Activity log | `az monitor activity-log list --offset 1h -o table` |

## Azure DevOps

The extension authenticates with **this same service principal** — there is no PAT
to supply. If an organisation URL is configured for the plugin it is the default, so
`--organization` is only needed to reach a different one.

| Task | Command |
|---|---|
| Projects | `az devops project list -o table` |
| Repositories | `az repos list --project PROJ -o table` |
| One repository | `az repos show --repository REPO --project PROJ -o json` |
| Pull requests | `az repos pr list --project PROJ --status active -o table` |
| One PR | `az repos pr show --id 12345 -o json` |
| Create a PR | `az repos pr create --project PROJ --repository REPO --source-branch feature/x --target-branch develop --title "..."` |
| Branch policies | `az repos policy list --project PROJ --repository REPO -o table` |
| Pipelines | `az pipelines list --project PROJ -o table` |
| Pipeline runs | `az pipelines runs list --project PROJ --top 10 -o table` |
| One run | `az pipelines runs show --id 98765 --project PROJ -o json` |
| Run a pipeline | `az pipelines run --name "My Pipeline" --project PROJ --branch main` |
| A work item | `az boards work-item show --id 12345 -o json` |
| Query work items | `az boards query --wiql "SELECT [System.Id], [System.Title] FROM workitems WHERE [System.TeamProject] = 'PROJ' AND [System.State] = 'Active'" -o table` |
| Anything not covered | `az devops invoke --area git --resource repositories --route-parameters project=PROJ` |

`az devops invoke` is the escape hatch onto the raw REST API, for the endpoints the
extension has no command for. `az devops -h`, `az repos -h`, `az pipelines -h` and
`az boards -h` list what does exist, and **`--help` is authoritative** — it matches
the installed version, which a table in a document eventually will not.

## Rules

- **Never run `az account get-access-token`.** It prints a live access token — about
  2,000 characters of credential — straight into output that a person reads and a
  transcript keeps. There is no reason to: every `az` command already authenticates
  itself.
- **Never run `az login` or `az logout`.** The plugin owns the sign-in. Logging out
  breaks it for everyone until an administrator re-authenticates.
- **Never print a secret value.** `az keyvault secret show` returns the value;
  `--query "[].name"` on `list` is almost always what was actually wanted. If a
  value is genuinely needed for a subsequent command, pipe it — do not echo it.
- **Assume nothing is `--yes` by default.** A destructive command
  (`delete`, `purge`) prompts, and a prompt here hangs until the command times out.
  If a deletion was genuinely asked for, pass `--yes`; if it was not, don't run it.
- **`--query` before `jq`.** A resource list can be enormous; narrow it at the CLI.

## Traps

| | |
|---|---|
| **Empty list ≠ nothing there** | A service principal sees only what it has a role on, and Azure filters rather than refusing. Check with `az account show` which subscription you are even in. |
| **Subscription scope** | Every resource command runs against the *current* subscription. `az account list -o table` shows the others; pass `--subscription` rather than switching, which is process-wide. |
| **`az devops` needs the principal in the org** | Being in the tenant is not enough — it must be added to the Azure DevOps organisation as a user. That failure reads like an auth error but is a permissions grant a human must make. |
| **Two Azure DevOps hosts** | `dev.azure.com/<org>` and the legacy `<org>.visualstudio.com` are the same organisation. Use whichever the plugin is configured with. |
| **`--ids` vs name+group** | Most `show`/`delete` commands take either a full resource id or `--name` + `--resource-group`. Mixing halves of the two is the commonest 400. |
| **WIQL quoting** | `az boards query --wiql` takes one long SQL-ish string: double quotes outside, single quotes for values. |
| **Preview commands change** | Anything marked `[Preview]` in `--help` can change between versions. Prefer a stable command, or `az devops invoke`. |

## What a failure means

- **`AADSTS7000215` / `AADSTS7000222` / "failed to authenticate"** — the
  credential. Most often the service principal's client secret has **expired**;
  secrets are time-limited and this is the commonest outage. A human
  re-authenticates the plugin from the admin app. Report it and stop.
- **`AuthorizationFailed` / `403`** — authenticated but no role. Names the action
  and scope it wanted, which is exactly what an administrator needs to grant it.
  Not something to retry.
- **`ResourceNotFound` on something you believe exists** — wrong subscription, or
  no role on it. Check `az account show` first.
- **`ERROR: 'x' is misspelled or not recognized by the system`** — a command from a
  different `az` version, or an extension that is not installed. Check `--help`.
- **A hang** — a prompt. Something wants `--yes`, or is asking which subscription
  to use.
