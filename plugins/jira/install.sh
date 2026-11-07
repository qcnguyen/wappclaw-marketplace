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
