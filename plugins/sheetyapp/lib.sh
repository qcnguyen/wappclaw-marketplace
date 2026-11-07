# Shared preamble for the sheetyapp scripts. Sourced, never executed.
#
# install.sh downloads shp into state/bin and records that directory (plus any
# runtime switches the binary needs on this machine) in state/env.sh, so every
# script runs the binary the install actually produced.
if [ -n "${PLUGIN_STATE_DIR:-}" ] && [ -f "$PLUGIN_STATE_DIR/env.sh" ]; then
  # shellcheck disable=SC1091
  . "$PLUGIN_STATE_DIR/env.sh"
fi

# **The sign-in is this plugin's own.** shp keeps its login and config in
# `~/.shp/` (credentials.json, config.json), resolved from $HOME — and the
# platform points HOME at state/home/ for every script. So signing this plugin in
# does not sign in any other `shp` on the machine, and a `shp` run from the plain
# shell sees a signed-out CLI. Everything that needs this account goes through
# the plugin.
#
# Sourced by auth.sh, auth-status.sh and run.sh, which must agree on that home: a
# login written under one and read under another can never be signed in.

SHP_CONFIG_FILE="$HOME/.shp/config.json"

require_shp() {
  command -v shp >/dev/null 2>&1 && return 0
  echo "The shp CLI is not available. Install the plugin from the admin app first." >&2
  return 1
}

# The API URL stored by the last sign-in (`shp auth login --api-url` writes it to
# config.json), without jq: find the "apiUrl" line and take the quoted value.
stored_api_url() {
  [ -f "$SHP_CONFIG_FILE" ] || return 0
  sed -n 's/.*"apiUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SHP_CONFIG_FILE" | head -1
}

# URLs compared without a trailing slash, so "https://x/" and "https://x" agree.
same_url() {
  [ "${1%/}" = "${2%/}" ]
}
