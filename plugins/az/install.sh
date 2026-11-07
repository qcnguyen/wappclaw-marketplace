#!/usr/bin/env bash
# Provision the Azure CLI, and give this plugin its own azure-devops extension.
#
# **This is the one install script here that sources lib.sh, and the reason is the
# point of the script.** Extensions live in `$AZURE_CONFIG_DIR/cliextensions`, so
# they are per config dir — an isolated config dir has none however many the
# machine has. The extension is therefore part of *this plugin's* installation, not
# a shared cache like npm's, and it has to be installed into the plugin's own
# directory or `az devops` will not exist at run time.
#
# **It also installs the CLI itself when it is missing, rather than telling the
# admin to.** An install run by the migration wizard has nobody to hand a shell
# command to: the wizard's whole job is to bring a fresh server up unattended, and
# a step whose success condition is "a human reads this, runs curl, comes back and
# presses the button again" is a step that has failed. So this script provisions,
# in a deliberate order — cheapest and least invasive first (see `ensure_az`) —
# and only explains the manual route when every automatic one is impossible.
set -uo pipefail
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"

# Where a root-free installation goes, if it comes to that. Under `state/`, so it
# is this plugin's, it survives a new version of the bundle, and it disappears
# with the plugin.
local_prefix="${PLUGIN_STATE_DIR:-$PLUGIN_DIR/state}/azure-cli"

# How this run got hold of `az`. Decides what goes in env.sh at the end: a
# machine-wide CLI needs no PATH entry, a plugin-local one is invisible without.
az_source="system"

# --- provisioning ------------------------------------------------------------

# Root without asking anyone. `sudo -n` fails immediately rather than blocking on
# a password prompt, which matters here: there is no terminal to type into, and a
# script that hangs waiting for one is worse than a script that says it cannot.
root_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    printf '%s' ""
    return 0
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    printf '%s' "sudo -n"
    return 0
  fi
  return 1
}

# The distro's own package, which is what Microsoft documents and what an
# administrator would have installed by hand. Only ever attempted when root is
# already available — this never prompts for a password and never partially
# configures a machine it cannot finish configuring.
install_machine_wide() {
  local sudo_cmd
  sudo_cmd=$(root_cmd) || return 1

  if command -v apt-get >/dev/null 2>&1; then
    command -v curl >/dev/null 2>&1 || return 1
    echo "  Installing the Azure CLI from Microsoft's apt repository..."
    # Microsoft's own one-shot installer: adds the repo, its key, and the package.
    curl -sL https://aka.ms/InstallAzureCLIDeb | $sudo_cmd bash 2>&1 | sed 's/^/    /'
  elif command -v dnf >/dev/null 2>&1; then
    echo "  Installing the Azure CLI with dnf..."
    $sudo_cmd dnf install -y azure-cli 2>&1 | tail -20 | sed 's/^/    /'
  elif command -v yum >/dev/null 2>&1; then
    echo "  Installing the Azure CLI with yum..."
    $sudo_cmd yum install -y azure-cli 2>&1 | tail -20 | sed 's/^/    /'
  else
    return 1
  fi

  hash -r 2>/dev/null || true
  command -v az >/dev/null 2>&1
}

# The root-free route: the CLI is a Python application, so it installs into a
# virtual environment this plugin owns. Slower than the package (it builds a few
# wheels) and it is why plugin.json allows this script twenty minutes, but it
# needs no administrator and touches nothing outside `state/` — the same shape as
# the m365 plugin installing its CLI into a prefix it can write to.
install_plugin_local() {
  command -v python3 >/dev/null 2>&1 || return 1
  python3 -c 'import venv' >/dev/null 2>&1 || return 1

  echo "  Installing the Azure CLI into this plugin's own directory (no administrator"
  echo "  needed; it builds a few packages, so give it several minutes)..."
  echo "    $local_prefix"
  rm -rf "$local_prefix"
  python3 -m venv "$local_prefix" 2>&1 | sed 's/^/    /' || return 1
  "$local_prefix/bin/python" -m pip install --upgrade --quiet --disable-pip-version-check \
    pip setuptools wheel 2>&1 | tail -5 | sed 's/^/    /'
  "$local_prefix/bin/python" -m pip install --disable-pip-version-check --no-input \
    azure-cli 2>&1 | tail -15 | sed 's/^/    /'

  [ -x "$local_prefix/bin/az" ] || return 1
  export PATH="$local_prefix/bin:$PATH"
  hash -r 2>/dev/null || true
  az_source="plugin"
  command -v az >/dev/null 2>&1
}

# Everything above, in the order that does the least damage for the most benefit:
# what is already here, then what a previous run of this script put here, then the
# machine package if we are already privileged, then the plugin's own copy.
ensure_az() {
  if command -v az >/dev/null 2>&1; then
    return 0
  fi

  # A previous run's plugin-local install. lib.sh sources env.sh, so this is
  # normally already on PATH; checking explicitly covers an env.sh that was lost
  # with the rest of a re-imported bundle's state.
  if [ -x "$local_prefix/bin/az" ]; then
    export PATH="$local_prefix/bin:$PATH"
    hash -r 2>/dev/null || true
    az_source="plugin"
    return 0
  fi

  echo "  az: not found on this machine — installing it now."
  echo

  if install_machine_wide; then
    echo
    return 0
  fi

  echo
  if install_plugin_local; then
    echo
    return 0
  fi

  return 1
}

# Written for every outcome, because every other script in this plugin sources it
# and a plugin-local CLI is unreachable without it.
record_env() {
  [ -n "${PLUGIN_STATE_DIR:-}" ] || return 0
  mkdir -p "$PLUGIN_STATE_DIR"
  if [ "$az_source" = "plugin" ]; then
    {
      printf '# Sourced by lib.sh before every command.\n'
      printf '# The Azure CLI is this plugin'"'"'s own, installed by install.sh.\n'
      printf 'export PATH="%s/bin:$PATH"\n' "$local_prefix"
    } > "$PLUGIN_STATE_DIR/env.sh"
  else
    printf '# Sourced by lib.sh before every command.\n# Nothing to add: az comes from the system.\n' \
      > "$PLUGIN_STATE_DIR/env.sh"
  fi
}

# --- the Azure CLI -----------------------------------------------------------

fail=0
echo "Checking the Azure CLI."
echo

if ! ensure_az; then
  echo "  az: NOT AVAILABLE, and it could not be installed automatically." >&2
  echo >&2
  echo "  Tried, in order:" >&2
  echo "    - an existing az on PATH" >&2
  echo "    - the distro package, which needs root this server does not have" >&2
  echo "      (no root, and no password-free sudo)" >&2
  echo "    - a private install under this plugin, which needs python3 with venv" >&2
  echo "      and pip able to reach pypi.org" >&2
  echo >&2
  echo "  So this needs either python3 (apt-get install python3-venv) and outbound" >&2
  echo "  access to pypi.org, or the CLI installed once by an administrator:" >&2
  echo "      curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash        # Debian/Ubuntu" >&2
  echo "      sudo dnf install azure-cli                                    # RHEL/Fedora" >&2
  echo "  or see https://learn.microsoft.com/cli/azure/install-azure-cli" >&2
  echo "  then run this install again." >&2
  record_env
  exit 1
fi

echo "  az: $(az version --query '"azure-cli"' -o tsv 2>/dev/null)  ($(command -v az))"
if [ "$az_source" = "plugin" ]; then
  echo "    (this plugin's own copy — nothing outside its folder was changed)"
fi
echo "  config dir: $AZURE_CONFIG_DIR"
echo "    (this plugin's own — its login and extensions are separate from the machine's)"
echo

# --- the azure-devops extension ---------------------------------------------
#
# Installed by default, because that is what this plugin is for as much as
# resource management is. Idempotent: added when absent, updated when present, so
# pressing Install again is an upgrade.
echo "Ensuring the azure-devops extension is present in this plugin's config dir..."
if az extension show --name azure-devops --query name -o tsv >/dev/null 2>&1; then
  current=$(az extension show --name azure-devops --query version -o tsv 2>/dev/null)
  echo "  already installed (version $current). Checking for an update..."
  if az extension update --name azure-devops --only-show-errors 2>&1 | grep -vi "latest version" | head -3; then :; fi
  echo "  version now: $(az extension show --name azure-devops --query version -o tsv 2>/dev/null)"
else
  if az extension add --name azure-devops --only-show-errors 2>&1 | tail -3; then
    version=$(az extension show --name azure-devops --query version -o tsv 2>/dev/null)
    if [ -n "$version" ]; then
      echo "  installed azure-devops $version"
    else
      echo "  the extension did not install." >&2
      fail=1
    fi
  else
    echo "  the extension could not be installed." >&2
    echo "  If this server restricts outbound traffic, the extension is fetched from" >&2
    echo "  Microsoft's package feed and that needs to be reachable." >&2
    fail=1
  fi
fi

echo
echo "Extensions in this plugin's config dir:"
az extension list --query "[].{name:name, version:version}" -o tsv 2>/dev/null | sed 's/^/  /' || echo "  (none)"

record_env

echo
if [ "$fail" -ne 0 ]; then
  echo "Install incomplete — fix the items above and run it again." >&2
  exit 1
fi

echo "Ready."
echo
echo "Next: set the client ID, tenant ID and secret in the admin app (and the Azure"
echo "DevOps organisation URL if you want az devops commands), then press Authenticate."
