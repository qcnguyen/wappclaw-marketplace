# Shared preamble for every script in this plugin. Sourced, never executed.

if [ -n "${PLUGIN_STATE_DIR:-}" ] && [ -f "$PLUGIN_STATE_DIR/env.sh" ]; then
  # shellcheck disable=SC1091
  . "$PLUGIN_STATE_DIR/env.sh"
fi

# **This plugin's Azure login is its own twice over: the platform's private `HOME`,
# plus `az`'s own `AZURE_CONFIG_DIR` pinned explicitly below.**
#
# It is set explicitly rather than left to follow a redirected `HOME`, for two
# reasons. It is what `az` documents, so it holds whatever `az` decides to keep
# where; and an `AZURE_CONFIG_DIR` inherited from the server's own environment
# would otherwise win and quietly put this plugin's credentials in a shared
# directory. HOME is redirected too, so anything else resolving `~` lands inside
# the plugin as well.
#
# Verified: with a private config dir, `az account show` reports "Please run 'az
# login'" while the machine-wide login is untouched — this box is signed in
# machine-wide as a service principal, and this plugin does not disturb it.
#
# **Extensions are per config dir, which is the part that surprises people.** They
# live in `$AZURE_CONFIG_DIR/cliextensions`, so an isolated config dir starts with
# *no* extensions however many the machine has — measured: the machine had
# azure-devops, the isolated dir listed none. That is why install.sh installs the
# extension into this directory, and why it is the one install script here that
# does source this file.
export AZURE_CONFIG_DIR="${PLUGIN_HOME:-$HOME}/.azure"
mkdir -p "$AZURE_CONFIG_DIR" 2>/dev/null || true

# Nothing is watching a command the agent runs, so a prompt would hang it until
# the timeout. `az` asks things — "select a subscription", "install extension?" —
# unless told not to.
export AZURE_CORE_ONLY_SHOW_ERRORS=true
export AZURE_CORE_NO_COLOR=true
export AZURE_CORE_DISABLE_PROGRESS_BAR=true
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no_prompt
export AZURE_CORE_COLLECT_TELEMETRY=false

require_az() {
  command -v az >/dev/null 2>&1 && return 0
  echo "The Azure CLI (az) is not available. Install the plugin from the admin app first." >&2
  return 1
}

az_check_config() {
  local missing=""
  [ -n "${AZ_CLIENT_ID:-}" ]     || missing="$missing  - Service principal client ID (AZ_CLIENT_ID)\n"
  [ -n "${AZ_TENANT_ID:-}" ]     || missing="$missing  - Entra tenant ID (AZ_TENANT_ID)\n"
  [ -n "${AZ_CLIENT_SECRET:-}" ] || missing="$missing  - Service principal secret (AZ_CLIENT_SECRET)\n"
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

# Hand the secret to `az login` **through a file**, using az's own `@file`
# convention for loading a parameter value.
#
# `az login --password "$SECRET"` is what every example shows and it puts the
# secret in **argv**, which `/proc/<pid>/cmdline` publishes to every account on the
# box. az accepts `--password "@/path/to/file"` instead, which is the same idea as
# the stdin the Jira and Azure DevOps plugins use — the secret travels somewhere
# only this process can read.
#
# The file goes in `/dev/shm` when there is one: tmpfs, so it never reaches
# persistent storage, and it is removed the moment the login returns. `state/` is
# the fallback.
az_secret_file() {
  local dir file
  if [ -d /dev/shm ] && [ -w /dev/shm ]; then dir=/dev/shm; else dir="${PLUGIN_STATE_DIR:-$HOME}"; fi
  file="$dir/.az-sp-$$"
  ( umask 077; printf '%s' "$AZ_CLIENT_SECRET" > "$file" ) || return 1
  printf '%s' "$file"
}

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

# **Is this login usable?** `az account get-access-token`, not `az account show`.
#
# `show` reads the local config and answers from it — a service principal whose
# secret was revoked yesterday still has an account on disk, so `show` exits 0 and
# a probe built on it stays green through the outage. `get-access-token` has to ask
# Entra for a token, so it fails when the credential has stopped working. Verified
# both exit 1 when nothing is logged in and 0 when something is.
#
# Its output is **discarded deliberately**: it prints a live access token.
az_usable() {
  az account get-access-token -o none >/dev/null 2>&1
}
