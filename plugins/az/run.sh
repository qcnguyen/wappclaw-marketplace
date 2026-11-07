#!/usr/bin/env bash
# Run one az command. The command arrives in the environment (PLUGIN_COMMAND) and
# on stdin as JSON — never on this script's command line — and runs **as written**.
#
# What this adds is only environment: the CLI's config dir pointed at this
# plugin's own (so its login and its azure-devops extension are the ones used),
# and prompts disabled so nothing can hang waiting for an answer nobody can give.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
require_az || exit 1

command_text="${PLUGIN_COMMAND:-}"
if [ -z "$command_text" ]; then
  echo "No command given. See GUIDELINE.md for the az command vocabulary." >&2
  exit 2
fi

# Re-login if the configured secret has changed since the stored login was made —
# a hash comparison in the common case, a login only when it actually differs.
az_ensure_login || true

# **Drop every service principal secret before running anything.** The command
# needs the *stored login*, never the credential that created it — so a command
# that dumps its own environment leaks nothing. `AZURE_CLIENT_SECRET` is unset too:
# this box has one in its ambient environment, and a command run through this
# plugin has no business seeing it either.
unset AZ_CLIENT_SECRET AZURE_CLIENT_SECRET

# Run the command under default shell semantics, not this script's: `pipefail`
# would turn `… | head -5` into exit 141 (SIGPIPE) and report a command that did
# exactly what was asked as a failure.
set +u +o pipefail

# `eval` because a command is a command: a JMESPath query or a resource tag is
# full of spaces and quotes, and word-splitting would break every one of them.
eval "$command_text"
