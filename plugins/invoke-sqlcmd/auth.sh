#!/usr/bin/env bash
# Verify the stored credential and, if a default server is set, prove it can log
# in to SQL. Nothing interactive: every mode here is non-interactive by design, so
# this is a one-shot check a human watches. Never prints a token or a password.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
sql_require_pwsh || exit 1
sql_pwsh auth.ps1
