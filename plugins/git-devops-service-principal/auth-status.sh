#!/usr/bin/env bash
# The probe behind `Plugin.authenticated`. Exit 0 means usable. Silent: nothing
# reads this script's output, only its exit code.
#
# It really does sign in, rather than checking that a credential is *present*.
# That distinction is the whole point of the probe: a stored secret that has
# since expired is the single commonest failure of service principal access, and
# a probe that only checked "is there a secret?" would report a green chip for
# every day of an outage. There is no cached token to consult, either — this
# plugin mints one per command and keeps none — so asking is the only way to know.
#
# Cost: one, or two, HTTPS calls, capped well inside the platform's 20s probe
# budget, and the answer is cached for 30s.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"

# Not configured is not "signed out" in any interesting sense, but it is
# certainly not usable.
[ -n "${AZDO_CLIENT_ID:-}" ]     || exit 1
[ -n "${AZDO_TENANT_ID:-}" ]     || exit 1
[ -n "${AZDO_CLIENT_SECRET:-}" ] || exit 1

token=$(azdo_token 8 2>/dev/null) || exit 1
[ -n "$token" ] || exit 1

# With no organisation set there is nothing further to ask, and a valid token is
# an honest "yes" to the question this probe asks.
azdo_resolve_org >/dev/null 2>&1 || exit 0

# Azure DevOps refuses a token it will not accept with 401, 403, or a 203 that is
# really an HTML sign-in page — so only a 200 counts. This is what makes the chip
# mean "can reach the organisation" rather than "Azure AD knows this app".
status=$(azdo_org_request "$token" '/_apis/projects?api-version=7.1&$top=1' \
  --max-time 8 -o /dev/null -w '%{http_code}' 2>/dev/null) || exit 1
[ "$status" = "200" ] || exit 1
exit 0
