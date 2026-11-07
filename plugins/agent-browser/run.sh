#!/usr/bin/env bash
# Run one command. It arrives in PLUGIN_COMMAND (and as JSON on stdin) and is
# executed as written — the guideline documents the real agent-browser CLI, so
# what the agent sends is what runs. This script only adds the binary on PATH,
# the plugin's own HOME and socket namespace, and the sandbox decision (lib.sh).
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
require_agent_browser || exit 1

command_text="${PLUGIN_COMMAND:-}"
if [ -z "$command_text" ]; then
  echo "No command given. See GUIDELINE.md for the agent-browser command vocabulary." >&2
  exit 2
fi

# The plugin owns which CLI and Chrome are installed (the 'CLI version' setting
# and Reinstall). `upgrade` would replace the binary behind the plugin's back,
# and `install --with-deps` calls plain sudo, which waits on a password nobody
# will type.
case "$command_text" in
  *"agent-browser upgrade"* | *"agent-browser install"*)
    echo "agent-browser and its Chrome are installed and upgraded by an administrator" >&2
    echo "(Plugins -> agent-browser -> Reinstall; the 'CLI version' setting picks the version)." >&2
    echo "'agent-browser doctor' reports what is wrong with the current install." >&2
    exit 2
    ;;
esac

# Default shell semantics for the agent's command: `pipefail` would turn a normal
# `... | head` (SIGPIPE, exit 141) into a failure, and `-u` would trip on its own
# unset variables.
set +u +o pipefail
eval "$command_text"
