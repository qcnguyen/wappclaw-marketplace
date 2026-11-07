#!/usr/bin/env bash
# Run one m365 command. The command arrives in the environment (PLUGIN_COMMAND)
# and on stdin as JSON — never on this script's command line, so nothing a
# caller sends is visible in `ps`.
#
# It is executed **as written**. That is the contract the guideline is built on:
# what the agent sends is what runs, so the guideline can document the real CLI
# rather than a translation nobody can debug through. All this script adds is
# what the plugin exists for — the binary on PATH, and the account signed in.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
require_m365 || exit 1

# Nothing is watching a command run by the agent, so a CLI prompt would hang it
# until the timeout. Fail on a missing required option instead.
export CLIMICROSOFT365_PROMPT=false

command_text="${PLUGIN_COMMAND:-}"
if [ -z "$command_text" ]; then
  echo "No command given. See GUIDELINE.md for the m365 command vocabulary." >&2
  exit 2
fi

# `eval` because a command is a command: SharePoint paths contain spaces
# constantly, and word-splitting them would break every one of them.
eval "$command_text"
