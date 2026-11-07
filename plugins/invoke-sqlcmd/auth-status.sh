#!/usr/bin/env bash
# The probe behind `Plugin.authenticated`. Exit 0 means usable. Silent — only the
# exit code is read. See auth-status.ps1 for what "usable" means per mode.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
command -v pwsh >/dev/null 2>&1 || exit 1
sql_pwsh auth-status.ps1 >/dev/null 2>&1
