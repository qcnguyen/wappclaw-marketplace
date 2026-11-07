#!/usr/bin/env bash
# Store the credential, and prove it works.
#
# Nothing here waits for a human — Basic auth with an API token needs no round
# trip to a browser — but it is still a streamed session, and the second half is
# why: storing a token proves nothing, so "signed in" has to be established by
# making a real request while somebody is watching the output.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
require_curl || exit 1
jira_check_config || exit 2

host=$(jira_host)
echo "Signing in to Jira."
echo "  site:  $host"
echo "  email: $JIRA_EMAIL"
echo

echo "1. Looking up the site's cloud id..."
jira_resolve_base || exit 1
echo "   cloudId:  $JIRA_CLOUD_ID"
echo "   API base: $JIRA_BASE"
echo

echo "2. Storing the credential..."
if ! jira_write_netrc; then
  echo "   Could not write the credential file in the plugin's private home." >&2
  echo "   Check the permissions on the plugin's state folder." >&2
  exit 1
fi
echo "   Written to the plugin's own home, mode 0600. It is never passed on a"
echo "   command line, so it cannot appear in \`ps\` or in a transcript."
echo

echo "3. Checking it against Jira..."
body=$(curl -sS -n --max-time 25 -w '\n%{http_code}' \
  -H 'Accept: application/json' "$JIRA_BASE/rest/api/3/myself" 2>&1) || {
  echo "   Could not reach $JIRA_BASE" >&2
  printf '   %s\n' "$(printf '%s' "$body" | head -2)" >&2
  exit 1
}
code=$(printf '%s' "$body" | tail -1)
body=$(printf '%s' "$body" | sed '$d')

case "$code" in
  200)
    if command -v jq >/dev/null 2>&1; then
      echo "   Jira says this is: $(printf '%s' "$body" | jq -r '"\(.displayName) <\(.emailAddress // "no email visible")>"')"
      echo "   accountId: $(printf '%s' "$body" | jq -r '.accountId')"
    else
      echo "   Jira accepted it (HTTP 200)."
    fi
    echo
    echo "Signed in. The agent can now call the Jira REST API with plain curl:"
    echo "   curl -sn \"\$JIRA_BASE/rest/api/3/issue/KEY-123\" | jq ."
    echo
    echo "This account's permissions are the plugin's permissions. Jira hides what an"
    echo "account cannot see rather than forbidding it, so a project this one lacks"
    echo "access to reports as 'does not exist'."
    exit 0
    ;;
  401)
    echo "   Jira refused the credential (HTTP 401)." >&2
    echo >&2
    echo "   In order of likelihood:" >&2
    echo "     1. The API token has expired or been revoked. Atlassian tokens can carry" >&2
    echo "        an expiry date. Create a new one and store it here:" >&2
    echo "        https://id.atlassian.com/manage-profile/security/api-tokens" >&2
    echo "     2. The email does not match the token's account. Basic auth here is" >&2
    echo "        email:token, so both have to belong together." >&2
    echo "     3. The token was pasted with a leading or trailing space." >&2
    ;;
  403)
    echo "   Authenticated, but forbidden (HTTP 403)." >&2
    echo "   The credential is good and the account is not permitted. Check that it has" >&2
    echo "   a Jira application licence, not just an Atlassian account." >&2
    ;;
  404)
    echo "   HTTP 404 from $JIRA_BASE" >&2
    echo "   The cloud id resolved but the gateway does not recognise it. Check the" >&2
    echo "   'Jira site' setting names the right site." >&2
    ;;
  *)
    echo "   Unexpected response (HTTP ${code:-none})." >&2
    printf '   %s\n' "$(printf '%s' "$body" | head -c 300)" >&2
    ;;
esac
exit 1
