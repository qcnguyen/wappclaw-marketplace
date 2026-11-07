#!/usr/bin/env bash
# Run one Invoke-Sqlcmd command with the stored credential in place.
#
# **This plugin deliberately departs from "eval the command verbatim".** It runs
# exactly one thing — Invoke-Sqlcmd — and refuses anything else, so a command that
# does not start with `Invoke-Sqlcmd` is rejected here, before PowerShell starts.
# run.ps1 then checks again on the parsed syntax tree, which is what catches
# `Invoke-Sqlcmd ...; Remove-Item ...` and other ways to smuggle a second command
# past a prefix check.
#
# The command is never eval'd by bash: it reaches PowerShell through the
# environment (PLUGIN_COMMAND), unmodified, and is parsed there.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"

command_text="${PLUGIN_COMMAND:-}"

# Leading whitespace is forgiven; anything else before the cmdlet name is not.
trimmed="${command_text#"${command_text%%[![:space:]]*}"}"

if [ -z "$trimmed" ]; then
  echo "No command given. Commands must start with Invoke-Sqlcmd, e.g.:" >&2
  echo "  Invoke-Sqlcmd -Query 'SELECT @@VERSION'" >&2
  exit 2
fi

# Case-insensitive, like PowerShell itself, and the name must end there —
# `Invoke-SqlcmdFoo` is a different command.
shopt -s nocasematch
if ! [[ "$trimmed" =~ ^Invoke-Sqlcmd([[:space:]]|$) ]]; then
  shopt -u nocasematch
  {
    echo "Rejected: this plugin only runs commands that begin with 'Invoke-Sqlcmd'."
    echo "  got: $(printf '%s' "$trimmed" | head -1 | cut -c1-120)"
    echo
    echo "Write the command exactly as you would in PowerShell, starting with the cmdlet:"
    echo "  Invoke-Sqlcmd -ServerInstance myserver.database.windows.net -Database mydb -Query 'SELECT TOP 10 * FROM sys.tables'"
  } >&2
  exit 2
fi
shopt -u nocasematch

sql_require_pwsh || exit 1

# Default shell semantics for the child: see WRITING-A-PLUGIN.md on pipefail.
set +u +o pipefail
export PLUGIN_COMMAND="$command_text"
sql_pwsh run.ps1
