#!/usr/bin/env bash
# The probe behind `Plugin.authenticated`. Exit 0 = signed in, to the configured
# environment, with a session the API still accepts. Silent: only the exit code
# is read.
#
# `shp auth status` is NOT the answer: it exits 0 whenever a credentials file
# exists — it reports a file on disk, not a session. A revoked or expired refresh
# token still says "logged in". So this makes the cheapest real call instead:
# `shp workbook list` goes to the API, refreshes the token if it has to, and exits
# non-zero when the session is gone ("Session expired") or the API refuses it.
#
# And the session has to be for the environment in the settings. The API URL is
# stored by the sign-in; if the setting has since changed, nobody has signed in to
# the environment now configured, so that reads as signed out too.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
command -v shp >/dev/null 2>&1 || exit 1

want="${SHEETYAPP_API_URL:-https://api.sheetyapp.com}"
have="$(stored_api_url)"
[ -n "$have" ] && ! same_url "$have" "$want" && exit 1

shp workbook list --json >/dev/null 2>&1
