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
