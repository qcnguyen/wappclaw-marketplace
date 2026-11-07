#!/usr/bin/env bash
# Sign this plugin in to SheetyApp with the device-code flow. Runs under a pty:
# `shp auth login` prints the URL (with the code already in it) immediately and
# then polls until a person approves it in a browser.
#
# The API/IdP URLs come from the plugin's settings and are passed on every login,
# because `shp auth login` is what writes them into shp's config — that is how a
# changed setting takes effect, and auth-status.sh treats a mismatch as signed out.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
require_shp || exit 1

api_url="${SHEETYAPP_API_URL:-https://api.sheetyapp.com}"
idp_url="${SHEETYAPP_IDP_URL:-https://idp.sheetyapp.com}"
web_url="${SHEETYAPP_WEB_URL:-https://go.sheetyapp.com}"

echo "Signing in to SheetyApp."
echo "API:               $api_url"
echo "Identity provider: $idp_url"
echo
echo "Open the URL below and sign in with the SheetyApp account this server should act as."
echo

# One login at a time: drop whatever an earlier sign-in left behind, so a stale
# refresh token can't be mistaken for the new account.
shp auth logout >/dev/null 2>&1 || true

# Piped on purpose. On a terminal, shp animates a "Waiting for authorization..."
# spinner by redrawing one line ~10 times a second; the admin page's stream can't
# redraw in place, so every frame arrives as a new line, forever, until sign-in.
# Through a pipe shp sees no terminal and prints that line once. The URL and code
# are printed (and flushed) before the wait, so they still appear immediately.
shp auth login --api-url "$api_url" --idp-url "$idp_url" 2>&1 | cat
code=${PIPESTATUS[0]}

echo
if [ "$code" -ne 0 ]; then
  echo "Sign-in did not complete (exit $code)." >&2
  echo "If the browser said the code expired, run Authenticate again and approve it sooner." >&2
  echo "If the URL could not be reached, check the API and identity provider URL settings." >&2
  exit "$code"
fi

shp auth status || true
echo
echo "One more step, done by the account above in the SheetyApp web app: the CLI can"
echo "only reach workbooks that are delegated to it. For each workbook the agent should"
echo "use, open"
echo "    $web_url/workbooks/<workbookId>/settings#connected-apps"
echo "and add the client 'cli' with the role the agent should have. Its access is that"
echo "role, capped by your own role in the workbook."
exit 0
