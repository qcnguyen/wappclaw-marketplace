#!/usr/bin/env bash
# Provision agent-browser: the npm package (a native Rust binary per platform,
# plus the skills it serves with `agent-browser skills get`), the Chrome build
# that CLI version pins, and the shared libraries Chrome needs on Linux. Then
# decide whether Chrome can run with its sandbox here. Idempotent — run it
# again to upgrade to $AGENT_BROWSER_VERSION.
#
# No Node.js is needed: the package's bin/agent-browser.js only picks the native
# binary for the platform, so the tarball is fetched from the npm registry with
# curl (checksum-verified) and the binary linked directly — the same thing the
# package's postinstall does for a global npm install.
#
# System packages only with root that needs no password (`sudo -n`, never plain
# sudo — this also runs under the migration wizard, where a prompt just hangs).
set -uo pipefail

state="${PLUGIN_STATE_DIR:?PLUGIN_STATE_DIR is not set}"
version="${AGENT_BROWSER_VERSION:-latest}"
registry="https://registry.npmjs.org"
mkdir -p "$state"

# --- Root without asking, and system packages ---------------------------------
apt_refreshed=0
sudo_cmd() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then sudo -n "$@"
  else return 1
  fi
}
can_root() { [ "$(id -u)" -eq 0 ] || { command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; }; }

# Install one or more packages; non-zero if any could not be installed.
system_install() {
  can_root || return 1
  if command -v apt-get >/dev/null 2>&1; then
    if ! sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null 2>&1; then
      [ "$apt_refreshed" -eq 1 ] && return 1
      apt_refreshed=1
      sudo_cmd apt-get update -qq >/dev/null 2>&1
      sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null 2>&1 || return 1
    fi
  elif command -v dnf >/dev/null 2>&1; then sudo_cmd dnf install -y -q "$@" >/dev/null 2>&1 || return 1
  elif command -v yum >/dev/null 2>&1; then sudo_cmd yum install -y -q "$@" >/dev/null 2>&1 || return 1
  elif command -v apk >/dev/null 2>&1; then sudo_cmd apk add --quiet "$@" >/dev/null 2>&1 || return 1
  else return 1
  fi
  hash -r 2>/dev/null || true
}

# --- A downloader -------------------------------------------------------------
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo "Neither curl nor wget is installed; trying to install curl."
  system_install curl || true
fi
download() { # url dest
  if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then wget -q -O "$2" "$1"
  else return 1
  fi
}
fetch() { # url -> stdout
  if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 "$1"
  elif command -v wget >/dev/null 2>&1; then wget -q -O - "$1"
  else return 1
  fi
}
sha1_of() {
  if command -v sha1sum >/dev/null 2>&1; then sha1sum "$1" | cut -d' ' -f1
  else shasum -a 1 "$1" | cut -d' ' -f1
  fi
}

# --- Which native binary ------------------------------------------------------
is_musl() { ldd --version 2>&1 | grep -qi musl || [ -e /lib/ld-musl-x86_64.so.1 ] || [ -e /lib/ld-musl-aarch64.so.1 ]; }
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) platform=linux-x64 ;;
  Linux/aarch64 | Linux/arm64) platform=linux-arm64 ;;
  Darwin/x86_64) platform=darwin-x64 ;;
  Darwin/arm64) platform=darwin-arm64 ;;
  *) echo "agent-browser publishes no binary for $(uname -s)/$(uname -m)." >&2; exit 1 ;;
esac
if [ "$(uname -s)" = Linux ] && is_musl; then platform="linux-musl-${platform#linux-}"; fi

# --- The agent-browser package ------------------------------------------------
pkg="$state/agent-browser"
binary="$pkg/bin/agent-browser-$platform"
installed_version() { [ -f "$pkg/package.json" ] && sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$pkg/package.json" | head -1; }
have_binary() { [ -x "$binary" ] && "$binary" --version >/dev/null 2>&1; }

echo "Resolving agent-browser@$version on $registry..."
meta="$(fetch "$registry/agent-browser/$version")" || meta=""
tarball="$(printf '%s' "$meta" | sed -n 's/.*"tarball":"\([^"]*\)".*/\1/p')"
shasum="$(printf '%s' "$meta" | sed -n 's/.*"shasum":"\([0-9a-f]\{40\}\)".*/\1/p')"
resolved="${tarball##*/agent-browser-}"
resolved="${resolved%.tgz}"

if [ -z "$tarball" ] || [ -z "$shasum" ]; then
  if have_binary; then
    echo "Could not resolve agent-browser@$version; keeping the installed $(installed_version)." >&2
  else
    echo "Could not resolve agent-browser@$version from $registry, and nothing is installed." >&2
    exit 1
  fi
elif have_binary && [ "$(installed_version)" = "$resolved" ]; then
  echo "agent-browser $resolved is already installed."
else
  echo "Downloading agent-browser $resolved..."
  tmp="$state/.agent-browser-download"
  rm -rf "$tmp" && mkdir -p "$tmp"
  if download "$tarball" "$tmp/package.tgz" && [ "$(sha1_of "$tmp/package.tgz")" = "$shasum" ] &&
    tar -xzf "$tmp/package.tgz" -C "$tmp" && [ -f "$tmp/package/bin/agent-browser-$platform" ]; then
    # Keep only this platform's binary; the others are ~100 MB of dead weight.
    find "$tmp/package/bin" -name 'agent-browser-*' ! -name "agent-browser-$platform" -delete
    chmod +x "$tmp/package/bin/agent-browser-$platform"
    rm -rf "$pkg"
    mv "$tmp/package" "$pkg"
    rm -rf "$tmp"
    echo "Installed agent-browser $resolved to $pkg."
  else
    rm -rf "$tmp"
    if have_binary; then
      echo "Downloading or verifying agent-browser $resolved failed; keeping the installed $(installed_version)." >&2
    else
      echo "Downloading or verifying $tarball failed, and nothing is installed." >&2
      exit 1
    fi
  fi
fi
have_binary || { echo "$binary does not run on this host." >&2; exit 1; }

mkdir -p "$state/bin"
ln -sfn "$binary" "$state/bin/agent-browser"
printf 'export PATH="%s:$PATH"\n' "$state/bin" >"$state/env.sh"
echo "Recorded $state/bin in \$PLUGIN_STATE_DIR/env.sh."

# --- Chrome -------------------------------------------------------------------
# From here on, run as the plugin's commands will: lib.sh's environment and the
# plugin's HOME, so Chrome lands where run.sh looks for it.
# shellcheck disable=SC1091
. "${PLUGIN_DIR:-$(dirname "$0")}/lib.sh"
agent-browser --version

# The Chrome download is a zip; the CLI unpacks it itself, unzip is not needed.
echo
out="$(agent-browser install 2>&1)"
code=$?
printf '%s\n' "$out" | grep -v -e 'install --with-deps' -e 'shared library' -e 'If browser fails'
[ "$code" -eq 0 ] || { echo "Downloading Chrome failed (exit $code)." >&2; exit 1; }

# Each CLI version pins a Chrome build; drop the ones earlier versions left.
browsers="$HOME/.agent-browser/browsers"
current="$(printf '%s\n' "$out" | sed -n 's/^ *Location: *//p' | tail -1)"
if [ -n "$current" ] && [ -d "$current" ]; then
  for d in "$browsers"/*; do
    [ -d "$d" ] && [ "$d" != "$current" ] && rm -rf "$d" && echo "Removed the old browser $(basename "$d")."
  done
fi

# A Chrome on disk is not a Chrome that starts: on a bare Linux server its shared
# libraries are usually missing. Install them when root is free; otherwise say
# exactly what is missing. (`agent-browser install --with-deps` would do this
# with plain sudo, which can wait on a password.)
missing_libs() {
  command -v ldd >/dev/null 2>&1 || return 0
  find "$browsers" -maxdepth 3 -type f \( -name chrome -o -name chrome-headless-shell \) 2>/dev/null |
    while read -r c; do ldd "$c" 2>/dev/null | grep 'not found'; done | sort -u
}
if [ "$(uname -s)" = Linux ] && [ -n "$(missing_libs)" ]; then
  echo "Chrome is missing shared libraries; installing them."
  if command -v apt-get >/dev/null 2>&1; then
    debs=(libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libatspi2.0-0
      libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libxshmfence1)
    system_install "${debs[@]}" libasound2t64 || system_install "${debs[@]}" libasound2 || true
  elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    system_install nss nspr atk at-spi2-atk cups-libs libdrm libxkbcommon at-spi2-core libXcomposite \
      libXdamage libXfixes libXrandr mesa-libgbm pango cairo alsa-lib || true
  elif command -v apk >/dev/null 2>&1; then
    system_install nss nspr atk at-spi2-atk cups-libs libdrm libxkbcommon at-spi2-core libxcomposite \
      libxdamage libxfixes libxrandr mesa-gbm pango cairo alsa-lib || true
  fi
  if [ -n "$(missing_libs)" ]; then
    echo "Chrome still cannot load:" >&2
    missing_libs | sed 's/^/  /' >&2
    echo "Installing them needs root (no root and no password-less sudo here). Until an" >&2
    echo "administrator installs them and presses Reinstall, no page can be opened;" >&2
    echo "'agent-browser read <url>' (which needs no browser) still works." >&2
    exit 1
  fi
fi
# Fonts pages fall back to (emoji, CJK), for screenshots that are not boxes.
# Best effort, never fatal.
if [ "$(uname -s)" = Linux ] && command -v apt-get >/dev/null 2>&1 && can_root; then
  system_install fonts-liberation fonts-noto-color-emoji fonts-noto-cjk >/dev/null 2>&1 || true
fi

# --- The sandbox --------------------------------------------------------------
# Launch Chrome for real: only that tells whether this host can sandbox it.
probe() { # extra env for the launch...
  local s="plugin-install-probe" rc
  env "$@" agent-browser --session "$s" --idle-timeout 30s open about:blank >"$state/.probe.log" 2>&1
  rc=$?
  agent-browser --session "$s" close >/dev/null 2>&1
  return "$rc"
}
echo
rm -f "$state/no-sandbox"
case "${CHROME_SANDBOX:-auto}" in
  auto)
    if probe -u AGENT_BROWSER_ARGS; then
      echo "Chrome starts with its sandbox."
    elif probe AGENT_BROWSER_ARGS=--no-sandbox; then
      touch "$state/no-sandbox"
      echo "Chrome cannot sandbox itself on this host (containers, VMs and Ubuntu 23.10+ AppArmor"
      echo "usually prevent it); it will run with --no-sandbox. Reinstall re-checks."
    else
      echo "Chrome does not start, with or without its sandbox:" >&2
      sed 's/^/  /' "$state/.probe.log" >&2
      exit 1
    fi
    ;;
  on | off)
    if probe; then
      echo "Chrome starts (sandbox: ${CHROME_SANDBOX})."
    else
      echo "Chrome does not start with the sandbox setting '${CHROME_SANDBOX}':" >&2
      sed 's/^/  /' "$state/.probe.log" >&2
      [ "$CHROME_SANDBOX" = on ] && echo "Set 'Chrome sandbox' to Auto or Always off and press Reinstall." >&2
      exit 1
    fi
    ;;
esac
rm -f "$state/.probe.log"

# --- Report -------------------------------------------------------------------
# Cloud providers, the AI gateway and the vault key show as "not set"; they are
# optional and not used by this plugin.
echo
agent-browser doctor --offline --quick || true
echo
echo "Installed. agent-browser needs no sign-in."
