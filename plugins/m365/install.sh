#!/usr/bin/env bash
# Provision the CLI for Microsoft 365. Idempotent: re-running updates it.
#
# Deliberately does NOT source lib.sh: lib.sh redirects HOME into the plugin so
# the CLI's *tokens* stay there, and npm has no business in that. Tokens are
# scoped, installs are not.
#
# **Not sourcing it is not enough, though.** The server forces `HOME` to the
# plugin's private home for every script it runs, lib.sh or no lib.sh, so this
# script does not get the server user's home by default — it has to ask for it,
# which is what `PLUGIN_REAL_HOME` is for and what `npm_env` below does. Without
# that, npm reads no `~/.npmrc` (so a private registry is invisible) and keeps its
# cache inside the plugin, where every install starts cold. Measured before the
# fix: 321 MB of package tree under the plugin's own home and no shared cache.
#
# It also installs what it needs rather than describing it. This runs under the
# migration wizard against servers nobody has logged into, so a step that ends in
# "run this as an administrator and press the button again" is a step that has
# failed — see `system_install`, and the plugin-owned prefix in the candidate list
# below, which is why "nowhere to install" is no longer an outcome.
set -uo pipefail

# Whether `apt-get update` has already been paid for in this run: a fresh image
# often has no package lists, and refreshing them is slow enough to be worth
# doing once, lazily, and only when an install has actually failed without it.
apt_refreshed=0

# Install a system package, but only when that can happen without a human: as
# root already, or with password-free sudo. `sudo -n` fails instead of prompting,
# which is what makes this safe to call unattended — there is no terminal here for
# anyone to type a password into, so a prompt would just hang until the session's
# timeout. Returns non-zero when the package could not be installed, for any
# reason; the caller decides whether that is fatal.
system_install() {
  local pkg="$1" bin="${2:-$1}" sudo_cmd
  if [ "$(id -u)" -eq 0 ]; then
    sudo_cmd=""
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo_cmd="sudo -n"
  else
    return 1
  fi

  if command -v apt-get >/dev/null 2>&1; then
    if ! DEBIAN_FRONTEND=noninteractive $sudo_cmd apt-get install -y -qq "$pkg" >/dev/null 2>&1; then
      [ "$apt_refreshed" -eq 1 ] && return 1
      apt_refreshed=1
      $sudo_cmd apt-get update -qq >/dev/null 2>&1
      DEBIAN_FRONTEND=noninteractive $sudo_cmd apt-get install -y -qq "$pkg" >/dev/null 2>&1 || return 1
    fi
  elif command -v dnf >/dev/null 2>&1; then
    $sudo_cmd dnf install -y -q "$pkg" >/dev/null 2>&1 || return 1
  elif command -v yum >/dev/null 2>&1; then
    $sudo_cmd yum install -y -q "$pkg" >/dev/null 2>&1 || return 1
  elif command -v apk >/dev/null 2>&1; then
    $sudo_cmd apk add --quiet "$pkg" >/dev/null 2>&1 || return 1
  else
    return 1
  fi

  hash -r 2>/dev/null || true
  command -v "$bin" >/dev/null 2>&1
}

# Run npm the way the server's own user would: its cache and its `.npmrc` from the
# real home, so a private registry works and a second install is warm. Only the
# *install* borrows the real home — the prefix search and everything the CLI does
# at run time stay where they were.
real_home="${PLUGIN_REAL_HOME:-$HOME}"
npm_env() {
  env HOME="$real_home" \
      npm_config_cache="$real_home/.npm" \
      npm_config_userconfig="$real_home/.npmrc" \
      "$@"
}

record_path() {
  # The install prefix's bin directory may not be on the *server process's* PATH.
  # Record it so this plugin's actions find the binary the install produced,
  # rather than depending on how the server happened to be started (lib.sh).
  [ -n "${PLUGIN_STATE_DIR:-}" ] || return 0
  mkdir -p "$PLUGIN_STATE_DIR"
  printf 'export PATH="%s:$PATH"\n' "$1" > "$PLUGIN_STATE_DIR/env.sh"
  echo "Recorded $1 in \$PLUGIN_STATE_DIR/env.sh for this plugin's actions."
}

working_m365() {
  command -v m365 >/dev/null 2>&1 && m365 --version >/dev/null 2>&1
}

# npm's configured global prefix is often root-owned (/usr/local), and this
# script runs as the *server's* user. So find a prefix we can actually write
# into — and test the directory npm really writes to (`lib/node_modules`, and
# the `@pnp` scope inside it if it already exists), not just the top level. A
# prefix whose top level is ours but whose packages were installed with sudo
# looks writable and then fails halfway through a rename.
usable_prefix() {
  local candidate="$1"
  [ -n "$candidate" ] || return 1
  mkdir -p "$candidate/lib/node_modules" 2>/dev/null || return 1
  [ -w "$candidate/lib/node_modules" ] || return 1
  [ ! -d "$candidate/lib/node_modules/@pnp" ] || [ -w "$candidate/lib/node_modules/@pnp" ] || return 1
  return 0
}

if working_m365; then
  echo "CLI for Microsoft 365 is already available at $(command -v m365)"
  m365 --version
  echo
  echo "Checking for an update..."
  echo
fi

# npm itself. Missing on a server whose node came as a single binary, and there is
# no root-free way to conjure it, so this is the one thing here that can still end
# in a sentence for an administrator — but only after trying.
if ! command -v npm >/dev/null 2>&1; then
  echo "npm is not on this server — installing it..."
  system_install npm >/dev/null 2>&1 || system_install nodejs npm >/dev/null 2>&1 || true
  echo
fi

# openssl, for the certificate sign-in mode. `auth.sh` opens a password-protected
# certificate here rather than handing the password to the CLI on a command line
# (process arguments are world-readable), and openssl is what opens it. Best
# effort and never fatal: device-code sign-in does not need it, nor does a
# certificate whose private key has no password.
if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is not on this server — installing it (the certificate sign-in mode uses it)..."
  if ! system_install openssl >/dev/null 2>&1; then
    echo "  Could not install openssl automatically. Nothing else here needs it:"
    echo "  device-code sign-in is unaffected, and so is a certificate with no password."
  fi
  echo
fi

prefix=""
# `$PLUGIN_STATE_DIR/npm-global` is last and is the reason this loop cannot come
# up empty: it is inside the plugin's own folder, so it is always writable, and a
# CLI installed there is this plugin's the way the az plugin's CLI is its own. The
# earlier candidates are preferred only because a shared prefix is shared — one
# copy, one update, and npm's cache already warm.
for candidate in \
  "$(npm_env npm config get prefix 2>/dev/null)" \
  /usr/local/share/npm-global \
  "$HOME/.npm-global" \
  "${PLUGIN_STATE_DIR:-}${PLUGIN_STATE_DIR:+/npm-global}"; do
  if usable_prefix "$candidate"; then
    prefix="$candidate"
    break
  fi
done

if [ -z "$prefix" ]; then
  # With a plugin-owned prefix in the list this is now nearly unreachable — it
  # means even `state/` could not be written to, or npm is absent. If a working
  # CLI is already here, that is a complete answer — the plugin can run — so say
  # what happened and succeed rather than failing over an update nobody asked for.
  if working_m365; then
    echo "No usable npm prefix, so the CLI could not be updated." >&2
    echo "The existing installation at $(command -v m365) works and will be used." >&2
    record_path "$(dirname "$(command -v m365)")"
    exit 0
  fi
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm is not on this server and could not be installed automatically." >&2
    echo "This plugin's CLI is an npm package, so npm is a hard requirement." >&2
    echo "Installing it needs root, which this server does not have (no root, and no" >&2
    echo "password-free sudo). An administrator has to run one of:" >&2
    echo "    apt-get install npm / dnf install npm" >&2
    echo "then run this install again." >&2
    exit 1
  fi
  echo "No writable npm prefix at all — not even inside this plugin's own folder." >&2
  echo "Check the permissions on ${PLUGIN_STATE_DIR:-the state directory}:" >&2
  echo "the server's user has to be able to write there, and it is where this plugin" >&2
  echo "keeps everything else it owns." >&2
  exit 1
fi

echo "Installing @pnp/cli-microsoft365 into $prefix (this takes a minute or two)..."
if ! npm_env npm install -g --prefix "$prefix" @pnp/cli-microsoft365; then
  if working_m365; then
    echo >&2
    echo "The install failed, but an existing CLI at $(command -v m365) works and will be used." >&2
    record_path "$(dirname "$(command -v m365)")"
    exit 0
  fi
  echo "The install failed and no working CLI is present." >&2
  exit 1
fi

bin_dir="$prefix/bin"
export PATH="$bin_dir:$PATH"

echo
if ! working_m365; then
  echo "Installed into $bin_dir, but m365 is not runnable from there." >&2
  exit 1
fi

echo "Installed: $(command -v m365)"
m365 --version
record_path "$bin_dir"

echo
echo "Next: authenticate the plugin, in the sign-in mode it is set to."
echo "  deviceCode  (the default) prints a code a person signs in with."
echo "  certificate signs in as the application, using a certificate you configure."
