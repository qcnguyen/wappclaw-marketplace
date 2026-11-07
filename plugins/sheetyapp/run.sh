#!/usr/bin/env bash
# Run one shp command. It arrives in PLUGIN_COMMAND (and as JSON on stdin) and is
# executed as written — the guideline documents the real shp CLI, so what the
# agent sends is what runs. This script only adds the binary on PATH and the
# plugin's signed-in account (via the platform's private HOME, see lib.sh).
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
require_shp || exit 1

command_text="${PLUGIN_COMMAND:-}"
if [ -z "$command_text" ]; then
  echo "No command given. See GUIDELINE.md for the shp command vocabulary." >&2
  exit 2
fi

# The sign-in belongs to an administrator (Authenticate in the admin app). A
# command that logs the plugin in or out would swap or drop that account for
# everyone using it, and `login` would block on a browser nobody is watching.
case "$command_text" in
  *"shp auth login"* | *"shp auth logout"*)
    echo "Signing in and out is done by an administrator (Plugins -> sheetyapp -> Authenticate)," >&2
    echo "not through commands. 'shp auth status' shows who is signed in." >&2
    exit 2
    ;;
esac

# Default shell semantics for the agent's command: `pipefail` would turn a normal
# `... | head` (SIGPIPE, exit 141) into a failure, and `-u` would trip on its own
# unset variables.
set +u +o pipefail
eval "$command_text"
