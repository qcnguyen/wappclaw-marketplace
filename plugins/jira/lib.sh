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
