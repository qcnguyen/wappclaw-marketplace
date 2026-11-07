# Shared preamble for every script in this plugin. Sourced, never executed.
#
# What this plugin actually does is small: it turns a service principal's client
# id + secret into a short-lived Azure DevOps **access token**, and puts that
# token where git will use it. Everything else here is about doing that without
# the token or the secret ever reaching a place someone else can read.

# The Azure DevOps resource (application) id. A fixed, public, well-known GUID —
# the same in every tenant — so a token minted for `<id>/.default` is a token for
# Azure DevOps. Do not put a tenant-specific value here.
AZDO_RESOURCE_ID='499b84ac-1321-427f-aa17-267ca6975798'

# The install records nothing PATH-critical today (git and curl come from the
# system), but the pattern is kept: if this plugin ever provisions a binary, the
# install writes its bin directory here and every script picks it up for free.
if [ -n "${PLUGIN_STATE_DIR:-}" ] && [ -f "$PLUGIN_STATE_DIR/env.sh" ]; then
  # shellcheck disable=SC1091
  . "$PLUGIN_STATE_DIR/env.sh"
fi

# **`HOME` is the plugin's own, forced by the platform**, so `~/.gitconfig` is not
# read. One thing in it was load-bearing and one class of thing was not, and the
# split is deliberate:
#
#   - **The commit identity is critical** — without `user.name`/`user.email` a
#     commit fails outright with "Author identity unknown". So it is a **plugin
#     setting** (`AZDO_COMMIT_NAME` / `AZDO_COMMIT_EMAIL`), injected below. That is
#     the right home for it: it is a decision about *who this plugin commits as*,
#     which is a property of the plugin, not of whoever happens to own the box.
#   - **Everything else in a global git config is tuning** — `http.postBuffer`,
#     `core.excludesFile`, `core.checkstat` — and this plugin deliberately does not
#     reproduce it. An earlier version pulled the whole machine config in with
#     `include.path` to recover the identity, which worked and was the wrong shape:
#     it dragged in a dozen unrelated settings, plus the machine's credential
#     helper, to solve something two settings already answer.
#
# `safe.directory` is the one worth knowing about: it is not reproduced either, so
# a checkout owned by a *different* user than the server process will be refused
# with git's own "dubious ownership" message. That message says exactly what to do,
# and on a box where the plugin clones its own working copies it cannot arise.

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Every setting/secret arrives in the environment under the key the manifest
# declared. Report *all* that are missing at once, naming the admin field, rather
# than failing on the first one and making the admin do this three times.
azdo_check_config() {
  local missing=""
  [ -n "${AZDO_CLIENT_ID:-}" ]     || missing="$missing  - Service principal client ID (AZDO_CLIENT_ID)\n"
  [ -n "${AZDO_TENANT_ID:-}" ]     || missing="$missing  - Entra tenant ID (AZDO_TENANT_ID)\n"
  [ -n "${AZDO_CLIENT_SECRET:-}" ] || missing="$missing  - Service principal secret (AZDO_CLIENT_SECRET)\n"
  [ -z "$missing" ] && return 0
  {
    echo "This plugin is not configured yet. Missing:"
    printf "$missing"
    echo
    echo "Set them in the admin app: Plugins -> $PLUGIN_NAME -> Settings."
    echo "The client ID and tenant ID are readable settings; the secret is write-only."
  } >&2
  return 1
}

# The organisation setting accepts a bare name or either URL style. Sets:
#   AZDO_ORG_NAME  the organisation's short name
#   AZDO_ORG_BASE  the base URL its REST API is reached at
azdo_resolve_org() {
  local raw="${AZDO_ORGANIZATION:-}"
  raw="${raw%/}"
  case "$raw" in
    '')
      AZDO_ORG_NAME=''
      AZDO_ORG_BASE=''
      return 1
      ;;
    https://dev.azure.com/*|http://dev.azure.com/*)
      AZDO_ORG_NAME="${raw##*/}"
      AZDO_ORG_BASE="https://dev.azure.com/$AZDO_ORG_NAME"
      ;;
    https://*.visualstudio.com|http://*.visualstudio.com)
      # Legacy host. Keep it as the base: it is what this organisation's own
      # remotes use, and both hosts serve the same API.
      local host="${raw#*://}"
      AZDO_ORG_NAME="${host%%.*}"
      AZDO_ORG_BASE="https://$host"
      ;;
    *://*)
      AZDO_ORG_NAME="${raw##*/}"
      AZDO_ORG_BASE="$raw"
      ;;
    *)
      AZDO_ORG_NAME="$raw"
      AZDO_ORG_BASE="https://dev.azure.com/$raw"
      ;;
  esac
  return 0
}

# **Where a command runs is not this plugin's business at all.**
#
# The platform decides: the directory the caller named through `run-plugin`'s
# `cwd`, or a throwaway one it owns when the caller named none — and it reports
# the path afterwards if the command left files there. `PLUGIN_CWD` says which
# directory that was, for a script that wants to know, but nothing here needs to.
#
# This plugin used to own the problem, and briefly owned it twice over: a
# `Default working directory` **setting** (a plugin deciding filesystem policy it
# has no basis for) and then a scratch directory of its own. Both are gone. Where
# output belongs is the caller's knowledge — a conversation's `tmp/`, a task run's
# folders — and the rule a plugin could get wrong, never writing into its own
# bundle (which the API lists and the file route serves), is now guaranteed by the
# platform instead of remembered by each author.

# ---------------------------------------------------------------------------
# The token
# ---------------------------------------------------------------------------

# One field out of a JSON object. jq when it is there (it is, on any box with a
# working install), a good-enough extractor when it is not — a missing jq must
# degrade the output, never break the sign-in.
azdo_json_field() {
  local json="$1" field="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null
    return 0
  fi
  printf '%s' "$json" \
    | tr ',' '\n' \
    | sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
    | head -1
}

# Mint an Azure DevOps access token via the client-credentials flow.
# The token goes to **stdout**; everything a human should read goes to stderr, so
# a caller can do `tok=$(azdo_token)` without the diagnostics polluting it.
#
# The secret is fed to curl on **stdin** (`--data-urlencode 'client_secret@-'`,
# which URL-encodes what it reads — client secrets routinely contain `~`, `+`,
# `/` and `=`). It must never be an argument: `/proc/<pid>/cmdline` is
# world-readable, so a secret on a command line is a secret published to every
# account on the box. `/proc/<pid>/environ` is not, which is why the environment
# is the channel this whole plugin system uses.
azdo_token() {
  local timeout="${1:-25}" resp code

  resp=$(printf '%s' "$AZDO_CLIENT_SECRET" | curl -sS --max-time "$timeout" \
    -X POST "https://login.microsoftonline.com/$AZDO_TENANT_ID/oauth2/v2.0/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=client_credentials' \
    --data-urlencode "client_id=$AZDO_CLIENT_ID" \
    --data-urlencode "scope=$AZDO_RESOURCE_ID/.default" \
    --data-urlencode 'client_secret@-' 2>&1)
  code=$?

  if [ "$code" -ne 0 ]; then
    echo "Could not reach login.microsoftonline.com (curl exit $code)." >&2
    echo "$resp" >&2
    return 1
  fi

  local token
  token=$(azdo_json_field "$resp" access_token)
  if [ -n "$token" ]; then
    printf '%s' "$token"
    return 0
  fi

  azdo_explain_token_error "$resp" >&2
  return 1
}

# Turn Entra's refusal into the thing to go and fix. `invalid_client` alone sends
# the reader nowhere; the AADSTS code in the description is the whole diagnosis,
# so it is quoted verbatim and then translated.
azdo_explain_token_error() {
  local resp="$1" err desc
  err=$(azdo_json_field "$resp" error)
  desc=$(azdo_json_field "$resp" error_description)

  echo "Azure AD refused the service principal sign-in."
  [ -n "$err" ] && echo "  error: $err"
  if [ -n "$desc" ]; then
    echo "  detail: $(printf '%s' "$desc" | head -1)"
  else
    echo "  raw response: $(printf '%s' "$resp" | head -c 400)"
  fi
  echo
  echo "What the codes mean:"
  case "$desc$resp" in
    *AADSTS7000215*)
      echo "  AADSTS7000215 - the client secret is wrong. Re-enter it in the admin app"
      echo "      (Plugins -> $PLUGIN_NAME -> Settings -> Service principal secret). Note that"
      echo "      Azure shows a secret's *Value* once and its *Secret ID* for ever; the"
      echo "      Value is what belongs here, and it is the commoner mix-up." ;;
    *AADSTS7000222*)
      echo "  AADSTS7000222 - the client secret has EXPIRED. Create a new one in Azure"
      echo "      (App registration -> Certificates & secrets) and store that." ;;
    *AADSTS700016*|*unauthorized_client*)
      echo "  AADSTS700016 - no application with this client ID exists in this tenant."
      echo "      Check the client ID and the tenant ID are from the same directory." ;;
    *AADSTS90002*|*AADSTS900023*)
      echo "  AADSTS90002 / 900023 - that tenant does not exist. The Entra tenant ID must be"
      echo "      the directory GUID; 'common' and 'organizations' cannot be used for a"
      echo "      client-credentials sign-in." ;;
    *AADSTS500011*|*AADSTS650057*)
      echo "  AADSTS500011 / 650057 - the resource is not available to this app. The service"
      echo "      principal exists but is not permitted the Azure DevOps API." ;;
    *)
      echo "  (No code recognised above. Search the AADSTS number in the detail line —"
      echo "   Microsoft documents each one, and the number is the precise cause.)" ;;
  esac
}

# ---------------------------------------------------------------------------
# Handing the token to git
# ---------------------------------------------------------------------------

# Put the token into git's configuration for this process and its children,
# through `GIT_CONFIG_COUNT`/`_KEY_n`/`_VALUE_n` (git >= 2.31).
#
# Why this and not `git -c http.extraHeader=...`: `-c` is an **argument**, so the
# token would be in `/proc/<pid>/cmdline` for every git process, readable by every
# account on the machine. The env form is inherited by git's own subprocesses
# (`git-remote-http` and friends) through `GIT_CONFIG_PARAMETERS`, an environment
# variable — verified on this box: with the token injected this way, no process's
# `cmdline` contains it and only their `environ` (owner-readable) does.
#
# Also why not a URL of the form `https://user:token@host/...`: that would be in
# argv, and worse, `git clone` writes the remote URL into the new repository's
# `.git/config` — a token persisted to disk in a folder somebody may share.
#
# The header is scoped **per host**, so a token for Azure DevOps is never sent to
# any other server the agent happens to fetch from.
azdo_export_git_env() {
  local token="$1" n=0
  azdo_resolve_org >/dev/null 2>&1 || true

  _azdo_git_cfg() {
    eval "export GIT_CONFIG_KEY_$n=\"\$1\""
    eval "export GIT_CONFIG_VALUE_$n=\"\$2\""
    n=$((n + 1))
  }

  # Both Azure DevOps host styles, always: an organisation migrated to
  # dev.azure.com keeps working `<org>.visualstudio.com` remotes for ever, and a
  # repository cloned years ago still carries the legacy URL in its config.
  _azdo_git_cfg 'http.https://dev.azure.com/.extraHeader' "Authorization: Bearer $token"
  if [ -n "${AZDO_ORG_NAME:-}" ]; then
    _azdo_git_cfg "http.https://$AZDO_ORG_NAME.visualstudio.com/.extraHeader" "Authorization: Bearer $token"
  else
    _azdo_git_cfg 'http.https://visualstudio.com/.extraHeader' "Authorization: Bearer $token"
  fi

  # **The commit identity, when this plugin has been given one.**
  #
  # Injected exactly like the credential, and isolated the same way: it is set on
  # the process, so nothing is written to `~/.gitconfig` and no other process on
  # the box is affected. Left unset, git falls through to the server user's own
  # identity, which is the previous behaviour and still the sensible default for a
  # single-purpose box.
  #
  # Two consequences of using config rather than `GIT_AUTHOR_*`/`GIT_COMMITTER_*`,
  # both wanted. It sets the **committer** as well as the author, which is what
  # anyone means by "commit as this identity". And `git config --get user.email`
  # reads back the value that commits will actually carry — with the env-var form
  # a check would report the machine's address while commits recorded a different
  # one, and a plugin whose self-report disagrees with its behaviour is worse than
  # one with no identity at all.
  #
  # Note this outranks a per-repository identity in that clone's own
  # `.git/config`: `GIT_CONFIG_*` has the same precedence as `-c`, which is the
  # highest there is. That is the intent of setting it on the plugin, but it is
  # the one surprising thing about it, so the setting's description says so.
  [ -n "${AZDO_COMMIT_NAME:-}" ]  && _azdo_git_cfg 'user.name'  "$AZDO_COMMIT_NAME"
  [ -n "${AZDO_COMMIT_EMAIL:-}" ] && _azdo_git_cfg 'user.email' "$AZDO_COMMIT_EMAIL"

  # Neutralise any credential helper reachable from here. It cannot help (the header
  # is already the credential) and it can hurt: a helper answering first with a
  # different account's token turns "signed in as the service principal" into a
  # silent 403. `credential.helper` is multi-valued and an empty entry resets the
  # list — verified behaviourally rather than from the documentation, with a helper
  # that announces itself: after an empty entry it does not run.
  _azdo_git_cfg 'credential.helper' ''

  export GIT_CONFIG_COUNT="$n"
  # Nothing is watching a command the agent runs, so a credential prompt would
  # hang it until the timeout instead of failing with a message.
  export GIT_TERMINAL_PROMPT=0
  export GIT_ASKPASS=/bin/true
  unset -f _azdo_git_cfg
}

# ---------------------------------------------------------------------------
# Checking the organisation (used by auth.sh and auth-status.sh ONLY)
# ---------------------------------------------------------------------------

# One authenticated GET against the organisation, for the two scripts that have
# to answer "will Azure DevOps actually accept this principal?".
#
# **Deliberately not exported to the agent's command.** This plugin is a
# credential handler: what it offers is ordinary `git`, already authenticated.
# There is no plugin-specific command to learn, and nothing here puts a token
# anywhere a command could read or print it.
#
# The token goes in through `-H @-` (stdin) rather than an argument, for the same
# reason the secret does: `/proc/<pid>/cmdline` is world-readable.
azdo_org_request() {
  local token="$1" path="$2"
  shift 2
  printf 'Authorization: Bearer %s\n' "$token" \
    | curl -sS -H @- "$@" "$AZDO_ORG_BASE$path"
}
