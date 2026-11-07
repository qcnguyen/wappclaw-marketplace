# Shared preamble for the agent-browser scripts. Sourced, never executed.
#
# install.sh unpacks the npm package into state/agent-browser and links the
# platform's native binary into state/bin, recorded in state/env.sh. The binary
# finds its skills (`agent-browser skills ...`) next to itself in that package.
if [ -n "${PLUGIN_STATE_DIR:-}" ] && [ -f "$PLUGIN_STATE_DIR/env.sh" ]; then
  # shellcheck disable=SC1091
  . "$PLUGIN_STATE_DIR/env.sh"
fi

# **Everything the CLI keeps is the plugin's own.** Chrome
# (~/.agent-browser/browsers), the auth vault, its encryption key and saved
# session state all resolve from $HOME, which the platform points at
# state/home/ for every script.
#
# The daemon's sockets do not: they live under $XDG_RUNTIME_DIR/agent-browser,
# shared by every agent-browser the server user runs. A namespace gives the
# plugin its own, so its sessions (including "default") never collide with a
# plain-shell agent-browser's.
export AGENT_BROWSER_NAMESPACE="${AGENT_BROWSER_NAMESPACE:-${PLUGIN_NAME:-agent-browser}}"

# Chrome's sandbox: install.sh records whether this host can provide it (see
# CHROME_SANDBOX in plugin.json). An explicit AGENT_BROWSER_ARGS wins.
no_sandbox=0
case "${CHROME_SANDBOX:-auto}" in
  off) no_sandbox=1 ;;
  auto) [ -n "${PLUGIN_STATE_DIR:-}" ] && [ -f "$PLUGIN_STATE_DIR/no-sandbox" ] && no_sandbox=1 ;;
esac
if [ "$no_sandbox" -eq 1 ] && [ -z "${AGENT_BROWSER_ARGS:-}" ]; then
  export AGENT_BROWSER_ARGS="--no-sandbox"
fi
unset no_sandbox

# An empty allowlist is "no restriction", not "nothing allowed".
[ -n "${AGENT_BROWSER_ALLOWED_DOMAINS:-}" ] || unset AGENT_BROWSER_ALLOWED_DOMAINS
[ "${PAGE_CONTENT_BOUNDARIES:-on}" = "on" ] && export AGENT_BROWSER_CONTENT_BOUNDARIES=1

require_agent_browser() {
  command -v agent-browser >/dev/null 2>&1 && return 0
  echo "The agent-browser CLI is not available. Install the plugin from the admin app first." >&2
  return 1
}
