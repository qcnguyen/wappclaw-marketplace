#!/usr/bin/env bash
# Sign in as the service principal, and prove the login works.
#
# Nothing waits for a human — a service principal sign-in is one request — but it
# is still a streamed session, because what usually goes wrong is not the
# credential: it is that the principal has no access to the subscription, or was
# never added to the Azure DevOps organisation. Those are worth diagnosing while
# somebody is watching the output.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
require_az || exit 1
az_check_config || exit 2

echo "Signing in to Azure as a service principal."
echo "  client ID: $AZ_CLIENT_ID"
echo "  tenant:    $AZ_TENANT_ID"
echo "  config:    $AZURE_CONFIG_DIR"
echo

# Clear any previous login in *this* plugin's config dir. A stale one for a
# different principal is how "I changed the credential and nothing happened"
# happens. The machine's own login is in a different directory and is untouched.
az logout >/dev/null 2>&1 || true

echo "1. Logging in..."
if ! az_login; then
  echo >&2
  echo "Sign-in failed. What the common causes look like:" >&2
  echo "  AADSTS7000215  the client secret is wrong. Azure shows a secret's *Value*" >&2
  echo "      once and its *Secret ID* for ever; the Value is what belongs here." >&2
  echo "  AADSTS7000222  the client secret has EXPIRED. Create a new one." >&2
  echo "  AADSTS700016   no application with this client ID exists in this tenant." >&2
  echo "      Check the client ID and tenant ID come from the same directory." >&2
  echo "  AADSTS90002    that tenant does not exist. It must be the directory GUID." >&2
  exit 1
fi
echo "   Logged in."
echo

# --- the subscription -------------------------------------------------------
if [ -n "${AZ_SUBSCRIPTION:-}" ]; then
  echo "2. Selecting the default subscription..."
  if az account set --subscription "$AZ_SUBSCRIPTION" --only-show-errors 2>&1 && true; then
    echo "   $AZ_SUBSCRIPTION"
  else
    echo "   Could not select '$AZ_SUBSCRIPTION'." >&2
    echo "   The login worked, so this is access rather than credentials: the service" >&2
    echo "   principal needs a role assignment on that subscription. Subscriptions it" >&2
    echo "   can see:" >&2
    az account list --query "[].{name:name, id:id}" -o tsv 2>/dev/null | sed 's/^/     /' >&2
    exit 1
  fi
else
  echo "2. No default subscription configured; using whatever the principal gets."
fi
account=$(az account show --query "{sub:name, id:id, tenant:tenantId, type:user.type}" -o tsv 2>/dev/null)
[ -n "$account" ] && echo "   account: $account"
echo

# --- Azure DevOps -----------------------------------------------------------
#
# The extension authenticates with the az login itself, so there is no PAT to
# manage — verified against a real organisation. What it does need is the service
# principal *added to the organisation as a user*, which existing in the tenant
# does not give it, and which fails in a way that looks nothing like a credential
# problem.
if [ -n "${AZ_DEVOPS_ORG:-}" ]; then
  echo "3. Configuring Azure DevOps..."
  az devops configure --defaults "organization=$AZ_DEVOPS_ORG" >/dev/null 2>&1 || true
  echo "   default organisation: $AZ_DEVOPS_ORG"
  if projects=$(az devops project list --organization "$AZ_DEVOPS_ORG" --query "value[].name" -o tsv 2>&1); then
    count=$(printf '%s\n' "$projects" | grep -c . || true)
    echo "   $count project(s) visible:"
    printf '%s\n' "$projects" | sed 's/^/     - /'
  else
    echo "   Could not list projects in $AZ_DEVOPS_ORG" >&2
    printf '   %s\n' "$(printf '%s' "$projects" | head -2)" >&2
    echo >&2
    echo "   The Azure login is good, so this is Azure DevOps access. A service" >&2
    echo "   principal must be added to the organisation as a user:" >&2
    echo "     Organisation settings -> Users -> Add users, add it by its application" >&2
    echo "     name with a Basic access level, then grant it project permissions." >&2
    echo "   Azure resource commands still work; only 'az devops' is affected." >&2
  fi
else
  echo "3. No Azure DevOps organisation configured — 'az devops' commands will need"
  echo "   an explicit --organization, or set it in the plugin's settings."
fi

echo
echo "Signed in. Ordinary az commands now work through this plugin:"
echo "   az group list -o table"
echo "   az repos list --project MyProject -o table"
echo
echo "This principal's roles are the plugin's permissions. A resource it has no role"
echo "on is invisible rather than forbidden, so an empty list may mean no access."
