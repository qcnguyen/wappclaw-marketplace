#!/usr/bin/env bash
# Run one command. It arrives in PLUGIN_COMMAND (and as JSON on stdin) and is
# executed as written — the guideline documents the real hyperframes CLI, so
# what the agent sends is what runs. This script only adds the tools on PATH
# and the plugin's own HOME (Chrome, HeyGen sign-in; see lib.sh).
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
require_hyperframes || exit 1

command_text="${PLUGIN_COMMAND:-}"
if [ -z "$command_text" ]; then
  echo "No command given. See GUIDELINE.md for the hyperframes command vocabulary." >&2
  exit 2
fi

# The HeyGen sign-in belongs to an administrator (Authenticate in the admin app):
# a command that logs in or out would swap or drop that account for everyone,
# and `login` would wait on a browser nobody is watching. Skills are the
# plugin's own (reference/), and installing them would only fill this HOME.
case "$command_text" in
  *"hyperframes auth login"* | *"hyperframes auth logout"*)
    echo "Signing in and out of HeyGen is done by an administrator (Plugins -> hyperframes -> Authenticate)," >&2
    echo "not through commands. 'hyperframes auth status' shows who is signed in." >&2
    exit 2
    ;;
  *"hyperframes skills"* | *"skills add heygen-com/hyperframes"*)
    echo "The HyperFrames skills matching the installed CLI are already in \$HYPERFRAMES_SKILLS_DIR; read them there." >&2
    echo "The CLI version is set by the plugin's 'CLI version' setting and changed with Reinstall." >&2
    exit 2
    ;;
esac

# Default shell semantics for the agent's command: `pipefail` would turn a normal
# `... | head` (SIGPIPE, exit 141) into a failure, and `-u` would trip on its own
# unset variables.
set +u +o pipefail
eval "$command_text"
