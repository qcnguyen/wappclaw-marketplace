#!/usr/bin/env bash
# Verify the service principal, and prove it can reach the organisation.
#
# Unlike an interactive device-code login, nothing here waits for a human — a
# client-credentials sign-in is a single HTTPS round trip. It is still a session
# rather than a request, and that is worth having: what usually goes wrong with
# service principal access to Azure DevOps is not the credential but the *second*
# step (the principal was never added to the organisation), and this is where a
# human is watching output and can act on the difference.
#
# It prints the token's own claims and the projects it can see. It never prints
# the token or the secret.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"

azdo_check_config || exit 2

echo "Checking the Azure DevOps service principal."
echo "  client ID: ${AZDO_CLIENT_ID}"
echo "  tenant:    ${AZDO_TENANT_ID}"
if azdo_resolve_org; then
  echo "  org:       $AZDO_ORG_BASE"
else
  echo "  org:       (not set — the sign-in can be checked, access to the org cannot)"
fi
echo

# --- step 1: can we get a token at all? -------------------------------------
echo "1. Requesting an Azure DevOps access token from Azure AD..."
token=$(azdo_token 25) || exit 1
echo "   Token issued."

# The claims say *who* the token is for, which is what makes a wrong-app-registration
# mistake visible. A JWT's payload is base64url — not encryption — so reading it
# here is just decoding, and it needs no network call and no extra permission.
decode_claims() {
  local payload="${1#*.}"
  payload="${payload%%.*}"
  payload="${payload//-/+}"
  payload="${payload//_//}"
  case $(( ${#payload} % 4 )) in
    2) payload="$payload==" ;;
    3) payload="$payload=" ;;
  esac
  printf '%s' "$payload" | base64 -d 2>/dev/null
}
claims=$(decode_claims "$token" || true)
if [ -n "$claims" ]; then
  appid=$(azdo_json_field "$claims" appid)
  tid=$(azdo_json_field "$claims" tid)
  oid=$(azdo_json_field "$claims" oid)
  exp=$(printf '%s' "$claims" | tr ',' '\n' | sed -n 's/.*"exp"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
  [ -n "$appid" ] && echo "   app id in token:  $appid"
  [ -n "$tid" ]   && echo "   tenant in token:  $tid"
  [ -n "$oid" ]   && echo "   principal object: $oid"
  if [ -n "$exp" ]; then
    echo "   expires:          $(date -u -d "@$exp" '+%Y-%m-%d %H:%M:%SZ' 2>/dev/null || echo "in $(( (exp - $(date +%s)) / 60 )) minutes")"
    echo "                     (a token is minted fresh for every command, so this is not a deadline)"
  fi
  if [ -n "$appid" ] && [ "$appid" != "$AZDO_CLIENT_ID" ]; then
    echo "   NOTE: the token names a different app id than the configured client ID." >&2
  fi
fi
echo

# --- step 2: does Azure DevOps accept it? -----------------------------------
#
# This is the check that matters, and the one people skip. A token can be
# perfectly valid and still be refused by Azure DevOps, because a service
# principal has to be *added to the organisation as a user* and given access —
# it is not enough for it to exist in the tenant. That failure looks nothing
# like a credential failure, so it is diagnosed separately here.
if ! azdo_resolve_org; then
  echo "No organisation configured, so access could not be verified."
  echo "Set 'Azure DevOps organisation' in the admin app and run Authenticate again."
  echo
  echo "The credential itself is good: a token was issued."
  exit 0
fi

echo "2. Asking $AZDO_ORG_BASE which projects this principal can see..."
body=$(azdo_org_request "$token" '/_apis/projects?api-version=7.1&$top=100' \
  --max-time 20 -w '\n%{http_code}' 2>&1) || true
status=$(printf '%s' "$body" | tail -1)
body=$(printf '%s' "$body" | sed '$d')

case "$status" in
  200)
    if command -v jq >/dev/null 2>&1; then
      count=$(printf '%s' "$body" | jq -r '.count // 0' 2>/dev/null || echo 0)
      echo "   $count project(s) visible:"
      printf '%s' "$body" | jq -r '.value[]? | "     - \(.name)"' 2>/dev/null
    else
      echo "   Access confirmed (HTTP 200)."
    fi
    echo
    echo "Signed in. Ordinary git commands against this organisation now work through"
    echo "this plugin — clone, fetch, pull, push, and everything that reads a clone."
    echo
    # The identity is a separate axis from the credential, and a sign-in screen is
    # where somebody is looking — so say which one commits will carry rather than
    # letting them find out at the first `git commit`. It comes from this plugin's
    # settings only: HOME is the plugin's own, so the machine's git config is not
    # read.
    if [ -n "${AZDO_COMMIT_EMAIL:-}" ] && [ -n "${AZDO_COMMIT_NAME:-}" ]; then
      echo "Commits will be authored as:"
      echo "  $AZDO_COMMIT_NAME <$AZDO_COMMIT_EMAIL>"
      case "$AZDO_COMMIT_EMAIL" in
        *@*) ;;
        *) echo "  NOTE: that email has no '@'. git will accept it; Azure DevOps will not" >&2
           echo "        match it to a person." >&2 ;;
      esac
    else
      echo "No commit identity is configured, so 'git commit' will fail with"
      echo "  'Author identity unknown'. Reading, cloning and fetching are unaffected."
      echo "  Set 'Commit author name' and 'Commit author email' in this plugin's settings."
    fi
    echo
    echo "Two things this does NOT prove, both worth knowing:"
    echo "  - Repository permissions are per project. Being able to list projects does not"
    echo "    mean this principal may read every repository in them, and it says nothing"
    echo "    about whether it may push."
    echo "  - A project this principal cannot see is simply absent from the list above,"
    echo "    not reported as forbidden. If a repository the agent needs 404s, the"
    echo "    principal's access to that project is the first thing to check."
    exit 0
    ;;
  203)
    echo "   Azure DevOps answered 203 (a sign-in page), which is how it refuses a token" >&2
    echo "   it will not accept. The token is valid, so this is an authorisation problem," >&2
    echo "   not a credential one:" >&2
    ;;
  401|403)
    echo "   Azure DevOps refused the token (HTTP $status)." >&2
    ;;
  404)
    echo "   HTTP 404 — no such organisation at $AZDO_ORG_BASE." >&2
    echo "   Check the 'Azure DevOps organisation' setting. A bare name, a" >&2
    echo "   https://dev.azure.com/<org> URL and a https://<org>.visualstudio.com URL" >&2
    echo "   are all accepted; a typo in the name gives exactly this." >&2
    exit 1
    ;;
  *)
    echo "   Unexpected response (HTTP ${status:-none}) from $AZDO_ORG_BASE." >&2
    printf '   %s\n' "$(printf '%s' "$body" | head -c 300)" >&2
    exit 1
    ;;
esac

# Shared advice for 203/401/403 — all three mean "the token is fine, the
# principal is not permitted".
{
  echo
  echo "   A service principal existing in the tenant is not enough. It must also be"
  echo "   added to the Azure DevOps organisation:"
  echo "     Organisation settings -> Users -> Add users, and add the service principal"
  echo "     by its application name, with a Basic access level and a project or team."
  echo "   Then, per project: Project settings -> Repositories -> Security, and grant it"
  echo "   Read (and Contribute, if it will push)."
  echo
  echo "   If the organisation is connected to a different Entra tenant than the one"
  echo "   configured here, no permission grant will help — the principal is invisible"
  echo "   to it. Organisation settings -> Microsoft Entra shows which tenant that is."
} >&2
exit 1
