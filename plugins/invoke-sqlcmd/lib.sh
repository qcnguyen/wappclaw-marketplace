# Shared preamble for the bash entry points. Sourced, never executed.
#
# The platform only runs bash, and Invoke-Sqlcmd is a PowerShell cmdlet. So every
# script here is a thin bash shim that finds `pwsh` and hands over to a `.ps1`
# beside it, where the real work happens. The credential never passes through
# bash at all: it arrives in the environment and is read by PowerShell from there.

# install.sh records where pwsh and the SqlServer module live, plus any runtime
# switches pwsh needs on this box (e.g. invariant globalization without libicu).
if [ -n "${PLUGIN_STATE_DIR:-}" ] && [ -f "$PLUGIN_STATE_DIR/env.sh" ]; then
  # shellcheck disable=SC1091
  . "$PLUGIN_STATE_DIR/env.sh"
fi

# Keep pwsh quiet and fast: no telemetry, no update check banner in the output.
export POWERSHELL_TELEMETRY_OPTOUT=1
export POWERSHELL_UPDATECHECK=Off
export POWERSHELL_CLI_TELEMETRY_OPTOUT=1

sql_require_pwsh() {
  if ! command -v pwsh >/dev/null 2>&1; then
    echo "PowerShell (pwsh) is not installed for this plugin." >&2
    echo "An administrator needs to press Install (or Reinstall) on the '$PLUGIN_NAME' plugin." >&2
    return 1
  fi
}

# Run one of this plugin's .ps1 files. -NoProfile so nothing on the box changes
# behaviour; -NonInteractive so a prompt fails instead of hanging until timeout.
sql_pwsh() {
  local script="$1"
  shift
  pwsh -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass \
    -File "${PLUGIN_DIR:-$(dirname "$0")}/$script" "$@"
}
